-- Chat abbreviations written out as words before the text goes to a voice (English).
-- Letter-by-letter abbreviations such as lfg or dps are the voice's business, not handled here.
-- The user's own list lives in TTSDB.replacements (copied from these defaults on first run, editable in the options).
TTS_DefaultReplacements = { ty = "thank you", thx = "thanks", np = "no problem", pls = "please", plz = "please",
    u = "you", r = "are", ur = "your", brb = "be right back", btw = "by the way", omg = "oh my god",
    idk = "i do not know", tbh = "to be honest", imo = "in my opinion", gz = "congrats", gj = "good job",
    gl = "good luck", hf = "have fun", wp = "well played", ez = "easy", rn = "right now", bc = "because",
    ok = "okay", k = "okay", nvm = "never mind", gtg = "got to go", yw = "you are welcome", ikr = "i know right",
    ["2s"] = "twos", ["3s"] = "threes", ["5s"] = "fives", ["10s"] = "tens", ["2x"] = "two times",
    ["1st"] = "first", ["2nd"] = "second", ["3rd"] = "third", ["+"] = "plus",
    ["/"] = "slash", ["&"] = "and", ["="] = "equals", ["@"] = "at", ["#"] = "number" }
-- Not a default: "-" (hyphenated words, and " - " is already a pause) and "<", ">" (guild tags, hearts).

-- A key is either a word (letters, digits, apostrophes) or a symbol (no letters, digits, apostrophes or spaces, e.g. "+").
-- Returns the normalised key, or nil.
function TTS_ReplacementKey(word)
    word = (word or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if word == "" then return nil end
    if not word:find("[^%w']") then return word end
    if not word:find("[%w'%s]") then return word end
    return nil
end

local function isSymbolKey(key) return key:find("[^%w']") ~= nil end

function TTS_ExpandChat(text, map)
    map = map or TTS_DefaultReplacements
    local symbols = {}
    for k in pairs(map) do if isSymbolKey(k) then symbols[#symbols + 1] = k end end
    table.sort(symbols, function(a, b) return #a > #b or (#a == #b and a < b) end)   -- longest first
    for _, k in ipairs(symbols) do
        local exp = map[k]
        text = text:gsub((k:gsub("%W", "%%%0")), function() return " " .. exp .. " " end)
    end
    return (text:gsub("([%w']+)", function(token)
        local lead, word, tail = token:match("^('*)(.-)('*)$")
        local exp = map[word:lower()]
        return exp and (lead .. exp .. tail)
    end))
end

-- Adds the default symbol rules a saved list is missing, once (lists saved before symbols existed).
function TTS_AddDefaultSymbols(map)
    for k, v in pairs(TTS_DefaultReplacements) do
        if isSymbolKey(k) and map[k] == nil then map[k] = v end
    end
end

-- Add or change a replacement. Returns true, or false and a reason.
function TTS_AddReplacement(map, word, replacement)
    local key = TTS_ReplacementKey(word)
    if not key then return false, "Use a word (letters, digits, apostrophes) or a symbol such as +, without spaces." end
    replacement = (replacement or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if replacement == "" then return false, "Type what the word should be read as." end
    map[key] = replacement
    return true
end

function TTS_SortedReplacements(map)
    local keys = {}
    for k in pairs(map) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

function TTS_ResetReplacements(map)
    for k in pairs(map) do map[k] = nil end
    for k, v in pairs(TTS_DefaultReplacements) do map[k] = v end
end
