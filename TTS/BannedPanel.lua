-- Options sub-panel (Interface -> AddOns -> TTS -> Banned phrases): phrases that are masked or left out of the speech.
-- Edits TTSDB.banned; the matching itself is in Banned.lua.
local ROWS = 7   -- the options area is about 413 x 428; see Options.lua
local MODES = { mask = "Mask: first syllable only", skip = "Skip: leave the phrase out", allow = "Allow: never match by sound" }
local NEXT = { mask = "skip", skip = "allow", allow = "mask" }

local panel = CreateFrame("Frame", "TTSBannedPanel", UIParent)
panel.name = "Banned phrases"
panel.parent = "TTS"
panel.okay, panel.cancel, panel.default = function() end, function() end, function() end

local function text(font, x, y, str)
    local fs = panel:CreateFontString(nil, "ARTWORK", font)
    fs:SetPoint("TOPLEFT", x, y)
    if str then fs:SetText(str) end
    return fs
end

text("GameFontNormalLarge", 16, -16, "Banned phrases")
local help = text("GameFontHighlightSmall", 16, -40, "Words that are masked or left out of the speech. Spelling, punctuation and look-alikes are ignored; similar sounding words match too.")
help:SetWidth(380); help:SetHeight(21); help:SetJustifyH("LEFT"); help:SetJustifyV("TOP")

text("GameFontNormalSmall", 16, -64, "Phrase")
local phraseBox = CreateFrame("EditBox", "TTSBannedPhrase", panel, "InputBoxTemplate")
phraseBox:SetPoint("TOPLEFT", 22, -76)
phraseBox:SetWidth(250)
phraseBox:SetHeight(20)
phraseBox:SetAutoFocus(false)
phraseBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

local mode = "mask"
local message = text("GameFontHighlightSmall", 16, -138)
message:SetWidth(380)
message:SetJustifyH("LEFT")

local rows = {}
local pageText, scroll

local function button(name, label, w, x, y)
    local b = CreateFrame("Button", name, panel, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetWidth(w)
    b:SetHeight(22)
    b:SetText(label)
    return b
end

local modeButton = button("TTSBannedMode", MODES.mask, 220, 16, -106)
modeButton:SetScript("OnClick", function()
    mode = NEXT[mode]
    modeButton:SetText(MODES[mode])
end)
local function setMode(m) mode = m; modeButton:SetText(MODES[m]) end

local checks = {}
local function addCheck(key, label, x, y)
    local name = "TTSBannedCheck_" .. key
    local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    _G[name .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self) TTSDB[key] = self:GetChecked() and true or false end)
    checks[key] = cb
end
addCheck("filterBanned", "Filter banned phrases", 14, -362)
addCheck("bannedBySound", "Also match similar sounding words", 14, -388)

local function keys() return TTSDB and TTSDB.banned and TTS_SortedBanned(TTSDB.banned) or {} end

local function refresh()
    local list = keys()
    FauxScrollFrame_Update(scroll, #list, ROWS, 24)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i, row in ipairs(rows) do
        local key = list[offset + i]
        row.key = key
        if key then
            row.label:SetText(key .. "   =>   " .. (MODES[TTSDB.banned[key]] and TTSDB.banned[key] or "mask"))
            row.remove:Show()
            row.edit:Show()
        else
            row.label:SetText("")
            row.remove:Hide()
            row.edit:Hide()
        end
    end
    for key, cb in pairs(checks) do cb:SetChecked(TTSDB and TTSDB[key] ~= false) end
    pageText:SetText(("%d banned phrases"):format(#list))
end
panel.refresh = refresh
panel:SetScript("OnShow", refresh)

local function add()
    if not TTSDB then return end
    TTSDB.banned = TTSDB.banned or {}
    local ok, reason = TTS_AddBanned(TTSDB.banned, phraseBox:GetText(), mode)
    if ok then
        message:SetText("Saved.")
        phraseBox:SetText("")
        phraseBox:ClearFocus()
    else
        message:SetText("|cffff5555" .. reason .. "|r")
    end
    refresh()
end
local addButton = button("TTSBannedAdd", "Add / change", 100, 282, -75)
addButton:SetScript("OnClick", add)
phraseBox:SetScript("OnEnterPressed", add)

for i = 1, ROWS do
    local row = {}
    local y = -156 - (i - 1) * 24
    row.label = text("GameFontHighlight", 22, y - 5)
    row.label:SetWidth(224)
    row.label:SetJustifyH("LEFT")
    row.edit = button("TTSBannedEdit" .. i, "Edit", 44, 250, y)
    row.remove = button("TTSBannedRemove" .. i, "Delete", 56, 298, y)
    row.edit:SetScript("OnClick", function()
        if not row.key then return end
        phraseBox:SetText(row.key); setMode(MODES[TTSDB.banned[row.key]] and TTSDB.banned[row.key] or "mask")
        message:SetText("Change the phrase or the mode and press Add / change.")
    end)
    row.remove:SetScript("OnClick", function()
        if not row.key then return end
        TTSDB.banned[row.key] = nil
        message:SetText("Deleted.")
        refresh()
    end)
    rows[i] = row
end

-- the scroll bar sits to the right of the rows; the mouse wheel works anywhere over the list
scroll = CreateFrame("ScrollFrame", "TTSBannedScroll", panel, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 16, -154)
scroll:SetWidth(350)
scroll:SetHeight(ROWS * 24)
scroll:SetScript("OnVerticalScroll", function(self, delta)
    FauxScrollFrame_OnVerticalScroll(self, delta, 24, refresh)
end)
panel:EnableMouseWheel(true)
panel:SetScript("OnMouseWheel", function(_, delta)
    local bar = _G["TTSBannedScrollScrollBar"]
    if bar then bar:SetValue(bar:GetValue() - delta * 24 * 3) end
end)
pageText = text("GameFontHighlightSmall", 16, -335)

InterfaceOptions_AddCategory(panel)

TTSBannedUI = { panel = panel, checks = checks, rows = rows, phrase = phraseBox, mode = modeButton, add = addButton, message = message,
    scroll = scroll, ROWS = ROWS }
function TTS_OpenBanned()
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end
