-- Offline test of the voice preview panel with a stubbed WoW UI API (no game needed).
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local Frame = {}
Frame.__index = function(t, k)
    if Frame[k] then return Frame[k] end
    return function() end
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:SetText(s) self.text = s end
function Frame:GetText() return self.text or "" end
function Frame:CreateFontString() return setmetatable({ scripts = {} }, Frame) end
function Frame:ClearFocus() self.cleared = true end
function Frame:Enable() self.disabled = false end
function Frame:Disable() self.disabled = true end
function CreateFrame(kind, name)
    local f = setmetatable({ scripts = {}, kind = kind }, Frame)
    if name then _G[name] = f end
    return f
end
UIParent = {}
UIDropDownMenu_SetWidth, UIDropDownMenu_SetText, UIDropDownMenu_Initialize, UIDropDownMenu_AddButton = function() end, function() end, function() end, function() end
UIDropDownMenu_CreateInfo = function() return {} end
local categories = {}
function InterfaceOptions_AddCategory(p) categories[#categories + 1] = p end

strmatch = string.match
function geterrorhandler() return error end
dofile("../TTS/Libs/LibStub/LibStub.lua")
dofile("../TTS/Libs/LibTTS-1.0/LibTTS-1.0.lua")
local TTS = LibStub("LibTTS-1.0")
TTSDB = { speed = 1.2 }

local installed = { TTS_Arctic = true, TTS_Kal = true, TTS_ExtraHQ = true, TTS_OtherHQ = true }
local enabledAddon = { TTS_Arctic = true, TTS_Kal = true, TTS_ExtraHQ = true, TTS_OtherHQ = true }
function GetAddOnInfo(name)
    if not installed[name] then return nil end
    return name, name, "", enabledAddon[name], true, enabledAddon[name] and nil or "DISABLED"
end
function IsAddOnLoaded() return false end
function LoadAddOn() end
TTS:DeclareProvider("arctic", { addon = "TTS_Arctic", name = "Arctic", extension = "TTS_OtherHQ" })
TTS:DeclareProvider("kal", { addon = "TTS_Kal", name = "Kal", extension = "TTS_ExtraHQ" })
TTS:DeclareProvider("plain", { addon = "TTS_Plain", name = "Plain" })
installed.TTS_Plain, enabledAddon.TTS_Plain = true, true

-- the providers record what they are asked to say
local asked = {}
for _, id in ipairs({ "arctic", "kal", "plain" }) do
    TTS:RegisterProvider(id, { name = id, features = { speed = { min = 0.6, max = 1.6 }, basic = true },
        Synthesize = function(_, text, options)
            asked[#asked + 1] = { id = id, text = text, basic = options.basic, speed = options.speed }
            return { { path = "x", wait = 0.1 } }
        end })
end

dofile("../TTS/Preview.lua")
local P = TTSPreview
eq(#categories, 1); eq(categories[1].name, "Voice preview"); eq(categories[1].parent, "TTS")
P.panel.refresh()
eq(P.count(), 5, "arctic and kal twice (plain and with extension), plain once")
eq(P.rows[1].variant.basic, true); eq(P.rows[2].variant.basic, nil, "second row of a voice uses the extension")

-- any installed provider is listed, also one that registers later or that declares no "basic" support
TTS:RegisterProvider("late", { name = "Late voice", features = { speed = true }, Synthesize = function() return {} end })
P.panel.refresh()
eq(P.count(), 6, "a voice registered after login gets a row")
eq(P.rows[5].variant.id, "late", "rows are sorted by id"); eq(P.rows[5].button.disabled, false)
TTS.providers.late = nil
P.panel.refresh()
eq(P.count(), 5, "rows follow the provider list")
TTS:DeclareProvider("noplain", { addon = "TTS_Plain", name = "NoPlain", extension = "TTS_OtherHQ", features = { speed = true } })
P.panel.refresh()
eq(P.count(), 6, "an extension voice without 'basic' gets one row, not two")
TTS.known.noplain = nil
P.panel.refresh()
eq(P.count(), 5)
for i = 1, P.count() do eq(P.rows[i].button.disabled, false, P.rows[i].variant.label) end

-- Play speaks the phrase with that voice only; plain rows ask for basic
P.box:SetText("good morning")
P.rows[1].button.scripts.OnClick()
eq(#asked, 1); eq(asked[1].id, "arctic"); eq(asked[1].text, "good morning"); eq(asked[1].basic, true); eq(asked[1].speed, 1.2)
P.rows[2].button.scripts.OnClick()
eq(asked[2].id, "arctic"); eq(asked[2].basic, nil, "with the extension")
P.rows[5].button.scripts.OnClick()
eq(asked[3].id, "plain"); eq(asked[3].basic, nil)
eq(TTSDB.voice, nil, "previewing does not change the chosen voice")

-- availability follows the addon state
installed.TTS_ExtraHQ = false; P.panel.refresh()
eq(P.rows[3].button.disabled, false, "kal without the extension still plays")
eq(P.rows[4].button.disabled, true, "kal with a missing extension cannot play")
assert(P.rows[4].label.text:find("HQ not installed"))
local kalDef = TTS.providers.kal
TTS.providers.kal = nil   -- not loaded, so availability comes from the addon state
installed.TTS_Kal = false; P.panel.refresh()
eq(P.rows[3].button.disabled, true); assert(P.rows[3].label.text:find("not installed"))
installed.TTS_Kal = true; enabledAddon.TTS_Kal = false; P.panel.refresh()
assert(P.rows[3].label.text:find("disabled"))
TTS.providers.kal = kalDef

-- Stop and closing the panel end the preview
TTS:RegisterProvider("arctic", { name = "arctic", features = { speed = true, basic = true },
    Synthesize = function() return { { path = "x", wait = 5 } } end })
P.rows[1].button.scripts.OnClick()
eq(P.consumer:IsBusy(), true)
P.panel.scripts.OnHide()
eq(P.consumer:IsBusy(), false, "hiding the panel stops the preview")
print("voice preview tests passed")
