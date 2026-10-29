-- Таблица лидеров: по кнопке LEADERS (в лобби есть большая доска в мире — окно там не показываем).
-- VIP на сервере — с короной и золотым именем.
local Players = game:GetService("Players")

return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local gui = UI.screen("LeaderboardUI", 5)
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 20),
		Size = UDim2.fromOffset(310, 440),
	})
	UI.scale(panel)
	UI.padding(panel, 14)
	UI.label(panel, "TOP PLAYERS", {TextColor3 = T.Accent, TextSize = 22, Size = UDim2.new(1, 0, 0, 26)})
	UI.label(panel, "by kills", {Position = UDim2.fromOffset(0, 26), TextColor3 = T.Muted, Font = UI.Medium, TextSize = 14, Size = UDim2.new(1, 0, 0, 18)})
	local header = UI.new("Frame", {Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1}, panel)
	UI.label(header, "#", {Size = UDim2.new(0, 30, 1, 0), TextColor3 = T.Muted, TextSize = 13})
	UI.label(header, "PLAYER", {Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -110, 1, 0), TextColor3 = T.Muted, TextSize = 13})
	UI.label(header, "KILLS", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 70, 1, 0), TextColor3 = T.Muted, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right})
	local list = UI.new("Frame", {Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 1, -78), BackgroundTransparency = 1}, panel)
	UI.new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)

	local data = {}
	local shownInGame = false
	local api = {}

	local function render()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
		end
		if #data == 0 then
			UI.label(list, "Nobody yet — be the first", {TextColor3 = T.Muted, Font = UI.Medium, TextSize = 15, Size = UDim2.new(1, 0, 0, 30)})
			return
		end
		for i, e in ipairs(data) do
			if i > 12 then break end
			local me = e.userId == ctx.player.UserId
			local row = UI.new("Frame", {
				LayoutOrder = i, Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = me and Color3.fromRGB(30, 52, 72) or (i % 2 == 0 and T.Panel2 or T.Panel),
				BackgroundTransparency = me and 0 or 0.3, BorderSizePixel = 0,
			}, list)
			UI.corner(row, 4)
			local c = i <= 3 and T.Gold or T.Text
			UI.label(row, tostring(e.rank or i), {Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 26, 1, 0), TextColor3 = c, TextSize = 15})
			local online = Players:GetPlayerByUserId(e.userId or 0)
			local vip = online and online:GetAttribute("VIP") == true
			UI.label(row, (vip and "👑 " or "") .. tostring(e.name), {Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -110, 1, 0), TextColor3 = vip and Color3.fromRGB(255, 200, 50) or (me and T.Accent or c), TextSize = 15, Font = UI.Medium, TextTruncate = Enum.TextTruncate.AtEnd})
			UI.label(row, tostring(e.kills), {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 60, 1, 0), TextColor3 = c, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right})
		end
	end

	ctx.Remotes.LeaderboardUpdated.OnClientEvent:Connect(function(newList)
		if type(newList) == "table" then
			data = newList
			render()
		end
	end)
	task.spawn(function()
		local ok, res = pcall(function()
			return ctx.Remotes.GetLeaderboard:InvokeServer()
		end)
		if ok and type(res) == "table" then
			data = res
		end
		render()
	end)

	function api.onState(state)
		panel.Visible = state ~= "Lobby" and shownInGame
	end
	function api.toggle()
		shownInGame = not shownInGame
		api.onState(ctx.state())
	end
	return api
end
