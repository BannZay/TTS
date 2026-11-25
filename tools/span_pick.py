import os
exec(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "span_spike.py"), encoding="utf-8-sig").read().split('if sys.argv[1] == "stats"')[0])
known = set(re.findall(r'^\["([a-z]+)"\]', open(R + r"\TTS_Diphone\Words.lua", encoding="utf8").read(), re.M))
top = [w.strip() for w in open(R + r"\tools\data\20k.txt")][1000:3000]
c = []
for w in top:
    if w in cmu and w in known and len(cmu[w]) >= 6:
        p = plan(cmu[w])
        if p and len(p) in (2, 3): c.append(w)
print(" ".join(c[::len(c)//7][:7]))

