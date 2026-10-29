-- Ориентиры на своей базе: SHIPYARD и AIR TERMINAL видны со спавна сквозь стены.
-- Позиции — в атрибутах папки Map.Teams (папки приходят всегда, а сами терминалы далеко могут
-- ещё не подгрузиться из-за StreamingEnabled). Вблизи метка уступает надписи самого терминала
-- (она такая же: тот же размер, шрифт и высота — подмена не заметна).
local RunService = game:GetService("RunService")

local SHOW_WITHIN = 1500 -- метки видны, пока игрок у своей базы
local NEAR = 330         -- ближе видна надпись самого терминала (если он уже подгружен)
local W, H = 190, 34     -- размер надписи на ПК; на низком экране телефона — меньше

local TARGETS = {
	{key = "Shipyard", title = "SHIPYARD", offset = 8, part = {"Shipyard", "ShipTerminal"}, color = Color3.fromRGB(90, 200, 255)},
	{key = "AirTerminal", title = "AIR TERMINAL", offset = 6, part = {"Decor", "AirTerminal"}, color = Color3.fromRGB(255, 205, 60)},
}

return function(ctx)
	local player = ctx.player
	local teamsFolder = workspace:WaitForChild("Map"):WaitForChild("Teams")
	local playerGui = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Folder")
	holder.Name = "BaseWaypointAnchors"
	holder.Parent = workspace.CurrentCamera

	local marks = {}
	for _, t in ipairs(TARGETS) do
		local anchor = Instance.new("Part")
		anchor.Name = t.key
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.Parent = holder

		local bb = Instance.new("BillboardGui")
		bb.Name = "Waypoint_" .. t.key
		bb.ResetOnSpawn = false
		bb.Adornee = anchor
		bb.AlwaysOnTop = true
		bb.Size = UDim2.fromOffset(W, H)
		bb.StudsOffset = Vector3.new(0, t.offset, 0)
		bb.MaxDistance = SHOW_WITHIN + 500
		bb.Enabled = false
		bb.Parent = playerGui -- прямо в PlayerGui: внутри ScreenGui билборд не рисуется
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 1)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.Text = t.title
		title.TextColor3 = t.color
		title.TextStrokeTransparency = 0.2
		title.Parent = bb
		marks[t.key] = {t = t, anchor = anchor, bb = bb}
	end

	-- надписи масштабируются по высоте экрана (и наши метки, и надписи самих терминалов)
	local function labelSize()
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local k = math.clamp(vp.Y / 800, 0.55, 1)
		return UDim2.fromOffset(math.floor(W * k), math.floor(H * k))
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then return end
		acc = 0
		local size = labelSize()
		for _, team in ipairs({"Blue", "Red"}) do
			local b = teamsFolder:FindFirstChild(team .. "Base")
			for _, t in ipairs(TARGETS) do
				local f = b and b:FindFirstChild(t.part[1])
				local p = f and f:FindFirstChild(t.part[2])
				local g = p and p:FindFirstChildOfClass("BillboardGui")
				if g and g.Size ~= size then g.Size = size end
			end
		end
		for _, m in pairs(marks) do
			if m.bb.Size ~= size then m.bb.Size = size end
		end
		local team = ctx.team()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local plaza = team and teamsFolder:GetAttribute(team .. "_Plaza")
		local active = team and ctx.state() == "Deployed" and hrp and hum and hum.Health > 0 and not hum.SeatPart
			and plaza and (hrp.Position - plaza).Magnitude < SHOW_WITHIN
		local base = team and teamsFolder:FindFirstChild(team .. "Base")
		for key, m in pairs(marks) do
			local pos = team and teamsFolder:GetAttribute(team .. "_" .. key)
			local show = false
			if active and pos then
				m.anchor.Position = pos
				local d = (hrp.Position - pos).Magnitude
				local real = base and base:FindFirstChild(m.t.part[1]) and base[m.t.part[1]]:FindFirstChild(m.t.part[2])
				show = d > 40 and not (real and d < NEAR)
			end
			m.bb.Enabled = show
		end
	end)

	return {}
end
