import glob, os, numpy as np, parselmouth
E = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "experiments", "arctic")
def hnr(p):
    s = parselmouth.Sound(p)
    if s.duration < 0.05: return None
    h = s.to_harmonicity_cc(time_step=0.005, minimum_pitch=75).values[0]; h = h[h > -100]
    return float(np.median(h)) if len(h) >= 3 else None
rows = []
for p in glob.glob(E + r"\prov\wav\*.wav"):
    k = os.path.basename(p)[:5]
    if k[4] in "24" and k[:4] not in ("0000",):
        v = hnr(p)
        if v is not None: rows.append((k, v))
vals = np.array([v for _, v in rows]); print("clips", len(rows), "HNR dB median %.1f  p10 %.1f  p90 %.1f" % (np.median(vals), *np.percentile(vals, [10, 90])))
d = dict(rows)
for k in ["00232","23052","23054","05292","05294","29242","29244","24182","24184","18252","18254","25002","25004"]:
    if k in d: print(k, "%.1f dB  (percentile %d)" % (d[k], (vals < d[k]).mean() * 100))
# corpus original for reference
orig = [hnr(p) for p in sorted(glob.glob(E + r"\corpus\cmu_us_slt_arctic\wav\*.wav"))[:5]]
print("original recordings HNR median:", np.round(orig, 1))

