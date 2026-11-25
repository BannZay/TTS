# Click metric on a phrase rendered from the addon plan, with ideal start times vs start times quantized to a frame rate
# (the game starts a clip at the first frame after its time, with the remainder carried over, like Core.NewQueue:Tick).
# Usage: click_sim.py "phrase" [fps ...]   (needs the clip wavs that render_phrase.ps1 caches in %TEMP%\vc_phrase)
import sys, os, subprocess, wave, numpy as np, random
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); TMP = os.path.join(os.environ["TEMP"], "vc_phrase"); SR = 16000
text = sys.argv[1]; fpss = [float(x) for x in sys.argv[2:]] or [60, 30]
plan = subprocess.run(["lua", "render_plan.lua", text, "arctic", "hq"], cwd=R + r"\tests", capture_output=True, text=True).stdout
rows = [l.split("\t") for l in plan.splitlines() if "\t" in l]
def load(p):
    rel = p.replace("Interface\\AddOns\\", ""); k = rel.replace("\\", "_").replace(".", "_"); w = os.path.join(TMP, k + ".wav")
    if not os.path.exists(w): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(R, rel), "-ar", str(SR), "-ac", "1", "-map_metadata", "-1", w])
    with wave.open(w) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(float)
clips = [load(r[0]) for r in rows]; waits = [float(r[1]) for r in rows]
def mix(starts):
    n = int((max(s + len(c) / SR for s, c in zip(starts, clips)) + 0.2) * SR); m = np.zeros(n)
    for s, c in zip(starts, clips): i = int(round(s * SR)); m[i:i + len(c)] += c
    return m
def clicks(m, starts):
    d = np.diff(m, 2); out = []
    for s in starts[1:]:
        i = int(s * SR); a = d[max(i - 32, 0):i + 32]; ref = d[max(i - 400, 0):i + 400]
        out.append(np.abs(a).max() / (np.sqrt((ref ** 2).mean()) + 1e-9))
    return np.array(out)
def sched(fps, phase):
    dt = 1 / fps; t = phase; timer = 0.0; starts = []; now = 0.0; k = 0
    # simulate Tick: frames at multiples of dt; clip k is due at ideal time; played at first frame at/after
    ideal = np.concatenate([[0], np.cumsum(waits)[:-1]])
    return [phase + np.ceil((ideal[k]) / dt) * dt for k in range(len(waits))]
ideal = np.concatenate([[0], np.cumsum(waits)[:-1]])
def report(name, starts, m):
    c = clicks(m, starts); print("%-10s joins %d  click ratio median %.1f  p90 %.1f  >8: %d" % (name, len(c), np.median(c), np.percentile(c, 90), (c > 8).sum()))
    with wave.open(os.path.join(R, "experiments", "arctic", "listen", "2_clicks_and_noise", "click_" + name + ".wav"), "w") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(np.clip(m, -32768, 32767).astype(np.int16).tobytes())
report("ideal", ideal, mix(ideal))
random.seed(1)
for fps in fpss:
    st = [s for s in sched(fps, random.random() / fps)]; st = [s - st[0] for s in st]
    report("fps%d" % fps, st, mix(st))
