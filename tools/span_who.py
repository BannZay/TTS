import os
exec(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "span_spike.py"), encoding="utf-8-sig").read().split('if sys.argv[1] == "stats"')[0])
ph = cmu["evening"]; a, b = plan(ph)[0]; n, i = idx[tuple(ph[a:b+1])][0]; s = utt[n]
print(n, [x[0] for x in s[i-1:i+len(ph)+1]], "%.2f-%.2f s" % (s[i][1], s[i+len(ph)-1][2]))
print(open(E + r"\corpus\cmu_us_slt_arctic\etc\txt.done.data").read().split(n)[1].split("\n")[0])
