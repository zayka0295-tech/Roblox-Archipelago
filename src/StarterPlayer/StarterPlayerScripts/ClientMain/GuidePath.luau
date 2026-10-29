-- Навигация обучения: светящаяся дорожка от ног игрока до цели и метка над целью с расстоянием.
-- Куда вести (шаг Tutorial и TutReady, см. TutorialService):
--  0 — к Капитану; 1 — к аэротерминалу; 2 — к верфи; задание выполнено (TutReady) — обратно к Капитану.
--  В технике и после обучения (шаг 3) навигации нет.
-- Позиции целей — атрибуты Map.Teams (<команда>_Captain / _AirTerminal / _Shipyard): сами модели далеко
-- могут ещё не подгрузиться (StreamingEnabled). Путь — PathfindingService (в обход зданий),
-- не нашёлся — дорожка по прямой. Пересчёт каждые REPATH сек или сразу, если игрок отошёл от пути;
-- между пересчётами дорожка каждый кадр начинается от ног игрока (к ближайшему месту пути).
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local DOT_STEP = 4      -- студов между точками дорожки
local MAX_DOTS = 110    -- дорожка видна на ~440 студов вперёд (дальше — метка цели)
local REPATH = 1.2
local ARRIVED = 12      -- ближе — дорожку не рисуем
local OFF_PATH = 8      -- дальше от пути — пересчитать сразу
local GOLD = Color3.fromRGB(255, 205, 60)

return function(ctx)
	local player = ctx.player
	local teams = workspace:WaitForChild("Map"):WaitForChild("Teams")

	-- названия не пишем: у целей есть свои таблички на карте (у Капитана — CaptainMark)
	local TARGETS = {
		Captain = {color = GOLD},
		AirTerminal = {color = GOLD},
		Shipyard = {color = Color3.fromRGB(90, 200, 255)},
	}

	-- точки дорожки (только у этого игрока: лежат в камере)
	local folder = Instance.new("Folder")
	folder.Name = "GuidePath"
	folder.Parent = workspace.CurrentCamera
	local dots = {}
	for i = 1, MAX_DOTS do
		local d = Instance.new("Part")
		d.Name = "Dot"
		d.Shape = Enum.PartType.Ball
		d.Size = Vector3.new(0.7, 0.7, 0.7)
		d.Material = Enum.Material.Neon
		d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
		d.Transparency = 1
		d.Parent = folder
		dots[i] = d
	end
	local shown = 0 -- сколько точек сейчас задействовано

	-- метка цели (сквозь стены, с расстоянием)
	local anchor = Instance.new("Part")
	anchor.Name = "GuideTarget"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = folder
	local bb = Instance.new("BillboardGui")
	bb.Name = "GuideMark"
	bb.ResetOnSpawn = false
	bb.Adornee = anchor
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.Size = UDim2.fromOffset(120, 40)
	bb.Enabled = false
	bb.Parent = player:WaitForChild("PlayerGui") -- внутри ScreenGui билборд не рисуется
	local function lbl(y, h, font)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0, y)
		l.Size = UDim2.fromScale(1, h)
		l.Font = font
		l.TextScaled = true
		l.TextStrokeTransparency = 0.2
		l.TextColor3 = GOLD
		l.Parent = bb
		return l
	end
	local distLbl = lbl(0, 0.5, Enum.Font.GothamBold)
	local arrowLbl = lbl(0.5, 0.5, Enum.Font.GothamBlack)
	arrowLbl.Text = "▼"

	-- текущая цель: позиция и описание, либо nil
	local function currentTarget()
		if ctx.state() ~= "Deployed" then return nil end
		local team = ctx.team()
		if not team then return nil end
		local s = player:GetAttribute("Tutorial")
		if s == nil or s >= 3 then return nil end
		local key
		if s == 0 or player:GetAttribute("TutReady") == true then
			key = "Captain"
		elseif s == 1 then
			key = "AirTerminal"
		else
			key = "Shipyard"
		end
		local pos = teams:GetAttribute(team .. "_" .. key)
		if typeof(pos) ~= "Vector3" then return nil end
		return pos, TARGETS[key]
	end

	local function feet()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then return nil end
		return hrp.Position - Vector3.new(0, hum.HipHeight + hrp.Size.Y / 2, 0), hum
	end

	local function hideDots(from)
		for i = from, shown do dots[i].Transparency = 1 end
		if from <= shown then shown = from - 1 end
	end

	-- расставить точки равномерно вдоль ломаной
	local function layout(points)
		local n, carry = 0, 0
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local seg = (b - a).Magnitude
			local t = carry
			while t <= seg and n < MAX_DOTS do
				n += 1
				dots[n].Position = a:Lerp(b, seg > 0 and t / seg or 0) + Vector3.new(0, 0.45, 0)
				t += DOT_STEP
			end
			carry = t - seg
			if n >= MAX_DOTS then break end
		end
		for i = n + 1, shown do dots[i].Transparency = 1 end
		shown = n
	end

	local route = nil       -- последний найденный путь (точки ломаной) или nil
	local repathNow = false -- игрок сошёл с пути — не ждать REPATH

	-- дорожка от ног: ближайшее место на пути + остаток пути после него; второе — расстояние до пути
	local function fromFeet(from)
		local fx = Vector3.new(from.X, 0, from.Z)
		local bi, bq, bd = 1, route[1], math.huge
		for i = 1, #route - 1 do
			local a, b = route[i], route[i + 1]
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local len2 = ab:Dot(ab)
			local t = len2 > 0 and math.clamp((fx - Vector3.new(a.X, 0, a.Z)):Dot(ab) / len2, 0, 1) or 0
			local q = a:Lerp(b, t)
			local d = (Vector3.new(q.X, 0, q.Z) - fx).Magnitude
			if d < bd then bi, bq, bd = i, q, d end
		end
		local points = {from, bq}
		for i = bi + 1, #route do table.insert(points, route[i]) end
		return points, bd
	end

	local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = DOT_STEP})
	task.spawn(function()
		while true do
			repathNow = false
			local pos = currentTarget()
			local from, hum = feet()
			if pos and from and not hum.SeatPart and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude > ARRIVED then
				local ok = pcall(function() path:ComputeAsync(from, pos) end)
				if ok and path.Status == Enum.PathStatus.Success then
					local points = {}
					for _, w in ipairs(path:GetWaypoints()) do table.insert(points, w.Position) end
					route = #points >= 2 and points or {from, pos}
				else
					route = {from, Vector3.new(pos.X, from.Y, pos.Z)} -- путь не нашёлся — по прямой
				end
			else
				route = nil
			end
			local t0 = os.clock()
			while os.clock() - t0 < REPATH and not repathNow do task.wait(0.1) end
		end
	end)

	-- кадр: бегущая волна по дорожке (видно направление), точки у самых ног прячем; метка цели
	RunService.RenderStepped:Connect(function()
		local pos, info = currentTarget()
		local from, hum = feet()
		local active = pos ~= nil and from ~= nil
		local d = active and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude or 0
		if active then
			anchor.Position = pos
			distLbl.TextColor3 = info.color
			arrowLbl.TextColor3 = info.color
			distLbl.Text = d >= 1000 and ("%.1f km"):format(d / 1000) or ("%d m"):format(d)
			-- когда сидит в технике на задании (летит/плывёт) — метка не нужна, счётчик метров в HUD
			bb.Enabled = not (hum.SeatPart and player:GetAttribute("TutReady") ~= true and info ~= TARGETS.Captain)
		else
			bb.Enabled = false
		end
		-- дорожка каждый кадр от текущего места игрока
		if active and route and not hum.SeatPart and d > ARRIVED then
			local points, off = fromFeet(from)
			if off > OFF_PATH then repathNow = true end
			layout(points)
		else
			hideDots(1)
		end
		local t = os.clock()
		for i = 1, shown do
			local dot = dots[i]
			if from and (dot.Position - from).Magnitude < 3 then
				dot.Transparency = 1
			else
				-- волна бежит от игрока к цели
				local w = (math.sin(i * 0.55 - t * 7) + 1) / 2
				dot.Transparency = 0.15 + 0.55 * (1 - w)
				dot.Color = info and info.color or GOLD
			end
		end
	end)

	return {}
end
