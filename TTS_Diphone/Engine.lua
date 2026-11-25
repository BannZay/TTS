-- Shared engine of the diphone voices: pronunciation and rhythm come from here, a voice addon supplies only its clips.
local TTS = LibStub("LibTTS-1.0")
local Core = TTS_DiphoneCore

TTS_Diphone = { voices = {} }
local Engine = TTS_Diphone

-- Without clips of several lengths the speed feature changes only the pauses (see the LibTTS docs).
local function features(pausesOnly)
    return {
        speed = { min = 0.6, max = 1.6, default = 1, pausesOnly = pausesOnly },
        pause = { min = 0.5, max = 4, default = 1 },   -- scales every pause: between words (small ones too), commas, sentences
        ending = { values = { "full", "rhythm", "off" }, default = "full" },   -- last word of a sentence: falling ending units and stretch / stretch only / treated like any word
        basic = true,   -- true: ignore the units addon's clips, to compare a voice with and without it
    }
end

-- def = { name, clips = {clip name = seconds or {seconds, head, tail}}, base = addon folder, optional: alias, gender, quality,
--         unitsAddon = name of an optional addon with longer units, loaded right after the voice (see AddUnits),
--         speedClips = true: the clips come in several lengths (name ends 1, 2, 3), so speed picks among them,
--         wordGaps = { func = seconds, content = seconds }: pause after a function word / a content word instead of the one default word pause,
--         for clips cut tight at the word edges }
function Engine.RegisterVoice(id, def)
    local voice = { words = _G.TTS_DiphoneWords, letters = TTS_DiphoneLetters, lts = TTS_DiphoneLTS,
        diphones = def.clips, alias = def.alias, base = def.base, wordGaps = def.wordGaps, speedClips = def.speedClips }
    Engine.voices[id] = voice
    TTS:RegisterProvider(id, {
        name = def.name, language = "en", gender = def.gender, quality = def.quality, features = features(not def.speedClips),
        Synthesize = function(_, text, options) return Core.Tokenize(text, voice, options) end,
    })
    if def.unitsAddon and LoadAddOn then   -- one addon name or a list, loaded in order; absent or disabled: the voice just keeps using diphones
        local list = type(def.unitsAddon) == "table" and def.unitsAddon or { def.unitsAddon }
        for _, addon in ipairs(list) do pcall(LoadAddOn, addon) end
    end
end

-- Adds longer units (3 to 6 phonemes, key = phoneme indices of two digits each, entry = seconds or { seconds, head, tail }) to
-- a registered voice. The files are <base>units\<key>.ogg. A unit may have more clips: entries <key>b, <key>c, <key>d (the engine picks the best join).
-- A voice may have several units addons: later ones are merged in, each entry keeping the folder of its own addon (voice.unitBase).
function Engine.AddUnits(id, units, base)
    local voice = Engine.voices[id]
    if not voice then return end
    if not voice.units then voice.units, voice.unitsBase = units, base; return end
    local merged, bases = {}, voice.unitBase or {}
    for k, v in pairs(voice.units) do merged[k] = v end
    for k, v in pairs(units) do merged[k] = v; if base ~= voice.unitsBase then bases[k] = base end end
    voice.units, voice.unitBase = merged, bases
end

-- The diphone voice for a word provider: the requested one, else its own choice, else any diphone voice.
local function fallbackVoice(requested, preferred)
    if requested then
        if TTS:Preload(requested) and Engine.voices[requested] then return Engine.voices[requested] end
        return nil, "unavailable:" .. requested
    end
    if preferred and TTS:Preload(preferred) and Engine.voices[preferred] then return Engine.voices[preferred] end
    local ids = {}
    for id in pairs(Engine.voices) do ids[#ids + 1] = id end
    table.sort(ids)
    if ids[1] then return Engine.voices[ids[1]] end
    for _, info in ipairs(TTS:ListProviders()) do
        if TTS:Preload(info.id) and Engine.voices[info.id] then return Engine.voices[info.id] end
    end
    return nil, "no_fallback_voice"
end

-- A provider of whole-word recordings. Every word it lacks goes to a diphone voice, using the same tokenizer and pauses.
-- def = { name, words = {word = seconds or {seconds, file}}, base = addon folder, optional: fallback = voice id, gender, quality }
function Engine.RegisterWordVoice(id, def)
    local provided = features(true)
    provided.fallback = true
    TTS:RegisterProvider(id, {
        name = def.name, language = "en", gender = def.gender, quality = def.quality, features = provided,
        Synthesize = function(_, text, options)
            local fallback, reason = fallbackVoice(options.fallback, def.fallback)
            if not fallback then return nil, reason end
            local voice = {}
            for k, v in pairs(fallback) do voice[k] = v end
            voice.wordClips, voice.wordBase = def.words, def.base
            return Core.Tokenize(text, voice, options)
        end,
    })
    if def.fallback then TTS:Preload(def.fallback) end   -- now, while loading is expected, not on the first sentence
end
