-- Core: pure logic (tokenizer, pronunciation, rhythm), no WoW API. Testable offline.
TTS_DiphoneCore = {}
local Core = TTS_DiphoneCore

-- Pauses in seconds, divided by the speed option (an optional pause option scales them further). The speed option also picks clips: >1 shorter ones (limited by the
-- shortest variant, about 1.6x), <1 longer ones (about 0.65x).
Core.WORD_PAUSE = 0.06
Core.COMMA_PAUSE = 0.20
Core.SENT_PAUSE = 0.38
Core.QUESTION_PAUSE = 0.42
Core.LETTER_PAUSE = 0.05

local function addPause(items, secs, data)
    if #items > 0 then items[#items].wait = items[#items].wait + secs * data.pause / data.speed end
end

---------------------------------------------------------------------------
-- Phonemes and rhythm. Phoneme strings: one char per phoneme (48 + index in PHONES), optionally preceded by
-- "^" (primary stress) or "~" (secondary stress) for vowels.
---------------------------------------------------------------------------

local PHONES = { "AA", "AE", "AH0", "AH", "AO", "AW", "AY", "B", "CH", "D", "DH", "EH", "ER", "EY", "F", "G", "HH",
    "IH", "IY", "JH", "K", "L", "M", "N", "NG", "OW", "OY", "P", "R", "S", "SH", "T", "TH", "UH", "UW", "V", "W", "Y",
    "Z", "ZH" }
local IDX = {}
for i, p in ipairs(PHONES) do IDX[p] = i end
local function code(name) return string.char(48 + IDX[name]) end

-- Typical phone lengths in milliseconds (before stress and position adjustments).
local MS = { AA = 120, AE = 125, AH0 = 65, AH = 95, AO = 125, AW = 140, AY = 140, B = 70, CH = 105, D = 65, DH = 55,
    EH = 100, ER = 120, EY = 130, F = 95, G = 70, HH = 70, IH = 80, IY = 115, JH = 105, K = 75, L = 80, M = 80, N = 75,
    NG = 85, OW = 130, OY = 150, P = 75, R = 80, S = 105, SH = 110, T = 70, TH = 95, UH = 90, UW = 115, V = 70, W = 70,
    Y = 65, Z = 95, ZH = 95 }
local BASEMS, ISVOWEL = {}, {}
for _, v in ipairs({ "AA", "AE", "AH0", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW" }) do
    ISVOWEL[IDX[v]] = true
end
for p, ms in pairs(MS) do BASEMS[IDX[p]] = ms / 1000 end

-- Cost of a join in the middle of a phone: consonants hold still there (closure, friction, hum), vowels move, diphthongs most.
Core.JOIN_AT = {}
for _, v in ipairs({ "AA", "AE", "AH", "AO", "EH", "ER", "IH", "IY", "UH", "UW" }) do Core.JOIN_AT[IDX[v]] = 0.3 end
for _, v in ipairs({ "AH0", "AW", "AY", "EY", "OW", "OY" }) do Core.JOIN_AT[IDX[v]] = 0.6 end

-- Clip names are the diphone key plus a digit: 1 short, 2 normal, 3 long, 4 second candidate (normal length).
-- A voice may have only some of them (older data sets have a bare key without a digit).
-- Entries are either a duration in seconds, or { seconds, head spectrum, tail spectrum } where the two strings
-- describe the first and last 10 ms of the clip (8 bands, one char each, 2 dB steps) for join-aware selection.
Core.RHYTHM_WEIGHT = 1       -- cost of a clip whose length is off by a factor e (about 2.7x)
Core.CLIP_COST = 0.15        -- cost of every clip, so that fewer and longer clips win when they fit the rhythm about as well
Core.UNIT_RHYTHM_WEIGHT = 0.25  -- same for a unit of an extension: low, so that a speed far from 1 does not push words back to plain diphones
Core.MAX_UNIT_PHONES = 8   -- longest unit a voice may have (phonemes)
Core.JOIN_WEIGHT = 0.04      -- cost per dB of average spectral mismatch between the end of one clip and the start of the next
local VARIANT_SUFFIXES = { "", "1", "2", "3", "4" }
local FINAL_VARIANTS = { "f", "fb", "fc" }   -- end units of a phrase-final word: the unit key (ending 00) plus these
Core.FINAL_STRETCH = 1.25    -- last syllable of a phrase-final word, against 1.15 mid-phrase (was 1.45, which sounded like a different speed)
Core.FINAL_RHYTHM_WEIGHT = 1.5   -- length mismatch weight of a phrase-final ending (a mid-phrase unit uses UNIT_RHYTHM_WEIGHT)
Core.FINAL_BONUS = 0.3     -- a phrase-final ending is preferred to the same ending cut from a word in the middle of a phrase
local UNIT_VARIANTS = { "", "b", "c", "d" }   -- extra clips of a unit: the unit key plus a letter (the file is units\<key><letter>.ogg)

local function entryInfo(e)
    if type(e) == "table" then return e[1], e[2], e[3] end
    return e
end

local function joinCost(a, b)   -- a: previous option, b: next option
    local sa, sb = a.tail, b.head
    if not (sa and sb) then return 0 end
    local sum = 0
    for i = 1, #sa do sum = sum + math.abs(sa:byte(i) - sb:byte(i)) end
    return Core.JOIN_WEIGHT * 2 * sum / #sa
end

-- Phoneme string -> diphone chain with a rhythm: vowels longer when stressed, shorter when unstressed, the last
-- syllable of a word stretched (more at the end of a phrase). Every diphone may exist in several lengths and as a
-- second candidate; the chain with the lowest total cost (length off from the wanted one + spectral mismatch at the
-- joins) is played.
local function speakPhones(items, phones, data, final)
    local seq, stress, i = {}, {}, 1
    while i <= #phones do
        local c = phones:sub(i, i)
        local s = 0
        if c == "^" then s = 1; i = i + 1; c = phones:sub(i, i)
        elseif c == "~" then s = 2; i = i + 1; c = phones:sub(i, i) end
        seq[#seq + 1] = c:byte() - 48
        stress[#stress + 1] = s
        i = i + 1
    end
    local n = #seq
    if n == 0 then return false end
    local D, lastVowel = {}, 0
    for k = 1, n do
        local d = BASEMS[seq[k]] or 0.09
        if ISVOWEL[seq[k]] then
            lastVowel = k
            if stress[k] == 1 then d = d * 1.2 elseif stress[k] == 2 then d = d * 1.05 else d = d * 0.85 end
        end
        D[k] = d
    end
    if lastVowel > 0 then
        for k = lastVowel, n do D[k] = D[k] * (final and Core.FINAL_STRETCH or 1.15) end
    end
    -- the options (available clips) at every position of the chain. Position k is the diphone between phoneme k-1 and k
    -- (k = 1: from silence, k = n + 1: to silence). A unit (3 to 6 phonemes, from the middle of the first to the middle of
    -- the last) covers the positions between its phonemes; it has no joins inside.
    local T, byFirst = {}, {}
    for k = 1, n + 1 do
        local target
        if k == 1 then target = D[1] / 2
        elseif k == n + 1 then target = D[n] / 2
        else target = (D[k - 1] + D[k]) / 2 end
        T[k] = target / (data.speedClips and data.speed or 1)   -- speed picks clips only for a voice that has clips of several lengths (else only the pauses change)
        byFirst[k] = {}
    end
    local prev = 0
    for k = 1, n + 1 do
        local cur = k <= n and seq[k] or 0
        local key = string.format("%02d%02d", prev, cur)
        local function collect(kk)
            local found = false
            for _, suffix in ipairs(VARIANT_SUFFIXES) do
                local name = kk .. suffix
                local dur, head, tail = entryInfo(data.diphones[name])
                if dur then
                    found = true
                    byFirst[k][#byFirst[k] + 1] = { name = name, dur = dur, head = head, tail = tail, first = k, last = k,
                        cost = Core.RHYTHM_WEIGHT * math.abs(math.log(dur / T[k])) + Core.CLIP_COST }
                end
            end
            return found
        end
        if not collect(key) and data.alias and data.alias[key] then collect(data.alias[key]) end
        prev = cur
    end
    if data.units then
        -- a unit covers the diphone positions first..last; its cost is the rhythm mismatch over them
        local function addUnit(key, first, last)
            if not data.units[key] then return end      -- extra clips (key.."b", ...) exist only for a unit that has the bare key
            local want = 0
            for k = first, last do want = want + T[k] end
            for _, suffix in ipairs(UNIT_VARIANTS) do   -- the cheapest chain picks the clip of the unit that joins best
                local name = key .. suffix
                local dur, head, tail = entryInfo(data.units[name])
                if dur then
                    byFirst[first][#byFirst[first] + 1] = { unit = name, dur = dur, head = head, tail = tail, first = first, last = last,
                        cost = Core.UNIT_RHYTHM_WEIGHT * math.abs(math.log(dur / want)) + Core.CLIP_COST }
                end
            end
        end
        local maxp = Core.MAX_UNIT_PHONES
        for s = 1, n - 2 do                                     -- middle units: phonemes s..e, mid to mid
            local key = ""
            for e = s, math.min(n, s + maxp - 1) do
                key = key .. string.format("%02d", seq[e])
                if e - s >= 2 then addUnit(key, s + 1, e) end
            end
        end
        -- At the end of a phrase a voice may have end units cut from a word said with the falling ending (clips <key>00f, fb, fc). The
        -- whole word is then not used: its clip has the pitch of a word in the middle of a phrase, so the word is built from the
        -- units before and one of those endings.
        local finalEnds = {}
        if final == true then   -- "rhythm" keeps the stretch but skips the falling ending units
            for s = math.max(1, n - maxp + 1), n - 1 do
                local key = ""
                for e = s, n do key = key .. string.format("%02d", seq[e]) end
                if data.units[key .. "00f"] then finalEnds[#finalEnds + 1] = { key .. "00", s + 1 } end
            end
        end
        local key = "00"                                        -- start units (silence before the word) and the whole word
        for e = 1, math.min(n, maxp) do
            key = key .. string.format("%02d", seq[e])
            if e >= 2 and e < n then addUnit(key, 1, e) end
            if e == n and #finalEnds == 0 then addUnit(key .. "00", 1, n + 1) end
        end
        for s = math.max(1, n - maxp + 1), n - 1 do             -- end units (silence after the word)
            local key = ""
            for e = s, n do key = key .. string.format("%02d", seq[e]) end
            addUnit(key .. "00", s + 1, n + 1)
        end
        for _, f in ipairs(finalEnds) do
            local want = 0
            for k = f[2], n + 1 do want = want + T[k] end
            -- these clips come from words said alone: already slowed and falling. Judge them against the unstretched length and
            -- with a strong length weight, so one that would make the word sound slower than its neighbours loses.
            want = want * 1.15 / Core.FINAL_STRETCH
            for _, suffix in ipairs(FINAL_VARIANTS) do
                local name = f[1] .. suffix
                local dur, head, tail = entryInfo(data.units[name])
                if dur then
                    byFirst[f[2]][#byFirst[f[2]] + 1] = { unit = name, dur = dur, head = head, tail = tail, first = f[2], last = n + 1,
                        cost = Core.FINAL_RHYTHM_WEIGHT * math.abs(math.log(dur / want)) + Core.CLIP_COST - Core.FINAL_BONUS }
                end
            end
        end
    end
    -- cheapest chain (Viterbi over positions): total[o] = own cost + best previous total + join cost. The previous clips
    -- are those ending just before o; if a diphone is missing, the nearest earlier ones.
    local byLast, any = {}, false
    for k = 1, n + 1 do byLast[k] = {} end
    for k = 1, n + 1 do
        for _, o in ipairs(byFirst[k]) do
            any = true
            local best, bestFrom
            local j = k - 1
            while j >= 1 and #byLast[j] == 0 do j = j - 1 end
            for _, p in ipairs(j >= 1 and byLast[j] or {}) do
                local c = p.total + joinCost(p, o) + (j == k - 1 and Core.JOIN_AT[seq[k - 1]] or 0)
                if not best or c < best then best, bestFrom = c, p end
            end
            o.total, o.from = (best or 0) + o.cost, bestFrom
            byLast[o.last][#byLast[o.last] + 1] = o
        end
    end
    if not any then return false end
    local last
    for k = n + 1, 1, -1 do
        if #byLast[k] > 0 then
            for _, o in ipairs(byLast[k]) do if not last or o.total < last.total then last = o end end
            break
        end
    end
    local chain = {}
    while last do table.insert(chain, 1, last); last = last.from end
    for _, o in ipairs(chain) do
        local path
        if o.unit then path = ((data.unitBase and data.unitBase[o.unit]) or data.unitsBase) .. "units\\" .. o.unit .. ".ogg"
        else path = data.base .. "diphones\\" .. o.name .. ".ogg" end
        items[#items + 1] = { path = path, wait = o.dur }
    end
    return true
end
-- Letter-to-sound: Festival's CMU decision trees (see tools/convert_lts.py). Returns a phoneme string.
function Core.LetterToSound(word, lts)
    local len, out = #word, {}
    local function at(p)
        if p < 1 then return p == 0 and "#" or "0" end
        if p > len then return p == len + 1 and "#" or "0" end
        return word:sub(p, p)
    end
    for pos = 1, len do
        local t = lts[word:sub(pos, pos)]
        if t then
            local F, V, N, i = t.F, t.V, t.N, 1
            while F[i] ~= 0 do
                if at(pos + F[i]) == V[i] then i = i + 1 else i = N[i] end
            end
            out[#out + 1] = V[i]
        end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Words not in the dictionary: endings (-s -ed -ing -ly) on a known stem, else letter-to-sound.
---------------------------------------------------------------------------

local SIBILANT, VOICELESS = {}, {}
for _, p in ipairs({ "S", "Z", "SH", "ZH", "CH", "JH" }) do SIBILANT[code(p)] = true end
for _, p in ipairs({ "P", "T", "K", "F", "TH", "S", "SH", "CH", "HH" }) do VOICELESS[code(p)] = true end
local T_OR_D = { [code("T")] = true, [code("D")] = true }

local function stems(word, ...)   -- candidate stems: word minus each given ending length, plus a restored "e" or undoubled letter
    local out = {}
    for _, cut in ipairs({ ... }) do
        local s = word:sub(1, #word - cut)
        if #s >= 3 then
            out[#out + 1] = s
            out[#out + 1] = s .. "e"
            if s:sub(-1) == s:sub(-2, -2) then out[#out + 1] = s:sub(1, -2) end
            if s:sub(-1) == "i" then out[#out + 1] = s:sub(1, -2) .. "y" end
        end
    end
    return out
end

local function viaEnding(word, words)
    local function find(list)
        for _, s in ipairs(list) do if words[s] then return words[s] end end
    end
    if word:sub(-3) == "ing" then
        local ph = find(stems(word, 3))
        if ph then return ph .. code("IH") .. code("NG") end
    elseif word:sub(-2) == "ed" then
        local ph = find(stems(word, 2, 1))
        if ph then
            local last = ph:sub(-1)
            if T_OR_D[last] then return ph .. code("IH") .. code("D") end
            return ph .. (VOICELESS[last] and code("T") or code("D"))
        end
    elseif word:sub(-2) == "ly" then
        local ph = find(stems(word, 2))
        if ph then return ph .. code("L") .. code("IY") end
    elseif word:sub(-1) == "s" and word:sub(-2) ~= "ss" then
        local ph = find(stems(word, 1, 2))
        if ph then
            local last = ph:sub(-1)
            if SIBILANT[last] then return ph .. code("IH") .. code("Z") end
            return ph .. (VOICELESS[last] and code("S") or code("Z"))
        end
    end
end

-- Chat abbreviations that are spelled out letter by letter (expanding them into words is the consumer's job).
local SPELL = { afk = true, aoe = true, lfg = true, lfm = true, ooc = true, pve = true, mmo = true, ui = true, lol = true,
    lmao = true, wtf = true, gg = true, dps = true, npc = true, pvp = true, wtb = true, wts = true, xp = true, hp = true,
    mp = true, cd = true, oom = true, rp = true }

local function spellOut(items, word, data)
    local before = #items
    for i = 1, #word do
        local ph = data.letters[word:sub(i, i)]
        if ph and speakPhones(items, ph, data, false) then addPause(items, Core.LETTER_PAUSE, data) end
    end
    if #items > before then items[#items].wait = math.max(items[#items].wait - Core.LETTER_PAUSE * data.pause, 0.03) end
end

local function strip(w) return (w:gsub("^'+", ""):gsub("'+$", "")) end

-- Plays a whole-word recording if the voice has one. An entry is seconds, or { seconds, file } when the word cannot be a
-- file name. The clip has one length, so speed does not change it.
local function sayClip(items, word, data)
    local entry = data.wordClips and data.wordClips[word]
    if not entry then return false end
    if type(entry) == "table" and type(entry[1]) == "table" then   -- several clips, played one after the other
        for _, part in ipairs(entry) do
            items[#items + 1] = { path = data.wordBase .. "words\\" .. part[2] .. ".ogg", wait = part[1] }
        end
        return true
    end
    local seconds, file = entryInfo(entry)
    items[#items + 1] = { path = data.wordBase .. "words\\" .. (file or word) .. ".ogg", wait = seconds }
    return true
end

-- Speaks one word: whole-word recording, dictionary, ending on a known stem, letter-to-sound; no-vowel words and acronyms
-- are spelled.
local function sayWord(items, word, data, final)
    word = strip(word)
    if word == "" then return end
    local plain = (word:gsub("'", ""))
    if sayClip(items, word, data) or sayClip(items, plain, data) then return end
    if SPELL[word] then return spellOut(items, word, data) end
    local ph = data.words[word] or data.words[plain]
    if not ph and word:find("[aeiouy]") then
        ph = viaEnding(plain, data.words)
        if not ph and data.lts then
            ph = Core.LetterToSound(plain, data.lts)
            if ph == "" then ph = nil end
        end
    end
    if ph and speakPhones(items, ph, data, final and data.ending ~= "off" and (data.ending == "rhythm" and "rhythm" or true)) then return end
    spellOut(items, (word:gsub("[^a-z]", "")), data)
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------

local ONES = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
    "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" }
local TENS = { [2] = "twenty", [3] = "thirty", [4] = "forty", [5] = "fifty", [6] = "sixty", [7] = "seventy",
    [8] = "eighty", [9] = "ninety" }
local BIG = { "thousand", "million", "billion" }

local function below100(n, out)
    if n >= 20 then
        out[#out + 1] = TENS[math.floor(n / 10)]
        if n % 10 > 0 then out[#out + 1] = ONES[n % 10] end
    elseif n > 0 then
        out[#out + 1] = ONES[n]
    end
end

local function below1000(n, out)
    if n >= 100 then
        out[#out + 1] = ONES[math.floor(n / 100)]
        out[#out + 1] = "hundred"
    end
    below100(n % 100, out)
end

-- Digit string -> list of words. Long numbers and numbers with leading zeros are read digit by digit.
function Core.NumberWords(s)
    local out = {}
    if #s > 12 or (#s > 1 and s:sub(1, 1) == "0") then
        for d in s:gmatch("%d") do out[#out + 1] = d == "0" and "zero" or ONES[tonumber(d)] end
        return out
    end
    local n = tonumber(s)
    if n == 0 then return { "zero" } end
    if #s == 4 and n >= 1100 and n <= 1999 then       -- "nineteen ninety nine", "fifteen hundred"
        local hi, lo = math.floor(n / 100), n % 100
        below100(hi, out)
        if lo == 0 then out[#out + 1] = "hundred"
        elseif lo < 10 then out[#out + 1] = "oh"; out[#out + 1] = ONES[lo]
        else below100(lo, out) end
        return out
    end
    local groups, g = {}, 0
    while n > 0 do groups[g] = n % 1000; n = math.floor(n / 1000); g = g + 1 end
    for k = g - 1, 0, -1 do
        if groups[k] > 0 then
            below1000(groups[k], out)
            if k > 0 then out[#out + 1] = BIG[k] end
        end
    end
    return out
end

local IRREGULAR_ORD = { one = "first", two = "second", three = "third", five = "fifth", eight = "eighth",
    nine = "ninth", twelve = "twelfth" }
local function ordinalize(words)
    local w = words[#words]
    words[#words] = IRREGULAR_ORD[w] or (w:sub(-1) == "y" and (w:sub(1, -2) .. "ieth")) or (w .. "th")
    return words
end
local ORD_SUFFIX = { st = true, nd = true, rd = true, th = true }

-- Splits one token (letters, digits, apostrophes) into the words to say.
local function tokenWords(token)
    local units = {}
    local num, suffix = token:match("^(%d+)(%a%a)$")
    if num and ORD_SUFFIX[suffix] then
        for _, w in ipairs(ordinalize(Core.NumberWords(num))) do units[#units + 1] = w end
        return units
    end
    local pos = 1
    while pos <= #token do
        local s, e = token:find("^%d+", pos)
        if s then
            for _, w in ipairs(Core.NumberWords(token:sub(s, e))) do units[#units + 1] = w end
        else
            s, e = token:find("^[a-z']+", pos)
            local piece = token:sub(s, e)
            units[#units + 1] = piece
        end
        pos = e + 1
    end
    return units
end

local function prepare(text)
    text = string.lower(text or "")
    text = text:gsub("(%d),(%d%d%d)", "%1%2")                 -- 1,000 -> 1000
    text = text:gsub("(%d+)%.(%d+)", function(a, b)           -- 3.14 -> 3 point 1 4
        return a .. " point " .. b:gsub("%d", " %0 ")
    end)
    text = text:gsub("(%d)%%", "%1 percent")
    return text
end

---------------------------------------------------------------------------
-- Tokenizer
---------------------------------------------------------------------------

local function gapPause(gap)
    if gap:find("%?") then return Core.QUESTION_PAUSE end
    if gap:find("[%.!:;\n]") then return Core.SENT_PAUSE end
    if gap:find(",") or gap:find("%s%-+%s") then return Core.COMMA_PAUSE end
    return Core.WORD_PAUSE
end

-- Function words run into the next word in speech (the measured gap in natural sentences is about 1 ms after them, 12 ms after a content word).
-- A voice with clips cut tight at the word edges sets wordGaps = { func = seconds, content = seconds } and gets this instead of the one WORD_PAUSE.
Core.WORDGAP_SPEED_POWER = 3   -- the wordGaps pauses are divided by speed^3 instead of speed
Core.FUNCTION_WORDS = {}
for w in ([[a an the to of in on at for and or but if so is are was were be been am will would can could shall should may might must do does did
    have has had not it its he she we you they i me him her us them my his our your their this that these those with by from as than then there here
    who which what when where how all some any no]]):gmatch("%a+") do Core.FUNCTION_WORDS[w] = true end

local function wordPause(prev, data)   -- pause between two plain words; prev = the word before
    local g = data.wordGaps
    if not g then return Core.WORD_PAUSE end
    return (prev == nil or Core.FUNCTION_WORDS[prev]) and g.func or g.content
end

-- voice = { words = {word=phoneString}, diphones = {key..variant=seconds}, letters = {ch=phoneString}, lts = trees,
--           base = clip folder, alias = {key=key} (similar diphone for those the voice lacks),
--           speedClips = clips of several lengths exist, units = longer units, unitsBase = their folder,
--           wordClips = {word=seconds or {seconds, file}}, wordBase = folder holding words\<file>.ogg }
-- options = { speed, pause }. Returns a list of {path, wait}.
function Core.Tokenize(text, voice, options)
    local items = {}
    local data = {}
    for k, v in pairs(voice) do data[k] = v end
    data.speed = options and options.speed or 1
    data.pause = options and options.pause or 1
    data.ending = options and options.ending or "full"   -- "full", "rhythm" (stretch only) or "off"
    if options and options.basic then data.units = nil end   -- as if no units addon were installed
    text = prepare(text)
    local toks, pos = {}, 1
    while pos <= #text do
        local s, e = text:find("[a-z0-9']+", pos)
        if not s then break end
        toks[#toks + 1] = { text = text:sub(s, e), gap = text:sub(pos, s - 1) }
        pos = e + 1
    end
    for t, tok in ipairs(toks) do
        local nextGap = toks[t + 1] and toks[t + 1].gap or "."
        local phraseEnd = gapPause(nextGap) > Core.WORD_PAUSE
        local units = tokenWords(tok.text)
        for k, w in ipairs(units) do
            local before = #items
            sayWord(items, w, data, phraseEnd and k == #units)
            if #items > before and before > 0 then
                local p = k == 1 and gapPause(tok.gap) or Core.WORD_PAUSE
                local speedDiv = data.speed
                if p == Core.WORD_PAUSE and data.wordGaps then
                    p = wordPause(k == 1 and toks[t - 1] and toks[t - 1].text or nil, data)
                    speedDiv = data.speed ^ Core.WORDGAP_SPEED_POWER   -- these gaps are tiny, so 1/speed alone would not be audible
                end
                items[before].wait = items[before].wait + p * data.pause / speedDiv
            end
        end
    end
    return items
end
