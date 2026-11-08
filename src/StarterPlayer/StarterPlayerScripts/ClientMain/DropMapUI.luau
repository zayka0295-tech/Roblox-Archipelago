-- Мини-карта десанта (после покупки, Remotes.DropRoute от CargoDropService): острова, базы, старт самолёта.
-- Игрок тыкает точку — рисуется линия полёта от старта через неё; FLY! — отправить на сервер.
-- Не выбрал за timeout — сервер сам пошлёт через центр. Карта: X — вправо, Z — вниз (север сверху).
local RunService = game:GetService("RunService")

local MAP_W, MAP_H = 640, 320

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local remote = ctx.Remotes:WaitForChild("DropRoute")
	local gui = UI.screen("DropMapUI", 50)
	gui.Enabled = false
	UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4}, gui)
	local panel = UI.panel(gui, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(MAP_W + 32, MAP_H + 150)})
	UI.scale(panel, 0.5)
	UI.label(panel, "CHOOSE YOUR DROP ROUTE", {Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 30), TextSize = 26, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center})
	local sub = UI.label(panel, "Tap the map: the plane flies from your base through that point", {Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})

	-- море
	local map = UI.new("TextButton", {
		Position = UDim2.fromOffset(16, 72), Size = UDim2.fromOffset(MAP_W, MAP_H), Text = "", AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(28, 86, 130), ClipsDescendants = true,
	}, panel)
	UI.corner(map, 8)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(48, 120, 170), Color3.fromRGB(22, 70, 110))}, map)
	local layer = UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, map)

	local timerLbl = UI.label(panel, "", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.fromOffset(300, 22), TextSize = 15, Font = UI.Medium, TextColor3 = T.Muted})
	local flyBtn = UI.button(panel, "FLY!", T.Good, {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -12), Size = UDim2.fromOffset(200, 50), TextSize = 26})

	local data, target, deadline
	local function toMap(x, z)
		return Vector2.new((x / data.mapX + 1) / 2 * MAP_W, (z / data.mapZ + 1) / 2 * MAP_H)
	end
	local function dot(pos, size, color, text, textColor)
		local d = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(pos.X, pos.Y), Size = UDim2.fromOffset(size, size), BackgroundColor3 = color}, layer)
		UI.corner(d, size)
		if text then
			UI.label(layer, text, {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(pos.X, pos.Y + size / 2 + 2), Size = UDim2.fromOffset(140, 16),
				TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = textColor or T.Text, TextStrokeTransparency = 0.4})
		end
		return d
	end
	local route = {}
	local function seg(a, b, color, thick)
		local d = b - a
		return UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
			Size = UDim2.fromOffset(d.Magnitude, thick), Rotation = math.deg(math.atan2(d.Y, d.X)), BackgroundColor3 = color, BorderSizePixel = 0,
		}, layer)
	end
	local startPos
	local function drawRoute()
		for _, r in ipairs(route) do r:Destroy() end
		route = {}
		if not target then return end
		local a = startPos
		local b = toMap(target.X, target.Y)
		local dir = (b - a).Magnitude > 1 and (b - a).Unit or Vector2.new(1, 0)
		-- пунктир от старта через точку и дальше (самолёт пролетит ещё немного)
		local finish = b + dir * (700 / (2 * data.mapX) * MAP_W)
		local len = (finish - a).Magnitude
		local s = 0
		while s < len do
			local e = math.min(len, s + 12)
			table.insert(route, seg(a + dir * s, a + dir * e, Color3.fromRGB(255, 220, 90), 3))
			s += 20
		end
		local mark = dot(b, 16, Color3.fromRGB(255, 220, 90))
		UI.stroke(mark, Color3.new(1, 1, 1), 2)
		table.insert(route, mark)
		local plane = UI.label(layer, "✈", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(finish.X, finish.Y), Size = UDim2.fromOffset(26, 26),
			TextSize = 24, Rotation = math.deg(math.atan2(dir.Y, dir.X)), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3})
		table.insert(route, plane)
	end

	local function build()
		for _, c in ipairs(layer:GetChildren()) do c:Destroy() end
		route = {}
		-- базы
		for team, b in pairs(data.map.bases) do
			local tc = Config.Teams[team]
			local p = toMap(b.x, b.z)
			local land = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.X, p.Y), Size = UDim2.fromOffset(46, 58), BackgroundColor3 = Color3.fromRGB(70, 110, 60)}, layer)
			UI.corner(land, 10)
			UI.stroke(land, tc.Color, 3)
			UI.label(layer, string.upper(tc.DisplayName) .. " BASE", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(p.X, p.Y + 32), Size = UDim2.fromOffset(120, 16),
				TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = tc.Color, TextStrokeTransparency = 0.3})
		end
		-- острова: обводка цветом владельца (GameState Island_<Id>_Owner, CaptureService)
		for _, isl in ipairs(data.map.islands) do
			local owner = ctx.GameState:GetAttribute("Island_" .. isl.id .. "_Owner")
			local ring = owner and Config.Teams[owner] and Config.Teams[owner].Color or Color3.fromRGB(200, 200, 200)
			local d = dot(toMap(isl.x, isl.z), isl.center and 30 or 22, Color3.fromRGB(90, 130, 70), isl.name)
			UI.stroke(d, ring, 2)
		end
		-- старт самолёта
		local side = data.team == "Red" and -1 or 1
		startPos = toMap(data.map.startX * side, 0)
		local s = dot(startPos, 14, Config.Teams[data.team].Color, "START", Config.Teams[data.team].Color)
		UI.stroke(s, Color3.new(1, 1, 1), 2)
	end

	local function close()
		gui.Enabled = false
		data = nil
	end
	local function send()
		if not data then return end
		local t = target or Vector2.zero
		remote:FireServer(t.X, t.Y)
		close()
	end

	map.InputBegan:Connect(function(input)
		if not data then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		-- input.Position и AbsolutePosition — в одной системе (без верхней панели Roblox), поправка не нужна
		local rel = (Vector2.new(input.Position.X, input.Position.Y) - map.AbsolutePosition) / map.AbsoluteSize
		if rel.X < 0 or rel.X > 1 or rel.Y < 0 or rel.Y > 1 then return end
		target = Vector2.new((rel.X * 2 - 1) * data.mapX, (rel.Y * 2 - 1) * data.mapZ)
		drawRoute()
		sub.Text = "Route set — press FLY! (tap again to change)"
	end)
	flyBtn.Activated:Connect(send)

	remote.OnClientEvent:Connect(function(d)
		if type(d) ~= "table" or type(d.map) ~= "table" or not Config.Teams[d.team] then return end
		data = {team = d.team, map = d.map, mapX = d.map.mapX, mapZ = d.map.mapZ}
		target = nil
		deadline = os.clock() + (d.map.timeout or 30)
		sub.Text = "Tap the map: the plane flies from your base through that point"
		build()
		gui.Enabled = true
	end)

	local shownLeft, shownTarget -- текст таймера меняем, только когда сменилась секунда или выбрана точка
	RunService.Heartbeat:Connect(function()
		if not data then shownLeft = nil return end
		local left = math.max(0, math.ceil(deadline - os.clock()))
		if left ~= shownLeft or target ~= shownTarget then
			shownLeft, shownTarget = left, target
			timerLbl.Text = ("Auto-launch in %d s%s"):format(left, target and "" or " (through the center)")
		end
		if left <= 0 then send() end
	end)
	return {}
end
