# Demo of multi-phone units: renders words with the 1000 most useful 3-6 phone units (cut from the corpus) plus ordinary diphones
# for the rest. Usage: unit_demo.py K word [word ...]   -> experiments\arctic\unit_<word>.wav
import json, re, sys, os, wave, collections
import numpy as np, parselmouth
from parselmouth.praat import call
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); E = R + r"\experiments\arctic"; SR = 16000; F0 = 173.93; TGT = 3379.0
MAXL = int(os.environ.get("VC_MAXL", "6")); TAG = os.environ.get("VC_TAG", "unit")   # longest unit in phones; output file prefix
P = "AA AE AH0 AH AO AW AY B CH D DH EH ER EY F G HH IH IY JH K L M N NG OW OY P R S SH T TH UH UW V W Y Z ZH".split()
IX = {p: i + 1 for i, p in enumerate(P)}
dic = {m.group(1): [P[ord(c) - 49] for c in m.group(2) if c not in "^~"] for m in re.finditer(r'^\["([a-z]+)"\]="([^"]*)",?$', open(R + r"\TTS_Diphone\Words.lua", encoding="utf8").read(), re.M)}
al = json.load(open(E + r"\out\align.json")); utt = {}; idx = collections.defaultdict(list)
for n, ps in al.items():
    seq = [("pau" if p[0] in ("pau", "sil", "") else ("AH0" if p[0] == "AH" and p[1] == "0" else p[0]), p[2], p[3], p[4]) for p in ps]; utt[n] = seq
    names = [s[0] for s in seq]
    for L in range(3, MAXL + 1):
        for i in range(len(names) - L + 1):
            t = tuple(names[i:i + L])
            if "pau" not in t: idx[t].append((n, i))
top = [w.strip() for w in open(R + r"\tools\data\20k.txt")][:20000]
cnt = collections.Counter()
for r, w in enumerate(top):
    p = dic.get(w)
    if p and re.fullmatch(r"[a-z]+", w) and len(p) >= 3:
        for L in range(3, MAXL + 1):
            for i in range(len(p) - L + 1):
                t = tuple(p[i:i + L])
                if t in idx: cnt[t] += (L - 2) / (r + 1)
K = int(sys.argv[1]); S = {t for t, _ in cnt.most_common(K)}
print("units allowed:", len(S))
flat, pulses = {}, {}
def prep(n):
    if n in flat: return
    snd = parselmouth.Sound(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n); m = call(snd, "To Manipulation", 0.01, 75, 400)
    t = call("Create PitchTier", "f", snd.xmin, snd.xmax); call(t, "Add point", snd.xmin, F0); call(t, "Add point", snd.xmax, F0); call([t, m], "Replace pitch tier")
    o = call(m, "Get resynthesis (overlap-add)"); flat[n] = np.clip(o.values[0] * 32768.0, -32768, 32767)
    pp = call(o, "To PointProcess (periodic, cc)", 75, 400); pulses[n] = np.array([call(pp, "Get time from index", i + 1) for i in range(call(pp, "Get number of points"))])
def snap(n, t):
    p = pulses[n]
    if len(p):
        j = np.abs(p - t).argmin()
        if abs(p[j] - t) <= 0.006: return int(round(p[j] * SR))
    return int(t * SR)
raw = {}
def rawdb(n, t0, t1):   # level (dB) of the original recording between t0 and t1
    if n not in raw: raw[n] = rd(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n)
    y = raw[n][int(t0 * SR):max(int(t1 * SR), int(t0 * SR) + 80)]
    return 20 * np.log10(np.sqrt((y ** 2).mean()) + 1)
def score(o, L, first_cut, last_cut):
    """lower = better. A mid-phone cut must lie in a steady part: not in a phone at a corpus word edge, not in a fading or silent stretch."""
    n, i = o; sq = utt[n]; s = 2.0 * sum(1 for k in range(L - 1) if sq[i + k][1] != sq[i + k + 1][1])
    if first_cut and (i == 0 or sq[i - 1][0] == "pau" or sq[i - 1][1] != sq[i][1]): s += 3
    if last_cut and (i + L >= len(sq) or sq[i + L][0] == "pau" or sq[i + L][1] != sq[i + L - 1][1]): s += 3
    a, b = sq[i], sq[i + L - 1]; top = max(rawdb(n, x[2], x[3]) for x in sq[i:i + L])
    if first_cut: s += 0.3 * max(0, top - rawdb(n, (a[2] + a[3]) / 2 - 0.01, (a[2] + a[3]) / 2 + 0.01) - 10)
    if last_cut: s += 0.3 * max(0, top - rawdb(n, (b[2] + b[3]) / 2 - 0.01, (b[2] + b[3]) / 2 + 0.01) - 10)
    return s
def fade(y):
    f = int(0.0025 * SR)
    if len(y) > 2 * f: y[:f] *= np.linspace(0, 1, f); y[-f:] *= np.linspace(1, 0, f)
    return y
def level(y): return np.clip(y * min(2.0, max(0.5, TGT / np.sqrt((y ** 2).mean() + 1))), -32768, 32767)
def rd(p):
    with wave.open(p) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(float)
def dip(key):
    for v in "24":
        p = E + r"\out2\wav\%s%s.wav" % (key, v)
        if os.path.exists(p): return rd(p)
    return None
for word in sys.argv[2:]:
    ph = dic[word]; n = len(ph); best = [99] * n; prev = [None] * n; best[0] = 0
    for i in range(n):
        if best[i] >= 99: continue
        if i + 1 < n and best[i + 1] > best[i] + 1: best[i + 1] = best[i] + 1; prev[i + 1] = (i, 1)
        for L in range(3, MAXL + 1):
            j = i + L - 1
            if j < n and tuple(ph[i:j + 1]) in S and best[j] > best[i] + 1: best[j] = best[i] + 1; prev[j] = (i, L)
    segs = []; j = n - 1
    while j: i, L = prev[j]; segs.append((i, j, L)); j = i
    segs = segs[::-1]; parts = []; desc = []
    if segs[0][2] == 1: parts.append(dip("00%02d" % IX[ph[0]])); desc.append("[0 %s]" % ph[0])
    for (i, j, L) in segs:
        if L == 1:
            parts.append(dip("%02d%02d" % (IX[ph[i]], IX[ph[j]]))); desc.append("[%s %s]" % (ph[i], ph[j]))
        else:
            occ = min(idx[tuple(ph[i:j + 1])], key=lambda o: score(o, L, i > 0, j < n - 1))
            nn, ii = occ; prep(nn); sq = utt[nn]; a, b = sq[ii], sq[ii + L - 1]
            s = int(round(a[2] * SR)) if i == 0 else snap(nn, (a[2] + a[3]) / 2); e = int(round(b[3] * SR)) if j == n - 1 else snap(nn, (b[2] + b[3]) / 2)
            parts.append(fade(level(flat[nn][s:e].copy()))); desc.append("{%s}" % " ".join(ph[i:j + 1]))
    if segs[-1][2] == 1: parts.append(dip("%02d00" % IX[ph[-1]])); desc.append("[%s 0]" % ph[-1])
    parts = [p for p in parts if p is not None]
    y = np.concatenate([np.zeros(int(.3 * SR))] + parts + [np.zeros(int(.3 * SR))])
    with wave.open(E + r"\%s_%s.wav" % (TAG, word), "w") as f: f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(np.clip(y, -32768, 32767).astype(np.int16).tobytes())
    print(word, "joins %d (diphones %d):" % (len(parts) - 1, n), " ".join(desc))
