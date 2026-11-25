local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not LoggingChat() then LoggingChat(true) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffTTS_ChatLog:|r chat logging on (Logs\\WoWChatLog.txt)")
end)
