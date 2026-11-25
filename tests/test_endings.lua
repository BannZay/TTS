-- Offline test of the Kokoro phrase-final endings (TTS_KokoroHQ_Endings) and of merging several units addons. Run from tests/.
-- Uses render_plan.lua with VC_ENDING (full|rhythm|off) and VC_NO_ENDINGS (as if the addon were missing).
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local WINDOWS = package.config:sub(1, 1) == "\\"

-- Runs render_plan.lua with extra environment variables. An empty value means unset
-- (cmd does that for "set X=", a POSIX shell needs "unset": an empty string is still set).
local function render(text, vars)
    local prefix = ""
    for _, v in ipairs(vars) do
        local name, value = v[1], v[2]
        if WINDOWS then prefix = prefix .. "set " .. name .. "=" .. value .. "&& "
        elseif value == "" then prefix = prefix .. "unset " .. name .. "; "
        else prefix = prefix .. "export " .. name .. "=" .. value .. "; " end
    end
    return assert(io.popen(prefix .. '"' .. (arg and arg[-1] or "lua") .. '" render_plan.lua "' .. text .. '" kokoro'))
end

-- plan("word", "full") -> total seconds, number of 00f clips, list of paths
local function plan(word, ending, noEndings)
    local h = render(word, { { "VC_ENDING", ending }, { "VC_NO_ENDINGS", noEndings and "1" or "" } })
    local total, finals, paths = 0, 0, {}
    for line in h:lines() do
        local path, secs = line:match("^(.-)%s+([%d.]+)$")
        if path then
            total = total + tonumber(secs); paths[#paths + 1] = path
            if path:match("00f[bc]?%.ogg$") then finals = finals + 1 end
        end
    end
    h:close()
    return total, finals, paths
end

local WORDS = { "time", "world", "again", "home", "people", "night", "beautiful", "morning", "water", "friend" }
local usedFull, sumFull, sumOff = 0, 0, 0
for _, w in ipairs(WORDS) do
    local full, nFull, paths = plan(w, "full")
    local off, nOff = plan(w, "off")
    local rhythm, nRhythm = plan(w, "rhythm")
    local none, nNone = plan(w, "full", true)
    eq(nOff, 0, w .. ": off does not use the ending clips")
    eq(nRhythm, 0, w .. ": rhythm does not use the ending clips")
    eq(nNone, 0, w .. ": without the addon full does not use them")
    if nFull > 0 then
        usedFull = usedFull + 1
        for _, p in ipairs(paths) do
            if p:match("00f[bc]?%.ogg$") then assert(p:find("TTS_KokoroHQ_Endings", 1, true), w .. ": ending clip from its own addon: " .. p) end
        end
    end
    -- the endings were sped up to mid-phrase tempo: the last word is not much longer than the same word in the middle of a phrase
    assert(full <= off * 1.35, string.format("%s: full %.3f against off %.3f", w, full, off))
    sumFull, sumOff = sumFull + full, sumOff + off
end
assert(usedFull >= 7, "most words get an ending clip, got " .. usedFull)
assert(sumFull <= sumOff * 1.2, string.format("last words stay close to their mid-phrase length: %.3f against %.3f", sumFull, sumOff))

-- speed changes only the pauses of a voice without clips of several lengths: the last word is the same clip at every speed
local function lastClip(speed)
    local h = render("please please please", { { "VC_SPEED", speed }, { "VC_ENDING", "full" }, { "VC_NO_ENDINGS", "" } })
    local last
    for line in h:lines() do last = line:match("^(.-)%s+[%d.]+$") or last end
    h:close()
    return last
end
eq(lastClip("0.7"), lastClip("1.5"), "last word does not change with speed")
-- two units addons merge; each clip keeps the folder of its addon
dofile("../TTS/Libs/LibStub/LibStub.lua")
strmatch = string.match
function CreateFrame() return { SetScript = function() end, Show = function() end, Hide = function() end } end
dofile("../TTS/Libs/LibTTS-1.0/LibTTS-1.0.lua")
for _, f in ipairs({ "Words", "Letters", "LTS", "Core", "Engine" }) do dofile("../TTS_Diphone/" .. f .. ".lua") end
TTS_Diphone.RegisterVoice("t", { name = "T", clips = {}, base = "A\\" })
TTS_Diphone.AddUnits("t", { ["0102"] = 0.1 }, "B\\")
local v = TTS_Diphone.voices.t
eq(v.unitsBase, "B\\"); eq(v.unitBase, nil, "the first addon needs no per-clip folder")
TTS_Diphone.AddUnits("t", { ["0304"] = 0.2 }, "C\\")
eq(v.units["0102"], 0.1); eq(v.units["0304"], 0.2)
eq(v.unitBase["0304"], "C\\"); eq(v.unitBase["0102"], nil)
print("endings tests passed")
