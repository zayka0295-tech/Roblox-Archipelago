-- Игровой HUD: команда, золото, K/D, авианосец, кнопки
return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local gui = UI.screen("HUD", 10)

	-- статистика сверху по центру (видна всегда)
	local stats = UI.panel(gui, {Name = "Stats", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(420, 46)})
	UI.scale(stats)
	local function coin(image, x)
		return UI.new("ImageLabel", {AnchorPoint = Vector2.new(0, 0.5), Position = x, Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1,
			Image = image, ScaleType = Enum.ScaleType.Fit}, stats)
	end
	coin(UI.Icons.Gold, UDim2.new(0, 10, 0.5, 0))
	local gold = UI.label(stats, "0", {Position = UDim2.fromOffset(48, 0), Size = UDim2.new(0.38, -48, 1, 0), TextColor3 = T.Gold, TextSize = 22, Font = UI.Display})
	-- диаманты (премиальная валюта): атрибут игрока Diamonds
	coin(UI.Icons.Diamond, UDim2.new(0.39, 0, 0.5, 0))
	local diamonds = UI.label(stats, "0", {Position = UDim2.new(0.39, 38, 0, 0), Size = UDim2.new(0.25, -38, 1, 0),
		TextColor3 = Color3.fromRGB(120, 220, 255), TextSize = 22, Font = UI.Display})
	for _, l in ipairs({gold, diamonds}) do UI.new("UIStroke", {Color = UI.Outline, Thickness = 1.5}, l) end
	local kd = UI.label(stats, "K 0 · D 0", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0.36, -16, 1, 0), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right})

	-- левая колонка (только в бою)
	local side = UI.new("Frame", {Name = "Side", Position = UDim2.fromOffset(16, 72), Size = UDim2.fromOffset(250, 300), BackgroundTransparency = 1}, gui)
	UI.scale(side)
	local badge = UI.panel(side, {Size = UDim2.new(1, 0, 0, 74)})
	local bar = UI.new("Frame", {Size = UDim2.new(0, 6, 1, -16), Position = UDim2.fromOffset(10, 8), BorderSizePixel = 0, BackgroundColor3 = T.Muted}, badge)
	UI.corner(bar, 3)
	local teamLbl = UI.label(badge, "NO TEAM", {Position = UDim2.fromOffset(26, 8), Size = UDim2.new(1, -34, 0, 24), TextSize = 19})
	local carrierLbl = UI.label(badge, "", {Position = UDim2.fromOffset(26, 34), Size = UDim2.new(1, -34, 0, 32), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})

	local btnSpawn = UI.button(side, "SPAWN POINT", T.Panel2, {Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 40), TextSize = 15})
	local btnBoard = UI.button(side, "LEADERS", T.Panel2, {Position = UDim2.fromOffset(0, 130), Size = UDim2.new(0.5, -4, 0, 40), TextSize = 15})
	local btnLobby = UI.button(side, "LOBBY", T.Panel2, {Position = UDim2.new(0.5, 4, 0, 130), Size = UDim2.new(0.5, -4, 0, 40), TextSize = 15})
	local spawnInfo = UI.label(side, "", {Position = UDim2.fromOffset(2, 176), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted})
	for _, b in ipairs({btnSpawn, btnBoard, btnLobby}) do UI.stroke(b) end

	local function refreshStats()
		gold.Text = tostring(ctx.stat("Gold"))
		diamonds.Text = tostring(player:GetAttribute("Diamonds") or 0)
		kd.Text = ("K %d · D %d"):format(ctx.stat("Kills"), ctx.stat("Deaths"))
	end
	player:GetAttributeChangedSignal("Diamonds"):Connect(function() refreshStats() end)
	local function refreshTeam()
		local team = ctx.team()
		if team then
			local c = Config.Teams[team]
			bar.BackgroundColor3 = c.Color
			teamLbl.Text = string.upper(c.DisplayName)
			teamLbl.TextColor3 = c.Color
			local _, text = ctx.carrierStatus(team)
			carrierLbl.Text = "Carrier: " .. text
		else
			bar.BackgroundColor3 = T.Muted
			teamLbl.Text = "NO TEAM"
			teamLbl.TextColor3 = T.Text
			carrierLbl.Text = ""
		end
		local choice = player:GetAttribute("SpawnChoice")
		spawnInfo.Text = "Next spawn: " .. (choice == "Carrier" and "carrier" or choice == "Island" and "island airfield" or "base")
	end

	local function hookStats(ls)
		for _, v in ipairs(ls:GetChildren()) do
			if v:IsA("ValueBase") then v.Changed:Connect(refreshStats) end
		end
		ls.ChildAdded:Connect(function(v)
			if v:IsA("ValueBase") then v.Changed:Connect(refreshStats) end
			refreshStats()
		end)
		refreshStats()
	end
	local existing = player:FindFirstChild("leaderstats")
	if existing then hookStats(existing) end
	player.ChildAdded:Connect(function(c)
		if c.Name == "leaderstats" then hookStats(c) end
	end)
	player:GetPropertyChangedSignal("Team"):Connect(refreshTeam)
	player:GetAttributeChangedSignal("SpawnChoice"):Connect(refreshTeam)
	ctx.GameState.AttributeChanged:Connect(refreshTeam)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshTeam()
		end
	end)

	btnSpawn.Activated:Connect(function()
		ctx.screens.SpawnSelectionUI.open("change")
	end)
	btnBoard.Activated:Connect(function()
		ctx.screens.LeaderboardUI.toggle()
	end)
	local busy = false
	btnLobby.Activated:Connect(function()
		if busy then return end
		busy = true
		local res = ctx.invoke("ReturnToLobby")
		UI.toast(res.msg, res.ok and "success" or "error")
		busy = false
	end)

	refreshStats()
	refreshTeam()

	local api = {}
	function api.onState(state)
		side.Visible = state == "Deployed"
	end
	return api
end
