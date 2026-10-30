-- Панель островов: сколько островов у каждой команды и кто владеет каждым (только чтение состояния сервера)
local RunService = game:GetService("RunService")

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local GameState = ctx.GameState
	local player = ctx.player
	local gui = UI.screen("IslandsUI", 6)
	local panel = UI.panel(gui, {
		Name = "Islands", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), -- на одном уровне с панелью золота (HUD.Stats)
		Size = UDim2.fromOffset(290, 92),
	})
	UI.scale(panel)
	UI.padding(panel, 10)
	UI.label(panel, "ISLANDS", {Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = T.Muted})
	local score = UI.label(panel, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.6, 0, 0, 18), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, RichText = true})
	local row = UI.new("Frame", {Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1}, panel)
	UI.new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, row)
	local chips = {}
	for i, def in ipairs(Config.Islands) do
		local chip = UI.new("TextLabel", {
			LayoutOrder = i, Size = UDim2.fromOffset(def.IsCenter and 32 or 25, 30), BackgroundColor3 = T.Panel2,
			Text = def.Letter or def.Id, TextColor3 = Color3.new(1, 1, 1), Font = UI.Bold, TextSize = 13,
		}, row)
		UI.corner(chip, 6)
		-- центр — золотая рамка, нефтяные платформы — бирюзовая
		local accent = def.IsRig and Color3.fromRGB(90, 220, 200) or Color3.fromRGB(255, 220, 120)
		local stroke = UI.new("UIStroke", {ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = (def.IsCenter or def.IsRig) and 2 or 1, Color = accent, Transparency = (def.IsCenter or def.IsRig) and 0 or 1}, chip)
		chips[def.Id] = {chip = chip, stroke = stroke}
	end
	local note = UI.label(panel, "", {Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Font = UI.Medium, TextColor3 = T.Muted})

	local function colorOf(owner)
		local t = Config.Teams[owner]
		return t and t.Color or Color3.fromRGB(70, 75, 85)
	end
	local function refresh()
		local blue = GameState:GetAttribute("Islands_Blue") or 0
		local red = GameState:GetAttribute("Islands_Red") or 0
		local bc, rc = colorOf("Blue"):ToHex(), colorOf("Red"):ToHex()
		score.Text = ('<font color="#%s">%d</font>  :  <font color="#%s">%d</font>'):format(bc, blue, rc, red)
		local my
		for key, t in pairs(Config.Teams) do
			if player.Team and (player.Team.Name == key or player.Team.Name == t.DisplayName) then my = key end
		end
		local mine = my == "Blue" and blue or my == "Red" and red or 0
		local treasury = my and (GameState:GetAttribute("Treasury_" .. my) or 0) or 0
		note.Text = my and ("Team treasury: ◆ %d · islands %d"):format(treasury, mine) or "Capture islands to earn gold"
		note.TextColor3 = my and T.Gold or T.Muted
	end
	GameState.AttributeChanged:Connect(refresh)
	player:GetPropertyChangedSignal("Team"):Connect(refresh)
	refresh()

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		local blink = (math.sin(t * 8) + 1) / 2
		for id, c in pairs(chips) do
			local owner = GameState:GetAttribute("Island_" .. id .. "_Owner") or "Neutral"
			local contested = GameState:GetAttribute("Island_" .. id .. "_Contested")
			local capturing = GameState:GetAttribute("Island_" .. id .. "_Capturing") or ""
			local base = colorOf(owner)
			if contested then
				c.chip.BackgroundColor3 = base:Lerp(Color3.fromRGB(255, 200, 60), blink)
			elseif capturing ~= "" then
				c.chip.BackgroundColor3 = base:Lerp(colorOf(capturing), blink * 0.7)
			else
				c.chip.BackgroundColor3 = base
			end
		end
	end)
	-- над островами: издалека — маленький значок, вблизи — подробная табличка
	local NEAR = 380
	local acc2 = 0
	RunService.Heartbeat:Connect(function(dt)
		acc2 += dt
		if acc2 < 0.2 then return end
		acc2 = 0
		local cam = workspace.CurrentCamera
		local neutral = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Neutral")
		if not cam or not neutral then return end
		for _, def in ipairs(Config.Islands) do
			local o = neutral:FindFirstChild(def.Outpost)
			local anchor = o and o:FindFirstChild("Capture") and o.Capture:FindFirstChild("LabelAnchor")
			if anchor then
				local near = (cam.CFrame.Position - anchor.Position).Magnitude < NEAR
				local panel = anchor:FindFirstChild("CaptureGui")
				local badge = anchor:FindFirstChild("IslandBadge")
				if panel then panel.Enabled = near end
				if badge then badge.Enabled = not near end
			end
		end
	end)
	return {}
end
