import os
src = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "build_arctic_units.py"), encoding="utf-8-sig").read().split("choice = {t:")[0]
exec(src)
want = [("EH","R","AH0"), ("AH0","L","AY"), ("AY","N","AH0"), ("M","AO","R","N","IH","NG")]
for t in want:
    n, i = pick(t); sq = utt[n]; L = len(t)
    print(t, "->", n, "words", [s[1] for s in sq[i:i+L]], "durs", [round(s[3]-s[2], 3) for s in sq[i:i+L]], "unit s %.3f" % (mid(sq[i+L-1]) - mid(sq[i])),
          "dB cuts %.0f/%.0f" % (rawdb(n, mid(sq[i]) - .01, mid(sq[i]) + .01), rawdb(n, mid(sq[i+L-1]) - .01, mid(sq[i+L-1]) + .01)), "occurrences", len(idx[t]))
