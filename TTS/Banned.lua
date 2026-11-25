-- Banned phrases: words or phrases a streamer does not want read aloud (chat chanting a slur, for example).
-- TTSDB.banned = { [phrase] = "mask" | "skip" }, empty by default.
--   mask: the voice reads only the first syllable of each word of the phrase (up to its first vowel group), so it is
--         heard as a cut-off sound and not as the word
--   skip: the phrase is left out of the speech
--   allow: a word that is never matched by sound (see below)
-- Matching ignores case, punctuation, doubled apostrophes and common look-alike characters (n1gg3r), and joins
-- letters spaced out one by one ("b a d w o r d", "b.a.d.w.o.r.d"). Clean.lua already shortens stretched letters.
-- It also goes by sound: a word matches when its simplified sound key (see soundKey) is the same as the phrase word's or
-- differs by one letter (keys of four letters or more). "allow" entries are words that must never match by sound,
-- for innocent words that sound like a banned one.
local LOOKALIKE = { ["0"] = "o", ["1"] = "i", ["3"] = "e", ["4"] = "a", ["5"] = "s", ["7"] = "t", ["@"] = "a", ["$"] = "s" }

local function fold(word)
    word = word:lower():gsub("[0-9@$]", function(c) return LOOKALIKE[c] end)
    return (word:gsub("'", ""))
end

-- Words of a text with their positions; runs of three or more single letters become one word.
local function tokens(text)
    local list, pos = {}, 1
    while true do
        local s, e = text:find("[%w'@$]+", pos)
        if not s then break end
        local norm = fold(text:sub(s, e))
        if norm ~= "" then list[#list + 1] = { s = s, e = e, norm = norm } end
        pos = e + 1
    end
    local merged, i = {}, 1
    while i <= #list do
        local j = i
        while list[j].norm:len() == 1 and list[j + 1] and list[j + 1].norm:len() == 1
            and text:sub(list[j].e + 1, list[j + 1].s - 1):find("^[%s%.%-_]+$") do j = j + 1 end
        if j - i >= 2 then
            local norm = {}
            for k = i, j do norm[#norm + 1] = list[k].norm end
            merged[#merged + 1] = { s = list[i].s, e = list[j].e, norm = table.concat(norm) }
            i = j + 1
        else
            merged[#merged + 1] = list[i]
            i = i + 1
        end
    end
    return merged
end

-- Rough sound of a word: c, q, k and ck alike, ph = f, z = s, x = ks, every vowel group one vowel, doubled letters one.
local function soundKey(word)
    word = word:gsub("ph", "f"):gsub("[cq]", "k"):gsub("x", "ks"):gsub("z", "s"):gsub("[aeiouy]+", "a")
    return (word:gsub("(.)%1+", "%1"))
end

local function nearKey(a, b)   -- at most one letter added, removed or changed
    if a == b then return true end
    if a:byte(1) ~= b:byte(1) then return false end   -- the first letter is the one people keep
    local la, lb = #a, #b
    if math.abs(la - lb) > 1 then return false end
    local i = 1
    while i <= la and i <= lb and a:byte(i) == b:byte(i) do i = i + 1 end
    if la == lb then return a:sub(i + 1) == b:sub(i + 1) end
    if la > lb then return a:sub(i + 1) == b:sub(i) end
    return a:sub(i) == b:sub(i + 1)
end

-- The first syllable: up to the end of the first vowel group.
local function mask(word)
    local _, e = word:find("[aeiouy]+")
    return e and word:sub(1, e) or word:sub(1, 1)
end

-- Returns the text to speak and whether anything was changed. exactOnly: no matching by sound.
function TTS_FilterBanned(text, banned, exactOnly)
    if not banned or not next(banned) then return text, false end
    local list = tokens(text)
    local cover, allowed = {}, {}
    for phrase, mode in pairs(banned) do
        if mode == "allow" then for _, t in ipairs(tokens(phrase)) do allowed[t.norm] = true end end
    end
    for _, t in ipairs(list) do t.key = soundKey(t.norm) end
    for phrase, mode in pairs(banned) do
      if mode ~= "allow" then
        local words, keys = {}, {}
        for _, t in ipairs(tokens(phrase)) do words[#words + 1] = t.norm; keys[#keys + 1] = soundKey(t.norm) end
        for i = 1, #list - #words + 1 do
            local hit = #words > 0
            for k = 1, #words do
                local t = list[i + k - 1]
                if t.norm ~= words[k] and not (not exactOnly and not allowed[t.norm] and #keys[k] >= 4 and nearKey(t.key, keys[k])) then
                    hit = false; break
                end
            end
            if hit then
                for k = i, i + #words - 1 do
                    if cover[k] ~= "skip" then cover[k] = (mode == "skip") and "skip" or "mask" end
                end
            end
        end
      end
    end
    if not next(cover) then return text, false end
    local out, last = {}, 1
    for i, t in ipairs(list) do
        if cover[i] then
            out[#out + 1] = text:sub(last, t.s - 1)
            if cover[i] == "mask" then out[#out + 1] = mask(t.norm) end
            last = t.e + 1
        end
    end
    out[#out + 1] = text:sub(last)
    return (table.concat(out):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")), true
end

-- Add or change a banned phrase. Returns true, or false and a reason.
function TTS_AddBanned(map, phrase, mode)
    phrase = (phrase or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if phrase == "" or phrase:find("[^%w'@$ ]") then
        return false, "A phrase may contain only letters, digits, apostrophes and spaces."
    end
    if mode ~= "mask" and mode ~= "skip" and mode ~= "allow" then return false, "Choose mask, skip or allow." end
    if #tokens(phrase) == 0 then return false, "Type a phrase." end
    map[phrase] = mode
    return true
end

function TTS_SortedBanned(map)
    local keys = {}
    for k in pairs(map) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end


