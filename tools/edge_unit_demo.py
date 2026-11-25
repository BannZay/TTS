# Demo of an "edge unit": the whole word "the" (DH AH0, with the silence at both ends) cut from the corpus, against the three diphones now used.
import json, os, re, sys, wave, subprocess, math, numpy as np, parselmouth
from parselmouth.praat import call
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); E = R + r"\experiments\arctic"; SR = 16000; F0 = 173.93; TGT = 3379.0
OUT = E + r"\listen\7_edge_unit_the"; os.makedirs(OUT, exist_ok=True)
al = json.load(open(E + r"\out\align.json"))
def rd(p):
    with wave.open(p) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(np.float32)
def wr(name, y):
    with wave.open(OUT + "\\" + name, "w") as f: f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(np.clip(y, -32768, 32767).astype(np.int16).tobytes())
raw = {}
def db(n, a, b):
    if n not in raw: raw[n] = rd(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n)
    y = raw[n][int(a * SR):max(int(b * SR), int(a * SR) + 80)]; return 20 * math.log10(math.sqrt(float((y ** 2).mean())) + 1)
# every occurrence of the word "the" = a word of exactly DH + AH(stress 0)
occ = []
for n, ps in al.items():
    for i in range(len(ps) - 1):
        a, b = ps[i], ps[i + 1]
        if a[0] == "DH" and b[0] == "AH" and str(b[1]) == "0" and a[2] == b[2] and (i == 0 or ps[i - 1][2] != a[2]) and (i + 2 >= len(ps) or ps[i + 2][2] != a[2]):
            occ.append((n, a[3], b[4], ps[i - 1][0] if i else "pau", ps[i + 2][0] if i + 2 < len(ps) else "pau"))
print("occurrences of the word 'the':", len(occ))
durs = [e - s for _, s, e, _, _ in occ]; med = float(np.median(durs)); print("median length %.3f s; diphone version about 0.129 s" % med)
def score(o):
    n, s, e, pv, nx = o; d = e - s
    top = db(n, s, e)
    return 4 * abs(math.log(d / 0.13)) + 0.3 * max(0, top - db(n, s, s + 0.02) - 12) + 0.3 * max(0, top - db(n, e - 0.02, e) - 12) + (2 if nx == "pau" else 0) + (2 if pv == "pau" else 0)
best = sorted(occ, key=score)[:2]
for k, (n, s, e, pv, nx) in enumerate(best):
    print("pick %d: %s %.2f-%.2f (%.3f s), after %s before %s" % (k + 1, n, s, e, e - s, pv, nx))
def flat(n):
    snd = parselmouth.Sound(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n); m = call(snd, "To Manipulation", 0.01, 75, 400)
    t = call("Create PitchTier", "f", snd.xmin, snd.xmax); call(t, "Add point", snd.xmin, F0); call(t, "Add point", snd.xmax, F0); call([t, m], "Replace pitch tier")
    return np.clip(call(m, "Get resynthesis (overlap-add)").values[0] * 32768.0, -32768, 32767)
clips = []
for n, s, e, _, _ in best:
    y = flat(n)[int(s * SR):int(e * SR)].copy(); f = int(0.0025 * SR); y[:f] *= np.linspace(0, 1, f); y[-f:] *= np.linspace(1, 0, f)
    clips.append(np.clip(y * min(2.0, max(0.5, TGT / float(np.sqrt((y ** 2).mean() + 1)))), -32768, 32767))
gap = np.zeros(int(0.3 * SR), np.float32)
# the three diphones used today: _DH (0011), DH AH0 (1103), AH0 _ (0300), medium/long variants as the engine chooses them
plan = subprocess.run(["lua", "render_plan.lua", "the", "arctic", "hq"], cwd=R + r"\tests", capture_output=True, text=True, env={**os.environ, "VC_NO_UNITS": "1"}).stdout
def dec(path):
    rel = path.replace("Interface\\AddOns\\", ""); w = os.path.join(os.environ["TEMP"], "vc_edge_" + rel.replace("\\", "_") + ".wav")
    if not os.path.exists(w): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(R, rel), "-ar", str(SR), "-ac", "1", w])
    return rd(w)
old = np.concatenate([dec(l.split("\t")[0]) for l in plan.splitlines() if "\t" in l])
wr("the_old_diphones.wav", np.concatenate([gap, old, gap]))
for k, c in enumerate(clips): wr("the_new_edge_unit_%d.wav" % (k + 1), np.concatenate([gap, c, gap]))
# the phrase with "the" replaced (both "the"s), old against new
phrase = "the quick brown fox jumps over the lazy dog"
def render(env, edge):
    pl = [l.split("\t") for l in subprocess.run(["lua", "render_plan.lua", phrase, "arctic", "hq"], cwd=R + r"\tests", capture_output=True, text=True, env={**os.environ, **env}).stdout.splitlines() if "\t" in l]
    names = [os.path.basename(p[0].replace("\\", "/"))[:-4] for p in pl]; out = []; i = 0
    while i < len(pl):
        if edge and names[i][:4] == "0011" and i + 2 < len(pl) and names[i + 1][:4] == "1103" and names[i + 2][:4] == "0300":
            out.append(clips[0]); i += 3; continue
        out.append(dec(pl[i][0])); i += 1
    return np.concatenate([gap] + out + [gap])
wr("phrase_old_with_units.wav", render({}, False)); wr("phrase_new_the_as_edge_unit.wav", render({}, True))
print("written to", OUT)
