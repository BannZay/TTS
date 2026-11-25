local TTS = LibStub("LibTTS-1.0")
local tts = TTS:NewConsumer("TTS")
TTS_Consumer = tts

local EVENTS = {
    CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "say",
    CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid", CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_GUILD = "guild", CHAT_MSG_OFFICER = "officer", CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_BATTLEGROUND = "battleground", CHAT_MSG_BATTLEGROUND_LEADER = "battleground",
    CHAT_MSG_CHANNEL = "channel", CHAT_MSG_EMOTE = "emote", CHAT_MSG_TEXT_EMOTE = "emote",
}
-- verb used when "say who is speaking" is on
local VERBS = { whisper = "whispers", emote = "" }
-- voice: unset until the user picks one; LibTTS then uses the first installed provider. A picked voice also becomes the
-- LibTTS default, so other addons without their own choice use it
local defaults = { enabled = true, say = true, party = true, raid = false, guild = false, whisper = true, own = false,
    officer = false, battleground = false, channel = false, emote = false,
    names = false, expand = true, muteCombat = false, filterBanned = true, bannedBySound = true, speed = 1, pause = 1, ending = "full", maxLength = 200,
    skipRepeats = false, maxWait = 30 }   -- maxWait: seconds a message may wait in the queue (0 = no limit)

function TTS_SetVoice(id)
    TTSDB.voice = id
    tts:SetProvider(id)
    TTS:SetDefaultProvider(id)
    tts:Preload()
end

-- Cut at a word boundary so the voice does not read a wall of text.
local function shorten(text, max)
    if not max or #text <= max then return text end
    local cut = text:sub(1, max)
    return (cut:gsub("%s+%S*$", ""))
end

local warned
local REPEAT_WINDOW = 5
local recent = {}   -- lower-cased text -> time it was last queued
function TTS_Speak(text, sender, kind)
    local db = TTSDB
    text = TTS_CleanChat(text)
    local banned = db.filterBanned ~= false and db.banned or nil
    text = TTS_FilterBanned(text, banned, not db.bannedBySound)
    if not text:find("%w") then return end   -- nothing left to read
    if db.expand ~= false then text = TTS_ExpandChat(text, db.replacements) end
    text = shorten(text, db.maxLength)
    local who = sender and TTS_FilterBanned((sender:gsub("%-.*", "")), banned, not db.bannedBySound)
    if who and who ~= "" and (db.names or kind == "emote") then
        local verb = VERBS[kind] or "says"
        text = who .. (verb ~= "" and (" " .. verb .. ". ") or " ") .. text
    end
    -- Chat only (kind is set): skip a message already read in the last REPEAT_WINDOW seconds
    local key, now
    if kind and db.skipRepeats then
        key, now = text:lower(), GetTime()
        local last = recent[key]
        if last and now - last < REPEAT_WINDOW then return end
    end
    local ttl = kind and db.maxWait and db.maxWait > 0 and math.min(db.maxWait, 60) or nil   -- drop it if it waits too long in the queue
    local handle, reason = tts:Speak(text, { speed = db.speed, pause = db.pause, ending = db.ending, channel = "chat", ttl = ttl })
    if key and handle then
        recent[key] = now
        for k, t in pairs(recent) do if now - t >= REPEAT_WINDOW then recent[k] = nil end end
    end
    if reason == "no_provider" and not warned then
        warned = true
        print("|cff66ccffTTS|r: no voice installed or enabled. Install a LibTTS voice addon.")
    end
end
function TTS_Stop() tts:Stop() end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
for ev in pairs(EVENTS) do f:RegisterEvent(ev) end
f:SetScript("OnEvent", function(_, event, msg, sender)
    if event == "ADDON_LOADED" then
        if msg ~= "TTS" then return end
        TTSDB = TTSDB or {}
        for k, v in pairs(defaults) do if TTSDB[k] == nil then TTSDB[k] = v end end
        TTSDB.banned = TTSDB.banned or {}
        if not TTSDB.replacements then
            TTSDB.replacements = {}
            TTS_ResetReplacements(TTSDB.replacements)
        elseif (tonumber(TTSDB.symbolsAdded) or 0) < 2 then   -- 2: + / & = @ #
            TTS_AddDefaultSymbols(TTSDB.replacements)
        end
        TTSDB.symbolsAdded = 2
        tts:SetProvider(TTSDB.voice)
        if TTSDB.voice then TTS:SetDefaultProvider(TTSDB.voice) end
        return
    end
    if event == "PLAYER_LOGIN" then tts:Preload(); return end
    local db = TTSDB
    if not db or not db.enabled or not db[EVENTS[event]] then return end
    if not db.own and sender == UnitName("player") then return end
    if db.muteCombat and UnitAffectingCombat("player") then return end
    TTS_Speak(msg, sender, EVENTS[event])
end)

local function voiceIds()
    local ids = {}
    for _, info in ipairs(TTS:ListProviders()) do ids[#ids + 1] = info.id end
    return table.concat(ids, "|")
end

-- Range the active voice offers for a feature, or the given limits when no voice is loaded yet.
local function range(feature, lo, hi)
    local features = TTS:GetFeatures(tts:GetActiveProvider() or "")
    local limits = features and features[feature]
    if type(limits) == "table" then return limits.min or lo, limits.max or hi end
    return lo, hi
end

SLASH_TTS1 = "/tts"
SlashCmdList["TTS"] = function(arg)
    arg = string.lower(arg or "")
    local db = TTSDB
    if arg == "" or arg == "help" then
        print("|cff66ccffTTS|r: /tts options | voice " .. voiceIds() .. " | on|off | stop | say|party|raid|guild|officer|battleground|channel|emote|whisper|own|names|expand|muteCombat|filterBanned|bannedBySound (toggle) | speed <0.6-1.6> | pause <0.5-4> | ending full|rhythm|off | test <text>")
    elseif arg == "on" or arg == "off" then
        db.enabled = (arg == "on"); print("TTS " .. arg)
    elseif arg == "stop" then TTS_Stop()
    elseif arg == "options" or arg == "config" then TTS_OpenOptions()
    elseif arg:sub(1, 5) == "voice" then
        local v = arg:sub(7)
        local known = TTS:GetProviderInfo(v)
        if known then
            TTS_SetVoice(v)
            local active = tts:GetActiveProvider()
            print("TTS voice: " .. tostring(active) .. (active ~= v and (" (" .. tostring(known.addon) .. " is not installed or is disabled)") or ""))
        else print("TTS voice is " .. tostring(tts:GetActiveProvider()) .. " (use /tts voice " .. voiceIds() .. ")") end
    elseif arg:sub(1, 5) == "speed" then
        local n = tonumber(arg:sub(7))
        local lo, hi = range("speed", 0.6, 1.6)
        if n and n >= lo and n <= hi then db.speed = n; print("TTS speed: " .. n)
        else print("TTS speed is " .. db.speed .. " (use /tts speed " .. lo .. " to " .. hi .. ")") end
    elseif arg:sub(1, 5) == "pause" then
        local n = tonumber(arg:sub(7))
        local lo, hi = range("pause", 0.5, 4)
        if n and n >= lo and n <= hi then db.pause = n; print("TTS pauses: x" .. n)
        else print("TTS pauses are x" .. (db.pause or 1) .. " (use /tts pause " .. lo .. " to " .. hi .. ")") end
    elseif arg:sub(1, 6) == "ending" then
        local v = arg:sub(8)
        if v == "full" or v == "rhythm" or v == "off" then db.ending = v; print("TTS sentence ending: " .. v)
        else print("TTS sentence ending is " .. (db.ending or "full") .. " (use /tts ending full|rhythm|off)") end
    elseif arg:sub(1, 4) == "test" then TTS_Speak(arg:sub(6))
    elseif type(defaults[arg]) == "boolean" then
        db[arg] = not db[arg]; print("TTS " .. arg .. ": " .. (db[arg] and "on" or "off"))
    end
end
