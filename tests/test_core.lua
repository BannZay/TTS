-- Offline tests. Usage: lua test_core.lua   (env VC_DATA = folder with the generated data, default ../TTS_Diphone)
local DATA_DIR = os.getenv("VC_DATA") or "../TTS_Diphone"
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end
dofile("../TTS_Diphone/Core.lua")
local C = TTS_DiphoneCore
local function join(t) return table.concat(t, " ") end

-- numbers
eq(join(C.NumberWords("0")), "zero")
eq(join(C.NumberWords("7")), "seven")
eq(join(C.NumberWords("13")), "thirteen")
eq(join(C.NumberWords("42")), "forty two")
eq(join(C.NumberWords("100")), "one hundred")
eq(join(C.NumberWords("1001")), "one thousand one")
eq(join(C.NumberWords("2500")), "two thousand five hundred")
eq(join(C.NumberWords("1999")), "nineteen ninety nine")
eq(join(C.NumberWords("1905")), "nineteen oh five")
eq(join(C.NumberWords("1500")), "fifteen hundred")
eq(join(C.NumberWords("2024")), "two thousand twenty four")
eq(join(C.NumberWords("1000000")), "one million")
eq(join(C.NumberWords("123456789")), "one hundred twenty three million four hundred fifty six thousand seven hundred eighty nine")
eq(join(C.NumberWords("007")), "zero zero seven")

-- synthetic data. Phone codes: char 49 = phoneme 1 (AA), 50 = phoneme 2 (AE) ... Diphone keys are pair + variant.
local function dd(list) local t = {} for _, k in ipairs(list) do t[k] = 0.1 end return t end
local data = {
  base = "Interface\\AddOns\\Voice\\",
  words = { ab = string.char(49, 50), ["don't"] = string.char(49, 50), one = string.char(49), first = string.char(50),
            walk = string.char(49), loud = string.char(49) },
  letters = { z = string.char(51), q = string.char(52) },
  diphones = dd({ "00012", "01022", "02002", "01002", "00022", "00032", "03002", "00042", "04002", "01032", "03002" }),
}
local t = C.Tokenize("ab", data)
eq(#t, 3, "diphone chain"); assert(t[1].path:find("diphones\\00012.ogg", 1, true)); assert(t[3].path:find("02002.ogg", 1, true))
t = C.Tokenize("ab. ab", data)
assert(math.abs(t[3].wait - (0.1 + C.SENT_PAUSE)) < 1e-9, "sentence pause")
t = C.Tokenize("ab, ab", data)
assert(math.abs(t[3].wait - (0.1 + C.COMMA_PAUSE)) < 1e-9, "comma pause")
t = C.Tokenize("ab? ab", data)
assert(math.abs(t[3].wait - (0.1 + C.QUESTION_PAUSE)) < 1e-9, "question pause")
t = C.Tokenize("ab ab", data, { pause = 2 })
assert(math.abs(t[3].wait - (0.1 + C.WORD_PAUSE * 2)) < 1e-9, "pause scale")
do   -- a voice with wordGaps: no pause after a function word, its own pause after a content word, sentence pauses unchanged, pause option scales it
  local g = {}
  for k, v in pairs(data) do g[k] = v end
  g.words = { ab = data.words.ab, the = data.words.ab }
  g.wordGaps = { func = 0, content = 0.025 }
  local function gap(text, opts) local x = C.Tokenize(text, g, opts); return x[3].wait - 0.1 end
  assert(math.abs(gap("the ab") - 0) < 1e-9, "no gap after a function word")
  assert(math.abs(gap("ab the") - 0.025) < 1e-9, "own gap after a content word")
  assert(math.abs(gap("ab the", { pause = 3 }) - 0.075) < 1e-9, "the pause option scales the gap")
  assert(math.abs(gap("the. ab") - C.SENT_PAUSE) < 1e-9, "sentence pause stays")
  assert(math.abs(gap("ab the", { speed = 0.5 }) - 0.025 * 8) < 1e-9, "speed strongly scales the content gap")
  assert(math.abs(gap("the ab", { speed = 0.5 }) - 0) < 1e-9, "still no gap after a function word")
end
eq(#C.Tokenize("!!! ???", data), 0, "nothing voiced")
eq(#C.Tokenize("don't", data), 3, "apostrophe word found as is")
eq(#C.Tokenize("'ab'", data), 3, "quotes around a word are stripped")
eq(#C.Tokenize("zq", data), 4, "no-vowel word spelled letter by letter")
eq(#C.Tokenize("1", data), 2, "digit read as a word")
eq(#C.Tokenize("1st", data), 2, "ordinal 1st is read as the word first")

-- rhythm: a stressed vowel picks a longer variant than an unstressed one when several are available
local rd = { ["00011"] = 0.05, ["00012"] = 0.10, ["00013"] = 0.16, ["01001"] = 0.05, ["01002"] = 0.10, ["01003"] = 0.16 }
local words = { st = "^" .. string.char(49), un = string.char(49) }     -- phoneme 1 = AA (a long vowel)
local s = C.Tokenize("st", { words = words, diphones = rd, letters = {}, base = "" })
local u = C.Tokenize("un", { words = words, diphones = rd, letters = {}, base = "" })
assert(s[1].wait >= u[1].wait, "stressed vowel is not shorter than unstressed")
assert(s[1].wait > 0.05 and u[1].wait < 0.16, "variants are chosen from the available ones")

-- speed: faster picks shorter clips and shorter pauses, slower the opposite
local function total(items) local s = 0 for _, it in ipairs(items) do s = s + it.wait end return s end
local sd = { words = { ab = string.char(49, 50) }, letters = {}, base = "", diphones = { ["00011"] = 0.05, ["00012"] = 0.10, ["00013"] = 0.16, ["01021"] = 0.05, ["01022"] = 0.10, ["01023"] = 0.16, ["02001"] = 0.05, ["02002"] = 0.10, ["02003"] = 0.16 } }
local normal = total(C.Tokenize("ab ab", sd, { speed = 1 }))
local fast = total(C.Tokenize("ab ab", sd, { speed = 1.5 }))
local slow = total(C.Tokenize("ab ab", sd, { speed = 0.7 }))
assert(fast < normal and normal < slow, "speed changes the length ("..fast.." "..normal.." "..slow..")")

-- another voice: own clip folder and aliases for diphones it lacks
local av = C.Tokenize("ab", { words = data.words, letters = {}, diphones = { ["0001"] = 0.1, ["0103"] = 0.1, ["0200"] = 0.1 },
  base = "Interface\\AddOns\\TTS_Arctic\\", alias = { ["0102"] = "0103" } })
eq(#av, 3, "alias fills the missing diphone")
assert(av[1].path:find("TTS_Arctic\\diphones\\0001.ogg", 1, true), "other voice path")
assert(av[2].path:find("0103.ogg", 1, true), "aliased clip is used")

-- join-aware selection: two candidates (suffix 2 and 4) with edge spectra; the one that matches the previous clip wins
local function sp(c) return string.rep(c, 8) end
local jd = { ["00012"] = { 0.1, sp("A"), sp("A") }, ["01022"] = { 0.1, sp("A"), sp("A") }, ["01024"] = { 0.1, sp("Z"), sp("Z") },
             ["02002"] = { 0.1, sp("A"), sp("A") } }
local jw = { ab = string.char(49, 50) }
local jt = C.Tokenize("ab", { words = jw, letters = {}, diphones = jd, base = "" })
eq(#jt, 3); assert(jt[2].path:find("01022.ogg", 1, true), "the candidate whose spectrum matches is chosen")
jd["01022"][2], jd["01022"][3] = sp("Z"), sp("Z")   -- now candidate 4 matches the neighbours better... no: both neighbours are A
jd["01024"][2], jd["01024"][3] = sp("A"), sp("A")
jt = C.Tokenize("ab", { words = jw, letters = {}, diphones = jd, base = "" })
assert(jt[2].path:find("01024.ogg", 1, true), "selection follows the join cost")

-- letter-to-sound: tiny tree for letter "a": if next letter is "b" -> phone 'X' else 'Y'
local lts = { a = { F = { 1, 0, 0 }, V = { "b", "X", "Y" }, N = { 3, 0, 0 } } }
eq(C.LetterToSound("ab", lts), "X", "lts yes branch")
eq(C.LetterToSound("ac", lts), "Y", "lts no branch")
eq(C.LetterToSound("a", lts), "Y", "lts word end is padding")

-- real data: the engine addon (words, letters, letter-to-sound) plus each voice addon
local BASE_DIR = DATA_DIR
strmatch = string.match   -- WoW alias used by LibStub
function CreateFrame() return { SetScript = function() end, Show = function() end, Hide = function() end } end
dofile("../TTS/Libs/LibStub/LibStub.lua"); dofile("../TTS/Libs/LibTTS-1.0/LibTTS-1.0.lua")
dofile(BASE_DIR .. "/Words.lua"); dofile(BASE_DIR .. "/Letters.lua"); dofile(BASE_DIR .. "/LTS.lua")
dofile(BASE_DIR .. "/Engine.lua")
local TTS = LibStub("LibTTS-1.0")
local function loadVoice(dir)
  dofile(BASE_DIR .. "/../" .. dir .. "/Diphones.lua")
  local missing = 0
  local def
  for id, v in pairs(TTS_Diphone.voices) do if v.base:find(dir, 1, true) then def = v end end
  for k in pairs(def.diphones) do
    local f = io.open(BASE_DIR .. "/../" .. dir .. "/diphones/" .. k .. ".ogg")
    if f then f:close() else missing = missing + 1 end
  end
  eq(missing, 0, dir .. ": clip entries without a file")
  return def
end
local arctic = loadVoice("TTS_Arctic")
local kal = loadVoice("TTS_Kal")
assert(not TTS:GetFeatures("kal").speed.pausesOnly, "clips of several lengths: speed picks among them")
local n = 0 for k in pairs(kal.diphones) do n = n + 1 end
eq(n, 5023, "kal clips")
local function count(str, voice) return #C.Tokenize(str, voice or kal) end
assert(count("hello world") > 8, "dictionary words")
assert(count("zxqvt") >= 10, "no-vowel word is spelled")
assert(count("blorptang") > 6, "unknown word goes through letter-to-sound")
assert(count("walks walked walking quickly") > 20, "endings on known stems")
assert(count("lol omg 42 3.14 1st 50% o'brien don't") > 40, "mixed chat line")
-- all four endings produce a different phoneme string from the bare stem
local function items(str) return C.Tokenize(str, kal) end
assert(#items("walks") > #items("walk") - 1, "-s adds a sound")
local nw = 0
for w in pairs(TTS_DiphoneWords) do nw = nw + 1 end
-- the same phrases through the Arctic voice (aliases fill its gaps)
assert(count("hello world", arctic) > 8, "arctic: dictionary words")
assert(count("lol omg 42 3.14 1st 50% o'brien don't", arctic) > 40, "arctic: mixed chat line")

-- whole-word provider: recorded words play as clips, everything else comes from the diphone voice
TTS_Diphone.RegisterWordVoice("words", { name = "Words", base = "Interface\\AddOns\\VC_Words\\", fallback = "kal",
  words = { hello = 0.4, friend = 0.5, you = 0.25, forty = 0.3, ["don't"] = { 0.35, "dont" }, con = { 0.3, "con_" }, lol = 0.6, morning = { { 0.2, "morning-1" }, { 0.1, "morning-2" } } } })
local words = TTS.providers.words
local function isWord(item) return item.path:find("VC_Words\\words\\", 1, true) end
local function wordPaths(items)
  local out = {}
  for _, it in ipairs(items) do if isWord(it) then out[#out + 1] = it.path:match("([^\\]+)%.ogg$") end end
  return table.concat(out, " ")
end
local mixed = words:Synthesize("hello blorptang friend", {})
eq(mixed[1].path, "Interface\\AddOns\\VC_Words\\words\\hello.ogg", "known word is a clip")
assert(math.abs(mixed[1].wait - (0.4 + C.WORD_PAUSE)) < 1e-9, "clip length plus the word pause")
assert(#mixed > 8, "unknown word comes from the fallback")
assert(mixed[2].path:find("TTS_Kal", 1, true), "fallback clip path " .. mixed[2].path)
assert(isWord(mixed[#mixed]), "the clip after the fallback run")
assert(math.abs(words:Synthesize("hello, friend", {})[1].wait - (0.4 + C.COMMA_PAUSE)) < 1e-9, "punctuation pause after a clip")
eq(wordPaths(words:Synthesize("you", {})), "you", "a word uses the clip")
eq(wordPaths(words:Synthesize("42", {})), "forty", "numbers are read as words, the clip is used, two comes from the voice")
eq(wordPaths(words:Synthesize("don't con 'hello'", {})), "dont con_ hello", "file name override, quotes stripped")
eq(wordPaths(words:Synthesize("dont", {})), "", "the clip is keyed by the word as written")
eq(wordPaths(words:Synthesize("good morning", {})), "morning-1 morning-2", "a word of several clips plays them in order")
local parts = words:Synthesize("morning", {})
assert(math.abs(parts[1].wait - 0.2) < 1e-9 and parts[2].wait >= 0.1 - 1e-9, "clip lengths, any pause goes after the last one")
eq(wordPaths(words:Synthesize("lol", {})), "lol", "a recorded word wins over spelling it out")
local slowClip = words:Synthesize("hello hello", { speed = 0.7, pause = 2 })
assert(math.abs(slowClip[1].wait - (0.4 + C.WORD_PAUSE * 2 / 0.7)) < 1e-9, "only the pause scales")
local viaArctic = words:Synthesize("blorptang", { fallback = "arctic" })
assert(viaArctic[1].path:find("TTS_Arctic", 1, true), "the request picks the fallback voice")
local noItems, why = words:Synthesize("hello", { fallback = "nope" })
eq(noItems, nil); eq(why, "unavailable:nope")
assert(C.Tokenize("hello", kal)[1].path:find("TTS_Kal", 1, true), "the voice itself does not change")
local consumer = TTS:NewConsumer("Test")
consumer:SetProvider("words")
local handle = assert(consumer:Speak("hello blorptang", { fallback = "arctic", speed = 1.2 }))
eq(#handle.info.ignored, 0, "fallback is an advertised feature")
assert(handle.items[2].path:find("TTS_Arctic", 1, true), "fallback option reaches the provider through Speak")
consumer:Stop()


-- longer units: the planner replaces runs of diphones by one clip, the voice keeps working without them
local noUnits = #C.Tokenize("morning publishing", arctic)
dofile(BASE_DIR .. "/../TTS_Arctic/Units.lua")   -- registers the units with the voice (Engine.AddUnits)
assert(arctic.units and arctic.unitsBase:find("TTS_Arctic\\", 1, true), "units register with the voice")
local missingUnits = 0
for k in pairs(arctic.units) do local f = io.open(BASE_DIR .. "/../TTS_Arctic/units/" .. k .. ".ogg"); if f then f:close() else missingUnits = missingUnits + 1 end end
eq(missingUnits, 0, "unit clip files")
local withUnits = C.Tokenize("morning publishing", arctic)
assert(#withUnits < noUnits - 4, "units give fewer clips: " .. #withUnits .. " against " .. noUnits)
local hasUnit = false
for _, it in ipairs(withUnits) do if it.path:find("\\units\\", 1, true) then hasUnit = true end end
assert(hasUnit, "a unit clip is played")
local fastU = C.Tokenize("morning", arctic, { speed = 1.6 })
assert(#fastU >= 1, "fast speech still plans")
-- word-edge units: a whole word can be one clip, and the silence before/after a word is part of a unit
local the = C.Tokenize("the", arctic)
eq(#the, 1, "the is one clip")
assert(the[1].path:find("units\\00110300.ogg", 1, true), "the = whole-word unit 00 DH AH0 00: " .. the[1].path)
local lazy = C.Tokenize("the lazy dog", arctic)
assert(#lazy <= 8, "word-edge units reduce the clips: " .. #lazy)
print(("%d dictionary words; all tests passed"):format(nw))
