import wave, numpy as np, sys, os
keys = sys.argv[1].split(","); E = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "experiments", "arctic"); SR = 16000
def rd(p):
    with wave.open(p) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16), f.getframerate()
out = []; gap = np.zeros(int(.5 * SR), np.int16)
for k in keys:
    for v in "24":
        p = E + r"\prov\wav\%s%s.wav" % (k, v)
        if os.path.exists(p):
            x, sr = rd(p); out += [x, gap]
        else: print("missing", k, v)
    out.append(gap)
with wave.open(E + r"\listen\2_clicks_and_noise\morning_parts.wav", "w") as f: f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(np.concatenate(out).tobytes())
