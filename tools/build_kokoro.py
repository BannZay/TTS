# Builds the Kokoro voice: TTS_Kokoro (diphones) and TTS_KokoroHQ (units of up to 8 phonemes, up to 3 clips per unit for join-aware choice in the engine).
# Source: isolated words rendered by Kokoro from their dictionary phonemes (experiments\neural\scripts\gen_words_par.py) and aligned by
# align_par.py. The unit set is the fewest-pieces plan of the first N dictionary words (as in build_arctic_units.py).
#   experiments\neural\.venv\Scripts\python.exe -I tools\build_kokoro.py [N=20000] [variants=3] [--plan-only]
# Needs experiments\neural\out\align_20k.json, experiments\neural\out\fallback.json (coverage.py), the corpus wavs, the Arctic loudness reference
# in experiments\arctic\out2 and ffmpeg.
import json, re, os, sys, wave, subprocess, shutil, math, collections
from concurrent.futures import ThreadPoolExecutor
from multiprocessing import Pool
import numpy as np

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); E = R + r"\experiments\neural"; OUT_V = R + r"\TTS_Kokoro"; OUT_U = R + r"\TTS_KokoroHQ"
SR = 16000; LO_DB = 28.8     # LO_DB: band level offset of the spectra strings (same as the Arctic voice)
MAXP = 8; NCAND = 80; NFINAL = 2500; WHOLE_N = 14000   # WHOLE_N: only the most common words get a whole-word clip
PH = "AA AE AH0 AH AO AW AY B CH D DH EH ER EY F G HH IH IY JH K L M N NG OW OY P R S SH T TH UH UW V W Y Z ZH".split()
IX = {p: i + 1 for i, p in enumerate(PH)}
IX["pau"] = 0
PEN = {}
for v in "AA AE AH EH ER IH IY UH UW AO".split(): PEN[v] = 0.3
for v in "AH0 AW AY EY OW OY".split(): PEN[v] = 0.6
def wavpath(n):   # "i:<name>" = isolated word (phrase-final fall), else the word as a medial word of a phrase ("<word> and" cut at the word)
    return E + r"\corpus20k\wav\%s.wav" % n[2:] if n.startswith("i:") else E + r"\corpus20k_ctx\wav\%s.wav" % n


def load_corpus(align, prefix=""):
    al = json.load(open(E + r"\out\%s.json" % align)); words = {}
    for n, ps in al.items():
        seq = [("AH0" if p[0] == "AH" and p[1] == "0" else p[0], p[3], p[4]) for p in ps if p[0] not in ("pau", "sil", "") and p[2] == 0]   # word 0 only ("and" is the carrier)
        if seq: words[prefix + n] = seq
    return words


# ---- audio helpers (per process caches) --------------------------------------------------------------------------------------------
_raw, _f0, _pulses = {}, {}, {}
def raw(n):
    if n not in _raw:
        with wave.open(wavpath(n)) as f: _raw[n] = np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(np.float32)
    return _raw[n]
def rms_db(y): return 20 * math.log10(math.sqrt(float((y ** 2).mean())) + 1) if len(y) else 0.0
def seg_db(n, t0, t1):
    a = int(t0 * SR); return rms_db(raw(n)[a:max(int(t1 * SR), a + 80)])
def snd(n):
    import parselmouth
    return parselmouth.Sound(raw(n).astype(np.float64) / 32768.0, sampling_frequency=SR)
def f0track(n):
    if n not in _f0: _f0[n] = snd(n).to_pitch(time_step=0.005, pitch_floor=75, pitch_ceiling=450).selected_array["frequency"]
    return _f0[n]
def pulses(n):
    if n not in _pulses:
        from parselmouth.praat import call
        pp = call(snd(n), "To PointProcess (periodic, cc)", 75, 450)
        _pulses[n] = np.array([call(pp, "Get time from index", i + 1) for i in range(call(pp, "Get number of points"))])
    return _pulses[n]
def snap(n, t):
    p = pulses(n)
    if len(p):
        j = np.abs(p - t).argmin()
        if abs(p[j] - t) <= 0.006: return int(round(p[j] * SR))
    return int(t * SR)
def band8(y, where):
    k = int(0.010 * SR); seg = y[:k] if where == "head" else y[-k:]
    if len(seg) < k: seg = np.pad(seg, (0, k - len(seg)))
    S = np.abs(np.fft.rfft(seg * np.hanning(k), 512)) ** 2; fr = np.fft.rfftfreq(512, 1 / SR)
    e = [100, 300, 600, 1000, 1600, 2500, 4000, 6000, 7900]
    return np.array([10 * np.log10(S[(fr >= e[i]) & (fr < e[i + 1])].mean() + 1e-3) for i in range(8)])
def spec(y, n, t, where):
    """10 chars: 8 spectral bands (2 dB steps) and 2 pitch chars (semitones above 60 Hz, 0 = unvoiced) of the clip edge."""
    f = f0track(n); v = f[min(len(f) - 1, max(0, int(t / 0.005)))]
    st = int(min(41, max(1, round(12 * math.log2(v / 60.0))))) if v > 0 else 0
    return "".join(chr(48 + int(min(41, max(0, round((x - LO_DB) / 2))))) for x in band8(y, where)) + chr(48 + st) * 2


def cut_span(seq, i, L, a, b):
    """Start and end time of the unit made of phones i..i+L-1: word edges use the phone's own edge, the rest the middle."""
    s = seq[i][1] if a else (seq[i][1] + seq[i][2]) / 2
    e = seq[i + L - 1][2] if b else (seq[i + L - 1][1] + seq[i + L - 1][2]) / 2
    return s, e


# ---- the choice of clips for a unit (runs in worker processes) ---------------------------------------------------------------------
W = None; TGT = 3000.0
def init(tgt):
    global W, TGT
    W = load_corpus("align_20k_ctx"); W.update(load_corpus("align_20k", "i:")); TGT = tgt
def make_clip(n, s, e, a, b):
    ss = int(round(s * SR)) if a else snap(n, s); ee = int(round(e * SR)) if b else snap(n, e)
    y = raw(n)[ss:ee].copy()
    if len(y) < int(0.02 * SR): return None
    if a or b:                                             # word edges: cut the leftover silence, keep 5 ms (the engine sets the pause between words)
        loud = np.where(np.abs(y) > 0.03 * np.abs(y).max())[0]
        if len(loud): y = y[max(0, loud[0] - 80) if a else 0:min(len(y), loud[-1] + 80) if b else len(y)]
    f = int(0.0025 * SR); y[:f] *= np.linspace(0, 1, f); y[-f:] *= np.linspace(1, 0, f)
    return np.clip(y * min(2.5, max(0.4, TGT / float(np.sqrt((y ** 2).mean() + 1)))), -32768, 32767)
def choose(job):
    """job = (key, occurrences [(word, first phone, length)], variants). Returns [(variant letter index, wav int16 bytes, seconds, head, tail)]."""
    key, occ, nvar = job; a, t, b = key; L = len(t)
    if len(occ) > NCAND:                                   # an even sample across the lengths
        occ = sorted(occ, key=lambda o: (lambda s: s[1] - s[0])(cut_span(W[o[0]], o[1], L, a, b)))
        occ = [occ[int(x)] for x in np.linspace(0, len(occ) - 1, NCAND)]
    durs = []
    for n, i, _ in occ:
        s, e = cut_span(W[n], i, L, a, b); durs.append(e - s)
    med = float(np.median(durs)); scored = []
    for (n, i, _), d in zip(occ, durs):
        sq = W[n]; s, e = cut_span(sq, i, L, a, b)
        top = max(seg_db(n, x[1], x[2]) for x in sq[i:i + L]); c = 0.0
        if not a: c += 0.3 * max(0, top - seg_db(n, (sq[i][1] + sq[i][2]) / 2 - 0.01, (sq[i][1] + sq[i][2]) / 2 + 0.01) - 10)
        if not b:
            m = (sq[i + L - 1][1] + sq[i + L - 1][2]) / 2; c += 0.3 * max(0, top - seg_db(n, m - 0.01, m + 0.01) - 10)
        r = math.log(max(d, 0.02) / max(med, 0.02)); c += (6.0 if r < 0 else 3.0) * abs(r)    # too short (reduced, unclear) costs more than too long
        scored.append((c, n, i, s, e))
    scored.sort(); feats = []
    for c, n, i, s, e in scored[:max(nvar * 4, 8)]:
        y = make_clip(n, s, e, a, b)
        if y is None: continue
        feats.append((c, n, y, spec(y, n, s, "head"), spec(y, n, e, "tail"), len(y) / SR))
    if not feats: return []
    def vec(f): return np.array([ord(ch) for ch in f[3] + f[4]], float)
    chosen = [feats[0]]
    while len(chosen) < min(nvar, len(feats)):             # next: the candidate most different at its edges from those already chosen
        best = max((f for f in feats if f not in chosen), key=lambda f: min(np.abs(vec(f) - vec(g)).mean() for g in chosen) - 0.5 * f[0])
        chosen.append(best)
    return [(v, f[2].astype(np.int16).tobytes(), f[5], f[3], f[4]) for v, f in enumerate(chosen)]


def build_index(words):
    units = collections.defaultdict(list); dip = collections.defaultdict(list)
    for n, seq in words.items():
        names = [s[0] for s in seq]; m = len(names)
        for L in range(3, MAXP + 1):
            for i in range(m - L + 1): units[(False, tuple(names[i:i + L]), False)].append((n, i, L))
        for L in range(2, min(MAXP, m - 1) + 1):
            units[(True, tuple(names[:L]), False)].append((n, 0, L)); units[(False, tuple(names[m - L:]), True)].append((n, m - L, L))
        if 2 <= m <= MAXP: units[(True, tuple(names), True)].append((n, 0, m))
        for i in range(m - 1): dip[(False, (names[i], names[i + 1]), False)].append((n, i, 2))
        dip[(True, (names[0],), False)].append((n, 0, 1)); dip[(False, (names[-1],), True)].append((n, m - 1, 1))
    return units, dip


def plan_units(idx, N):
    dic = {m.group(1): [PH[ord(c) - 49] for c in m.group(2) if c not in "^~"] for m in re.finditer(
        r'^\["([a-z]+)"\]="([^"]*)",?$', open(R + r"\TTS_Diphone\Words.lua", encoding="utf8").read(), re.M)}
    top = [w.strip() for w in open(R + r"\tools\data\20k.txt", encoding="utf8")]
    words = [(w, dic[w], 1.0 / (r + 1)) for r, w in enumerate(top[:N]) if w in dic and re.fullmatch(r"[a-z]+", w)]
    freq = collections.Counter()
    def unit_keys(p):
        n = len(p)
        for L in range(3, MAXP + 1):
            for i in range(n - L + 1): yield (False, tuple(p[i:i + L]), False)
        for L in range(2, min(MAXP, n - 1) + 1):
            yield (True, tuple(p[:L]), False); yield (False, tuple(p[n - L:]), True)
        if 2 <= n <= MAXP: yield (True, tuple(p), True)
    for rank, (w, p, wt) in enumerate(words):
        for k in unit_keys(p):
            if k[0] and k[2] and rank >= WHOLE_N: continue     # a rare word is not kept whole (size): it is built from units
            if k in idx: freq[k] += wt
    fmax = math.log(1 + max(freq.values()))
    def disc(k): return 0.3 * math.log(1 + freq[k]) / fmax
    used = collections.Counter(); INF = 1e9
    for w, p, wt in words:
        n = len(p); best = [INF] * (n + 1); prev = [None] * (n + 1)
        def jp(i): return 0.5 * PEN.get(p[i], 0)
        def relax(j, c, frm, k):
            if c < best[j]: best[j] = c; prev[j] = (frm, k)
        relax(0, 1.0, -1, None)
        for L in range(2, min(MAXP, n - 1) + 1):
            k = (True, tuple(p[:L]), False)
            if k in freq: relax(L - 1, 1.0 - disc(k), -1, k)
        if n >= 2 and n <= MAXP and (True, tuple(p), True) in freq: relax(n, 1.0 - disc((True, tuple(p), True)), -1, (True, tuple(p), True))
        for i in range(n):
            if best[i] >= INF: continue
            if i + 1 < n: relax(i + 1, best[i] + 1 + jp(i), i, None)
            for L in range(3, MAXP + 1):
                j = i + L - 1
                if j < n:
                    k = (False, tuple(p[i:j + 1]), False)
                    if k in freq: relax(j, best[i] + 1 + jp(i) - disc(k), i, k)
            if i == n - 1: relax(n, best[i] + 1 + jp(i), i, None)
            if n - i >= 2:
                k = (False, tuple(p[i:]), True)
                if k in freq: relax(n, best[i] + 1 + jp(i) - disc(k), i, k)
        j = n
        while j >= 0 and prev[j] is not None:
            frm, k = prev[j]
            if k is not None: used[k] += wt
            j = frm
            if j < 0: break
    return sorted(used, key=lambda k: -used[k]), used, words


def ukey(k):
    a, t, b = k
    return ("00" if a else "") + "".join("%02d" % IX[p] for p in t) + ("00" if b else "")


if __name__ == "__main__":
    nums = [x for x in sys.argv[1:] if not x.startswith("--")]
    N = int(nums[0]) if nums else 20000; NVAR = int(nums[1]) if len(nums) > 1 else 3
    words = load_corpus("align_20k_ctx"); uidx, didx = build_index(words)
    iuidx, _ = build_index(load_corpus("align_20k", "i:"))      # isolated words: only their endings are used (phrase-final fall)
    units, used, dwords = plan_units(uidx, N); nw = len(dwords)
    kinds = collections.Counter(("whole" if a and b else "start" if a else "end" if b else "middle") for a, _, b in units)
    print("corpus words", len(words), "| dictionary words planned", nw, "| units", len(units), dict(kinds), "| diphone keys", len(didx))
    est = 0
    for k in units: est += min(NVAR, max(1, len(uidx[k]))) * (0.045 + 0.075 * len(k[1]) ) * 16000 * 2 * 0.17 / 1.0   # ~ogg bytes
    print("rough size: %.0f MB (%d variants)" % (est / 1048576, NVAR))
    if "--plan-only" in sys.argv: sys.exit()

    ref = []
    for fn in sorted(os.listdir(R + r"\experiments\arctic\out2\wav"))[::40]:
        if fn.endswith("2.wav"):
            with wave.open(R + "\\experiments\\arctic\\out2\\wav\\" + fn) as f: ref.append(float(np.sqrt((np.frombuffer(f.readframes(f.getnframes()), np.int16).astype(np.float64) ** 2).mean() + 1)))
    tgt = float(np.median(ref)); print("loudness target %.0f" % tgt)
    tmp = os.path.join(os.environ["TEMP"], "vc_kokoro"); shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
    for d in (OUT_V, OUT_U): shutil.rmtree(d, ignore_errors=True)
    os.makedirs(OUT_V + r"\diphones"); os.makedirs(OUT_U + r"\units")

    def run(keys, idx, nvar, label):
        jobs = [(k, idx[k], 1 if (k[0] and k[2] and len(k[1]) > 1) else nvar) for k in keys]; res = {}
        with Pool(min(16, os.cpu_count()), initializer=init, initargs=(tgt,)) as p:
            for c, (k, r) in enumerate(zip(keys, p.imap(choose, jobs, chunksize=8))):
                res[k] = r
                if c % 2000 == 0: print(label, c, "of", len(keys), flush=True)
        return res
    dkeys = [k for k in didx]
    dres = run(dkeys, didx, 2, "diphones")
    ures = run(units, uidx, NVAR, "units")
    # endings for the last word of a phrase: the end units of the plan plus the most used last 2 to 4 phonemes of the dictionary words
    # (a word the plan keeps whole has no end unit of its own, but its ending is shared with many others)
    endf = collections.Counter()
    for w, p, wt in dwords:
        for L in range(2, min(4, len(p) - 1) + 1): endf[(False, tuple(p[len(p) - L:]), True)] += wt
    fset = {k for k in units if k[2] and not k[0]} | {k for k, _ in endf.most_common(NFINAL)}
    # No phrase-final endings (<key>f clips): they are cut from words said alone and run about 35% longer than the same ending
    # mid-phrase, so the last word sounded slower. Set WITH_FINAL to build them again.
    WITH_FINAL = False
    fkeys = [k for k in fset if k in iuidx] if WITH_FINAL else []
    fres = run(fkeys, iuidx, 1, "final")                 # whole words have no join inside: one clip is enough

    encode = []; dlines = []; ulines = []
    # diphone names: two 2-digit phone indices, silence = 00; the clip name adds 2 (best) or 4 (second candidate)
    for k, r in dres.items():
        a, t, b = k
        key = "00%02d" % IX[t[0]] if a else ("%02d00" % IX[t[0]] if b else "%02d%02d" % (IX[t[0]], IX[t[1]]))
        for v, data, sec, head, tail in r:
            name = key + ("2" if v == 0 else "4"); fn = os.path.join(tmp, name + ".raw")
            open(fn, "wb").write(data); encode.append((fn, os.path.join(OUT_V, "diphones", name + ".ogg")))
            dlines.append((name, '["%s"]={%.3f,"%s","%s"},' % (name, sec, head, tail)))
    for k, r in ures.items():
        for v, data, sec, head, tail in r:
            name = ukey(k) + ("", "b", "c", "d")[v]; fn = os.path.join(tmp, name + ".raw")
            open(fn, "wb").write(data); encode.append((fn, os.path.join(OUT_U, "units", name + ".ogg")))
            ulines.append((name, '["%s"]={%.3f,"%s","%s"},' % (name, sec, head, tail)))
    for k, r in fres.items():                                  # endings for the last word of a phrase: <key>f, <key>fb
        for v, data, sec, head, tail in r:
            name = ukey(k) + ("f", "fb", "fc")[v]; fn = os.path.join(tmp, name + ".raw")
            open(fn, "wb").write(data); encode.append((fn, os.path.join(OUT_U, "units", name + ".ogg")))
            ulines.append((name, '["%s"]={%.3f,"%s","%s"},' % (name, sec, head, tail)))
    def enc(j): subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", j[0], "-c:a", "libvorbis", "-q:a", "5", j[1]], check=True)
    with ThreadPoolExecutor(12) as ex: list(ex.map(enc, encode))

    have = {l[0][:4] for l in dlines}
    fb = json.load(open(E + r"\out\fallback.json")); alias = []
    for ab, cd in sorted(fb.items()):
        a, b = ab.split(); c, d = cd.split(); ka = "%02d%02d" % (IX[a], IX[b]); kc = "%02d%02d" % (IX[c], IX[d])
        if ka not in have and kc in have: alias.append('["%s"]="%s"' % (ka, kc))
    dlines.sort(); ulines.sort()
    open(OUT_V + r"\Diphones.lua", "w", encoding="utf8", newline="\n").write(
        "-- Generated by tools/build_kokoro.py from Kokoro (af_heart) words rendered from their dictionary phonemes.\n"
        "-- clip name = diphone key (two 2-digit phoneme indices) + 2 (best candidate) or 4 (second candidate) -> { seconds, head spectrum, tail spectrum }\n"
        "-- spectrum = 8 bands (2 dB steps) and 2 pitch chars (semitones above 60 Hz, 0 = unvoiced) of the first / last 10 ms\n"
        "TTS_KokoroClips = {\n" + "\n".join(l[1] for l in dlines) + "\n}\n"
        "TTS_KokoroAlias = {\n" + ",\n".join(alias) + "\n}\n"
        'TTS_Diphone.RegisterVoice("kokoro", { name = "Kokoro", gender = "female", quality = "natural", unitsAddon = { "TTS_KokoroHQ", "TTS_KokoroHQ_Endings" }, wordGaps = { func = 0, content = 0.025 }, clips = TTS_KokoroClips, alias = TTS_KokoroAlias, base = "Interface\\\\AddOns\\\\TTS_Kokoro\\\\" })\n')
    open(OUT_V + r"\TTS_Kokoro.toc", "w", encoding="utf8", newline="\n").write("""## Interface: 30300
## Title: TTS Kokoro voice
## Notes: Natural female voice (Kokoro neural voice, cut into diphones).
## Author: BannZay
## Version: 1.0
## X-License: MIT
## X-Website: https://github.com/BannZay/TTS
## LoadOnDemand: 1
## Dependencies: TTS_Diphone
## X-LibTTS-Provider: kokoro
## X-LibTTS-Name: Kokoro (female, natural)
## X-LibTTS-Extension: TTS_KokoroHQ
## X-LibTTS-Language: en
## X-LibTTS-Gender: female
## X-LibTTS-Features: speed, pause

Diphones.lua
""")
    open(OUT_U + r"\Units.lua", "w", encoding="utf8", newline="\n").write(
        "-- Generated by tools/build_kokoro.py. Unit = phoneme indices (two digits each) -> { seconds, head spectrum, tail spectrum }; a letter b, c, d after the key\n"
        "-- is another clip of the same unit (the engine picks the one that joins best). A key starting with 00 starts at the beginning of a word, one ending with 00\n"
        "-- ends at the end of a word, 00...00 is a whole word. The file is units/<key>.ogg.\n"
        "TTS_KokoroUnitClips = {\n" + "\n".join(l[1] for l in ulines) + "\n}\n"
        'TTS_Diphone.AddUnits("kokoro", TTS_KokoroUnitClips, "Interface\\\\AddOns\\\\TTS_KokoroHQ\\\\")\n')
    open(OUT_U + r"\TTS_KokoroHQ.toc", "w", encoding="utf8", newline="\n").write("""## Interface: 30300
## Title: TTS Kokoro voice HQ
## Notes: Optional high quality: longer units (up to 8 phonemes, also at word starts and ends, several clips each) for the Kokoro voice, fewer joins.
## Author: BannZay
## Version: 1.0
## X-License: MIT
## X-Website: https://github.com/BannZay/TTS
## LoadOnDemand: 1
## Dependencies: TTS_Diphone, TTS_Kokoro

Units.lua
""")
    for d in (OUT_V, OUT_U): open(d + r"\CREDITS.txt", "w", encoding="utf8").write(
        "Voice: Kokoro-82M (af_heart), Apache License 2.0, https://huggingface.co/hexgrad/Kokoro-82M\n"
        "The clips are audio generated with this model, then cut into units, level-adjusted and re-encoded to Ogg Vorbis.\n"
        "A copy of the Apache License 2.0 is in LICENSE-Apache-2.0.txt.\n"
        "The model card names CC BY audio in the Kokoro v1.0 training data: Koniwa tnc (CC BY 3.0) and SIWIS (CC BY 4.0).\n"
        "Phonemes: CMU Pronouncing Dictionary. Clips were rendered from dictionary pronunciations and cut into diphones and units by tools/build_kokoro.py.\n"
        "\nCMU Pronouncing Dictionary licence:\n\n" + open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "cmudict.LICENSE"), encoding="utf8").read())
    for d in (OUT_V, OUT_U): shutil.copy(os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "LICENSE-Apache-2.0.txt"), d)
    sz = lambda d: sum(os.path.getsize(os.path.join(d, f)) for f in os.listdir(d)) / 1048576
    print("TTS_Kokoro: %d clips, %.1f MB | TTS_KokoroHQ: %d clips, %.1f MB | alias %d" % (len(dlines), sz(OUT_V + r"\diphones"), len(ulines), sz(OUT_U + r"\units"), len(alias)))


