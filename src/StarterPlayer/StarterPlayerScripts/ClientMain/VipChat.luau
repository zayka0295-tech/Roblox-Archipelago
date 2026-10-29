-- Чат: у VIP (атрибут игрока VIP) перед именем золотой тег [👑 VIP] и золотое имя.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

return function(ctx)
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then return {} end
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local src = message.TextSource
		local p = src and Players:GetPlayerByUserId(src.UserId)
		if p and p:GetAttribute("VIP") == true then
			props.PrefixText = '<font color="#FFC832"><b>[👑 VIP]</b></font> <font color="#FFD86A">' .. message.PrefixText .. "</font>"
		end
		return props
	end
	return {}
end
