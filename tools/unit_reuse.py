import os
import re
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = "AA AE AH0 AH AO AW AY B CH D DH EH ER EY F G HH IH IY JH K L M N NG OW OY P R S SH T TH UH UW V W Y Z ZH".split()
dic = {m.group(1): [P[ord(c) - 49] for c in m.group(2) if c not in "^~"] for m in re.finditer(r'^\["([a-z]+)"\]="([^"]*)",?$', open(R + r"\TTS_Diphone\Words.lua", encoding="utf8").read(), re.M)}
S = {tuple(P[int(k[i:i + 2]) - 1] for i in range(0, len(k), 2)) for k in re.findall(r'^\["(\d+)"\]=\{', open(R + r"\TTS_Arctic\Units.lua").read(), re.M)}
top = [w.strip() for w in open(R + r"\tools\data\20k.txt")]
def joins(p):
    n = len(p); b = [99] * n; b[0] = 0
    for i in range(n):
        if i + 1 < n: b[i + 1] = min(b[i + 1], b[i] + 1)
        for L in range(3, 7):
            if i + L - 1 < n and tuple(p[i:i + L]) in S: b[i + L - 1] = min(b[i + L - 1], b[i] + 1)
    return b[n - 1]
def stat(ws, label):
    ws = [w for w in ws if w in dic and len(dic[w]) >= 3 and re.fullmatch(r"[a-z]+", w)]
    d = sum(len(dic[w]) - 1 for w in ws); u = sum(joins(dic[w]) for w in ws)
    print("%-34s %5d words: joins per word %.2f -> %.2f (%.0f%% fewer)" % (label, len(ws), d / len(ws), u / len(ws), 100 * (1 - u / d)))
stat(top[:10000], "built for (rank 1-10000)")
stat(top[10000:20000], "NOT built for (rank 10001-20000)")
allw = [w for w in dic if re.fullmatch(r"[a-z]+", w)]; seen = set(top[:20000])
import random; random.seed(1); rest = [w for w in allw if w not in seen]; stat(random.sample(rest, 5000), "rare words outside the 20k list")
