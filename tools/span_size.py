import os
exec(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "span_spike.py"), encoding="utf-8-sig").read().split('if sys.argv[1] == "stats"')[0])
top = [w.strip() for w in open(R + r"\tools\data\20k.txt")]
for N in (1000, 5000, 10000):
    keys = set(); dur = 0.0
    for w in top[:N]:
        if w not in cmu or len(cmu[w]) < 2: continue
        p = plan(cmu[w])
        if not p: continue
        for a, b in p:
            k = tuple(cmu[w][a:b + 1])
            if k not in keys:
                keys.add(k); n, i = idx[k][0]; s = utt[n]; dur += s[i + len(k) - 1][2] - s[i][1]
    print("top %d: %d unique units, %.0f s audio (~%.1f MB as ogg at ~12 KB/s)" % (N, len(keys), dur, dur * 12 / 1024))


