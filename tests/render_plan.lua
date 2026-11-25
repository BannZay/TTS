-- Prints the playback plan for a phrase: "<clip path> <seconds>" per clip.
-- Usage: lua render_plan.lua "text" [arctic|kal|kokoro]    (env VC_SPEED sets the speed)
local ENGINE = "../TTS_Diphone/"
dofile("../TTS/Libs/LibStub/LibStub.lua")
strmatch = string.match   -- WoW alias used by LibStub
function CreateFrame() return { SetScript = function() end, Show = function() end, Hide = function() end } end
dofile("../TTS/Libs/LibTTS-1.0/LibTTS-1.0.lua")
for _, f in ipairs({ "Words", "Letters", "LTS", "Core", "Engine" }) do dofile(ENGINE .. f .. ".lua") end
local C = TTS_DiphoneCore
local id = (arg[2] == "arctic" or arg[2] == "kokoro") and arg[2] or "kal"
local alt = os.getenv("VC_ARCTIC_DIR")   -- optional: experiment folder (relative to the repo root) instead of TTS_Arctic
if id == "kokoro" then dofile("../TTS_Kokoro/Diphones.lua")
else dofile(id == "arctic" and ("../" .. (alt or "TTS_Arctic") .. "/Diphones.lua") or "../TTS_Kal/Diphones.lua") end
local v = TTS_Diphone.voices[id]
if id == "arctic" and not os.getenv("VC_NO_UNITS") then dofile("../TTS_Arctic/Units.lua") end   -- VC_NO_UNITS=1: diphones only
if id == "kokoro" and not os.getenv("VC_NO_UNITS") then dofile("../TTS_KokoroHQ/Units.lua"); if not os.getenv("VC_NO_ENDINGS") then dofile("../TTS_KokoroHQ_Endings/Units.lua") end end   -- VC_NO_ENDINGS=1: as if the endings addon were missing
if alt and id == "arctic" then
  v.base = "Interface\\AddOns\\" .. alt:gsub("/", "\\") .. "\\"
end
if os.getenv("VC_JOIN") then C.JOIN_WEIGHT = tonumber(os.getenv("VC_JOIN")) end
if os.getenv("VC_RHYTHM") then C.RHYTHM_WEIGHT = tonumber(os.getenv("VC_RHYTHM")) end
local options = { speed = tonumber(os.getenv("VC_SPEED") or ""), ending = os.getenv("VC_ENDING") }   -- VC_ENDING: full|rhythm|off
if arg[1]:sub(1, 1) == "@" then   -- @file: one word per line, prints word and the seconds the voice needs for it
  for w in io.lines(arg[1]:sub(2)) do
    local t = 0
    for _, it in ipairs(C.Tokenize(w, v, options)) do t = t + it.wait end
    print(w, t)
  end
  return
end
for _, it in ipairs(C.Tokenize(arg[1], v, options)) do print(it.path, it.wait) end
