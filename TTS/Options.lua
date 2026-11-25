-- Options panel (Interface -> AddOns -> TTS). Every control applies its change immediately.
-- The Interface Options area is only about 412 x 428, so the chat channels, the word replacements, the banned phrases
-- and the voice preview are sub-panels (Replacements.lua, BannedPanel.lua, Preview.lua). Nothing may go below y = -420
-- or right of x = 396; Unit_Tests_TTS has a layout test for every panel.
local TTS = LibStub("LibTTS-1.0")

local LEFT, RIGHT = 16, 206

local panel = CreateFrame("Frame", "TTSOptionsPanel", UIParent)
panel.name = "TTS"
panel.okay, panel.cancel, panel.default = function() end, function() end, function() end

local sources = CreateFrame("Frame", "TTSSourcesPanel", UIParent)
sources.name = "Chat channels"
sources.parent = "TTS"
sources.okay, sources.cancel, sources.default = function() end, function() end, function() end

local function text(font, x, y, str, parent)
    local fs = (parent or panel):CreateFontString(nil, "ARTWORK", font)
    fs:SetPoint("TOPLEFT", x, y)
    if str then fs:SetText(str) end
    return fs
end

text("GameFontNormalLarge", LEFT, -16, "TTS")
local subtitle = text("GameFontHighlightSmall", LEFT, -38, "Reads chat aloud with prerecorded voice clips. Slash commands: /tts help")
subtitle:SetWidth(370); subtitle:SetHeight(14); subtitle:SetJustifyH("LEFT"); subtitle:SetJustifyV("TOP")

local checks = {}
local function addCheck(key, label, x, y, parent)
    local name = "TTSCheck_" .. key
    local cb = CreateFrame("CheckButton", name, parent or panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    _G[name .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self)
        TTSDB[key] = self:GetChecked() and true or false
    end)
    checks[key] = cb
    return cb
end

-- Left column: voice and speech
addCheck("enabled", "Enable TTS", LEFT - 2, -56)
text("GameFontNormal", LEFT, -88, "Voice")
local radios = {}
local function addRadio(value, label, y)
    local name = "TTSVoice_" .. value
    local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", LEFT - 2, y)
    _G[name .. "Text"]:SetText(label)
    _G[name .. "Text"]:SetWidth(330)
    _G[name .. "Text"]:SetJustifyH("LEFT")
    cb.value, cb.label = value, label
    cb:SetScript("OnClick", function(self)
        TTS_SetVoice(self.value)
        panel.refresh()
    end)
    radios[value] = cb
    return cb
end
local y = -102
for _, info in ipairs(TTS:ListProviders()) do
    addRadio(info.id, info.name, y)
    y = y - 26
end
y = y - 20   -- the rest follows the number of voices (up to three fit)

local refreshing   -- true while panel.refresh sets the controls; a range change must not rewrite the saved value

local function addSlider(name, label, lo, hi, step, x, sy, low, high, parent, width)
    local s = CreateFrame("Slider", name, parent or panel, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", x, sy)
    s:SetWidth(width or 170)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    _G[name .. "Low"]:SetText(low)
    _G[name .. "High"]:SetText(high)
    return s
end

local speedSlider = addSlider("TTSSpeedSlider", "", 0.6, 1.6, 0.1, LEFT + 4, y, "slow", "fast")
local function speedText(v) _G["TTSSpeedSliderText"]:SetText(("Speaking speed: x%.1f"):format(v)) end
speedSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value * 10 + 0.5) / 10
    speedText(value)
    if TTSDB and not refreshing then TTSDB.speed = value end
end)

local pauseSlider = addSlider("TTSPauseSlider", "", 0.5, 4, 0.1, RIGHT + 8, y, "short", "long")
local function pauseText(v) _G["TTSPauseSliderText"]:SetText(("Word pauses: x%.1f"):format(v)) end
pauseSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value * 10 + 0.5) / 10
    pauseText(value)
    if TTSDB and not refreshing then TTSDB.pause = value end
end)

local lengthSlider = addSlider("TTSLengthSlider", "", 50, 500, 10, LEFT + 4, y - 46, "short", "long")
local function lengthText(v) _G["TTSLengthSliderText"]:SetText(("Longest message: %d"):format(v)) end
lengthSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value / 10 + 0.5) * 10
    lengthText(value)
    if TTSDB and not refreshing then TTSDB.maxLength = value end
end)

-- Chat channels sub-panel
text("GameFontNormalLarge", LEFT, -16, "Chat channels", sources)
text("GameFontHighlightSmall", LEFT, -42, "Read messages from:", sources)
local channels = {
    { "say", "Say and yell" }, { "party", "Party" }, { "raid", "Raid and raid warnings" }, { "guild", "Guild" },
    { "battleground", "Battleground" }, { "officer", "Officer" }, { "channel", "Chat channels" }, { "whisper", "Whispers" },
    { "own", "My own messages" }, { "emote", "Emotes" },
}
for i, c in ipairs(channels) do
    addCheck(c[1], c[2], LEFT - 2 + ((i - 1) % 2) * 250, -60 - math.floor((i - 1) / 2) * 26, sources)
end
text("GameFontNormal", LEFT, -190, "Queue", sources)
addCheck("skipRepeats", "Skip repeats within 5 seconds", LEFT - 2, -208, sources)
local waitSlider = addSlider("TTSWaitSlider", "", 0, 60, 1, LEFT + 4, -250, "no limit", "1 min", sources, 340)
local function waitText(v)
    _G["TTSWaitSliderText"]:SetText(v > 0 and ("Drop messages waiting longer than %d s"):format(v) or "Drop messages waiting: never")
end
waitSlider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value + 0.5)
    waitText(value)
    if TTSDB and not refreshing then TTSDB.maxWait = value end
end)
sources:SetScript("OnShow", function() panel.refresh() end)

-- Speech
y = y - 80
text("GameFontNormal", LEFT, y, "Speech")
addCheck("names", "Say who speaks", LEFT - 2, y - 14)
addCheck("expand", "Expand words", RIGHT + 14, y - 14)
addCheck("muteCombat", "Mute in combat", LEFT - 2, y - 40)
-- Sentence ending: checked = "full" (falling ending on the last word), unchecked = "off". "rhythm" is set with /tts ending.
local endingCheck = CreateFrame("CheckButton", "TTSCheck_ending", panel, "InterfaceOptionsCheckButtonTemplate")
endingCheck:SetPoint("TOPLEFT", RIGHT + 14, y - 40)
_G["TTSCheck_endingText"]:SetText("Alter last word")
endingCheck:SetScript("OnClick", function(self) TTSDB.ending = self:GetChecked() and "full" or "off" end)
-- Bottom: test row and notes
local box = CreateFrame("EditBox", "TTSTestBox", panel, "InputBoxTemplate")
box:SetPoint("TOPLEFT", LEFT + 6, y - 72)
box:SetWidth(190)
box:SetHeight(20)
box:SetAutoFocus(false)
box:SetText("Hello world, how are you today?")

local function speak()
    box:ClearFocus()
    TTS_Stop()
    TTS_Speak(box:GetText())
end
box:SetScript("OnEnterPressed", speak)
box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local test = CreateFrame("Button", "TTSTestButton", panel, "UIPanelButtonTemplate")
test:SetPoint("LEFT", box, "RIGHT", 10, 0)
test:SetWidth(70)
test:SetHeight(22)
test:SetText("Speak")
test:SetScript("OnClick", speak)

local stop = CreateFrame("Button", "TTSStopButton", panel, "UIPanelButtonTemplate")
stop:SetPoint("LEFT", test, "RIGHT", 6, 0)
stop:SetWidth(70)
stop:SetHeight(22)
stop:SetText("Stop")
stop:SetScript("OnClick", function() TTS_Stop() end)

local hqNote = text("GameFontHighlightSmall", LEFT, y - 98)
hqNote:SetWidth(370)
hqNote:SetHeight(26)
hqNote:SetJustifyH("LEFT")
hqNote:SetJustifyV("TOP")

-- "missing", "disabled" or "ok" for an optional addon
local function addonState(name)
    local found, _, _, enabled, _, reason = GetAddOnInfo(name)
    if not found or reason == "MISSING" then return "missing" end
    if not enabled then return "disabled" end
    return "ok"
end

-- A slider shows only if the active voice offers its feature, with that voice's range.
local function applyFeature(control, info, name)
    if not info or not info.features then return end
    local feature = info.features[name]
    if feature then control:Show() else control:Hide() end
    if type(feature) == "table" and feature.min and feature.max then control:SetMinMaxValues(feature.min, feature.max) end
end

function panel.refresh()
    local db = TTSDB
    if not db then return end
    local active = TTS_Consumer:GetActiveProvider()
    for value, cb in pairs(radios) do
        local k = TTS:GetProviderInfo(value)
        local label = k.name
        if k.loaded then
            cb:Enable()
        elseif k.reason == "missing" then
            label = label .. " - not installed"; cb:Disable()
        elseif k.reason == "disabled" then
            label = label .. " - disabled"; cb:Disable()
        else
            cb:Enable()   -- installed: selecting it loads it
        end
        _G["TTSVoice_" .. value .. "Text"]:SetText(label)
        cb:SetChecked(value == active)
    end
    local info = active and TTS:GetProviderInfo(active)
    local ext = info and info.extension
    if not ext then
        local speed = info and info.features and info.features.speed
        local pace = type(speed) == "table" and not speed.pausesOnly   -- clips of several lengths
        hqNote:SetText(not active and "No voice is installed."
            or pace and "This voice has natural rhythm and the speed control built in."
            or "This voice has natural rhythm built in; the speed control changes the pauses.")
    elseif info.extensionLoaded and info.features and info.features.speed and info.features.speed.pausesOnly then
        hqNote:SetText(ext .. " is loaded: fewer joins. The speed control changes the pauses.")
    elseif info.extensionLoaded then
        hqNote:SetText(ext .. " is loaded: natural rhythm and the speed control are active.")
    else
        local st = addonState(ext)
        hqNote:SetText(st == "missing" and ("Optional: install " .. ext .. " for better quality with this voice.")
            or st == "disabled" and (ext .. " is installed but disabled in the AddOns list.")
            or (ext .. " is installed and loads with this voice."))
    end
    for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
    endingCheck:SetChecked(db.ending ~= "off")
    applyFeature(endingCheck, info, "ending")
    -- Kokoro: the falling endings come from an optional addon; without it the box only stretches the last word
    local endingsState = active == "kokoro" and addonState("TTS_KokoroHQ_Endings")
    endingCheck.tooltipText = (endingsState == "missing" or endingsState == "disabled")
        and ("Optional: " .. (endingsState == "missing" and "install" or "enable") .. " TTS_KokoroHQ_Endings for the falling ending of the last word. Without it only the length is adjusted.") or nil
    refreshing = true
    applyFeature(speedSlider, info, "speed")
    speedSlider:SetValue(db.speed or 1)
    speedText(db.speed or 1)
    applyFeature(pauseSlider, info, "pause")
    pauseSlider:SetValue(db.pause or 1)
    pauseText(db.pause or 1)
    lengthSlider:SetValue(db.maxLength or 200)
    lengthText(db.maxLength or 200)
    local mw = math.min(db.maxWait or 30, 60)
    waitSlider:SetValue(mw)
    waitText(mw)
    refreshing = false
end
panel:SetScript("OnShow", panel.refresh)

InterfaceOptions_AddCategory(panel)
InterfaceOptions_AddCategory(sources)

TTSOptions = { panel = panel, radios = radios, checks = checks, speedSlider = speedSlider, lengthSlider = lengthSlider,
    sources = sources, hqNote = hqNote, box = box, test = test, stop = stop }
function TTS_OpenOptions()
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)   -- the first call only opens the frame on some clients
end
