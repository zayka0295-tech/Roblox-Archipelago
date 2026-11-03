-- Выбор точки появления: база, авианосец или аэродром острова (Config.IslandAirfield — пока остров у команды).
-- В лобби открывается с плиты DEPLOY (Remotes.OpenSpawnMenu), в бою — из HUD (смена точки).
-- В карточках — мини-модели (VehiclePreview): база, авианосец и центральный остров в цвете команды; недоступный — серый.
return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local VehiclePreview = require(script.Parent.VehiclePreview)
	local gui = UI.screen("SpawnSelectionUI", 30)
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(780, 400), Visible = false,
	})
	UI.scale(panel)
	UI.padding(panel, 18)
	UI.label(panel, "SPAWN POINT", {TextSize = 24, Size = UDim2.new(1, 0, 0, 28)})
	local teamLine = UI.label(panel, "", {Position = UDim2.fromOffset(0, 30), TextSize = 15, Font = UI.Medium, TextColor3 = T.Muted})

	local mode = "deploy"
	local options = {}
	local function makeCard(key, title, i, model, zoom)
		local card = UI.new("TextButton", {
			AutoButtonColor = false, Text = "", Position = UDim2.new((i - 1) / 3, (i - 1) * 4, 0, 66),
			Size = UDim2.new(1 / 3, -8, 0, 220), BackgroundColor3 = T.Panel2, BorderSizePixel = 0,
		}, panel)
		UI.corner(card, 8)
		local stroke = UI.stroke(card, T.Line, 1)
		UI.label(card, title, {Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 30), TextSize = 24})
		-- мини-модель вместо описания (клик проходит на карточку)
		local preview = VehiclePreview.new(UI, T, Config, card, model, {
			Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 118), Active = false,
		}, zoom)
		local tag = UI.label(card, "", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -10), Size = UDim2.new(1, -32, 0, 40), TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Bottom})
		options[key] = {card = card, stroke = stroke, preview = preview, tag = tag}
		local busy = false
		card.Activated:Connect(function()
			if busy then return end
			busy = true
			local res = ctx.invoke("SelectSpawn", key)
			busy = false
			if not res.ok then
				UI.toast(res.msg, "error")
			elseif mode == "change" then
				UI.toast(res.msg, "success")
			end
		end)
	end
	local _, _, airDef = ctx.islandStatus(nil)
	makeCard("Base", "BASE", 1, "Base", 1.1)
	makeCard("Carrier", "CARRIER", 2, "Carrier", 1.15)
	makeCard("Island", "AIRFIELD " .. (airDef and airDef.Letter or ""), 3, "CentralIsland", 1.2)

	local back = UI.button(panel, "CLOSE", T.Panel2, {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(0.34, 0, 0, 50)})
	UI.stroke(back)
	local deploy = UI.button(panel, "DEPLOY", T.Good, {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.new(0.62, 0, 0, 50), TextSize = 22})

	local function refresh()
		if not panel.Visible then return end
		local team = ctx.team()
		local tc = team and Config.Teams[team]
		teamLine.Text = tc and ("Team: " .. tc.DisplayName) or "No team selected"
		teamLine.TextColor3 = tc and tc.Color or T.Muted
		local choice = player:GetAttribute("SpawnChoice") or "Base"
		local available, ctext = ctx.carrierStatus(team)

		options.Base.tag.Text = "HOME ISLAND · AVAILABLE"
		options.Base.tag.TextColor3 = T.Good
		options.Carrier.tag.Text = available and ("AVAILABLE · " .. ctext) or ("LOCKED · " .. ctext)
		options.Carrier.tag.TextColor3 = available and T.Good or T.Bad
		options.Carrier.card.BackgroundColor3 = available and T.Panel2 or Color3.fromRGB(30, 30, 36)
		local isl, itext = ctx.islandStatus(team)
		options.Island.tag.Text = isl and ("AVAILABLE · " .. itext) or ("LOCKED · " .. itext)
		options.Island.tag.TextColor3 = isl and T.Good or T.Bad
		options.Island.card.BackgroundColor3 = isl and T.Panel2 or Color3.fromRGB(30, 30, 36)
		-- модели — в цвет команды; недоступные — серые и приглушённые
		for _, o in pairs(options) do o.preview.paint(team) end
		for key, ok in pairs({Carrier = available, Island = isl}) do
			local vp = options[key].preview.frame
			vp.ImageColor3 = ok and Color3.new(1, 1, 1) or Color3.fromRGB(150, 150, 160)
			vp.ImageTransparency = ok and 0 or 0.2
		end

		for key, o in pairs(options) do
			local sel = key == choice
			o.stroke.Color = sel and (tc and tc.Color or T.Accent) or T.Line
			o.stroke.Thickness = sel and 3 or 1
		end
		deploy.Visible = mode == "deploy"
		back.Size = mode == "deploy" and UDim2.new(0.34, 0, 0, 50) or UDim2.new(1, 0, 0, 50)
	end

	local api = {}
	function api.open(m)
		mode = m or "deploy"
		panel.Visible = true
		if mode == "deploy" and ctx.screens.LobbyUI then ctx.screens.LobbyUI.hide() end
		refresh()
	end
	function api.close()
		panel.Visible = false
		if mode == "deploy" and ctx.state() == "Lobby" and ctx.screens.LobbyUI then ctx.screens.LobbyUI.show() end
	end
	function api.onState(state)
		if panel.Visible and ((mode == "deploy" and state ~= "Lobby") or (mode == "change" and state ~= "Deployed")) then
			panel.Visible = false
		end
	end

	back.Activated:Connect(api.close)
	local busy = false
	deploy.Activated:Connect(function()
		if busy then return end
		busy = true
		deploy.Text = "…"
		local res = ctx.invoke("Deploy")
		busy = false
		deploy.Text = "DEPLOY"
		UI.toast(res.msg, res.ok and "success" or "error")
		if res.ok then panel.Visible = false end
	end)

	ctx.Remotes:WaitForChild("OpenSpawnMenu").OnClientEvent:Connect(function()
		if ctx.state() == "Lobby" then api.open("deploy") end
	end)
	player:GetAttributeChangedSignal("SpawnChoice"):Connect(refresh)
	player:GetPropertyChangedSignal("Team"):Connect(refresh)
	ctx.GameState.AttributeChanged:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
	return api
end
