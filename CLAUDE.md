# TTS and LibTTS

Pseudo text-to-speech for WoW 3.3.5a, built from prerecorded diphone clips.

## Layout

| Folder | Role |
|---|---|
| `LibTTS-1.0/` | Git submodule, the library (source of truth, repo `BannZay/LibTTS-1.0`). API in `LibTTS-1.0/docs/LibTTS.md` |
| `TTS_Diphone/` | Shared LoD engine: dictionary, letter-to-sound, rhythm. Provider side. Voice API in `docs/TTS_Diphone.md` |
| `TTS/` | Consumer: reads chat aloud. Embeds the library in `Libs/` |
| `TTS_Arctic`, `TTS_Kal` | Voice addons (LoD), depend on the engine. Arctic includes longer units (`Units.lua`, up to 8 phonemes, built by `tools/build_arctic_units.py`); Kal includes three clip lengths (`tools/build_kal.ps1`) |
| `TTS_KokoroHQ_Endings` | Optional falling endings (`00f` clips) for the last word of a sentence (LoD), built by `tools/build_kokoro_endings.py` from `experiments/kokoro_final_units`. Loaded by the voice after `TTS_KokoroHQ` (`unitsAddon` list) |
| `tools/`, `experiments/` | Generators and research, not shipped |

The addons ship the committed copies in `Libs/`, and the tests load `TTS/Libs/`. To change the library: edit it in `LibTTS-1.0/`, run `tools/sync_libs.ps1`, run its test (`LibTTS-1.0/tests/test_libtts.lua`) and the tests here, commit and push in the submodule, then commit the new submodule pointer and the copies here. `test_tts.lua` fails if a copy is stale. CI does not check out the submodule.

## Tests

Run from `tests/`, no game needed:

```powershell
Get-ChildItem test_*.lua | ForEach-Object { lua $_.Name }
```

`test_tts.lua` runs the real addons end to end and reads the real TOC files. `render_plan.lua "text" arctic` prints the clip plan; `VC_SPEED` sets the speed option (it scales the pauses too; `pause` is a second setting for pauses only).

## Non-obvious facts

- The client cannot stop, time or set the volume of a script sound, so playback runs on known durations. See "Client limits" in the library docs.
- Clip names are the diphone key plus a digit: 1 short, 2 normal, 3 long, 4 second candidate. Only a voice with `speedClips` (Kal) changes the pace with speed; others change only the pauses (`pausesOnly` on the feature).
- Windows reserved names (con, prn, aux, nul) cannot be file names.

## Release

One GitHub release per version with five zips: `KokoroHQ`, `Kokoro`, `Arctic`, `Kal`, `All` (every voice). Each holds `TTS`, `TTS_Diphone` and its voice folders (an HQ zip includes the base voice). All shipped folders have the same version. The list is `VARIANTS` in `.github/workflows/release.yml`. `TTS_KokoroHQ_Endings` stays in the repository only. Zips are named `TTS-<name>.zip` without a version, because the README links to `releases/latest/download/`.
