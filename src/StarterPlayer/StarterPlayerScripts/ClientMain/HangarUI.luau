-- Ангар (терминал аэродрома и палубы): список самолётов с ценой и статусом, как верфь (ShopUI).
-- Открывает сервер (Remotes.OpenHangar), выбор — Remotes.BuyPlane; отказ сервер объясняет уведомлением.
return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local VehiclePreview = require(script.Parent.VehiclePreview)
	local gui = UI.screen("HangarUI", 40)
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(680, 130 + 96 * #(Config.PlaneOrder or {"Fighter"})), Visible = false,
	})
	UI.scale(panel)
	UI.padding(panel, 16)
	local title = UI.label(panel, "HANGAR", {TextSize = 28, Size = UDim2.new(1, -140, 0, 32)})
	local balance = UI.money(panel, {{UI.Icons.Gold, T.Gold}}, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(300, 28), TextSize = 18})
	local list = UI.new("Frame", {Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -104), BackgroundTransparency = 1}, panel)
	UI.new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, list)
	local close = UI.button(panel, "CLOSE", T.Panel2, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 46)})
	UI.stroke(close)

	local rows = {}
	local busy = false
	local openTeam, openPos
	local api = {}

	-- сколько самолётов типа kind у команды в воздухе (кроме моего — его заменит новый)
	local function teamPlanes(kind)
		local f = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Planes")
		local n = 0
		for _, m in ipairs(f and f:GetChildren() or {}) do
			if m:GetAttribute("IsPlane") and m:GetAttribute("Team") == openTeam and (not kind or m:GetAttribute("PlaneType") == kind)
				and m.Name ~= (m:GetAttribute("PlaneType") or "") .. "_" .. player.Name then
				n += 1
			end
		end
		return n
	end

	local function refresh()
		if not panel.Visible then return end
		local gold = ctx.stat("Gold")
		balance(1, tostring(gold))
		local tc = openTeam and Config.Teams[openTeam]
		title.TextColor3 = tc and tc.Color or T.Text
		local L = Config.Limits or {}
		local total = teamPlanes(nil)
		for kind, r in pairs(rows) do
			local P = Config.Planes[kind]
			local limit, n = L.PlanesPerTeam or 99, total
			if kind == "Bomber" and L.BombersPerTeam then limit, n = L.BombersPerTeam, teamPlanes("Bomber") end
			if P.Heli and L.HelisPerTeam then limit, n = L.HelisPerTeam, teamPlanes(kind) end
			local full = n >= limit or total >= (L.PlanesPerTeam or 99)
			local noun = kind == "Bomber" and "bombers" or P.Heli and "helicopters" or "planes"
			r.status.Text = P.Heli and ("Team %s airborne: %d of %d · seats 2"):format(noun, n, limit)
				or ("Team %s airborne: %d of %d · bombs %d"):format(noun, n, limit, P.Bombs or 0)
			r.status.TextColor3 = full and T.Bad or T.Muted
			if busy then
				UI.setEnabled(r.buy, false, T.Good, "…")
			elseif full then
				UI.setEnabled(r.buy, false, T.Good, "LIMIT")
			else
				UI.setEnabled(r.buy, true, gold >= P.Price and T.Good or T.Panel2, ("TAKE OFF · ◆%d"):format(P.Price))
			end
		end
	end

	for i, kind in ipairs(Config.PlaneOrder or {"Fighter"}) do
		local P = Config.Planes[kind]
		if P then
			local row = UI.new("Frame", {LayoutOrder = i, Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, list)
			UI.corner(row, 8)
			UI.plate(row)
			UI.padding(row, 10)
			local preview = VehiclePreview.new(UI, T, Config, row, kind, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(112, 68)})
			UI.label(row, string.upper(P.DisplayName), {Position = UDim2.fromOffset(124, 0), Size = UDim2.new(1, -314, 0, 22), TextSize = 19})
			UI.label(row, P.Description or "", {Position = UDim2.fromOffset(124, 24), Size = UDim2.new(1, -314, 0, 30), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
			local st = UI.label(row, "", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 124, 1, 0), Size = UDim2.new(1, -314, 0, 16), TextSize = 12, Font = UI.Medium})
			local buy = UI.button(row, "TAKE OFF", T.Good, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(176, 48), TextSize = 16})
			rows[kind] = {status = st, buy = buy, preview = preview}
			buy.Activated:Connect(function()
				if busy or not buy:GetAttribute("Enabled") then return end
				busy = true
				refresh()
				local res = ctx.invoke("BuyPlane", kind)
				busy = false
				if res.msg then UI.toast(res.msg, res.ok and "success" or "error") end
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
	ctx.Remotes:WaitForChild("OpenHangar").OnClientEvent:Connect(api.open)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.Visible then
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not hrp or (hum and hum.SeatPart) or (openPos and (hrp.Position - openPos).Magnitude > 30) then
					api.close()
				else
					refresh()
				end
			end
		end
	end)
	return api
end
