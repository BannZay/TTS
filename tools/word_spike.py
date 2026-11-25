import json, wave, os, subprocess, numpy as np, parselmouth
from parselmouth.praat import call
E = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "experiments", "arctic"); SR = 16000
al = json.load(open(E + r"\out\align.json"))["arctic_a0506"]
ph = [(p[0], p[2], p[3], p[4]) for p in al]
print([x[0] for x in ph if x[1] == 5], [x for x in ph if x[1] == 5][0], [x for x in ph if x[1] == 5][-1])
w = [x for x in ph if x[1] == 5]; t0, t1 = w[0][2], w[-1][3]
src = E + r"\corpus\cmu_us_slt_arctic\wav\arctic_a0506.wav"
snd = parselmouth.Sound(src)
def save(s, name):
    x = np.clip(s.values[0] * 32768, -32768, 32767).astype(np.int16)
    x = np.concatenate([np.zeros(int(.3 * SR), np.int16), x, np.zeros(int(.3 * SR), np.int16)])
    with wave.open(E + "\\" + name, "w") as f: f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(x.tobytes())
save(snd.extract_part(t0, t1, preserve_times=False), "morning_word_natural.wav")
f0med = 173.93
manip = call(snd, "To Manipulation", 0.01, 75, 400)
tier = call("Create PitchTier", "flat", snd.xmin, snd.xmax); call(tier, "Add point", snd.xmin, f0med); call(tier, "Add point", snd.xmax, f0med)
call([tier, manip], "Replace pitch tier"); flat = call(manip, "Get resynthesis (overlap-add)")
save(flat.extract_part(t0, t1, preserve_times=False), "morning_word_flat.wav")
