-- End-to-end offline test: real TTS.lua, library, engine and voice addons, loaded the way the client would load them.
-- The stub reads the real TOC files, so discovery, load-on-demand dependencies and file lists are checked too.
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

strmatch = string.match
function geterrorhandler() return error end
local played = {}
function PlaySoundFile(path) played[#played + 1] = path end
function UnitName() return "Me" end
local messages = {}
print = (function(real) return function(...) messages[#messages + 1] = tostring((...)); if ... == "PASS" then real("end-to-end tests passed") end end end)(print)
SlashCmdList = {}
local eventFrame
function CreateFrame()
    local f = { scripts = {} }
    f.SetScript = function(self, name, fn) self.scripts[name] = fn; if name == "OnEvent" then eventFrame = self end end
    f.Show, f.Hide, f.RegisterEvent = function() end, function() end, function() end
    return f
end
function TTS_OpenOptions() end

-- parses the TOC files in the repository
local NAMES = { "TTS", "TTS_Diphone", "TTS_Arctic", "TTS_Kal", "TTS_Kokoro", "TTS_KokoroHQ", "TTS_KokoroHQ_Endings" }
local TOC, disabled, loaded, loads = {}, {}, {}, {}
for _, name in ipairs(NAMES) do
    local toc = { meta = {}, files = {}, deps = {} }
    for line in io.lines("../" .. name .. "/" .. name .. ".toc") do
        local key, value = line:match("^##%s*([%w%-_]+):%s*(.-)%s*$")
        if key then
            toc.meta[key] = value
            if key == "Dependencies" then for dep in value:gmatch("[^%s,]+") do toc.deps[#toc.deps + 1] = dep end end
        elseif line:match("%S") and not line:match("^#") then
            toc.files[#toc.files + 1] = line:gsub("%s+$", "")
        end
    end
    TOC[name] = toc
end
function GetNumAddOns() return #NAMES end
function GetAddOnMetadata(i, key) return TOC[type(i) == "number" and NAMES[i] or i].meta[key] end
function GetAddOnInfo(n)
    local name = type(n) == "number" and NAMES[n] or n
    if not TOC[name] then return nil end
    return name, name, "", not disabled[name], true, disabled[name] and "DISABLED" or nil
end
function IsAddOnLoaded(name) return loaded[name] end
local function loadFile(name, file)
    file = file:gsub("\\", "/")
    local path = "../" .. name .. "/" .. file
    if file:match("%.xml$") then     -- the library's loader: one script next to it
        local dir = path:match("^(.*/)")
        for script in io.lines(path) do
            local s = script:match('Script file="([^"]+)"')
            if s then dofile(dir .. s) end
        end
    else
        dofile(path)
    end
end
function LoadAddOn(name)
    if loaded[name] then return 1 end
    if disabled[name] or not TOC[name] then return nil, disabled[name] and "DISABLED" or "MISSING" end
    for _, dep in ipairs(TOC[name].deps) do
        if not LoadAddOn(dep) then return nil, "DEP_MISSING" end
    end
    loaded[name] = true
    loads[#loads + 1] = name
    for _, file in ipairs(TOC[name].files) do
        if not file:match("^Options") and not file:match("^Replacements") and not file:match("^BannedPanel") and not file:match("^Preview") then loadFile(name, file) end
    end
    return 1
end

-- embedded copies must match each other and the library submodule (tools/sync_libs.ps1). Line endings are ignored,
-- the two repositories are checked out separately. Without the submodule (CI) only the copies are compared.
local function read(path)
    local h = io.open(path, "rb")
    if not h then return nil end
    local data = h:read("*a"); h:close()
    return (data:gsub("\r\n", "\n"))
end
local library = read("../LibTTS-1.0/LibTTS-1.0.lua")
if not library then print("LibTTS-1.0 submodule not checked out, not compared with the embedded copies") end
local source = library or assert(read("../TTS/Libs/LibTTS-1.0/LibTTS-1.0.lua"))
for _, addon in ipairs({ "TTS", "TTS_Diphone" }) do
    assert(read("../" .. addon .. "/Libs/LibTTS-1.0/LibTTS-1.0.lua") == source, addon .. ": run tools/sync_libs.ps1")
end

-- the client starts TTS; voices stay unloaded
LoadAddOn("TTS")
local TTS = LibStub("LibTTS-1.0")
eq(table.concat(loads, ","), "TTS", "voices are not loaded at startup")
assert(TTS_Consumer, "consumer exists")
eq(TTS:ListProviders()[1].name, "Arctic (female, natural)", "TOC fields reach the library")

local function event(name, ...) eventFrame.scripts.OnEvent(eventFrame, name, ...) end
event("ADDON_LOADED", "SomethingElse")
assert(not TTSDB, "other addons are ignored")
TTSDB = { voice = "kal" }
event("ADDON_LOADED", "TTS")
eq(TTSDB.speed, 1, "defaults filled"); eq(TTSDB.voice, "kal", "saved voice kept")
eq(TTS:GetDefaultProvider(), "kal", "saved voice is the default for other addons")

-- login loads the saved voice, with the engine as a dependency
event("PLAYER_LOGIN")
eq(table.concat(loads, ","), "TTS,TTS_Diphone,TTS_Kal", "load order")
eq(TTS:GetFeatures("kal").speed.pausesOnly, false)

-- the Kokoro voice loads both of its units addons (several are merged); the endings keep their own folder
do
    assert(TTS:Preload("kokoro"), "kokoro loads")
    assert(loaded.TTS_KokoroHQ and loaded.TTS_KokoroHQ_Endings, "both units addons loaded with the voice")
    local kv, n = TTS_Diphone.voices.kokoro, 0
    for name in pairs(kv.units) do
        if name:match("00f[bc]?$") then n = n + 1; assert(kv.unitBase[name]:find("TTS_KokoroHQ_Endings", 1, true), name) end
    end
    assert(n > 4000, "ending clips merged: " .. n)
end

-- the "basic" option (voice preview) hears the voice as if its units addon were not installed
do
    local text = "The quick brown fox jumps over the lazy dog, and then everybody went home."
    local function usesUnits(options)
        for _, item in ipairs(TTS_DiphoneCore.Tokenize(text, TTS_Diphone.voices.kokoro, options)) do
            if item.path:find("\\units\\", 1, true) then return true end
        end
        return false
    end
    eq(usesUnits({}), true, "with the units addon its clips are used")
    eq(usesUnits({ basic = true }), false, "basic skips the units")
    eq(usesUnits({}), true, "basic leaves the voice unchanged")
end

-- the "ending" option controls how the last word of a sentence is spoken (the saved setting is passed on by TTS)
do
    local function total(ending)
        local s = 0
        for _, item in ipairs(TTS_DiphoneCore.Tokenize("good morning everybody.", TTS_Diphone.voices.kal, { ending = ending })) do s = s + item.wait end
        return s
    end
    assert(total("off") < total("full"), "off: the last word is not stretched")
    eq(total("rhythm") > total("off"), true, "rhythm stretches the last word")
    eq(total(nil), total("full"), "full is the default")
    eq(TTS:GetFeatures("kal").ending.default, "full", "feature advertised")
    eq(TTSDB.ending, "full", "saved default")
    SlashCmdList.TTS("ending off"); eq(TTSDB.ending, "off")
    SlashCmdList.TTS("ending bogus"); eq(TTSDB.ending, "off", "invalid value ignored")
    SlashCmdList.TTS("ending full"); eq(TTSDB.ending, "full")
end

local function run(seconds) for _ = 1, seconds * 20 do TTS:Tick(0.05) end end

-- a chat line is spoken with clips of the chosen voice; own lines and off channels stay silent
event("CHAT_MSG_SAY", "hello world", "Someone")
assert(TTS:IsBusy()); run(4)
assert(#played > 8, "clips played"); assert(played[1]:find("^Interface\\AddOns\\TTS_Kal"), played[1])
eq(TTS:IsBusy(), false)
played = {}
event("CHAT_MSG_SAY", "hello", "Me"); event("CHAT_MSG_RAID", "hello", "Someone")
eq(TTS:IsBusy(), false, "own message and raid are off by default")

-- speed from the saved settings reaches the engine (it scales the pauses too)
local function length(text)
    local seconds = 0
    for _, item in ipairs(TTS_DiphoneCore.Tokenize(text, TTS_Diphone.voices.kal, { speed = TTSDB.speed })) do seconds = seconds + item.wait end
    return seconds
end
local normal = length("hello there, friend")
SlashCmdList.TTS("speed 1.5"); eq(TTSDB.speed, 1.5)
assert(length("hello there, friend") < normal, "faster")
SlashCmdList.TTS("speed 9"); eq(TTSDB.speed, 1.5, "outside the voice's range")
assert(messages[#messages]:find("0.6 to 1.6", 1, true), "range comes from the voice")
SlashCmdList.TTS("speed 1")

-- /tts test and /tts stop
SlashCmdList.TTS("test good morning")
assert(TTS:IsBusy()); SlashCmdList.TTS("stop"); eq(TTS:IsBusy(), false, "stop clears the queue")

-- switching voice loads the other one
SlashCmdList.TTS("voice arctic")
eq(TTSDB.voice, "arctic"); assert(loaded.TTS_Arctic and TTS_Diphone.voices.arctic.units, "voice loads with its units")
eq(TTS:GetDefaultProvider(), "arctic", "the default follows the picked voice")
played = {}
SlashCmdList.TTS("test ok"); run(3)
assert(played[1]:find("TTS_Arctic", 1, true), played[1])
SlashCmdList.TTS("voice nothing")
eq(TTSDB.voice, "arctic", "an unknown voice is refused")

-- with no voice at all: one warning, no error
messages = {}
TTS.providers = {}
TTS.known = {}
TTS_Consumer:SetProvider(nil)
TTS_Speak("hello"); TTS_Speak("hello")
eq(#messages, 1, "warned once"); assert(messages[1]:find("no voice installed"))

print("PASS")
