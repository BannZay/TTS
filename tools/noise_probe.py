import wave, glob, os, numpy as np, subprocess
def rd(p):
    with wave.open(p) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(float), f.getframerate()
def fl(x, sr): 
    n = int(.02*sr); r = np.array([np.sqrt((x[i:i+n]**2).mean()) for i in range(0, len(x)-n, n)]); return 20*np.log10(np.percentile(r,5)+1e-9), 20*np.log10(np.percentile(r,95)+1e-9)
src = sorted(glob.glob(r"corpus\cmu_us_slt_arctic\wav\*.wav"))[:8]
for p in src[:5]:
    x, sr = rd(p); lo, hi = fl(x, sr); print("corpus %s sr %d floor %.0f dB speech %.0f dB" % (os.path.basename(p), sr, lo, hi))
wav = sorted(glob.glob(r"out2\wav\*.wav"))
print(len(wav), "final wavs")
fs = []
for p in wav[::200]:
    x, sr = rd(p)
    if len(x) > 1000: fs.append((20*np.log10(np.sqrt((x**2).mean())+1e-9), os.path.basename(p)))
print("final clip RMS dB: min %.0f median %.0f max %.0f" % (min(f[0] for f in fs), np.median([f[0] for f in fs]), max(f[0] for f in fs)))
