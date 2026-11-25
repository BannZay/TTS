# TTS for WoW 3.3.5a

Reads chat aloud. The 3.3.5 client has no text-to-speech, so TTS plays short prerecorded voice clips one after another. It handles any English word. You choose the voice when you download.

## Install

Download one zip (the links below get the latest version; older ones are on the [releases page](https://github.com/BannZay/TTS/releases)) and extract it into `Interface\AddOns`. Each zip is complete on its own:

| Zip | Size | Voice | Folders besides `TTS` and `TTS_Diphone` | Sample |
|---|---|---|---|---|
| [`TTS-KokoroHQ`](https://github.com/BannZay/TTS/releases/latest/download/TTS-KokoroHQ.zip) | ~125 MB | Neural female voice, with longer units and fewer joins | `TTS_Kokoro`, `TTS_KokoroHQ` | https://github.com/user-attachments/assets/28e6e4a4-a540-4249-9594-fbab37131d41 |
| [`TTS-Kokoro`](https://github.com/BannZay/TTS/releases/latest/download/TTS-Kokoro.zip) | ~8 MB | The same voice without the longer units, a much smaller download | `TTS_Kokoro` | https://github.com/user-attachments/assets/b74006c4-70ef-4d5d-ae37-2eeb768e74a5 |
| [`TTS-Arctic`](https://github.com/BannZay/TTS/releases/latest/download/TTS-Arctic.zip) | ~60 MB | Female voice cut from human recordings | `TTS_Arctic` | https://github.com/user-attachments/assets/0f9d4868-7fee-4bb1-9e37-28fe780ea696 |
| [`TTS-Kal`](https://github.com/BannZay/TTS/releases/latest/download/TTS-Kal.zip) | ~20 MB | Male robotic voice | `TTS_Kal` | https://github.com/user-attachments/assets/15359196-fd3a-4a36-953b-3e88731c1a76 |
| [`TTS-All`](https://github.com/BannZay/TTS/releases/latest/download/TTS-All.zip) | ~200 MB | All the voices, the largest download | `TTS_Kokoro`, `TTS_KokoroHQ`, `TTS_Arctic`, `TTS_Kal` | |

To have several voices, extract several zips into the same folder, then pick a voice in the options.

All samples say the same five phrases, rendered offline from the clips the addon would play.

Restart the client if it was running: it only finds new addons and sound files at startup.

### Addons

| Folder | What it is |
|---|---|
| `TTS` | The addon: reads chat, options |
| `TTS_Diphone` | Speech engine and pronunciation dictionary, used by every voice |
| `TTS_Kokoro` | Kokoro voice (neural, female) |
| `TTS_KokoroHQ` | Longer units for Kokoro, with fewer joins |
| `TTS_KokoroHQ_Endings` | Optional falling sentence endings for Kokoro HQ, see below |
| `TTS_Arctic` | Arctic voice (human recordings, female) |
| `TTS_Kal` | Kal voice (robotic, male) |

### Optional: falling sentence endings

`TTS_KokoroHQ_Endings` gives the last word of a sentence a falling tone when "Alter last word" is on. It works with the `TTS-KokoroHQ` voice and is not in any release zip. To use it, copy the folder from [this repository](https://github.com/BannZay/TTS) into `Interface\AddOns`. Without it, the option only changes the length of the last word.

## Use

Options are under Interface -> AddOns -> TTS, or `/tts options`.

| Command | Effect |
|---|---|
| `/tts help` | List the commands |
| `/tts on`, `/tts off` | Enable or disable |
| `/tts stop` | Stop speaking |
| `/tts test <text>` | Say the text |
| `/tts speed <0.6-1.6>` | Speaking speed |
| `/tts pause <0.5-4>` | Length of pauses |
| `/tts ending full`, `rhythm`, `off` | How the last word of a sentence is read |
| `/tts say`, `party`, `raid`, `guild`, `officer`, `battleground`, `channel`, `whisper`, `emote` | Toggle reading a chat channel |
| `/tts own`, `names`, `expand`, `muteCombat` | Toggle: my own messages, say who speaks, expand chat words, mute in combat |

By default it reads say, yell, party and whispers from other players.

The options also have:

- **Chat channels**: what is read, skipping repeated messages, and dropping messages that waited too long.
- **Word replacements**: how chat words and symbols are read.
- **Banned phrases**: words that are masked or left out of the speech.
- **Voice preview**: hear a phrase with each installed voice.

The voice you pick is also used by other addons built on LibTTS, unless they choose their own.

## Limits

- The client cannot stop a sound that has started. After Stop, the current clip still finishes.
- Clips play in the Sound Effects channel. Their volume is the game's Sound Effects volume.
- With the Kokoro voice, the speed setting changes the pauses, not the pace of the words.
- English only.

## For addon authors

TTS is built on [LibTTS-1.0](https://github.com/BannZay/LibTTS-1.0), a small library that connects addons that speak with addons that supply voices. Voices for the diphone engine are described in [docs/TTS_Diphone.md](docs/TTS_Diphone.md).

## Development

The library is a git submodule; the addons carry committed copies of it. Fetch it with `git submodule update --init`.

Tests need Lua 5.1 and no game. Run them from `tests/`:

```powershell
Get-ChildItem test_*.lua | ForEach-Object { lua $_.Name }
```

The generated voice clips are committed. Some of the scripts in `tools/` that built them need research data that is not in the repository (`experiments/`, `tools/data/20k.txt`), so those voices cannot be rebuilt from a clone alone.

## Licence

The code is under the [MIT licence](LICENSE). Voice clips, dictionary and letter-to-sound data come from third parties and keep their own terms; see the `CREDITS.txt` file in each addon folder. The Kokoro model that rendered the voice is [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), Apache License 2.0; its licence text ships with the voice folders.
