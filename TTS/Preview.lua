-- Voice preview (Interface -> AddOns -> TTS -> Voice preview): speak one phrase with each installed voice, with and
-- without its optional extension, without changing the chosen voice.
local TTS = LibStub("LibTTS-1.0")
local preview = TTS:NewConsumer("TTS Preview")   -- its own handle: previews never touch the chat reading

local PHRASES = {
    "Hello world, how are you today?",
    "The quick brown fox jumps over the lazy dog.",
    "Warning! The boss is casting, move out of the fire.",
    "Does anyone have a spare healing potion? I am almost out.",
    "Thank you for the group, see you in the dungeon tomorrow.",
}

-- One entry per way to hear the phrase: { label, provider id, basic = true to skip the extension, extension = addon name }.
-- A voice with an optional extension gets two: plain and with the extension.
local function variants()
    local list = {}
    for _, info in ipairs(TTS:ListProviders()) do
        -- the split needs the engine's "basic" option; a voice that declares features without it cannot be played plain
        if info.extension and (not info.features or info.features.basic) then
            list[#list + 1] = { label = info.name .. " - base", id = info.id, basic = true }
            list[#list + 1] = { label = info.name .. " - Higher Quality", id = info.id, extension = info.extension }
        else
            list[#list + 1] = { label = info.name, id = info.id }
        end
    end
    return list
end

local function addonState(name)
    local found, _, _, enabled, _, reason = GetAddOnInfo(name)
    if not found or reason == "MISSING" then return "missing" end
    if not enabled then return "disabled" end
    return "ok"
end

-- nil when the variant can be played, else why not
local function unavailable(v)
    local ok, reason = TTS:IsAvailable(v.id)
    if not ok then return reason == "disabled" and "disabled" or "not installed" end
    if v.extension then
        local st = addonState(v.extension)
        if st ~= "ok" then return st == "disabled" and "HQ disabled" or "HQ not installed" end
    end
end

local function play(v, text)
    preview:Stop()
    preview:Speak(text, { provider = v.id, basic = v.basic, speed = TTSDB and TTSDB.speed or 1, pause = TTSDB and TTSDB.pause or 1, ending = TTSDB and TTSDB.ending, interrupt = true })
end

local panel = CreateFrame("Frame", "TTSPreviewPanel", UIParent)
panel.name = "Voice preview"
panel.parent = "TTS"
panel.okay, panel.cancel, panel.default = function() end, function() end, function() end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Voice preview")
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("Hear one phrase with every voice. Your chosen voice is not changed.")
subtitle:SetWidth(380); subtitle:SetHeight(21); subtitle:SetJustifyH("LEFT"); subtitle:SetJustifyV("TOP")

local phraseLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
phraseLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
phraseLabel:SetText("Phrase")

local box = CreateFrame("EditBox", "TTSPreviewBox", panel, "InputBoxTemplate")
box:SetPoint("TOPLEFT", phraseLabel, "BOTTOMLEFT", 4, -8)
box:SetWidth(240)
box:SetHeight(20)
box:SetAutoFocus(false)
box:SetText(PHRASES[1])
box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

local drop = CreateFrame("Frame", "TTSPreviewDrop", panel, "UIDropDownMenuTemplate")
drop:SetPoint("LEFT", box, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(drop, 80)
UIDropDownMenu_SetText(drop, "Examples")
UIDropDownMenu_Initialize(drop, function()
    for _, phrase in ipairs(PHRASES) do
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = phrase, true
        info.func = function() box:SetText(phrase); box:SetCursorPosition(0) end
        UIDropDownMenu_AddButton(info)
    end
end)

local rows = {}
local stop = CreateFrame("Button", "TTSPreviewStop", panel, "UIPanelButtonTemplate")
stop:SetWidth(60)
stop:SetHeight(22)
stop:SetText("Stop")
stop:SetScript("OnClick", function() preview:Stop() end)

local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
note:SetPoint("LEFT", stop, "RIGHT", 10, 0)
note:SetWidth(300); note:SetHeight(26); note:SetJustifyH("LEFT")
note:SetText("A clip that already started finishes first.")

-- One row per variant. Voices are looked up on every refresh, so a voice that registers after login also shows up.
local shown = 0   -- rows in use; the others stay hidden for reuse
local function layout()
    local list = variants()
    local anchor = box
    for i, v in ipairs(list) do
        local row = rows[i]
        if not row then
            local btn = CreateFrame("Button", "TTSPreviewPlay" .. i, panel, "UIPanelButtonTemplate")
            btn:SetWidth(60)
            btn:SetHeight(22)
            btn:SetText("Play")
            row = { button = btn, label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight") }
            row.label:SetPoint("LEFT", btn, "RIGHT", 10, 0)
            row.label:SetWidth(300); row.label:SetHeight(28); row.label:SetJustifyH("LEFT")
            btn:SetScript("OnClick", function() box:ClearFocus(); play(row.variant, box:GetText()) end)
            rows[i] = row
        end
        row.variant = v
        row.button:ClearAllPoints()
        row.button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == box and -4 or 0, anchor == box and -18 or -10)
        row.button:Show()
        row.label:Show()
        anchor = row.button
    end
    for i = #list + 1, shown do rows[i].button:Hide(); rows[i].label:Hide(); rows[i].variant = nil end
    shown = #list
    stop:ClearAllPoints()
    stop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
end

function panel.refresh()
    layout()
    for i = 1, shown do
        local row = rows[i]
        local why = unavailable(row.variant)
        row.label:SetText(row.variant.label .. (why and (" - " .. why) or ""))
        if why then row.button:Disable() else row.button:Enable() end
    end
end
panel:SetScript("OnShow", panel.refresh)
TTS:RegisterCallback(function() if panel:IsShown() then panel.refresh() end end)
panel:SetScript("OnHide", function() preview:Stop() end)

InterfaceOptions_AddCategory(panel)

TTSPreview = { panel = panel, rows = rows, count = function() return shown end, box = box, stop = stop, consumer = preview, variants = variants, play = play }
