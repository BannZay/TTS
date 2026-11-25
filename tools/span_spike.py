# Spike: render words from the LONGEST phone spans the corpus has (greedy fewest units) instead of diphones; also report
# how many units per word that would need over the top-N frequent words.
import json, re, sys, wave, os, numpy as np, parselmouth
from collections import defaultdict
from parselmouth.praat import call
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); E = R + r"\experiments\arctic"; SR = 16000; F0 = 173.93
al = json.load(open(E + r"\out\align.json"))
def norm(p): return re.sub(r"\d", "", p)
utt = {}
for n, ps in al.items():
    seq = [(norm(p[0]), p[3], p[4]) for p in ps if norm(p[0]) not in ("pau", "sil", "")]
    utt[n] = seq
# n-gram index: tuple(phones) -> [(utt, i)]
idx = defaultdict(list)
for n, seq in utt.items():
    names = [s[0] for s in seq]
    for L in range(2, 8):
        for i in range(len(names) - L + 1): idx[tuple(names[i:i + L])].append((n, i))
cmu = {}
for l in open(R + r"\tools\data\cmudict.dict", encoding="latin-1"):
    p = l.split(" #")[0].split()
    if len(p) > 1 and re.fullmatch(r"[a-z']+", p[0]) and p[0] not in cmu: cmu[p[0]] = [norm(x) for x in p[1:]]
def plan(ph, maxL=7):   # DP: fewest units; a unit covers span of >=2 phones; consecutive units overlap by one phone (join at phone middle)
    n = len(ph); INF = 99; best = [INF] * n; prev = [None] * n; best[0] = 0
    # state i = a unit ended inside phone i (we are at the middle of phone i)
    for i in range(n):
        if best[i] >= INF: continue
        for L in range(min(maxL, n - i), 1, -1):
            if tuple(ph[i:i + L]) in idx and best[i + L - 1] > best[i] + 1:
                best[i + L - 1] = best[i] + 1; prev[i + L - 1] = i
    if best[n - 1] >= INF: return None
    out = []; j = n - 1
    while j:
        out.append((prev[j], j)); j = prev[j]
    return out[::-1]
if sys.argv[1] == "stats":
    top = [w.strip() for w in open(R + r"\tools\data\20k.txt")][:int(sys.argv[2])]
    ok = u = d = 0
    for w in top:
        if w not in cmu or len(cmu[w]) < 2: continue
        p = plan(cmu[w])
        if p: ok += 1; u += len(p); d += len(cmu[w]) - 1
    print("words fully coverable: %d; units %d vs diphones %d (%.0f%%)" % (ok, u, d, 100 * u / d)); sys.exit()
flatcache = {}
def flat(n):
    if n not in flatcache:
        snd = parselmouth.Sound(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n)
        manip = call(snd, "To Manipulation", 0.01, 75, 400); t = call("Create PitchTier", "f", snd.xmin, snd.xmax)
        call(t, "Add point", snd.xmin, F0); call(t, "Add point", snd.xmax, F0); call([t, manip], "Replace pitch tier")
        flatcache[n] = call(manip, "Get resynthesis (overlap-add)").values[0] * 32768
    return flatcache[n]
def xfade(a, b, ms=8):
    k = int(ms / 1000 * SR); k = min(k, len(a), len(b)); w = np.hanning(2 * k)[:k]
    return np.concatenate([a[:-k], a[-k:] * (1 - w) + b[:k] * w, b[k:]])
for word in sys.argv[2:]:
    ph = cmu[word]; pl = plan(ph); print(word, ph, "units:", [(" ".join(ph[a:b + 1])) for a, b in pl], "(diphone joins would be %d, now %d)" % (len(ph) - 1, len(pl) - 1))
    y = None
    for a, b in pl:
        occ = idx[tuple(ph[a:b + 1])][0]; n, i = occ; seq = utt[n]; L = b - a + 1
        t0 = (seq[i][1] + seq[i][2]) / 2 if a > 0 else seq[i][1]
        t1 = (seq[i + L - 1][1] + seq[i + L - 1][2]) / 2 if b < len(ph) - 1 else seq[i + L - 1][2]
        x = flat(n)[int(t0 * SR):int(t1 * SR)]; y = x if y is None else xfade(y, x)
    y = np.concatenate([np.zeros(int(.3 * SR)), y, np.zeros(int(.3 * SR))])
    with wave.open(E + r"\listen\4_spans_vs_diphones\span_%s.wav" % word, "w") as f: f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(np.clip(y, -32768, 32767).astype(np.int16).tobytes())
