import os
import json, re, math, collections
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); E = R + r"\experiments\arctic"
P = "AA AE AH0 AH AO AW AY B CH D DH EH ER EY F G HH IH IY JH K L M N NG OW OY P R S SH T TH UH UW V W Y Z ZH".split()
dic = {m.group(1): [P[ord(c) - 49] for c in m.group(2) if c not in "^~"] for m in re.finditer(r'^\["([a-z]+)"\]="([^"]*)",?$', open(R + r"\TTS_Diphone\Words.lua", encoding="utf8").read(), re.M)}
al = json.load(open(E + r"\out\align.json")); occ = collections.defaultdict(list); total = 0.0
for n, ps in al.items():
    names = [("pau" if p[0] in ("pau", "sil", "") else ("AH0" if p[0] == "AH" and p[1] == "0" else p[0])) for p in ps]; total = max(total, 0)
    for L in range(3, 9):
        for i in range(len(names) - L + 1):
            t = tuple(names[i:i + L])
            if "pau" not in t: occ[t].append((ps[i][3] + ps[i][4]) / 2 and (ps[i + L - 1][3] + ps[i + L - 1][4] - ps[i][3] - ps[i][4]) / 2)
print("corpus audio %.0f min; distinct 3-8 phone runs %d, occurrences %d; mean unit length %.2f s" % (sum(ps[-1][4] for ps in al.values()) / 60, len(occ), sum(len(v) for v in occ.values()), sum(sum(v) for v in occ.values()) / sum(len(v) for v in occ.values())))
top = [w.strip() for w in open(R + r"\tools\data\20k.txt")]
PEN = {**{v: 0.3 for v in "AA AE AH EH ER IH IY UH UW AO".split()}, **{v: 0.6 for v in "AH0 AW AY EY OW OY".split()}}
def units_for(words, maxp):
    freq = collections.Counter()
    for w, p in words:
        for L in range(3, maxp + 1):
            for i in range(len(p) - L + 1):
                t = tuple(p[i:i + L])
                if t in occ: freq[t] += 1
    fmax = math.log(1 + max(freq.values())); used = set(); saved = 0; base = 0
    for w, p in words:
        n = len(p); best = [1e9] * n; prev = [None] * n; best[0] = 0.0
        for i in range(n):
            if best[i] >= 1e9: continue
            jp = 0.5 * PEN.get(p[i], 0) if i > 0 else 0
            if i + 1 < n and best[i + 1] > best[i] + 1 + jp: best[i + 1] = best[i] + 1 + jp; prev[i + 1] = (i, 1)
            for L in range(3, maxp + 1):
                j = i + L - 1; t = tuple(p[i:j + 1])
                if j < n and t in freq:
                    c = best[i] + 1 + jp - 0.3 * math.log(1 + freq[t]) / fmax
                    if c < best[j]: best[j] = c; prev[j] = (i, L)
        j = n - 1
        while j:
            i, L = prev[j]
            if L > 1: used.add(tuple(p[i:j + 1]))
            j = i
    return used
def stats(label, words, maxp):
    u = units_for(words, maxp); mean = sum(sum(occ[t]) / len(occ[t]) for t in u) / len(u)
    print("%-34s maxlen %d: %6d units, mean %.2f s -> %5.1f MB (1 candidate each), %5.1f MB (x3)" % (label, maxp, len(u), mean, len(u) * mean * 22 / 1024, 3 * len(u) * mean * 22 / 1024))
W = lambda n: [(w, dic[w]) for w in top[:n] if w in dic and re.fullmatch(r"[a-z]+", w) and len(dic[w]) >= 3]
stats("top 10000 (today)", W(10000), 6)
stats("top 20000", W(20000), 6)
stats("top 20000", W(20000), 8)
allw = [(w, p) for w, p in dic.items() if re.fullmatch(r"[a-z]+", w) and len(p) >= 3]
stats("whole dictionary (%d words)" % len(allw), allw, 6)
stats("whole dictionary", allw, 8)
print("every distinct 3-6 run in the corpus: %d units" % sum(1 for t in occ if len(t) <= 6))
