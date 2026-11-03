-- Верфь: список кораблей с ценой и статусом (авианосец и линкор — командные, катер и подлодка — личные)
return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local GameState = ctx.GameState
	local VehiclePreview = require(script.Parent.VehiclePreview)
	local gui = UI.screen("ShopUI", 40)
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(680, 540), Visible = false,
	})
	UI.scale(panel)
	UI.padding(panel, 16)
	local title = UI.label(panel, "SHIPYARD", {TextSize = 28, Size = UDim2.new(1, -140, 0, 32)})
	local balance = UI.label(panel, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(300, 26), TextSize = 18, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Right})
	local list = UI.new("Frame", {Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -104), BackgroundTransparency = 1}, panel)
	UI.new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, list)
	local close = UI.button(panel, "CLOSE", T.Panel2, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 46)})
	UI.stroke(close)

	local DEFS = {
		Carrier = {name = Config.Carrier.Name, price = Config.Economy.CarrierPrice, desc = Config.Carrier.Description, team = true},
	}
	for kind, c in pairs(Config.Ships) do
		DEFS[kind] = {name = c.DisplayName, price = c.Price, desc = c.Description, team = c.Team}
	end

	local rows = {}
	local busy = false
	local openTeam, openPos
	local api = {}

	local function status(kind)
		local team = openTeam
		local d = DEFS[kind]
		if kind == "Carrier" then
			local _, text, st = ctx.carrierStatus(team)
			return st, text
		end
		if d.team then
			local active = GameState:GetAttribute(("Ship_%s_%s_Active"):format(kind, team)) or 0
			local sinking = GameState:GetAttribute(("Ship_%s_%s_Sinking"):format(kind, team)) or 0
			local limit = GameState:GetAttribute(("Ship_%s_%s_Limit"):format(kind, team)) or 1
			local text = ("Team ship · afloat %d of %d"):format(active, limit) .. (sinking > 0 and (" · sinking: " .. sinking) or "")
			if active + sinking >= limit then
				return sinking > 0 and "Sinking" or "Full", text
			end
			return "None", text
		end
		local own = player:GetAttribute("Owns_" .. kind)
		own = type(own) == "number" and own or 0
		return "None", own > 0 and ("Personal · yours afloat: " .. own) or "Personal ship · no limit"
	end

	local function refresh()
		if not panel.Visible then return end
		local gold = ctx.stat("Gold")
		local treasury = openTeam and (GameState:GetAttribute("Treasury_" .. openTeam) or 0) or 0
		balance.Text = ("◆ %d · treasury ◆ %d"):format(gold, treasury)
		local tc = openTeam and Config.Teams[openTeam]
		title.TextColor3 = tc and tc.Color or T.Text
		for kind, r in pairs(rows) do
			local d = DEFS[kind]
			local st, text = status(kind)
			r.status.Text = text
			r.status.TextColor3 = (st == "Active" and T.Good) or ((st == "Sinking" or st == "Destroyed") and T.Bad) or T.Muted
			if busy then
				UI.setEnabled(r.buy, false, T.Good, "…")
			elseif st == "Active" then
				UI.setEnabled(r.buy, false, T.Good, "AFLOAT")
			elseif st == "Full" then
				UI.setEnabled(r.buy, false, T.Good, "LIMIT")
			elseif st == "Sinking" or st == "Destroyed" then
				UI.setEnabled(r.buy, false, T.Good, "SINKING")
			else
				local funds = d.team and treasury or gold
				UI.setEnabled(r.buy, true, funds >= d.price and T.Good or T.Panel2, d.team and ("TREASURY · ◆%d"):format(d.price) or ("BUY · ◆%d"):format(d.price))
			end
		end
	end

	for i, kind in ipairs(Config.ShipOrder or {"Carrier"}) do
		local d = DEFS[kind]
		if d then
			local row = UI.new("Frame", {LayoutOrder = i, Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, list)
			UI.corner(row, 8)
			UI.plate(row)
			UI.padding(row, 10)
			local preview = VehiclePreview.new(UI, T, Config, row, kind, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(112, 68)})
			UI.label(row, string.upper(d.name), {Position = UDim2.fromOffset(124, 0), Size = UDim2.new(1, -314, 0, 22), TextSize = 19})
			UI.label(row, d.desc or "", {Position = UDim2.fromOffset(124, 24), Size = UDim2.new(1, -314, 0, 30), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
			local st = UI.label(row, "", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 124, 1, 0), Size = UDim2.new(1, -314, 0, 16), TextSize = 12, Font = UI.Medium})
			local buy = UI.button(row, "BUY", T.Good, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(176, 48), TextSize = 16})
			rows[kind] = {status = st, buy = buy, preview = preview}
			buy.Activated:Connect(function()
				if busy or not buy:GetAttribute("Enabled") then return end
				busy = true
				refresh()
				local res = ctx.invoke("BuyShip", kind)
				busy = false
				UI.toast(res.msg, res.ok and "success" or "error")
				if res.ok then api.close() else refresh() end
			end)
		end
	end

	function api.open(team)
		openTeam = team
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		openPos = hrp and hrp.Position
		for _, r in pairs(rows) do r.preview.paint(team) end
		panel.Visible = true
		refresh()
	end
	function api.close()
		panel.Visible = false
	end
	function api.onState(state)
		if state ~= "Deployed" then api.close() end
	end

	close.Activated:Connect(api.close)
	ctx.Remotes.OpenShop.OnClientEvent:Connect(api.open)
	GameState.AttributeChanged:Connect(refresh)
	player.AttributeChanged:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.Visible then
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp or (openPos and (hrp.Position - openPos).Magnitude > 30) then
					api.close()
				else
					refresh()
				end
			end
		end
	end)
	return api
end
