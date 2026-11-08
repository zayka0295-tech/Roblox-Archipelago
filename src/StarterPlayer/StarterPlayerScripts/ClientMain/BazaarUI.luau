-- Военный базар (BazaarService): E у прилавка на площади базы — окно магазина (Remotes.OpenBazaar).
-- Строка на предмет (Config.Bazaar.Items): крутящаяся мини-модель (VehiclePreviews[Preview]), описание, цена в диамантах.
-- Купленное — по атрибуту игрока Items (биты). После покупки — карточка «куплено» с большой 3D-моделью.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VehiclePreview = require(script.Parent.VehiclePreview)

local DIAMOND = Color3.fromRGB(120, 220, 255)

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local gui = UI.screen("BazaarUI", 40)

	-- ViewportFrame с моделью kind, которая медленно крутится (views обновляет RenderStepped)
	local views = {}
	local function view(parent, kind, props, zoom)
		local vp = VehiclePreview.frame(UI, parent, props)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		cam.Parent = vp
		vp.CurrentCamera = cam
		local v = {vp = vp, cam = cam}
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild("VehiclePreviews", 30)
			local tpl = folder and folder:WaitForChild(kind, 10)
			-- пока ждали модель, карточку могли уже заменить (showBought) — не держим мёртвую запись в views
			if not tpl or not vp.Parent then return end
			local m = tpl:Clone()
			local team = player.Team and player.Team.Name
			local tc = team and Config.Teams[team]
			for _, d in ipairs(m:GetDescendants()) do
				if tc and d:IsA("BasePart") and d:GetAttribute("TeamPaint") then d.Color = tc.Color end
			end
			m.Parent = vp
			local cf, size = m:GetBoundingBox()
			v.center = cf.Position
			v.dist = size.Magnitude / 2 / math.tan(math.rad(cam.FieldOfView / 2)) * 0.7 / (zoom or 1)
			table.insert(views, v)
		end)
		return v
	end

	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(680, 240), Visible = false,
	})
	UI.scale(panel)
	UI.padding(panel, 16)
	UI.label(panel, "★ MILITARY BAZAAR", {TextSize = 28, Size = UDim2.new(1, -160, 0, 32), TextColor3 = T.Gold})
	local balance = UI.money(panel, {{UI.Icons.Diamond, DIAMOND}}, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(200, 28), TextSize = 20})
	local list = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -104), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
	}, panel)
	UI.new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, list)
	local close = UI.button(panel, "CLOSE", T.Panel2, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 46)})
	UI.stroke(close)

	-- карточка «куплено»: большая модель крутится, название и как пользоваться
	local done = UI.panel(gui, {
		Name = "Bought", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 430), Visible = false, ZIndex = 5,
	})
	UI.scale(done)
	UI.padding(done, 16)
	UI.stroke(done, T.Gold, 2)
	local doneTitle = UI.label(done, "", {Size = UDim2.new(1, 0, 0, 30), TextSize = 26, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center})
	local doneHint = UI.label(done, "", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -56), Size = UDim2.new(1, 0, 0, 48),
		TextSize = 15, Font = UI.Medium, TextColor3 = T.Text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
	})
	local doneOk = UI.button(done, "GREAT!", T.Good, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 46)})
	local doneView
	local function showBought(it)
		if doneView then
			for i, v in ipairs(views) do if v == doneView then table.remove(views, i) break end end
			doneView.vp.Parent:Destroy()
		end
		doneView = view(done, it.Preview, {Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -150)}, 1.15)
		doneTitle.Text = string.upper(it.Name) .. " UNLOCKED!"
		doneHint.Text = it.Description
		done.Visible = true
	end
	doneOk.Activated:Connect(function() done.Visible = false end)

	local rows = {}
	local busy = false
	local openPos
	local api = {}

	local function owns(it)
		return bit32.band(player:GetAttribute("Items") or 0, it.Bit) ~= 0
	end

	local function refresh()
		local dia = player:GetAttribute("Diamonds") or 0
		balance(1, tostring(dia))
		for _, r in ipairs(rows) do
			if owns(r.item) then
				UI.setEnabled(r.buy, false, T.Good, "OWNED ✓")
			elseif busy then
				UI.setEnabled(r.buy, false, T.Good, "…")
			else
				UI.setEnabled(r.buy, true, dia >= r.item.Price and T.Good or T.Panel2, ("BUY · 💎%d"):format(r.item.Price))
			end
		end
	end

	for i, it in ipairs(Config.Bazaar.Items) do
		local row = UI.new("Frame", {LayoutOrder = i, Size = UDim2.new(1, -6, 0, 96), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, list)
		UI.corner(row, 8)
		UI.plate(row)
		UI.padding(row, 10)
		view(row, it.Preview, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(110, 76)})
		UI.label(row, string.upper(it.Name), {Position = UDim2.fromOffset(122, 0), Size = UDim2.new(1, -312, 0, 22), TextSize = 19})
		UI.label(row, it.Description, {Position = UDim2.fromOffset(122, 24), Size = UDim2.new(1, -312, 0, 46), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
		local buy = UI.button(row, "", T.Good, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(176, 48), TextSize = 16})
		table.insert(rows, {item = it, buy = buy})
		buy.Activated:Connect(function()
			if busy or not buy:GetAttribute("Enabled") then return end
			if (player:GetAttribute("Diamonds") or 0) < it.Price then
				UI.toast(("Not enough diamonds — you need 💎%d"):format(it.Price), "error")
				return
			end
			busy = true
			refresh()
			local res = ctx.invoke("Bazaar", "buy", it.Id)
			busy = false
			refresh()
			if res.ok then
				showBought(it)
			elseif res.msg then
				UI.toast(res.msg, "error")
			end
		end)
	end

	function api.open()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		openPos = hrp and hrp.Position
		panel.Visible = true
		refresh()
	end
	function api.close()
		panel.Visible = false
		done.Visible = false
	end
	function api.onState(state)
		if state ~= "Deployed" then api.close() end
	end

	close.Activated:Connect(api.close)
	ctx.Remotes:WaitForChild("OpenBazaar").OnClientEvent:Connect(api.open)
	player:GetAttributeChangedSignal("Diamonds"):Connect(refresh)
	player:GetAttributeChangedSignal("Items"):Connect(refresh)

	RunService.RenderStepped:Connect(function()
		if not panel.Visible and not done.Visible then return end
		local a = os.clock() * 0.6
		local dir = Vector3.new(math.cos(a), 0.45, math.sin(a)).Unit
		for i = #views, 1, -1 do
			local v = views[i]
			if v.vp.Parent then
				v.cam.CFrame = CFrame.lookAt(v.center + dir * v.dist, v.center)
			else
				table.remove(views, i)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.Visible then
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp or (openPos and (hrp.Position - openPos).Magnitude > 30) then api.close() end
			end
		end
	end)
	return api
end
