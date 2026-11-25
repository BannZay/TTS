# All recordings of the word "will" in the corpus as flat-pitch cuts, in order of length, with 0.5 s between them; and the one the builder picks.
import json, math, wave, os, numpy as np, parselmouth
from parselmouth.praat import call
E = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "experiments", "arctic"); SR = 16000; F0 = 173.93; TGT = 3379.0
al = json.load(open(E + r"\out\align.json")); rows = []
for n, ps in al.items():
    for i in range(len(ps) - 2):
        a, b, c = ps[i], ps[i + 1], ps[i + 2]
        if (a[0], b[0], c[0]) == ("W", "IH", "L") and a[2] == b[2] == c[2] and (i == 0 or ps[i - 1][2] != a[2]) and (i + 3 >= len(ps) or ps[i + 3][2] != a[2]):
            rows.append((c[4] - a[3], n, a[3], c[4]))
rows.sort()
def flat(n):
    snd = parselmouth.Sound(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n); m = call(snd, "To Manipulation", 0.01, 75, 400)
    t = call("Create PitchTier", "f", snd.xmin, snd.xmax); call(t, "Add point", snd.xmin, F0); call(t, "Add point", snd.xmax, F0); call([t, m], "Replace pitch tier")
    return np.clip(call(m, "Get resynthesis (overlap-add)").values[0] * 32768.0, -32768, 32767)
out = []; gap = np.zeros(int(0.6 * SR))
os.makedirs(E + r"\listen\9_word_will\candidates", exist_ok=True)
for k, (d, n, s, e) in enumerate(rows, 1):
    y = flat(n)[int(s * SR):int(e * SR)].copy(); f = int(0.0025 * SR); y[:f] *= np.linspace(0, 1, f); y[-f:] *= np.linspace(1, 0, f)
    y = np.clip(y * min(2.0, max(0.5, TGT / float(np.sqrt((y ** 2).mean() + 1)))), -32768, 32767)
    z = np.concatenate([np.zeros(int(.3 * SR)), y, np.zeros(int(.3 * SR))])
    with wave.open(E + r"\listen\9_word_will\candidates\will_%02d_%s_%.3fs.wav" % (k, n, d), "w") as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(z.astype(np.int16).tobytes())
    out += [z, gap]; print(k, n, "%.3f s" % d)
