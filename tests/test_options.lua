-- Offline test of the options panel with a stubbed WoW UI API (no game needed).
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

-- generic frame stub: any method is a no-op that remembers a few values
local Frame = {}
Frame.__index = function(t, k)
    if Frame[k] then return Frame[k] end
    return function() end
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:SetText(s) self.text = s end
function Frame:GetText() return rawget(self, "text") or "" end
function Frame:SetChecked(v) self.checked = v and true or false end
function Frame:GetChecked() return self.checked and 1 or nil end
function Frame:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
function Frame:GetValue() return self.value end
function Frame:CreateFontString() return setmetatable({ scripts = {} }, Frame) end
function Frame:ClearFocus() self.cleared = true end
function Frame:Enable() self.disabled = false end
function Frame:Disable() self.disabled = true end
function Frame:Show() self.hidden = false end
function Frame:Hide() self.hidden = true end
function Frame:SetMinMaxValues(lo, hi) self.lo, self.hi = lo, hi end
local created = {}
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ scripts = {}, kind = kind, template = template }, Frame)
    if name then
        _G[name] = f
        for _, suffix in ipairs({ "Text", "Low", "High" }) do _G[name .. suffix] = setmetatable({ scripts = {} }, Frame) end
    end
    created[#created + 1] = f
    return f
end
UIParent = {}
local categories = {}
function InterfaceOptions_AddCategory(p) categories[#categories + 1] = p end
local opened = 0
function InterfaceOptionsFrame_OpenToCategory(p) opened = opened + 1 end

strmatch = string.match
function geterrorhandler() return error end
dofile("../TTS/Libs/LibStub/LibStub.lua")
dofile("../TTS/Libs/LibTTS-1.0/LibTTS-1.0.lua")
local TTS = LibStub("LibTTS-1.0")
TTS_Consumer = TTS:NewConsumer("TTS")
TTSDB = { speed = 1, enabled = true, say = true, party = true, raid = false, guild = false, whisper = true, own = false }
local installed = { TTS_Arctic = true, TTS_Kal = true, TTS_ExtraHQ = true }
local enabledAddon = { TTS_Arctic = true, TTS_Kal = true, TTS_ExtraHQ = true }
local loadedAddon = {}
function GetAddOnInfo(name)
    if not installed[name] then return nil end
    return name, name, "", enabledAddon[name], true, enabledAddon[name] and nil or "DISABLED"
end
function IsAddOnLoaded(name) return loadedAddon[name] end
function LoadAddOn() end
TTS:DeclareProvider("arctic", { addon = "TTS_Arctic", name = "Arctic (female, natural)" })
TTS:DeclareProvider("kal", { addon = "TTS_Kal", name = "Kal (male, robotic)", extension = "TTS_ExtraHQ" })
local function register(id, features)
    TTS.providers[id] = nil
    TTS:RegisterProvider(id, { name = id, features = features, Synthesize = function() return {} end })
end
local prepared = 0
function TTS_SetVoice(id) TTSDB.voice = id; TTS_Consumer:SetProvider(id); prepared = prepared + 1 end
local spoken, stopped = {}, 0
function TTS_Speak(t) spoken[#spoken + 1] = t end
function TTS_Stop() stopped = stopped + 1 end

dofile("../TTS/Options.lua")
local O = TTSOptions
eq(#categories, 2, "panels registered"); eq(categories[1].name, "TTS"); eq(categories[2].parent, "TTS", "chat channels sub-panel")

-- refresh copies the saved settings into the controls
O.panel.refresh()
eq(O.checks.say.checked, true); eq(O.checks.raid.checked, false); eq(O.speedSlider.value, 1)

-- voice radio buttons: one per known voice
assert(O.radios.arctic and O.radios.kal, "a radio button per known voice")
TTSDB.voice = "arctic"; TTS_Consumer:SetProvider("arctic")
O.panel.refresh()
register("kal")
O.panel.refresh()
eq(O.radios.kal.checked, true, "chosen voice not loaded: the loaded one is shown as active")
register("arctic")
O.panel.refresh()
eq(O.radios.arctic.checked, true); eq(O.radios.kal.checked, false)
O.radios.kal.scripts.OnClick(O.radios.kal)
eq(TTSDB.voice, "kal"); eq(O.radios.kal.checked, true); eq(O.radios.arctic.checked, false)
eq(prepared, 1, "choosing a voice loads its addon")
TTS.providers.arctic = nil
installed.TTS_Arctic = false; O.panel.refresh()
assert(_G.TTSVoice_arcticText.text:find("not installed"), "missing voice addon is reported")
eq(O.radios.arctic.disabled, true, "missing voice cannot be selected")
installed.TTS_Arctic = true; enabledAddon.TTS_Arctic = false; O.panel.refresh()
assert(_G.TTSVoice_arcticText.text:find("disabled"), "disabled voice addon is reported")
enabledAddon.TTS_Arctic = true; O.panel.refresh()
eq(O.radios.arctic.disabled, false, "installed voice can be selected")

-- the extension note follows the addon state
TTS_Consumer:SetProvider("kal")
O.panel.refresh()
assert(O.hqNote.text:find("is installed and loads"), "extension installed")
loadedAddon.TTS_ExtraHQ = true; O.panel.refresh()
assert(O.hqNote.text:find("is loaded"), "extension loaded")
register("kal", { speed = { pausesOnly = true } }); O.panel.refresh()
assert(O.hqNote.text:find("changes the pauses"), "an extension without length variants does not promise a speed control")
register("kal"); loadedAddon.TTS_ExtraHQ = nil
installed.TTS_ExtraHQ = false; O.panel.refresh()
assert(O.hqNote.text:find("Optional: install"), "extension missing")
installed.TTS_ExtraHQ = true

-- sliders follow what the active voice offers, and showing them does not rewrite the saved value
TTSDB.speed = 1.5
register("kal", { speed = { min = 0.8, max = 1.2 } })
O.panel.refresh()
eq(O.speedSlider.lo, 0.8); eq(O.speedSlider.hi, 1.2); eq(O.speedSlider.hidden, false)
eq(TTSDB.speed, 1.5, "a narrower voice keeps the saved value")
register("kal", { speed = { min = 0.6, max = 1.6 } })
O.panel.refresh()
eq(O.slider, nil, "no pause slider: speed controls the pauses too")
TTSDB.speed = 1
TTS.providers.kal = nil
TTS_Consumer:SetProvider("arctic")
-- clicking a checkbox writes the setting
O.checks.raid:SetChecked(true); O.checks.raid.scripts.OnClick(O.checks.raid)
eq(TTSDB.raid, true, "raid on")
O.checks.say:SetChecked(false); O.checks.say.scripts.OnClick(O.checks.say)
eq(TTSDB.say, false, "say off")
O.checks.enabled:SetChecked(false); O.checks.enabled.scripts.OnClick(O.checks.enabled)
eq(TTSDB.enabled, false)

O.speedSlider:SetValue(1.34)
eq(TTSDB.speed, 1.3, "speed slider rounds")

-- test box and buttons
O.box:SetText("good morning")
O.test.scripts.OnClick()
eq(spoken[1], "good morning"); eq(stopped, 1, "test restarts speech")
O.box.scripts.OnEnterPressed(O.box)
eq(#spoken, 2, "Enter speaks too")
O.stop.scripts.OnClick()
eq(stopped, 3)

TTS_OpenOptions()
eq(opened, 2, "options opened (twice for the 3.3.5 quirk)")
-- more settings
O.checks.names:SetChecked(true); O.checks.names.scripts.OnClick(O.checks.names)
eq(TTSDB.names, true, "names on")
TTSDB.maxLength = 120; O.panel.refresh(); eq(O.lengthSlider.value, 120)
O.lengthSlider:SetValue(333); eq(TTSDB.maxLength, 330, "length slider rounds")
for _, k in ipairs({ "officer", "battleground", "channel", "emote", "expand", "muteCombat" }) do assert(O.checks[k], k) end

-- word replacements sub-panel
dofile("../TTS/Expand.lua")
scrollOffset = 0
function FauxScrollFrame_Update(_, total) scrollTotal = total end
function FauxScrollFrame_GetOffset() return scrollOffset end
function FauxScrollFrame_OnVerticalScroll() end
function keysNow() return TTS_SortedReplacements(TTSDB.replacements) end
local realNew = TTS.NewConsumer
TTS.NewConsumer = function() return { Stop = function() end, Speak = function(_, t) spoken = t end } end
dofile("../TTS/Replacements.lua")
TTS.NewConsumer = realNew
local R = TTSReplacementsUI
eq(#categories, 3, "sub-panel registered"); eq(categories[3].parent, "TTS")
TTSDB.replacements = {}; TTS_ResetReplacements(TTSDB.replacements)
R.panel.refresh()
eq(R.rows[1].label.text, "#   =>   number", "sorted first row")
R.word:SetText("GGWP"); R.read:SetText("good game well played"); R.add.scripts.OnClick()
eq(TTSDB.replacements.ggwp, "good game well played")
R.word:SetText("bad word"); R.read:SetText("x"); R.add.scripts.OnClick()
assert(R.message.text:find("letters"), "invalid word reported")
local n = 0; for _ in pairs(TTSDB.replacements) do n = n + 1 end
R.read:SetText("hello there"); R.playRead.scripts.OnClick()
eq(spoken, "hello there", "play next to the Read as box speaks its text")
R.word:SetText(""); R.panel.refresh()
R.rows[1].remove.scripts.OnClick()
eq(TTSDB.replacements["#"], nil, "delete removes")
scrollOffset = 3; R.panel.refresh()
eq(R.rows[1].key, keysNow()[4], "scrolled list starts at the offset"); eq(scrollTotal, #keysNow(), "scroll range covers the list")
R.rows[1].play.scripts.OnClick()
eq(spoken, TTSDB.replacements[R.rows[1].key], "play speaks the replacement")
scrollOffset = 0
R.word:SetText("GGW"); R.word.scripts.OnTextChanged(R.word, true)
eq(R.rows[1].key, "ggwp", "search box filters the list"); eq(R.rows[2].key, nil, "only matches remain")
assert(R.panel.refresh and R.rows[1].label.text:find("good game"), "filtered row shows its text")
R.word:SetText(""); R.word.scripts.OnTextChanged(R.word, true)
assert(R.rows[2].key, "empty search shows everything")
R.reset.scripts.OnClick()
eq(TTSDB.replacements.ggwp, nil, "restore defaults")

-- banned phrases sub-panel
dofile("../TTS/Banned.lua")
dofile("../TTS/BannedPanel.lua")
local Bn = TTSBannedUI
eq(#categories, 4, "banned sub-panel registered"); eq(categories[4].parent, "TTS")
TTSDB.banned = {}
Bn.phrase:SetText("Bad Word"); Bn.add.scripts.OnClick()
eq(TTSDB.banned["bad word"], "mask", "default mode is mask")
Bn.mode.scripts.OnClick()
Bn.phrase:SetText("worse"); Bn.add.scripts.OnClick()
eq(TTSDB.banned.worse, "skip", "mode button switches to skip")
Bn.phrase:SetText("no!"); Bn.add.scripts.OnClick()
assert(Bn.message.text:find("letters"), "invalid phrase reported")
TTSDB.filterBanned = nil; Bn.panel.refresh()
eq(Bn.checks.filterBanned.checked, true, "filter is on by default"); eq(Bn.checks.bannedBySound.checked, true)
Bn.checks.bannedBySound:SetChecked(false); Bn.checks.bannedBySound.scripts.OnClick(Bn.checks.bannedBySound)
eq(TTSDB.bannedBySound, false, "sound matching switched off")
eq(O.checks.filterBanned, nil, "no banned settings in the main panel"); eq(O.replacements, nil, "no replacements button")
Bn.panel.refresh()
eq(Bn.rows[1].label.text, "bad word   =>   mask", "sorted first row")
Bn.rows[1].remove.scripts.OnClick()
eq(TTSDB.banned["bad word"], nil, "delete removes")
print("options panel tests passed")


