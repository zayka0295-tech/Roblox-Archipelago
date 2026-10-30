-- Десант на парашюте (донат «ParachuteDrop», Config.ParachuteDrop).
--  • Покупка на золотой плите лобби (LobbyPadService): за свою (автоматическую) команду (setPendingTeam).
--  • Сначала мини-карта (DropMapUI, Remotes.DropRoute): игрок выбирает точку, через которую полетит
--    самолёт (от своей базы). Не выбрал за ROUTE_TIMEOUT — через центр. Выдача покупки ждёт выбора:
--    вышел до вылета — покупка не считается выданной, Roblox повторит при следующем заходе.
--  • Игрок появляется сразу в кресле грузового самолёта (декорация, не игровой: не стреляет, не попадает
--    под огонь). Самолёт летит на Altitude от своей базы через карту; кнопка JUMP или прыжок —
--    выпрыгнуть (ParachuteUI). Долетел до конца маршрута — выбрасывает сам.
--  • Парашют раскрывает сервер на OpenHeight над землёй/водой: купол на персонаже + LinearVelocity по вертикали
--    (спуск DescentSpeed, вбок рулится как обычно). Медленный спуск — без урона от падения (FallDamageService).
--    Состояние для интерфейса — атрибут игрока Parachute ("fall" / "open" / nil).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local SpawnService = require(Services.SpawnService)
local MonetizationService = require(Services.MonetizationService)
local Notifier = require(Services.Notifier)

local CargoDropService = {}
local PD = Config.ParachuteDrop
local flights = {}     -- [модель] = {root, dir, endPos, seats}
local chutes = {}      -- [игрок] = {state, t, gear}
local pendingTeam = {} -- [игрок] = команда плиты, на которой начал покупку
local choosing = {}    -- [игрок] = {target = Vector3?}: карта открыта, ждём выбора маршрута
local ROUTE_TIMEOUT = 30
local MAP_X, MAP_Z = 3600, 1800 -- пределы карты для выбора точки
local mapData -- острова и базы для мини-карты (собирается один раз)

-- папка одна: если в place сохранилась старая, берём её (клиенты ищут по имени — с двумя папками
-- звук двигателя и ParachuteUI могли смотреть в пустую)
local folder = workspace:FindFirstChild("CargoDrops") or Instance.new("Folder")
folder.Name = "CargoDrops"
folder.Parent = workspace
for _, c in ipairs(workspace:GetChildren()) do
	if c.Name == "CargoDrops" and c ~= folder then c:Destroy() end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false

------------------------------------------------------------------ модель самолёта
-- всё в осях корня: вперёд = −Z, вверх = +Y
local BODY = Color3.fromRGB(98, 106, 92)
local DARK = Color3.fromRGB(52, 56, 52)
local ALONG = CFrame.Angles(0, math.rad(90), 0) -- ось цилиндра (X) вдоль фюзеляжа

local function buildPlane(team, cf)
	local model = Instance.new("Model")
	model.Name = "CargoPlane_" .. team
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
	root.CFrame = cf
	root.Parent = model
	model.PrimaryPart = root

	local function add(name, size, offset, color, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color or BODY
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, true
		for k, v in pairs(props or {}) do p[k] = v end
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = root, p
		w.Parent = p
		return p
	end
	local cyl = {Shape = Enum.PartType.Cylinder}
	-- фюзеляж, нос, хвостовая балка
	add("Fuselage", Vector3.new(64, 13, 13), CFrame.new(0, 0, 0) * ALONG, BODY, cyl)
	add("Nose", Vector3.new(13, 13, 13), CFrame.new(0, 0, -32), BODY, {Shape = Enum.PartType.Ball})
	add("Cockpit", Vector3.new(8, 2.6, 5), CFrame.new(0, 3.6, -33), Color3.fromRGB(30, 40, 50), {Material = Enum.Material.Glass, Transparency = 0.2})
	add("TailBoom", Vector3.new(22, 9, 9), CFrame.new(0, 2, 41) * ALONG, BODY, cyl)
	add("TailCone", Vector3.new(9, 9, 9), CFrame.new(0, 2, 52), BODY, {Shape = Enum.PartType.Ball})
	-- крыло (верхнеплан) и оперение
	add("Wing", Vector3.new(100, 1.6, 15), CFrame.new(0, 6.6, -4))
	add("Fin", Vector3.new(1.4, 17, 12), CFrame.new(0, 13, 48))
	add("Stabilizer", Vector3.new(36, 1.2, 9), CFrame.new(0, 5.5, 50))
	-- четыре двигателя с винтами
	for _, x in ipairs({-34, -17, 17, 34}) do
		add("Engine", Vector3.new(12, 3.8, 3.8), CFrame.new(x, 4.6, -9) * ALONG, DARK, cyl)
		add("Propeller", Vector3.new(0.3, 11, 11), CFrame.new(x, 4.6, -15.3) * ALONG, Color3.fromRGB(40, 40, 40), {Shape = Enum.PartType.Cylinder, Transparency = 0.65})
	end
	-- обтекатели шасси и полоса команды
	add("GearPod", Vector3.new(4, 4, 16), CFrame.new(-6.6, -5, 2), DARK)
	add("GearPod", Vector3.new(4, 4, 16), CFrame.new(6.6, -5, 2), DARK)
	local tc = Config.Teams[team] and Config.Teams[team].Color or BODY
	add("TeamStripe", Vector3.new(0.3, 2, 46), CFrame.new(-6.45, 0.5, -2), tc)
	add("TeamStripe", Vector3.new(0.3, 2, 46), CFrame.new(6.45, 0.5, -2), tc)
	add("FinStripe", Vector3.new(1.6, 4, 12.2), CFrame.new(0, 18, 48), tc)
	-- грузовой отсек: пол и кресла десанта лицом вперёд, красная лампа «готовность»
	add("Floor", Vector3.new(10, 0.4, 40), CFrame.new(0, -4.6, 4), DARK)
	local lamp = add("JumpLight", Vector3.new(1, 1, 0.4), CFrame.new(0, 4, 20), Color3.fromRGB(255, 60, 40), {Material = Enum.Material.Neon})
	local pl = Instance.new("PointLight")
	pl.Color, pl.Range, pl.Brightness = Color3.fromRGB(255, 80, 60), 16, 2
	pl.Parent = lamp
	local seats = {}
	for i, off in ipairs({Vector3.new(-2.5, -3.8, 8), Vector3.new(2.5, -3.8, 8), Vector3.new(-2.5, -3.8, 14), Vector3.new(2.5, -3.8, 14)}) do
		local s = Instance.new("Seat")
		s.Name = "DropSeat" .. i
		s.Size = Vector3.new(2, 1, 2)
		s.CFrame = cf * CFrame.new(off)
		s.Color = DARK
		s.CanCollide, s.CanQuery, s.CanTouch, s.Massless = false, false, false, true
		s:SetAttribute("CargoSeat", true)
		-- камера десантника — поодаль и чуть выше, чтобы самолёт был виден целиком (SeatCamera)
		s:SetAttribute("CamMinZoom", 85)
		s:SetAttribute("CamLift", 10)
		s.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = root, s
		w.Parent = s
		table.insert(seats, s)
	end

	-- полёт: постоянная скорость и неизменный курс (физика сервера — клиенты видят плавно)
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = cf.LookVector * PD.Speed
	lv.MaxForce = math.huge
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.CFrame = cf.Rotation
	ao.RigidityEnabled = true
	ao.Parent = root
	model.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end)
	return model, root, seats
end

------------------------------------------------------------------ парашют
local function clearChute(player)
	local c = chutes[player]
	chutes[player] = nil
	if player.Parent then player:SetAttribute("Parachute", nil) end
	if c and c.gear then c.gear:Destroy() end
	if c and c.pack then c.pack:Destroy() end
end

local function weldedPart(parent, weldTo, name, size, cfw, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cfw
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
	p.Parent = parent
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = weldTo, p
	w.Parent = p
	return p
end

-- ранец с парашютом на спине (на UpperTorso: поворачивается вместе с позой «лицом вниз»)
local function wearPack(char)
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then return nil end
	local pack = Instance.new("Model")
	pack.Name = "ParachutePack"
	local olive = Color3.fromRGB(74, 82, 60)
	local back = torso.CFrame * CFrame.new(0, 0.1, torso.Size.Z / 2 + 0.45)
	weldedPart(pack, torso, "Container", Vector3.new(1.9, 2.1, 0.9), back, olive)
	weldedPart(pack, torso, "Flap", Vector3.new(1.95, 0.5, 0.95), back * CFrame.new(0, 0.85, 0.02), olive:Lerp(Color3.new(0, 0, 0), 0.25))
	weldedPart(pack, torso, "Ripcord", Vector3.new(0.3, 0.3, 0.2), back * CFrame.new(0.75, -0.6, 0.5), Color3.fromRGB(220, 60, 40), Enum.Material.SmoothPlastic)
	for _, s in ipairs({-0.55, 0.55}) do
		weldedPart(pack, torso, "Strap", Vector3.new(0.22, torso.Size.Y + 0.1, 0.12), torso.CFrame * CFrame.new(s, 0, -torso.Size.Z / 2 - 0.04), Color3.fromRGB(35, 35, 35))
	end
	pack.Parent = char
	return pack
end

local function openChute(player, c, char, hrp)
	local gear = Instance.new("Model")
	gear.Name = "Parachute"
	local team = TeamService.getTeamName(player)
	local tc = team and Config.Teams[team] and Config.Teams[team].Color or Color3.fromRGB(230, 230, 230)
	local white = Color3.fromRGB(236, 236, 230)
	local base = hrp.CFrame
	local function piece(name, size, cfw, color, material)
		return weldedPart(gear, hrp, name, size, cfw, color, material)
	end
	local function line(a, b, color, w)
		piece("Line", Vector3.new(w or 0.06, w or 0.06, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color or Color3.fromRGB(210, 210, 205))
	end
	-- купол-крыло (ram-air): CELLS секций по дуге, чередуются цвет команды и белый;
	-- спереди тёмные воздухозаборники, снизу рёбра между секциями
	local CELLS, SPAN, CHORD, R, TOP = 9, 19, 6.5, 15, 15
	local step = SPAN / CELLS / R -- радиан на секцию
	local left, right = (base * CFrame.new(-1.1, 4.2, 0)).Position, (base * CFrame.new(1.1, 4.2, 0)).Position
	for i = 1, CELLS do
		local a = (i - (CELLS + 1) / 2) * step
		local cell = base * CFrame.new(math.sin(a) * R, TOP + math.cos(a) * R - R, 0) * CFrame.Angles(0, 0, -a)
		piece("Cell", Vector3.new(SPAN / CELLS + 0.08, 0.9, CHORD), cell, i % 2 == 0 and white or tc)
		piece("Intake", Vector3.new(SPAN / CELLS - 0.25, 0.55, 0.12), cell * CFrame.new(0, -0.05, -CHORD / 2 - 0.02), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic)
		piece("Rib", Vector3.new(0.08, 0.5, CHORD - 0.3), cell * CFrame.new(SPAN / CELLS / 2, -0.6, 0), white)
		-- стропы переднего и заднего ряда к свободным концам своей стороны
		local riser = a < 0 and left or right
		line((cell * CFrame.new(0, -0.45, -CHORD / 2 + 0.6)).Position, riser)
		line((cell * CFrame.new(0, -0.45, CHORD / 2 - 0.8)).Position, riser)
	end
	-- свободные концы от плеч и клеванты (за них держатся руки — поза в SkydivePose)
	for _, s in ipairs({-1, 1}) do
		local riser = s < 0 and left or right
		line((base * CFrame.new(s * 0.75, 1.3, 0.1)).Position, riser, Color3.fromRGB(40, 40, 40), 0.22)
		piece("Toggle", Vector3.new(0.35, 0.5, 0.35), base * CFrame.new(s * 1.15, 3.6, -0.15), Color3.fromRGB(230, 120, 30), Enum.Material.SmoothPlastic)
	end
	local att = Instance.new("Attachment")
	att.Name = "ChuteAttachment"
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Name = "ChuteDrag"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.LineDirection = Vector3.yAxis
	lv.LineVelocity = -PD.DescentSpeed
	lv.MaxForce = 60000
	lv.Parent = gear
	att.Parent = hrp
	gear.Parent = char
	c.gear = gear
	c.att = att
	c.state = "open"
	player:SetAttribute("Parachute", "open")
end

local function startChute(player)
	clearChute(player)
	local c = {state = "fall", t = os.clock()}
	c.pack = player.Character and wearPack(player.Character)
	chutes[player] = c
	player:SetAttribute("Parachute", "fall")
end

local function stepChutes()
	for player, c in pairs(chutes) do
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 or hum.SeatPart or os.clock() - c.t > 90 then
			if c.att then c.att:Destroy() end
			clearChute(player)
		else
			groundParams.FilterDescendantsInstances = {char, folder}
			local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -3000, 0), groundParams)
			local height = hit and (hrp.Position.Y - hit.Position.Y) or math.huge
			local feet = hum.HipHeight + hrp.Size.Y / 2
			if c.state == "fall" then
				-- обычно раскрыть просит клиент (Remotes.ChuteOpen); это — запасной вариант
				if height < PD.ServerOpenHeight then openChute(player, c, char, hrp) end
			elseif height < feet + 1.5 then
				-- приземлился (или в воду) — купол снимаем
				if c.att then c.att:Destroy() end
				clearChute(player)
			end
		end
	end
end

------------------------------------------------------------------ полёт
local function eject(seat)
	local w = seat:FindFirstChild("SeatWeld")
	if w then w:Destroy() end
end

-- маршрут: от своей базы (StartX) через выбранную точку и дальше на AFTER студов (время долететь и прыгнуть)
local AFTER = 700
local function routeOf(team, target)
	local side = team == "Red" and -1 or 1
	local start = Vector3.new(PD.StartX * side, PD.Altitude, 0)
	local t = Vector3.new(math.clamp(target.X, -MAP_X, MAP_X), PD.Altitude, math.clamp(target.Z, -MAP_Z, MAP_Z))
	local d = Vector3.new(t.X - start.X, 0, t.Z - start.Z)
	if d.Magnitude < 300 then d = Vector3.new(side, 0, 0) * 300 end -- точка почти над стартом
	local finish = start + d + d.Unit * AFTER
	return start, finish
end

local function newFlight(team, target)
	local start, finish = routeOf(team, target)
	local dir = (finish - start).Unit
	local model, root, seats = buildPlane(team, CFrame.lookAt(start, start + dir))
	local f = {model = model, root = root, dir = dir, endPos = finish, seats = seats}
	flights[model] = f
	for _, s in ipairs(seats) do
		local last
		s:GetPropertyChangedSignal("Occupant"):Connect(function()
			local hum = s.Occupant
			if hum then
				last = Players:GetPlayerFromCharacter(hum.Parent)
			elseif last then
				-- выпрыгнул (или выбросило в конце маршрута)
				local p = last
				last = nil
				if p.Parent then startChute(p) end
			end
		end)
	end
	return f
end

local function stepFlights()
	for model, f in pairs(flights) do
		if not model.Parent then
			flights[model] = nil
		elseif not f.done and (f.endPos - f.root.Position):Dot(f.dir) <= 0 then
			-- конец маршрута: всех, кто не прыгнул, выбрасываем; самолёт улетает и исчезает
			f.done = true
			for _, s in ipairs(f.seats) do
				if s.Occupant then
					local p = Players:GetPlayerFromCharacter(s.Occupant.Parent)
					if p then Notifier.send(p, "Drop zone ends here — jumping!", "info") end
					eject(s)
				end
			end
			task.delay(12, function()
				flights[model] = nil
				model:Destroy()
			end)
		end
	end
end

------------------------------------------------------------------ десант
-- острова и базы для мини-карты
local function buildMapData()
	local islands = {}
	local neutral = workspace.Map:FindFirstChild("Neutral")
	for _, def in ipairs(Config.Islands) do
		local m = neutral and neutral:FindFirstChild(def.Outpost)
		if m then
			local p = m:GetPivot().Position
			table.insert(islands, {id = def.Id, name = def.Name, x = p.X, z = p.Z, center = def.IsCenter == true})
		end
	end
	local bases = {}
	for _, team in ipairs(Config.TeamOrder) do
		local pos = workspace.Map.Teams:GetAttribute(team .. "_Plaza")
		if typeof(pos) == "Vector3" then bases[team] = {x = pos.X, z = pos.Z} end
	end
	return {islands = islands, bases = bases, mapX = MAP_X, mapZ = MAP_Z, startX = PD.StartX, timeout = ROUTE_TIMEOUT}
end

-- высадить игрока за команду team: сначала карта и выбор маршрута (ждём), потом свой самолёт.
-- Возвращает true, если игрок вылетел (для выдачи покупки).
function CargoDropService.drop(player, team)
	if not player.Parent or not Config.Teams[team] or choosing[player] then return false end
	local pick = {}
	choosing[player] = pick
	mapData = mapData or buildMapData()
	ReplicatedStorage.Remotes.DropRoute:FireClient(player, {team = team, map = mapData})
	local t0 = os.clock()
	while not pick.target and player.Parent and os.clock() - t0 < ROUTE_TIMEOUT + 2 do task.wait(0.1) end
	choosing[player] = nil
	if not player.Parent then return false end
	local target = pick.target or Vector3.zero
	local ok = SpawnService.joinAndDeploy(player, team, true, function(char, hum, hrp)
		hum:UnequipTools()
		local f = newFlight(team, target)
		local seat
		for _, s in ipairs(f.seats) do if not s.Occupant then seat = s break end end
		if not seat then return end
		pcall(function() player:RequestStreamAroundAsync(seat.Position, 3) end)
		if player.Character ~= char then return end
		char:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
		seat:Sit(hum)
		Notifier.send(player, "Parachute drop! Press JUMP to bail out — the chute opens by itself", "success")
	end)
	return ok
end

function CargoDropService.setPendingTeam(player, team)
	pendingTeam[player] = team
end

-- игрок сейчас выбирает маршрут или летит в грузовом самолёте (плита не предлагает покупку снова)
function CargoDropService.isBusy(player)
	if choosing[player] then return true end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.SeatPart ~= nil and hum.SeatPart:GetAttribute("CargoSeat") == true
end

function CargoDropService.init()
	MonetizationService.register("ParachuteDrop", function(player)
		-- команда плиты; если покупка пришла позже (перезаход) — текущая или меньшая команда
		local team = pendingTeam[player] or TeamService.getTeamName(player)
		if not team then
			team = TeamService.count("Blue") <= TeamService.count("Red") and "Blue" or "Red"
		end
		pendingTeam[player] = nil
		return CargoDropService.drop(player, team)
	end)
	-- клиент падающего: «пора раскрывать» (он знает свою высоту без задержки). Раннее раскрытие читеру
	-- ничего не даёт (медленнее спуск), поэтому проверяем только состояние
	ReplicatedStorage.Remotes:WaitForChild("ChuteOpen").OnServerEvent:Connect(function(player)
		local c = chutes[player]
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if c and c.state == "fall" and hrp and os.clock() - c.t > 0.4 then openChute(player, c, char, hrp) end
	end)
	-- игрок выбрал точку на карте (x, z в студах мира)
	ReplicatedStorage.Remotes:WaitForChild("DropRoute").OnServerEvent:Connect(function(player, x, z)
		local pick = choosing[player]
		if not pick or pick.target then return end
		if type(x) ~= "number" or type(z) ~= "number" or x ~= x or z ~= z then return end
		pick.target = Vector3.new(math.clamp(x, -MAP_X, MAP_X), 0, math.clamp(z, -MAP_Z, MAP_Z))
	end)
	RunService.Heartbeat:Connect(function()
		stepFlights()
		stepChutes()
	end)
	Players.PlayerRemoving:Connect(function(p)
		pendingTeam[p] = nil
		chutes[p] = nil
		choosing[p] = nil
	end)
end

return CargoDropService
