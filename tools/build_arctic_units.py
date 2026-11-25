# Builds the units of the TTS_Arctic addon (units/ and Units.lua): multi-phoneme units ("longer diphones", up to 8 phonemes) cut from the CMU Arctic slt
# recordings. A unit replaces a chain of diphones and has no joins inside. Three kinds:
#   middle unit   from the middle of its first phoneme to the middle of its last one (3 or more phonemes); key = phoneme indices
#   start unit    from the start of a word (the silence before it) to the middle of a later phoneme; key = "00" + phonemes
#   end unit      from the middle of a phoneme to the end of the word; key = phonemes + "00"
#   whole word    a word as one clip, silence at both ends; key = "00" + phonemes + "00"
# The unit set is what the fewest-pieces plans of the first N dictionary words need.
#   experiments\arctic\.venv\Scripts\python.exe -I tools\build_arctic_units.py [N=20000] [maxPhones=8]
# Needs experiments\arctic\out\align.json, the corpus wavs, the shipped diphones in experiments\arctic\out2 (loudness) and ffmpeg.
import json, re, os, sys, wave, subprocess, shutil, math, collections
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import parselmouth
from parselmouth.praat import call

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); E = R + r"\experiments\arctic"; OUT = R + r"\TTS_Arctic"
SR = 16000; F0 = 173.93; LO_DB = 28.8     # LO_DB: band level offset of the shipped diphone spectra (build2.py)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
MAXP = int(sys.argv[2]) if len(sys.argv) > 2 else 8
PH = "AA AE AH0 AH AO AW AY B CH D DH EH ER EY F G HH IH IY JH K L M N NG OW OY P R S SH T TH UH UW V W Y Z ZH".split()
IX = {p: i + 1 for i, p in enumerate(PH)}
dic = {m.group(1): [PH[ord(c) - 49] for c in m.group(2) if c not in "^~"] for m in re.finditer(
    r'^\["([a-z]+)"\]="([^"]*)",?$', open(R + r"\TTS_Diphone\Words.lua", encoding="utf8").read(), re.M)}

# ---- the corpus: entries (phoneme, word number, start, end); occurrence lists per unit ------------------------------------------
al = json.load(open(E + r"\out\align.json")); utt = {}
idx = collections.defaultdict(list)        # unit = (starts_word, phonemes, ends_word) -> [(utterance, first entry, length)]
for n, ps in al.items():
    seq = [("pau" if p[0] in ("pau", "sil", "") else ("AH0" if p[0] == "AH" and p[1] == "0" else p[0]), p[2], p[3], p[4]) for p in ps]
    utt[n] = seq; names = [s[0] for s in seq]
    for L in range(3, MAXP + 1):                                   # middle units: any run
        for i in range(len(names) - L + 1):
            t = tuple(names[i:i + L])
            if "pau" not in t: idx[(False, t, False)].append((n, i, L))
    i = 0
    while i < len(seq):                                            # edge units: runs at the start / end of a word
        if seq[i][0] == "pau": i += 1; continue
        j = i
        while j + 1 < len(seq) and seq[j + 1][0] != "pau" and seq[j + 1][1] == seq[i][1]: j += 1
        word = tuple(names[i:j + 1]); m = len(word)
        if m <= MAXP: idx[(True, word, True)].append((n, i, m))
        for L in range(2, min(MAXP, m - 1) + 1):
            idx[(True, word[:L], False)].append((n, i, L))
            idx[(False, word[m - L:], True)].append((n, j - L + 1, L))
        i = j + 1

# ---- which units: fewest-pieces plan of every word; units that many words share are cheaper -----------------------------------
top = [w.strip() for w in open(R + r"\tools\data\20k.txt", encoding="utf8")]
words = [(w, dic[w], 1.0 / (r + 1)) for r, w in enumerate(top[:N]) if w in dic and re.fullmatch(r"[a-z]+", w)]
freq = collections.Counter()
def unit_keys(p):
    n = len(p)
    for L in range(3, MAXP + 1):
        for i in range(n - L + 1): yield (False, tuple(p[i:i + L]), False)
    for L in range(2, min(MAXP, n - 1) + 1):
        yield (True, tuple(p[:L]), False); yield (False, tuple(p[n - L:]), True)
    if n <= MAXP: yield (True, tuple(p), True)
for w, p, wt in words:
    for k in unit_keys(p):
        if k in idx: freq[k] += wt
fmax = math.log(1 + max(freq.values()))
# a join in the middle of a vowel is audible, one in a consonant hardly (same table as Core.JOIN_AT in the engine)
PEN = {}
for v in "AA AE AH EH ER IH IY UH UW AO".split(): PEN[v] = 0.3
for v in "AH0 AW AY EY OW OY".split(): PEN[v] = 0.6
def disc(k): return 0.3 * math.log(1 + freq[k]) / fmax
used = collections.Counter()
for w, p, wt in words:
    n = len(p); INF = 1e9
    best = [INF] * (n + 1); prev = [None] * (n + 1)      # state i < n: at the middle of phoneme i after a clip; state n: the silence after the word
    def jp(i): return 0.5 * PEN.get(p[i], 0)
    def relax(j, c, frm, k):
        if c < best[j]: best[j] = c; prev[j] = (frm, k)
    relax(0, 1.0, -1, None)                               # diphone [_ p0]
    for L in range(2, min(MAXP, n - 1) + 1):              # start unit
        k = (True, tuple(p[:L]), False)
        if k in freq: relax(L - 1, 1.0 - disc(k), -1, k)
    if (True, tuple(p), True) in freq and n <= MAXP: relax(n, 1.0 - disc((True, tuple(p), True)), -1, (True, tuple(p), True))
    for i in range(n):
        if best[i] >= INF: continue
        if i + 1 < n: relax(i + 1, best[i] + 1 + jp(i), i, None)                  # diphone
        for L in range(3, MAXP + 1):                                              # middle unit
            j = i + L - 1
            if j < n:
                k = (False, tuple(p[i:j + 1]), False)
                if k in freq: relax(j, best[i] + 1 + jp(i) - disc(k), i, k)
        relax(n, best[i] + 1 + jp(i), i, None) if i == n - 1 else None            # diphone [p_last _]
        if n - i >= 2:                                                            # end unit
            k = (False, tuple(p[i:]), True)
            if k in freq: relax(n, best[i] + 1 + jp(i) - disc(k), i, k)
    j = n
    while j >= 0 and prev[j] is not None:
        frm, k = prev[j]
        if k is not None: used[k] += wt
        j = frm
        if j < 0: break
units = sorted(used, key=lambda k: -used[k])
kinds = collections.Counter(("whole" if a and b else "start" if a else "end" if b else "middle") for a, _, b in units)
print("words planned:", len(words), "; units needed:", len(units), dict(kinds), "; middle units by length:",
      dict(collections.Counter(len(t) for a, t, b in units if not a and not b)))

# ---- the recording to cut each unit from --------------------------------------------------------------------------------------
raw = {}
def rd(p):
    with wave.open(p) as f: return np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(np.float32)
def rawdb(n, t0, t1):
    if n not in raw: raw[n] = rd(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n)
    y = raw[n][int(t0 * SR):max(int(t1 * SR), int(t0 * SR) + 80)]
    return 20 * math.log10(math.sqrt(float((y ** 2).mean())) + 1)
def mid(s): return (s[2] + s[3]) / 2
# typical phoneme lengths of the engine (Core.lua MS, milliseconds): the diphone voice sets the tempo the units should fit
MS = dict(AA=120, AE=125, AH0=65, AH=95, AO=125, AW=140, AY=140, B=70, CH=105, D=65, DH=55, EH=100, ER=120, EY=130, F=95, G=70, HH=70,
          IH=80, IY=115, JH=105, K=75, L=80, M=80, N=75, NG=85, OW=130, OY=150, P=75, R=80, S=105, SH=110, T=70, TH=95, UH=90, UW=115,
          V=70, W=70, Y=65, Z=95, ZH=95)
def expected(k):
    a, t, b = k; d = sum(MS[p] for p in t) / 1000
    return d - (0 if a else MS[t[0]] / 2000) - (0 if b else MS[t[-1]] / 2000)
def span(sq, i, L, a, b):
    """start and end time of the unit in the recording: word edges use the phoneme's own edge, the rest the middle."""
    return (sq[i][2] if a else mid(sq[i])), (sq[i + L - 1][3] if b else mid(sq[i + L - 1]))
def pick(k):
    a, t, b = k; occ = idx[k]; L = len(t)
    durs = [span(utt[n], i, L, a, b)[1] - span(utt[n], i, L, a, b)[0] for n, i, _ in occ]
    med = max(float(np.median(durs)), 0.85 * expected(k))      # corpus speech is faster than the voice: fast, reduced words are hard to recognise
    best = None
    for (n, i, _), d in zip(occ, durs):
        sq = utt[n]; s = 2.0 * sum(1 for q in range(L - 1) if sq[i + q][1] != sq[i + q + 1][1])
        if a:   # word start: a clean pause before it is best
            s += 0.0 if (i == 0 or sq[i - 1][0] == "pau") else 1.0
        elif i == 0 or sq[i - 1][0] == "pau" or sq[i - 1][1] != sq[i][1]: s += 3     # cut in the middle of a phoneme at a word edge
        if b:
            s += 0.0 if (i + L >= len(sq) or sq[i + L][0] == "pau") else 1.0
        elif i + L >= len(sq) or sq[i + L][0] == "pau" or sq[i + L][1] != sq[i + L - 1][1]: s += 3
        top_db = max(rawdb(n, x[2], x[3]) for x in sq[i:i + L])
        if not a: s += 0.3 * max(0, top_db - rawdb(n, mid(sq[i]) - 0.01, mid(sq[i]) + 0.01) - 10)
        if not b: s += 0.3 * max(0, top_db - rawdb(n, mid(sq[i + L - 1]) - 0.01, mid(sq[i + L - 1]) + 0.01) - 10)
        r = math.log(max(d, 0.02) / max(med, 0.02))
        s += (8.0 if r < 0 else 3.0) * abs(r)                                      # tempo: too short (reduced, unclear) costs more than too long
        if best is None or s < best[0]: best = (s, n, i)
    return best[1], best[2]
choice = {k: pick(k) for k in units}
need = sorted({n for n, _ in choice.values()}); print("recordings to flatten:", len(need))

flat, pulses = {}, {}
for c, n in enumerate(need):
    snd = parselmouth.Sound(E + r"\corpus\cmu_us_slt_arctic\wav\%s.wav" % n); m = call(snd, "To Manipulation", 0.01, 75, 400)
    t = call("Create PitchTier", "f", snd.xmin, snd.xmax); call(t, "Add point", snd.xmin, F0); call(t, "Add point", snd.xmax, F0); call([t, m], "Replace pitch tier")
    o = call(m, "Get resynthesis (overlap-add)"); flat[n] = np.clip(o.values[0] * 32768.0, -32768, 32767)
    pp = call(o, "To PointProcess (periodic, cc)", 75, 400); pulses[n] = np.array([call(pp, "Get time from index", i + 1) for i in range(call(pp, "Get number of points"))])
    if c % 200 == 0: print("flattened", c, "of", len(need))
def snap(n, t):
    p = pulses[n]
    if len(p):
        j = np.abs(p - t).argmin()
        if abs(p[j] - t) <= 0.006: return int(round(p[j] * SR))
    return int(t * SR)
def band8(y, where):
    n = int(0.010 * SR); seg = y[:n] if where == "head" else y[-n:]
    if len(seg) < n: seg = np.pad(seg, (0, n - len(seg)))
    S = np.abs(np.fft.rfft(seg * np.hanning(n), 512)) ** 2; fr = np.fft.rfftfreq(512, 1 / SR)
    e = [100, 300, 600, 1000, 1600, 2500, 4000, 6000, 7900]
    return np.array([10 * np.log10(S[(fr >= e[i]) & (fr < e[i + 1])].mean() + 1e-3) for i in range(8)])
def q(arr): return "".join(chr(48 + int(min(41, max(0, round((x - LO_DB) / 2))))) for x in arr)
ref = []
for fn in sorted(os.listdir(E + r"\out2\wav"))[::40]:
    if fn.endswith("2.wav"): ref.append(float(np.sqrt((rd(E + "\\out2\\wav\\" + fn).astype(np.float64) ** 2).mean() + 1)))
tgt = float(np.median(ref)); print("loudness target %.0f" % tgt)

shutil.rmtree(OUT + r"\units", ignore_errors=True); os.makedirs(OUT + r"\units")
tmp = os.path.join(os.environ["TEMP"], "vc_arctic_units"); shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
jobs, table = [], []; stretched = 0
for k in units:
    a, t, b = k; n, i = choice[k]; L = len(t); sq = utt[n]
    s, e = span(sq, i, L, a, b)
    y = flat[n][(int(round(s * SR)) if a else snap(n, s)):(int(round(e * SR)) if b else snap(n, e))].copy()
    if len(y) < int(0.04 * SR): continue
    want = expected(k)
    if len(y) / SR < 0.8 * want:                           # still much shorter than the voice would say it: lengthen a little (flat pitch keeps it clean)
        snd = parselmouth.Sound(y / 32768.0, sampling_frequency=SR)
        y = np.clip(call(snd, "Lengthen (overlap-add)", 140, 300, min(1.3, 0.9 * want / (len(y) / SR))).values[0] * 32768.0, -32768, 32767)
        stretched += 1
    f = int(0.0025 * SR); y[:f] *= np.linspace(0, 1, f); y[-f:] *= np.linspace(1, 0, f)
    y = np.clip(y * min(2.0, max(0.5, tgt / float(np.sqrt((y ** 2).mean() + 1)))), -32768, 32767)
    key = ("00" if a else "") + "".join("%02d" % IX[p] for p in t) + ("00" if b else "")
    wav = os.path.join(tmp, key + ".wav")
    with wave.open(wav, "w") as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(y.astype(np.int16).tobytes())
    jobs.append((wav, os.path.join(OUT, "units", key + ".ogg")))
    table.append('["%s"]={%.3f,"%s","%s"},' % (key, len(y) / SR, q(band8(y, "head")), q(band8(y, "tail"))))
def enc(j): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", j[0], "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", j[1]], check=True)
with ThreadPoolExecutor(4) as ex: list(ex.map(enc, jobs))

open(OUT + r"\Units.lua", "w", encoding="utf8", newline="\n").write(
    "-- Generated by tools/build_arctic_units.py. Unit = phoneme indices (two digits each, as in the diphone names) -> { seconds, head spectrum, tail spectrum }.\n"
    "-- A middle unit runs from the middle of its first phoneme to the middle of its last one. A key starting with 00 is a unit that starts at the\n"
    "-- beginning of a word, one ending with 00 ends at the end of a word, 00...00 is a whole word. The file is units/<key>.ogg.\n"
    "TTS_ArcticUnitClips = {\n" + "\n".join(table) + "\n}\n"
    'TTS_Diphone.AddUnits("arctic", TTS_ArcticUnitClips, "Interface\\\\AddOns\\\\TTS_Arctic\\\\")\n')
size = sum(os.path.getsize(os.path.join(OUT, "units", f)) for f in os.listdir(OUT + r"\units"))
print("lengthened units:", stretched)
print("wrote %d units, %.1f MB (%.1f KB per unit, %.2f s audio)" % (len(jobs), size / 1048576, size / 1024 / len(jobs), sum(float(re.search(r'\{([\d.]+),', l).group(1)) for l in table)))
