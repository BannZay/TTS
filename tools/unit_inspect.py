import os
exec(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "unit_demo.py"), encoding="utf-8-sig").read().split("for word in sys.argv[2:]:")[0].replace("K = int(sys.argv[1])", "K = 1000"))
for t in [("R","AH0","L"), ("L","AY","N"), ("P","AH","B","L","IH")]:
    L = len(t); occ = min(idx[t], key=lambda o: score(o, L, True, True))
    n, i = occ; sq = utt[n][i:i + L]; prep(n)
    print(t, "->", n, [(s[0], s[1], round(s[2], 2), round(s[3], 2)) for s in sq])
    a = (sq[0][2] + sq[0][3]) / 2; b = (sq[-1][2] + sq[-1][3]) / 2; y = flat[n][int(a * SR):int(b * SR)]
    fr = [20 * np.log10(np.sqrt((y[k:k + 160] ** 2).mean()) + 1) for k in range(0, len(y) - 160, 160)]
    print("   frame levels dB (10 ms):", [int(x) for x in fr], "word ids", [s[1] for s in sq])
