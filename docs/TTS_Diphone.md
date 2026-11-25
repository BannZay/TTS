# TTS_Diphone voices

`TTS_Diphone` is the engine behind the voice addons of this repository. It is a [LibTTS](https://github.com/BannZay/LibTTS-1.0/blob/main/docs/LibTTS.md) provider.

## Diphone voices

`TTS_Diphone` is a shared engine holding the dictionary, letter-to-sound rules and rhythm logic. A voice addon depends on it, supplies clips, and calls:

```lua
TTS_Diphone.RegisterVoice("myvoice", { name = "My voice", clips = clips, base = "Interface\\AddOns\\MyVoice\\",
    alias = alias, gender = "female", quality = "natural" })
```

Optional fields of `RegisterVoice`:

- `speedClips = true`: the voice has clips of several lengths (name ends 1 short, 2 normal, 3 long), so the speed option changes the pace, not only the pauses.
- `unitsAddon`: an addon with longer units, loaded with the voice (`TTS_Diphone.AddUnits`), or a list of such addons, loaded in order. A unit key may have more clips, named key plus `b`, `c` or `d`. The engine picks the clip that joins best with its neighbours. Several addons are merged: each clip is played from the folder of the addon that added it.
- The `ending` option (`full`, `rhythm`, `off`; "Alter last word" in the options, `/tts ending`) is for the last word of a sentence. `off`: the word like any other. `rhythm`: its last syllable is stretched. `full`: stretched, and if the voice has phrase-final ending clips (units named key plus `00f`, `00fb`, `00fc`, cut from words said alone, so with a falling pitch) the word is built from the units before and one of them.
- `TTS_KokoroHQ_Endings` (optional, LoD, loaded with the Kokoro voice) holds those clips for Kokoro. The clips come from words said alone and ran about 35% longer than the same ending mid-phrase, so `tools/build_kokoro_endings.py` speeds each stored clip up by 1.35 (ffmpeg `atempo`, pitch kept) and writes the new lengths into `Units.lua`. It depends only on the voice, not on `TTS_KokoroHQ`. Without it `full` behaves like `rhythm`: the checkbox then only changes the length, and its tooltip says so. Not tested in the game: how the sped-up endings sound (only the plan and the lengths are tested offline).
- `wordGaps = { func = seconds, content = seconds }`: for clips cut tight at the word edges. The pause after a function word (a, the, will, to, I and so on) is `func`, after any other word `content`, instead of one fixed word pause. Commas and sentence ends keep their pauses. The `pause` option scales all of them.

## Whole-word voices

A voice can record common words and leave the rest to a diphone voice. Pronunciation of unknown words, numbers, abbreviations and pauses all stay in the shared engine, so the two sources join in one sentence.

```lua
TTS_Diphone.RegisterWordVoice("mywords", {
    name = "Common words",
    base = "Interface\\AddOns\\MyWords\\",     -- clips are in <base>words\<file>.ogg
    fallback = "arctic",                       -- optional; otherwise the first diphone voice
    words = {
        hello = 0.41,                          -- seconds; the file is words\hello.ogg
        ["don't"] = 0.33,
        con = { 0.29, "con_" },                -- { seconds, file } when the word cannot be a file name
        morning = { { 0.2, "morning-1" }, { 0.1, "morning-2" } },   -- a word made of several clips, played in order
    },
})
```

The addon needs `## Dependencies: TTS_Diphone`. Keys are lower case. Windows reserves `con`, `prn`, `aux` and `nul` as file names.

- **Lookup:** a recorded word is used first, even for abbreviations that would otherwise be spelled out. Expansions and numbers are checked word by word, so `u` plays the `you` clip.
- **Fallback:** a request can pick another diphone voice with `fallback = "kal"`. If no diphone voice is available, the request fails with `no_fallback_voice`.
- **Speed:** clips have one length, so speed changes only the pauses around them. Fallback words still change.
- **Sound:** for natural joins, record the words with the same speaker as the fallback voice.
