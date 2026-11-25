import os
import json, math, wave, numpy as np
E = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "experiments", "arctic"); SR = 16000
al = json.load(open(E + r"\out\align.json"))
def rd(n):
    with wave.open(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(float)
rows = []
for n, ps in al.items():
    for i in range(len(ps) - 2):
        a, b, c = ps[i], ps[i + 1], ps[i + 2]
        if (a[0], b[0], c[0]) == ("W", "IH", "L") and a[2] == b[2] == c[2] and (i == 0 or ps[i - 1][2] != a[2]) and (i + 3 >= len(ps) or ps[i + 3][2] != a[2]):
            y = rd(n)[int(a[3] * SR):int(c[4] * SR)]; rows.append((c[4] - a[3], 20 * math.log10(math.sqrt((y ** 2).mean()) + 1), n, round(a[3], 2), ps[i - 1][0] if i else "-", ps[i + 3][0] if i + 3 < len(ps) else "-"))
rows.sort()
print(len(rows), "occurrences of the word 'will' (W IH L); diphone voice needs 0.27 s for it")
for r in rows: print("%.3f s  %.0f dB  %s @%.2f  after %s before %s" % r)
