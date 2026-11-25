-- Removes what a voice should not read from a chat line: link and colour codes, URLs, raid icons, emoticons and
-- stretched letters or punctuation.
local ICONS = { rt1 = "star", rt2 = "circle", rt3 = "diamond", rt4 = "triangle", rt5 = "moon", rt6 = "square",
    rt7 = "cross", rt8 = "skull" }

function TTS_CleanChat(text)
    text = text:gsub("|H[^|]*|h%[?(.-)%]?|h", "%1")             -- item, spell, quest, player links: keep the name
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")   -- colours
    text = text:gsub("|T.-|t", "")                              -- inline textures
    text = text:gsub("{(%a[%w]*)}", function(name)              -- raid target icons: {skull}, {rt8}
        name = name:lower()
        return " " .. (ICONS[name] or name) .. " "
    end)
    text = text:gsub("%f[%S]https?://%S+", "link"):gsub("%f[%S]www%.%S+", "link")
    text = text:gsub("<3", " ")
    text = text:gsub("%f[%S][:;=]%-?[%)%(DPpOo/]%f[%s%z]", " ")   -- :) ;-) :D :P :( :/
    text = text:gsub("%a%a%a+", function(w)                      -- noooooo -> noo
        local out, prev, run = {}, nil, 0
        for c in w:gmatch(".") do
            run = (c == prev) and run + 1 or 1
            prev = c
            if run <= 2 then out[#out + 1] = c end
        end
        return table.concat(out)
    end)
    text = text:gsub("([!?])[!?]+", "%1")                        -- ?!?! -> ?
    return text
end
