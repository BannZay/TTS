-- Options sub-panel (Interface -> AddOns -> TTS -> Word replacements): the words that are read as something else.
-- Edits TTSDB.replacements; the lookup itself is in Expand.lua.
local ROWS = 10   -- the options area is about 413 x 428; see Options.lua

local panel = CreateFrame("Frame", "TTSReplacementsPanel", UIParent)
panel.name = "Word replacements"
panel.parent = "TTS"
panel.okay, panel.cancel, panel.default = function() end, function() end, function() end

local function text(font, x, y, str)
    local fs = panel:CreateFontString(nil, "ARTWORK", font)
    fs:SetPoint("TOPLEFT", x, y)
    if str then fs:SetText(str) end
    return fs
end

text("GameFontNormalLarge", 16, -16, "Word replacements")
local help = text("GameFontHighlightSmall", 16, -40, "Whole words in chat are read as the text you set. Letters, digits and apostrophes only.")
help:SetWidth(380); help:SetHeight(21); help:SetJustifyH("LEFT"); help:SetJustifyV("TOP")

local function edit(name, x, w)
    local e = CreateFrame("EditBox", name, panel, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", x, -76)
    e:SetWidth(w)
    e:SetHeight(20)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end
text("GameFontNormalSmall", 16, -64, "Word")
text("GameFontNormalSmall", 120, -64, "Read as")
local wordBox = edit("TTSReplaceWord", 22, 90)
local readBox = edit("TTSReplaceRead", 126, 116)

local message = text("GameFontHighlightSmall", 16, -102)
message:SetWidth(380)
message:SetJustifyH("LEFT")

local TTSLib = LibStub("LibTTS-1.0")
local speaker = TTSLib:NewConsumer("TTS Replacements")   -- own handle: never touches the chat reading
local rows = {}
local pageText, scroll

local total = 0
-- the Word box doubles as a search box: what is typed in it filters the list (substring, case-insensitive)
local function keys()
    local all = TTSDB and TTSDB.replacements and TTS_SortedReplacements(TTSDB.replacements) or {}
    total = #all
    local q = wordBox:GetText():lower()
    if q == "" then return all end
    local found = {}
    for _, k in ipairs(all) do
        if k:lower():find(q, 1, true) then found[#found + 1] = k end
    end
    return found
end

local function refresh()
    local list = keys()
    FauxScrollFrame_Update(scroll, #list, ROWS, 24)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i, row in ipairs(rows) do
        local key = list[offset + i]
        row.key = key
        if key then
            row.label:SetText(key .. "   =>   " .. TTSDB.replacements[key])
            row.remove:Show()
            row.edit:Show()
            row.play:Show()
        else
            row.label:SetText("")
            row.remove:Hide()
            row.edit:Hide()
            row.play:Hide()
        end
    end
    pageText:SetText(#list == total and ("%d replacements"):format(total) or ("%d of %d replacements"):format(#list, total))
end
panel.refresh = refresh
panel:SetScript("OnShow", refresh)

local function button(name, label, w, x, y)
    local b = CreateFrame("Button", name, panel, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetWidth(w)
    b:SetHeight(22)
    b:SetText(label)
    return b
end

local function add()
    if not TTSDB then return end
    local ok, reason = TTS_AddReplacement(TTSDB.replacements, wordBox:GetText(), readBox:GetText())
    if ok then
        message:SetText("Saved.")
        wordBox:SetText(""); readBox:SetText("")
        wordBox:ClearFocus(); readBox:ClearFocus()
    else
        message:SetText("|cffff5555" .. reason .. "|r")
    end
    refresh()
end
local function say(str)
    if not (str and str ~= "" and TTSDB) then return end
    speaker:Stop()
    speaker:Speak(str, { speed = TTSDB.speed, pause = TTSDB.pause, ending = TTSDB.ending, interrupt = true })
end
local playRead = button("TTSReplacePlayRead", "Play", 40, 248, -75)
playRead:SetScript("OnClick", function() say(readBox:GetText()) end)
local addButton = button("TTSReplaceAdd", "Add / change", 100, 292, -75)
addButton:SetScript("OnClick", add)
wordBox:SetScript("OnEnterPressed", function() readBox:SetFocus() end)
wordBox:SetScript("OnTextChanged", function(_, userInput)
    if not userInput then return end   -- Edit / Add fill and clear the box themselves
    local bar = _G["TTSReplaceScrollScrollBar"]
    if bar then bar:SetValue(0) end
    refresh()
end)
readBox:SetScript("OnEnterPressed", add)

for i = 1, ROWS do
    local row = {}
    local y = -124 - (i - 1) * 24
    row.label = text("GameFontHighlight", 22, y - 5)
    row.label:SetWidth(180)
    row.label:SetJustifyH("LEFT")
    row.play = button("TTSReplacePlay" .. i, "Play", 40, 206, y)
    row.edit = button("TTSReplaceEdit" .. i, "Edit", 44, 250, y)
    row.remove = button("TTSReplaceRemove" .. i, "Delete", 56, 298, y)
    row.play:SetScript("OnClick", function()
        if row.key then say(TTSDB.replacements[row.key]) end
    end)
    row.edit:SetScript("OnClick", function()
        if not row.key then return end
        wordBox:SetText(row.key); readBox:SetText(TTSDB.replacements[row.key])
        message:SetText("Change the text and press Add / change.")
    end)
    row.remove:SetScript("OnClick", function()
        if not row.key then return end
        TTSDB.replacements[row.key] = nil
        message:SetText("Deleted.")
        refresh()
    end)
    rows[i] = row
end

-- the scroll bar sits to the right of the rows; the mouse wheel works anywhere over the list
scroll = CreateFrame("ScrollFrame", "TTSReplaceScroll", panel, "FauxScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 16, -122)
scroll:SetWidth(350)
scroll:SetHeight(ROWS * 24)
scroll:SetScript("OnVerticalScroll", function(self, delta)
    FauxScrollFrame_OnVerticalScroll(self, delta, 24, refresh)
end)
panel:EnableMouseWheel(true)
panel:SetScript("OnMouseWheel", function(_, delta)
    local bar = _G["TTSReplaceScrollScrollBar"]
    if bar then bar:SetValue(bar:GetValue() - delta * 24 * 3) end
end)

pageText = text("GameFontHighlightSmall", 16, -377)

local reset = button("TTSReplaceReset", "Restore defaults", 120, 276, -372)
reset:SetScript("OnClick", function()
    if not TTSDB then return end
    TTS_ResetReplacements(TTSDB.replacements)
    message:SetText("Default list restored.")
    refresh()
end)

InterfaceOptions_AddCategory(panel)

TTSReplacementsUI = { panel = panel, rows = rows, word = wordBox, read = readBox, add = addButton, playRead = playRead, reset = reset,
    message = message, scroll = scroll, ROWS = ROWS }
function TTS_OpenReplacements()
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end
