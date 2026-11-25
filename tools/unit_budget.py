import os
import json, re, collections, math
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); E = R + r"\experiments\arctic"
P = "AA AE AH0 AH AO AW AY B CH D DH EH ER EY F G HH IH IY JH K L M N NG OW OY P R S SH T TH UH UW V W Y Z ZH".split()
dic = {m.group(1): [P[ord(c) - 49] for c in m.group(2) if c not in "^~"] for m in re.finditer(r'^\["([a-z]+)"\]="([^"]*)",?$', open(R + r"\TTS_Diphone\Words.lua", encoding="utf8").read(), re.M)}
al = json.load(open(E + r"\out\align.json")); have = set()
for ps in al.values():
    names = [("AH0" if p[0] == "AH" and p[1] == "0" else p[0]) for p in ps]
    for L in range(3, 9):
        for i in range(len(names) - L + 1):
            t = tuple(names[i:i + L])
            if "pau" not in t and "" not in t: have.add(t)
top = [w.strip() for w in open(R + r"\tools\data\20k.txt")][:20000]
words = [(dic[w], 1.0 / (r + 1)) for r, w in enumerate(top) if w in dic and re.fullmatch(r"[a-z]+", w) and len(dic[w]) >= 3]
tw = sum(w for _, w in words); base = sum((len(p) - 1) * w for p, w in words)
cnt = collections.Counter()
for p, w in words:
    for L in range(3, 7):
        for i in range(len(p) - L + 1):
            t = tuple(p[i:i + L])
            if t in have: cnt[t] += w * (L - 2)
ranked = [t for t, _ in cnt.most_common()]
def joins(S):
    tot = 0.0
    for p, w in words:
        n = len(p); best = [99] * n; best[0] = 0
        for i in range(n):
            if best[i] >= 99: continue
            best[i + 1 if i + 1 < n else i] = min(best[i + 1 if i + 1 < n else i], best[i] + 1) if i + 1 < n else best[i]
            for L in range(3, min(7, n - i + 1)):
                if tuple(p[i:i + L]) in S and i + L - 1 < n: best[i + L - 1] = min(best[i + L - 1], best[i] + 1)
        tot += best[n - 1] * w
    return tot
print("distinct n-grams present in corpus:", len(cnt), "; weighted diphone joins:", round(base, 1))
for K in (0, 250, 500, 1000, 2000, 4000, 8000):
    j = joins(set(ranked[:K])); print("K=%5d units (3-6 phones): joins per word %.2f vs diphones %.2f  (%.0f%% fewer)" % (K, j / tw, base / tw, 100 * (1 - j / base)))
