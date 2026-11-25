import os
src = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "build_arctic_units.py"), encoding="utf-8-sig").read().split("choice = {k:")[0]
import sys; sys.argv = ["x", "20000", "8"]
exec(src)
k = (True, ("W", "IH", "L"), True)
occ = idx[k]; print("occurrences of the whole word 'will':", len(occ))
rows = []
for n, i, L in occ:
    sq = utt[n]; s, e = span(sq, i, L, True, True); top = max(rawdb(n, x[2], x[3]) for x in sq[i:i+L])
    rows.append((n, round(e - s, 3), "prev=" + (sq[i-1][0] if i else "-"), "next=" + (sq[i+L][0] if i + L < len(sq) else "-"),
                 "dB start/mid/end %.0f/%.0f/%.0f" % (rawdb(n, s, s + .02), top, rawdb(n, e - .02, e)), [round(x[3]-x[2], 3) for x in sq[i:i+L]]))
n0, i0 = pick(k); print("picked:", n0, i0)
for r in sorted(rows, key=lambda r: r[1]): print(("* " if r[0] == n0 else "  ") + str(r))
