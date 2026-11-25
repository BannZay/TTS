import sys, os, subprocess, wave, numpy as np
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); SR = 16000; W = R + r"\experiments\arctic\out2\wav"; OUT = R + r"\experiments\arctic\listen\2_clicks_and_noise"
text = sys.argv[1]
plan = subprocess.run(["lua", "render_plan.lua", text, "arctic", "hq"], cwd=R + r"\tests", capture_output=True, text=True).stdout
rows = [l.split("\t") for l in plan.splitlines() if "\t" in l]
def rd(p):
    with wave.open(p) as f: x = np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(float); sr = f.getframerate()
    if sr != SR:
        n = int(len(x) * SR / sr); x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
    return x
def ogg(p):
    rel = p.replace("Interface\\AddOns\\", ""); w = os.path.join(os.environ["TEMP"], "vc_phrase", rel.replace("\\", "_").replace(".", "_") + ".wav")
    if not os.path.exists(w): os.makedirs(os.path.dirname(w), exist_ok=True); subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(R, rel), "-ar", str(SR), "-ac", "1", "-map_metadata", "-1", w])
    return rd(w)
def mix(clips):
    ends = np.cumsum([0] + [float(r[1]) for r in rows[:-1]]); n = int((ends[-1] + len(clips[-1]) / SR + .6) * SR); m = np.zeros(n)
    for s, c in zip(ends, clips): i = int(round((s + .3) * SR)); m[i:i + len(c)] += c
    return m
def wr(name, m):
    with wave.open(os.path.join(OUT, name), "w") as f: f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(np.clip(m, -32768, 32767).astype(np.int16).tobytes())
a, b = [], []; snr = []
for r in rows:
    key = os.path.basename(r[0].replace("\\", "/")).replace(".ogg", ""); o = ogg(r[0]); a.append(o)
    pw = os.path.join(W, key + ".wav"); w = rd(pw) if os.path.exists(pw) else o; b.append(w)
    n = min(len(o), len(w)); e = o[:n] - w[:n]; snr.append(10 * np.log10((w[:n] ** 2).sum() / ((e ** 2).sum() + 1e-9) + 1e-9))
wr("noise_ogg.wav", mix(a)); wr("noise_wav.wav", mix(b))
print("clips %d, ogg-vs-wav SNR median %.1f dB (min %.1f)" % (len(rows), np.median(snr), min(snr)))
