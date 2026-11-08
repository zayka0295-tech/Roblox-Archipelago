-- Боты, которые играют как люди (и в Studio, и онлайн — каждый игрок занимает место одного бота своей команды).
-- Ботам разрешены только истребители, катера и зенитки базы (ALLOWED_ROLE); код остальных ролей оставлен, но не используется.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local CombatService = require(Services.CombatService)
local CarrierService = require(Services.CarrierService)
local TurretService = require(Services.TurretService)
local PlaneService = require(Services.PlaneService)
local ShipService = require(Services.ShipService)
local LogisticsService = require(Services.LogisticsService)
local NavalWeaponsService = require(Services.NavalWeaponsService)
local BotNames = require(Services.BotNames)

local BotService = {}
local B = Config.Bots
local P = Config.Planes.Fighter
local rng = Random.new()
local folder
local slots = {}     -- все роли обеих команд
local bySlotBot = {} -- [бот] = слот
local startT = 0

local ANIM = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	tool = "rbxassetid://507768375",
	sit = "rbxassetid://2506281703",
}
local SHIP_ROLE = {bsCaptain = "Battleship", gbCaptain = "Gunboat", subCaptain = "Submarine"}
-- ботам разрешены только истребитель (spawnForBot), катер и зенитки своей базы; авианосец, линкор, подлодка и их турели — только игрокам
local ALLOWED_ROLE = {pilot = true, gbCaptain = true, baseGunner = true}

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = {workspace.Terrain}
terrainParams.IgnoreWater = true

local function other(team) return team == "Blue" and "Red" or "Blue" end

local function clampArena(p)
	local v = Vector2.new(p.X, p.Z)
	if v.Magnitude > B.ArenaRadius then v = v.Unit * B.ArenaRadius end
	return Vector3.new(v.X, p.Y, v.Y)
end

------------------------------------------------------------------ создание бота
local SKIN = {Color3.fromRGB(234, 184, 146), Color3.fromRGB(255, 204, 153), Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 105, 70), Color3.fromRGB(105, 64, 40), Color3.fromRGB(245, 205, 48)}

-- slot: ник, ранг и цвет кожи хранятся в слоте — после смерти бот возвращается тем же «игроком»
local function makeBot(team, label, slot)
	local tc = Config.Teams[team].Color
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = slot and slot.skin or SKIN[1]
	desc.TorsoColor = tc
	desc.LeftArmColor = tc:Lerp(Color3.new(0, 0, 0), 0.2)
	desc.RightArmColor = tc:Lerp(Color3.new(0, 0, 0), 0.2)
	desc.LeftLegColor = Color3.fromRGB(56, 62, 50)
	desc.RightLegColor = Color3.fromRGB(56, 62, 50)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[BotService] failed to create bot: " .. tostring(model))
		return nil
	end
	model.Name = label
	-- техника (катера, самолёты) видна игрокам на любом расстоянии (Persistent) — бот за штурвалом тоже
	-- должен, иначе стриминг выгружает его: катер без капитана, и попасть в него нельзя
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	require(script.Parent.UniformService).dress(model, team) -- форма команды, как у игроков
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = "Characters" end
	end
	model:SetAttribute("IsBot", true)
	model:SetAttribute("Team", team)
	model:SetAttribute("State", "Deployed")
	model:SetAttribute("DisplayName", label)
	if slot and slot.rank then model:SetAttribute("Rank", slot.rank) end -- RankTags рисует ранг, как у игроков
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.MaxHealth = B.Health
	hum.Health = B.Health
	hum.WalkSpeed = B.WalkSpeed
	-- имя над головой — стандартное, как у игроков (не отличить по табличке)
	hum.DisplayName = label
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	return model
end

local function setupAnims(st, seated)
	local animator = st.hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", st.hum)
	local function load(id, prio)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(a) end)
		if not ok then return nil end
		track.Looped = true
		track.Priority = prio
		return track
	end
	if seated then
		local sit = load(ANIM.sit, Enum.AnimationPriority.Action)
		if sit then sit:Play() end
		return
	end
	local idle = load(ANIM.idle, Enum.AnimationPriority.Idle)
	local walk = load(ANIM.walk, Enum.AnimationPriority.Movement)
	local hold = load(ANIM.tool, Enum.AnimationPriority.Action)
	if idle then idle:Play() end
	if hold then hold:Play() end
	st.hum.Running:Connect(function(speed)
		if not walk then return end
		if speed > 0.5 then
			if not walk.IsPlaying then walk:Play(0.15) end
			walk:AdjustSpeed(speed / 14)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
end

local function infantrySpawnPoint(team)
	local sx = team == "Blue" and -1 or 1
	local ov = OverlapParams.new()
	ov.FilterType = Enum.RaycastFilterType.Exclude
	ov.FilterDescendantsInstances = {workspace.Terrain, folder}
	for _ = 1, 25 do
		local x, z = sx * rng:NextNumber(120, 190), rng:NextNumber(-120, 120)
		if Vector2.new(x, z).Magnitude < B.ArenaRadius then
			local r = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -300, 0), terrainParams)
			if r and r.Position.Y > 4 then
				local pos = r.Position + Vector3.new(0, 3.5, 0)
				if #workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(4, 5, 4), ov) == 0 then return pos end
			end
		end
	end
	return Vector3.new(sx * 150, 14, 0)
end

------------------------------------------------------------------ цели
local function collectEnemies()
	local list = {Blue = {}, Red = {}}
	for bot, slot in pairs(bySlotBot) do
		local hum = bot:FindFirstChildOfClass("Humanoid")
		if bot.Parent and hum and hum.Health > 0 and not hum.SeatPart then
			local torso = bot:FindFirstChild("UpperTorso") or bot:FindFirstChild("HumanoidRootPart")
			if torso then table.insert(list[slot.team], {pos = torso.Position, kind = "inf"}) end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local team = TeamService.getTeamName(p)
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if team and p:GetAttribute("State") == "Deployed" and hum and hum.Health > 0 and hrp and not hum.SeatPart then
			table.insert(list[team], {pos = hrp.Position, kind = "inf"})
		end
	end
	for model, pst in pairs(PlaneService.getAll()) do
		if model.Parent and pst.team and list[pst.team] then
			table.insert(list[pst.team], {pos = pst.root.Position, kind = "plane", vel = pst.root.AssemblyLinearVelocity})
		end
	end
	for _, team in ipairs(Config.TeamOrder) do
		local info = CarrierService.getInfo(team)
		if info and info.state == "Active" and info.model and info.model:FindFirstChild("Hull") then
			table.insert(list[team], {pos = info.model.Hull.Position + Vector3.new(0, 14, 0), kind = "carrier", vel = info.model.Hull.AssemblyLinearVelocity})
		end
	end
	for _, cst in ipairs(LogisticsService.getShips()) do
		if list[cst.team] then
			table.insert(list[cst.team], {pos = cst.root.Position + Vector3.new(0, 5, 0), kind = "ship", ship = "Cargo", vel = cst.root.AssemblyLinearVelocity})
		end
	end
	for model, sst in pairs(ShipService.getAll()) do
		if model.Parent and not sst.dead and list[sst.team] and (model:GetAttribute("Depth") or 0) < 6 then
			table.insert(list[sst.team], {pos = sst.root.Position + Vector3.new(0, 5, 0), kind = "ship", ship = sst.kind, vel = sst.root.AssemblyLinearVelocity})
		end
	end
	return list
end

local function nearest(enemies, from, kind, range)
	local best, bestD
	for _, e in ipairs(enemies) do
		if e.kind == kind then
			local d = (e.pos - from).Magnitude
			if d < range and (not bestD or d < bestD) then best, bestD = e, d end
		end
	end
	return best, bestD
end

local function spreadDir(dir, deg)
	local s = math.rad(deg)
	return (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(rng:NextNumber(-s, s), rng:NextNumber(-s, s), 0)).LookVector
end

------------------------------------------------------------------ пехота
local function thinkInfantry(st, enemies, now)
	local hrp = st.model:FindFirstChild("HumanoidRootPart")
	local head = st.model:FindFirstChild("Head")
	if not hrp or not head then return end
	local myPos = hrp.Position
	local best, bestD
	for _, e in ipairs(enemies) do
		if e.kind == "inf" or e.kind == "plane" then
			local d = (e.pos - myPos).Magnitude
			local limit = e.kind == "plane" and B.PlaneRange or B.DetectRange
			if d < limit and (not bestD or d < bestD) then best, bestD = e, d end
		end
	end
	local hum = st.hum
	if not best then
		hum.AutoRotate = true
		if now > st.moveT then
			st.moveT = now + rng:NextNumber(2.5, 4)
			hum:MoveTo(clampArena(Vector3.new(rng:NextNumber(-60, 60), myPos.Y, rng:NextNumber(-90, 90))))
		end
		return
	end
	if best.kind ~= "plane" and bestD > B.EngageRange then
		hum.AutoRotate = true
		if now > st.moveT then
			st.moveT = now + 1
			hum:MoveTo(clampArena(best.pos))
		end
	else
		hum.AutoRotate = false
		if now > st.moveT then
			st.moveT = now + rng:NextNumber(1.2, 2.6)
			local toE = Vector3.new(best.pos.X - myPos.X, 0, best.pos.Z - myPos.Z)
			local side = toE.Magnitude > 0.1 and toE.Unit:Cross(Vector3.yAxis) or Vector3.xAxis
			hum:MoveTo(clampArena(myPos + side * rng:NextNumber(-14, 14)))
		end
		hrp.CFrame = CFrame.lookAt(myPos, Vector3.new(best.pos.X, myPos.Y, best.pos.Z))
	end
	if now - st.lastShot >= B.FireInterval then
		st.lastShot = now + rng:NextNumber(0, 0.15)
		local origin = head.Position
		local aim = best.pos
		if best.kind == "plane" and best.vel then aim += best.vel * (bestD / 900) end
		local dir = spreadDir((aim - origin).Unit, best.kind == "plane" and B.PlaneSpread or B.Spread)
		local params = RaycastParams.new()
		params.CollisionGroup = "Weapons" -- оружие видит и грузовые суда
		params.FilterType = Enum.RaycastFilterType.Exclude
		local fx = workspace:FindFirstChild("Effects")
		params.FilterDescendantsInstances = fx and {st.model, fx} or {st.model}
		local range = math.max(B.DetectRange, B.PlaneRange) + 60
		local res = workspace:Raycast(origin, dir * range, params)
		local barrel = st.rifle and st.rifle:FindFirstChild("Barrel")
		CombatService.tracer(barrel and barrel.Position or origin, res and res.Position or origin + dir * range, nil, "Rifle")
		if res then CombatService.applyHit(st.model, res.Instance, B.Damage, nil, "Rifle") end
	end
end

------------------------------------------------------------------ стрелок турели
local function thinkGunner(st, enemies, now)
	local turret = st.slot.turret

	if not turret or not turret.Parent then return end
	local gun = turret:FindFirstChild("GunBody")
	if not gun then return end
	local from = gun.Position
	local W = Config.Weapons and Config.Weapons[turret:GetAttribute("WeaponType") or ""]
	if W then
		local target = nearest(enemies, from, "ship", 1800) or nearest(enemies, from, "carrier", 1800)
			or nearest(enemies, from, "plane", 700) or nearest(enemies, from, "inf", 1300)
		if target then
			local d = (target.pos - from).Magnitude
			local t = d / W.ShellSpeed
			local aim = target.pos + (target.vel or Vector3.zero) * t + Vector3.new(0, 0.5 * W.Gravity * t * t, 0)
			local miss = d * math.tan(math.rad(target.kind == "plane" and 3 or 1))
			aim += Vector3.new(rng:NextNumber(-miss, miss), rng:NextNumber(-miss, miss) * 0.4, rng:NextNumber(-miss, miss))
			TurretService.botAim(turret, aim, true)
		else
			TurretService.botAim(turret, from + gun.CFrame.LookVector * 100, false)
		end
		return
	end
	local target = nearest(enemies, from, "plane", B.GunnerRange)
		or nearest(enemies, from, "ship", 900)
		or nearest(enemies, from, "inf", 450)
		or nearest(enemies, from, "carrier", 900)
	if target then
		local d = (target.pos - from).Magnitude
		local miss = d * math.tan(math.rad(target.kind == "plane" and (B.GunnerPlaneSpread or 4) or 1.5))
		local aim = target.pos + Vector3.new(rng:NextNumber(-miss, miss), rng:NextNumber(-miss, miss), rng:NextNumber(-miss, miss))
		TurretService.botAim(turret, aim, true)
	else
		TurretService.botAim(turret, from + gun.CFrame.LookVector * 100, false)
	end
end

------------------------------------------------------------------ капитан
local WAYPOINTS = {
	Blue = {Vector3.new(-1485, 0, 513), Vector3.new(-837, 0, 513), Vector3.new(-607, 0, 0), Vector3.new(-837, 0, -513), Vector3.new(-1485, 0, -513)},
}
WAYPOINTS.Red = {}
for i, w in ipairs(WAYPOINTS.Blue) do WAYPOINTS.Red[i] = Vector3.new(-w.X, 0, -w.Z) end

local function thinkCaptain(st, now)
	local info = CarrierService.getInfo(st.team)
	if not info or info.state ~= "Active" or info.driver ~= st.model or not info.ctrl then return end
	local c = info.ctrl
	local pos = c.root.Position
	local wps = WAYPOINTS[st.team]
	st.wp = st.wp or 1
	local fwd = CFrame.Angles(0, c.yaw, 0):VectorToWorldSpace(Vector3.zAxis)
	-- выход с якорной стоянки: сначала прямо по курсу, чтобы корма при повороте не задела корабли у причалов
	if not st.anchorExit then
		st.anchorExit = Vector3.new(pos.X, 0, pos.Z) + Vector3.new(fwd.X, 0, fwd.Z).Unit * 380
	end
	local target
	if not st.anchorExitDone then
		target = st.anchorExit
		if Vector3.new(target.X - pos.X, 0, target.Z - pos.Z).Magnitude < 60 then
			st.anchorExitDone = true
			target = wps[st.wp]
		end
	else
		target = wps[st.wp]
	end
	local to = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if st.anchorExitDone and to.Magnitude < 220 then
		st.wp = st.wp % #wps + 1
		return
	end
	local a = math.atan2(fwd:Cross(to.Unit).Y, fwd:Dot(to.Unit)) -- > 0: цель слева
	local steer = -math.clamp(a * 2, -1, 1)
	local desired = math.abs(a) > 0.9 and 16 or B.CruiseSpeed

	-- застряли (мель / препятствие): сдать назад и сменить точку
	st.lastPos = st.lastPos or pos
	st.stuckT = st.stuckT or now
	if (pos - st.lastPos).Magnitude > 12 then
		st.lastPos, st.stuckT = pos, now
	elseif now - st.stuckT > 8 then
		st.reverseUntil = now + 5
		st.wp = st.wp % #wps + 1
		st.lastPos, st.stuckT = pos, now
	end
	if st.reverseUntil and now < st.reverseUntil then
		desired, steer = -8, -steer
	end
	local throttle = math.clamp((desired - c.setpoint) / 4, -1, 1)
	CarrierService.botDrive(st.team, st.model, throttle, steer)
end

------------------------------------------------------------------ корабли ботов
local SHIP_ROUTES = {
	Battleship = {Vector3.new(-1215, 0, -94), Vector3.new(-756, 0, -351), Vector3.new(-513, 0, 270), Vector3.new(-945, 0, 405)},
	Submarine = {Vector3.new(-1282, 0, 243), Vector3.new(-878, 0, 581), Vector3.new(-567, 0, 0), Vector3.new(-878, 0, -580), Vector3.new(-1282, 0, -243)},
	-- катера ходят кругом по всей карте открытой водой (в обход островов и нефтяных платформ)
	Gunboat = {Vector3.new(-1900, 0, 400), Vector3.new(-800, 0, 1200), Vector3.new(700, 0, 1150), Vector3.new(1700, 0, 300),
		Vector3.new(1700, 0, -400), Vector3.new(700, 0, -1150), Vector3.new(-800, 0, -1200), Vector3.new(-1900, 0, -400)},
}

-- препятствия для кораблей: суша (Terrain выше воды) и опоры нефтяных платформ
local shoreParams = RaycastParams.new()
shoreParams.FilterType = Enum.RaycastFilterType.Include
shoreParams.IgnoreWater = true
local function refreshShore()
	local list = {workspace.Terrain}
	local neutral = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Neutral")
	for _, rig in ipairs(neutral and neutral:GetChildren() or {}) do
		local hull = rig:FindFirstChild("Hull")
		if hull then table.insert(list, hull) end
	end
	shoreParams.FilterDescendantsInstances = list
end
local function blocked(pos, dir, len)
	return workspace:Raycast(Vector3.new(pos.X, 6, pos.Z), dir * len, shoreParams) ~= nil
end
-- между точками суша? (стрелять сквозь остров бессмысленно)
local function landBetween(a, b)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	return d.Magnitude > 1 and blocked(a, d.Unit, d.Magnitude) or false
end
-- куда плыть, если впереди берег: ближайший к цели свободный сектор (nil — путь свободен)
local AVOID_ANGLES = {25, -25, 50, -50, 80, -80, 115, -115, 150, -150}
local function avoidDirection(pos, fwd, toGoal, speed)
	local look = 70 + math.abs(speed) * 2.5
	if not blocked(pos, fwd, look) then return nil end
	local best, bestScore
	for _, deg in ipairs(AVOID_ANGLES) do
		local dir = CFrame.Angles(0, math.rad(deg), 0):VectorToWorldSpace(fwd)
		if not blocked(pos, dir, look * 1.3) then
			local score = dir:Dot(toGoal) - math.abs(deg) / 400 -- ближе к цели и меньше поворот
			if not bestScore or score > bestScore then best, bestScore = dir, score end
		end
	end
	return best
end
local function mirror(team, v)
	if team == "Blue" then return v end
	return Vector3.new(-v.X, 0, -v.Z)
end

-- руль и ход к точке; при застревании — задний ход и следующая точка
local function driveToward(st, sst, goal, cruise, now, vertical)
	local pos = sst.root.Position
	if st.detourUntil and now < st.detourUntil and st.detourDir then
		goal = pos + st.detourDir * 120 -- объезжаем
	end
	local to = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
	local dist = to.Magnitude
	if dist < 1 then return dist end
	local fwd = CFrame.Angles(0, sst.yaw, 0):VectorToWorldSpace(Vector3.zAxis)
	-- берег впереди: отворачиваем заранее (лучи раз в 0.3 с), а не упираемся носом в остров
	if not st.avoidT or now - st.avoidT > 0.3 then
		st.avoidT = now
		st.avoidDir = avoidDirection(pos, fwd, to.Unit, sst.speed or 0)
	end
	if st.avoidDir then to = st.avoidDir * dist end
	local a = math.atan2(fwd:Cross(to.Unit).Y, fwd:Dot(to.Unit)) -- > 0: цель слева
	local steer = -math.clamp(a * 2, -1, 1)
	local desired = math.abs(a) > 0.9 and cruise * 0.55 or cruise
	st.lastPos = st.lastPos or pos
	st.stuckT = st.stuckT or now
	if (pos - st.lastPos).Magnitude > 10 then
		st.lastPos, st.stuckT = pos, now
	elseif now - st.stuckT > 6 then
		-- застряли: назад, потом отворот на 75° (в другую сторону, чем прошлый раз)
		st.reverseUntil = now + 3
		st.detourSign = -(st.detourSign or 1)
		st.detourDir = CFrame.Angles(0, math.rad(75) * st.detourSign, 0):VectorToWorldSpace(fwd)
		st.detourUntil = now + 10
		st.skipWp = true
		st.lastPos, st.stuckT = pos, now
	end
	if st.reverseUntil and now < st.reverseUntil then
		desired, steer = -sst.cfg.MaxReverseSpeed * 0.8, -steer
	end
	local throttle = math.clamp((desired - sst.setpoint) / 4, -1, 1)
	ShipService.botDrive(sst.model, st.model, throttle, steer, vertical or 0)
	return dist
end

-- Выход из гавани: у каждого корабля свой док между причальными стенками и носом в море,
-- фарватеры параллельные — идём прямо вперёд, без очереди и ожидания авианосца
local function harborExit(st, sst, kind, now)
	if st.exitDone then return false end
	local base = workspace.Map.Teams:FindFirstChild(st.team .. "Base")
	local berth = base and base.Zones:FindFirstChild("Berth_" .. kind)
	if not berth then st.exitDone = true return false end
	local pos = sst.root.Position
	-- корабль уже далеко от причала (например, бот сел позже) — правила не нужны
	if not st.exitPts and Vector3.new(pos.X - berth.Position.X, 0, pos.Z - berth.Position.Z).Magnitude > 120 then
		st.exitDone = true
		return false
	end
	if not st.exitPts then
		local sea = Vector3.new(berth.CFrame.LookVector.X, 0, berth.CFrame.LookVector.Z).Unit
		local b0 = Vector3.new(berth.Position.X, 0, berth.Position.Z)
		-- прямо по своему фарватеру до конца стенок и дальше в открытое море
		st.exitPts = {b0 + sea * 450, b0 + sea * 700}
		st.exitIdx = 1
	end
	local goal = st.exitPts[st.exitIdx]
	local dist = driveToward(st, sst, goal, sst.cfg.MaxSpeed * 0.55, now, 0)
	if dist < 90 then
		st.exitIdx += 1
		if st.exitIdx > #st.exitPts then st.exitDone = true end
	end
	return true
end

-- у каждого корабля свой док и фарватер — гавань не «занята» (свободен ли причал, проверяет ShipService)
local function harborBusy(team, now)
	return false
end
BotService._harborBusy = harborBusy

local function thinkShip(st, foes, now)
	local kind = SHIP_ROLE[st.slot.role]
	local model = kind == "Battleship" and ShipService.teamShip("Battleship", st.team) or st.slot.ship
	if not model then return end
	local sst = ShipService.getState(model)
	if not sst or sst.dead or sst.driver ~= st.model then return end
	if harborExit(st, sst, kind, now) then return end
	local route = SHIP_ROUTES[kind]
	-- у каждого катера свой старт на круге — расходятся по карте, а не идут колонной
	st.wp = st.wp or (kind == "Gunboat" and rng:NextInteger(1, #route) or 1)
	if st.skipWp then
		st.wp = st.wp % #route + 1
		st.skipWp = nil
	end
	local pos = sst.root.Position
	local cruise = sst.cfg.MaxSpeed * 0.7
	local vertical = 0

	if kind == "Gunboat" then
		-- противолодочная охота: подлодка противника на сонаре нашей команды
		local sub, subD
		for m2, s2 in pairs(ShipService.getAll()) do
			if s2.kind == "Submarine" and not s2.dead and s2.team ~= st.team and m2:GetAttribute("Sonar_" .. st.team) then
				local d2 = Vector3.new(s2.root.Position.X - pos.X, 0, s2.root.Position.Z - pos.Z).Magnitude
				if d2 < 450 and (not subD or d2 < subD) then sub, subD = s2, d2 end
			end
		end
		if sub then
			-- идём прямо над ней; рядом — сброс бомбы
			local lead = sub.root.Position + sub.root.AssemblyLinearVelocity * 2
			driveToward(st, sst, lead, sst.cfg.MaxSpeed * 0.9, now)
			if subD < 26 then NavalWeaponsService.fire(st.model, "depthcharge") end
			if sst.aimTurret then TurretService.botAim(sst.aimTurret, sub.root.Position, false) end
			return
		end
		-- охота: ближайший вражеский корабль, кружим на дистанции и стреляем
		local target = nearest(foes, pos, "ship", 1600) or nearest(foes, pos, "carrier", 1600)
		if target then
			local d = (target.pos - pos).Magnitude
			local goal = target.pos
			if d < 380 then
				local rel = Vector3.new(pos.X - target.pos.X, 0, pos.Z - target.pos.Z)
				rel = rel.Magnitude > 0.1 and rel.Unit or Vector3.xAxis
				goal = target.pos + rel * 300 + rel:Cross(Vector3.yAxis) * 160
			end
			driveToward(st, sst, goal, sst.cfg.MaxSpeed * 0.8, now)
			if sst.aimTurret then
				local W = Config.Weapons.Medium
				local t = d / W.ShellSpeed
				local aim = target.pos + (target.vel or Vector3.zero) * t + Vector3.new(0, 0.5 * W.Gravity * t * t, 0)
				local miss = d * math.tan(math.rad(1.2))
				aim += Vector3.new(rng:NextNumber(-miss, miss), 0, rng:NextNumber(-miss, miss))
				TurretService.botAim(sst.aimTurret, aim, d < 1200 and not landBetween(pos, target.pos))
			end
			return
		elseif sst.aimTurret then
			TurretService.botAim(sst.aimTurret, pos + CFrame.Angles(0, sst.yaw, 0):VectorToWorldSpace(Vector3.zAxis) * 100 + Vector3.new(0, 3, 0), false)
		end
	elseif kind == "Submarine" then
		local depth = sst.depth or 0
		-- цель: корабль, авианосец или грузовое судно противника
		local target = nearest(foes, pos, "ship", 900) or nearest(foes, pos, "carrier", 900)
		if target and not sst.forceSurface then
			local d = (target.pos - pos).Magnitude
			local lead = target.pos + (target.vel or Vector3.zero) * (d / Config.SubWeapons.Torpedo.Speed)
			local per = sst.cfg.PeriscopeDepth or 8
			local wantD = 6
			local v2 = depth < wantD - 1 and -1 or (depth > wantD + 1 and 1 or 0)
			driveToward(st, sst, lead, sst.cfg.MaxSpeed * 0.7, now, v2)
			-- нос на цель и мы на перископной глубине — пуск
			local fwd = CFrame.Angles(0, sst.yaw, 0):VectorToWorldSpace(Vector3.zAxis)
			local to = Vector3.new(lead.X - pos.X, 0, lead.Z - pos.Z)
			if depth <= per and d < 850 and to.Magnitude > 1 and fwd:Dot(to.Unit) > math.cos(math.rad(7)) then
				NavalWeaponsService.fire(st.model, "torpedo")
			end
			return
		end
		-- патруль на глубине, у базы (первая точка) — на поверхности
		local wantDepth = st.wp == 1 and 0 or 14
		vertical = depth < wantDepth - 1 and -1 or (depth > wantDepth + 1 and 1 or 0)
		cruise = sst.cfg.MaxSpeed * 0.8
	elseif kind == "Battleship" then
		-- сближение с противником на дистанцию огня главного калибра
		local target, bestD
		local base = workspace.Map.Teams:FindFirstChild(st.team .. "Base")
		local baseX = base and base:GetPivot().Position.X or 0
		for _, e in ipairs(foes) do
			local big = e.kind == "carrier" or (e.kind == "ship" and e.ship == "Battleship")
			-- цель у нашего острова не преследуем: мелочь там добивают наводчики, зенитки и катера
			local awayFromHome = math.abs(e.pos.X - baseX) > 1300
			if big and awayFromHome then
				local d = (e.pos - pos).Magnitude
				if d < 2200 and (not bestD or d < bestD) then target, bestD = e, d end
			end
		end
		if target then
			local d = (target.pos - pos).Magnitude
			if d > 950 then
				driveToward(st, sst, target.pos, cruise, now)
				return
			end
			cruise = sst.cfg.MaxSpeed * 0.4 -- в зоне огня — малым ходом по маршруту
		end
	end
	local dist = driveToward(st, sst, mirror(st.team, route[st.wp]), cruise, now, vertical)
	if dist < 200 then st.wp = st.wp % #route + 1 end
end

------------------------------------------------------------------ пилот
local planeRayParams = RaycastParams.new()
planeRayParams.FilterType = Enum.RaycastFilterType.Include
planeRayParams.IgnoreWater = true
local planeRayT = -math.huge

local function thinkPilot(st, enemies, now)
	local model, pst = PlaneService.planeOf(st.model)
	if not model or not pst or not pst.root.Parent then return end
	local root = pst.root
	local pos = root.Position
	local fwd = root.CFrame.LookVector
	local speed = pst.speed or 0
	local input = {throttle = 1, firing = false}

	-- список «земли» для луча высоты — раз в 5 с, а не на каждый такт каждого пилота
	if now - planeRayT > 5 then
		planeRayT = now
		local list = {workspace.Terrain}
		for _, n in ipairs({"Teams", "Neutral", "Nature", "Carriers"}) do
			local f = workspace.Map:FindFirstChild(n)
			if f then table.insert(list, f) end
		end
		planeRayParams.FilterDescendantsInstances = list
	end
	local g = workspace:Raycast(pos, Vector3.new(0, -800, 0), planeRayParams)
	local agl = g and (pos.Y - g.Position.Y) or pos.Y

	local flat = Vector3.new(fwd.X, 0, fwd.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.xAxis
	if pst.onGround and speed < P.TakeoffSpeed + 4 then
		input.aim = speed > P.TakeoffSpeed - 3 and (flat + Vector3.new(0, 0.4, 0)).Unit or flat
		PlaneService.setBotInput(st.model, input)
		return
	end

	local target = nearest(enemies, pos, "plane", B.PilotRange)
	local kind = "plane"
	if not target then
		target = nearest(enemies, pos, "carrier", 2600)
		kind = "carrier"
	end
	if not target then
		target = nearest(enemies, pos, "ship", 2600)
		kind = "ship"
	end
	if not target then
		target = nearest(enemies, pos, "inf", 2600)
		kind = "inf"
	end
	local aimPoint, desired
	if target then
		aimPoint = target.pos
		local d = (aimPoint - pos).Magnitude
		if kind == "plane" and target.vel then aimPoint += target.vel * (d / 800) end
		desired = (aimPoint - pos).Unit
		if kind ~= "plane" then
			if desired.Y < -0.42 then desired = Vector3.new(desired.X, -0.42, desired.Z).Unit end -- не круче ~25°
			if d < 260 then st.pullUntil = now + 2.6 end -- выход из штурмовки
		end
	else
		local ang = now * 0.12 + st.slot.index
		desired = (Vector3.new(math.cos(ang) * 810, 260, math.sin(ang) * 610) - pos).Unit
	end
	if st.pullUntil and now < st.pullUntil then
		desired = (flat + Vector3.new(0, 0.9, 0)).Unit
	end
	-- расхождение при лобовом сближении с самолётом (иначе столкновение)
	if kind == "plane" and target and target.vel then
		local rel = target.pos - pos
		local d = rel.Magnitude
		local myVel = root.AssemblyLinearVelocity
		local closing = -(target.vel - myVel):Dot(rel.Unit)
		if d < 170 and closing > 60 and not (st.breakUntil and now < st.breakUntil) then
			st.breakUntil = now + 1.8
			local side = flat:Cross(Vector3.yAxis).Unit * (rng:NextNumber() < 0.5 and -1 or 1)
			st.breakDir = (flat * 0.4 + side + Vector3.new(0, 0.45, 0)).Unit
		end
	end
	if st.breakUntil and now < st.breakUntil and st.breakDir then
		desired = st.breakDir
		aimPoint = nil -- не стреляем во время отворота
	end
	-- безопасность: высота, потолок, границы
	if agl < 90 and desired.Y < 0.15 then desired = Vector3.new(desired.X, 0.45, desired.Z).Unit end
	local vy = root.AssemblyLinearVelocity.Y
	-- выход из снижения: чем быстрее снижаемся, тем раньше
	local pullAlt = math.max(70, -vy * 2.6)
	if (agl < pullAlt and vy < -10) or agl < 60 then desired = (flat + Vector3.new(0, 1.2, 0)).Unit end
	if pos.Y > P.MaxAltitude - 220 and desired.Y > 0 then
		desired = Vector3.new(desired.X, desired.Y * math.clamp((P.MaxAltitude - pos.Y) / 220, 0, 1), desired.Z).Unit
	end
	if pos.Y > P.MaxAltitude then desired = (flat + Vector3.new(0, -0.35, 0)).Unit end
	if math.abs(pos.X) > Config.Planes.Fighter.BoundsX - 200 or math.abs(pos.Z) > Config.Planes.Fighter.BoundsZ - 100 then
		desired = (Vector3.new(-pos.X, 0, -pos.Z).Unit + Vector3.new(0, 0.1, 0)).Unit
	end
	input.aim = desired
	input.throttle = desired.Y < -0.25 and 0.5 or 1
	if aimPoint then
		local to = aimPoint - pos
		input.firing = to.Magnitude < 650 and fwd:Dot(to.Unit) > math.cos(math.rad(6)) and agl > 25
	end
	PlaneService.setBotInput(st.model, input)
end

------------------------------------------------------------------ слоты и появление
local function seatFree(seat)
	return seat and seat.Parent and seat.Occupant == nil
end

local function slotSeat(slot)
	if slot.role == "bsCaptain" then
		local m = ShipService.teamShip("Battleship", slot.team)
		return m and m:FindFirstChild("HelmSeat")
	elseif slot.role == "bsGunner" then
		return slot.turret and slot.turret:FindFirstChild("TurretSeat")
	end
	if slot.role == "captain" then
		local info = CarrierService.getInfo(slot.team)
		return info and info.state == "Active" and info.model and info.model:FindFirstChild("HelmSeat")
	elseif slot.role == "carrierGunner" or slot.role == "baseGunner" then
		return slot.turret and slot.turret:FindFirstChild("TurretSeat")
	end
	return nil
end

local baseTurrets = {} -- [команда] = {t = os.clock(), list = зенитки базы по порядку}
local function refreshTurret(slot)
	if slot.role == "bsGunner" then
		local m = ShipService.teamShip("Battleship", slot.team)
		slot.turret = m and m:FindFirstChild(slot.index == 1 and "Turret_A" or "Turret_B") or nil
		return
	end
	if slot.role == "carrierGunner" then
		local info = CarrierService.getInfo(slot.team)
		if not (info and info.state == "Active" and info.model) then
			slot.turret = nil
			return
		end
		local list = {}
		for _, c in ipairs(info.model:GetChildren()) do
			if c:IsA("Model") and c:GetAttribute("CarrierTurret") then table.insert(list, c) end
		end
		table.sort(list, function(a, b) return a.Name < b.Name end)
		slot.turret = list[slot.index]
	elseif slot.role == "baseGunner" then
		-- зенитки базы неподвижны: список раз в 30 с (или если турель пропала), а не GetDescendants всей базы
		-- каждую секунду для каждого ждущего слота
		local now = os.clock()
		local cache = baseTurrets[slot.team]
		local cached = cache and cache.list[slot.index]
		if not cache or now - cache.t > 30 or (cached and not cached.Parent) then
			local list = {}
			local base = workspace.Map.Teams:FindFirstChild(slot.team .. "Base")
			for _, d in ipairs(base and base:GetDescendants() or {}) do
				if d:IsA("Model") and d:GetAttribute("BaseTurret") then table.insert(list, d) end
			end
			table.sort(list, function(a, b) return a:GetFullName() < b:GetFullName() end)
			cache = {t = now, list = list}
			baseTurrets[slot.team] = cache
		end
		slot.turret = cache.list[slot.index]
	end
end

local function canSpawn(slot)
	if slot.role == "infantry" then return true end
	if slot.role == "pilot" then return true end
	if slot.role == "gbCaptain" or slot.role == "subCaptain" then return true end
	if slot.role ~= "captain" and slot.role ~= "bsCaptain" then refreshTurret(slot) end
	return seatFree(slotSeat(slot))
end

local function spawnSlot(slot)
	slot.spawning = true
	if not slot.nick then
		local used = {}
		for _, s in ipairs(slots) do if s.nick then used[s.nick] = true end end
		for _, p in ipairs(Players:GetPlayers()) do used[p.DisplayName] = true; used[p.Name] = true end
		slot.nick = BotNames.new(used)
		slot.rank = BotNames.rank(#Config.Ranks.List)
		slot.skin = SKIN[math.random(1, #SKIN - 1)]
	end
	local label = slot.nick
	local bot = makeBot(slot.team, label, slot)
	slot.spawning = false
	if not bot then
		slot.respawnAt = os.clock() + 5
		slot.role = slot.baseRole
		return
	end
	-- пока модель собиралась (makeBot ждёт), место бота занял игрок — не спускаем технику зря
	if slot.disabled then
		bot:Destroy()
		slot.role = slot.baseRole
		return
	end
	local hum = bot:FindFirstChildOfClass("Humanoid")
	local st = {model = bot, hum = hum, team = slot.team, slot = slot, lastShot = 0, moveT = 0, nextThink = 0}
	slot.state = st

	if slot.role == "infantry" then
		local pos = infantrySpawnPoint(slot.team)
		bot:PivotTo(CFrame.lookAt(pos, Vector3.new(0, pos.Y, pos.Z)))
		bot.Parent = folder
		local rifle = ServerStorage.Weapons.Rifle:Clone()
		for _, d in ipairs(rifle:GetDescendants()) do
			if d:IsA("LocalScript") or d:IsA("Script") then d:Destroy() end
		end
		rifle.Parent = bot
		hum:EquipTool(rifle)
		st.rifle = rifle
		local ff = Instance.new("ForceField")
		ff.Visible = false
		ff.Parent = bot
		Debris:AddItem(ff, 3)
		setupAnims(st, false)
	elseif slot.role == "pilot" then
		local base = workspace.Map.Teams:FindFirstChild(slot.team .. "Base")
		local marker = base and base.Zones:FindFirstChild("PlaneSpawn")
		bot:PivotTo(CFrame.new((marker and marker.Position or Vector3.zero) + Vector3.new(0, 30, 0)))
		bot.Parent = folder
		local info = CarrierService.getInfo(slot.team)
		local fromCarrier = info and info.state == "Active" and info.model and math.abs(info.model:GetAttribute("Speed") or 0) < 2 and rng:NextNumber() < 0.5
		local ok = PlaneService.spawnForBot(bot, slot.team, fromCarrier and "Carrier" or "Base", fromCarrier and info.model or nil)
		if not ok then
			bot:Destroy()
			slot.state = nil
			slot.respawnAt = os.clock() + 3
			slot.role = slot.baseRole
			return
		end
		setupAnims(st, true)
	elseif slot.role == "gbCaptain" or slot.role == "subCaptain" then
		local kind = SHIP_ROLE[slot.role]
		if slot.ship and slot.ship.Parent then ShipService.remove(slot.ship) end
		slot.ship = nil
		local base = workspace.Map.Teams:FindFirstChild(slot.team .. "Base")
		local berth = base and base.Zones:FindFirstChild("Berth_" .. kind)
		bot:PivotTo(CFrame.new((berth and berth.Position or Vector3.zero) + Vector3.new(0, 40, 0)))
		bot.Parent = folder
		local m = ShipService.botSpawnPersonal(bot, slot.team, kind)
		if not m then
			bot:Destroy()
			slot.state = nil
			slot.respawnAt = os.clock() + 5
			slot.role = slot.baseRole
			return
		end
		slot.ship = m
		setupAnims(st, true)
	else
		local seat = slotSeat(slot)
		if not seatFree(seat) then
			bot:Destroy()
			slot.state = nil
			slot.respawnAt = os.clock() + 3
			slot.role = slot.baseRole
			return
		end
		bot:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
		bot.Parent = folder
		seat:Sit(hum)
		setupAnims(st, true)
	end

	local hrp = bot:FindFirstChild("HumanoidRootPart")
	if hrp then pcall(function() hrp:SetNetworkOwner(nil) end) end
	bySlotBot[bot] = slot
	CombatService.trackBot(bot)
	st.spawnedAt = os.clock()
	hum.Died:Connect(function()
		local ship = slot.ship
		if ship and (slot.role == "gbCaptain" or slot.role == "subCaptain") then
			task.delay(2, function()
				if ship.Parent and ship:GetAttribute("IsVessel") then ShipService.remove(ship) end
			end)
		end
		bySlotBot[bot] = nil
		if slot.state == st then slot.state = nil end
		slot.respawnAt = os.clock() + B.RespawnTime
		slot.role = slot.baseRole
		slot.waitSince = nil
		Debris:AddItem(bot, 3)
	end)
end

local function buildSlots()
	local n = 0
	for _, team in ipairs(Config.TeamOrder) do
		local num = 0
		local function add(role, index)
			if not ALLOWED_ROLE[role] then return end
			num += 1
			n += 1
			table.insert(slots, {team = team, role = role, baseRole = role, index = index, number = num, respawnAt = 0})
		end
		local R = B.Roles or {}
		for i = 1, (R.Captain or 0) do add("captain", i) end
		for i = 1, (R.CarrierGunners or 0) do add("carrierGunner", i) end
		for i = 1, (R.BaseGunners or 0) do add("baseGunner", i) end
		for i = 1, (R.Pilots or 0) do add("pilot", i) end
		for i = 1, (R.BattleshipCaptain or 0) do add("bsCaptain", i) end
		for i = 1, (R.BattleshipGunners or 0) do add("bsGunner", i) end
		for i = 1, (R.Gunboats or 0) do add("gbCaptain", i) end
		for i = 1, (R.Submarines or 0) do add("subCaptain", i) end
		local used = num
		-- если ролей меньше, чем ботов на команду, — остальные в самолёты/на катера по очереди
		for i = 1, math.max(0, B.PerTeam - used) do add(i % 2 == 0 and "pilot" or "gbCaptain", 100 + i) end
	end
end

------------------------------------------------------------------ запасные роли
-- экипажи командной техники: если её нет, бот не стоит без дела
local CREW_ROLE = {captain = true, carrierGunner = true, bsCaptain = true, bsGunner = true}
local function pickFallback(slot)
	local L = Config.Limits or {}
	local team = slot.team
	local options = {
		{role = "pilot", ok = PlaneService.teamCount(team) < (L.PlanesPerTeam or 99) - 1},
		{role = "gbCaptain", ok = ShipService.teamCount("Gunboat", team) < (L.GunboatsPerTeam or 99)},
	}
	-- разные боты — разные предпочтения, чтобы не все сели в самолёты
	local start = slot.number % #options
	for k = 0, #options - 1 do
		local o = options[(start + k) % #options + 1]
		if o.ok then return o.role end
	end
	return nil -- всё занято лимитами — ждём, пешком боты не воюют
end

------------------------------------------------------------------ игроки вместо ботов
-- на команду ботов = PerTeam − живых игроков в ней; лишние уходят с конца списка
-- (сначала добор, подлодки, катера… экипаж авианосца — последним)
local function humans(team)
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if TeamService.getTeamName(p) == team then n += 1 end
	end
	return n
end

local function despawnSlot(slot)
	local st = slot.state
	slot.state = nil
	if st then
		bySlotBot[st.model] = nil
		PlaneService.removeOf(st.model)
		if st.model.Parent then st.model:Destroy() end
	end
	local ship = slot.ship
	if ship and ship.Parent then ShipService.remove(ship) end
	slot.ship = nil
	slot.role = slot.baseRole
	slot.waitSince = nil
end

local function applyQuota(now)
	for _, team in ipairs(Config.TeamOrder) do
		local allowed = math.max(0, B.PerTeam - humans(team))
		local k = 0
		for _, slot in ipairs(slots) do
			if slot.team == team then
				k += 1
				if k > allowed then
					slot.disabled = true
					-- бот мог досоздаться уже после отключения слота
					if (slot.state or slot.ship) and not slot.spawning then despawnSlot(slot) end
				elseif slot.disabled then
					slot.disabled = false
					slot.respawnAt = now + 2
				end
			end
		end
	end
end

------------------------------------------------------------------ главный цикл
local function manage(now)
	applyQuota(now)
	-- бот-командир спускает авианосец и линкор бесплатно (казну не тратит) — только в команде
	-- без живых игроков; когда игроки есть, технику покупают они сами из казны
	if B.BuyCarrier and now - startT > (B.CarrierBuyDelay or 15) then
		for _, team in ipairs(Config.TeamOrder) do
			local info = CarrierService.getInfo(team)
			if info and info.state == "None" and humans(team) == 0 then CarrierService.botPurchase(team) end
		end
	end
	if B.BuyBattleship and now - startT > (B.CarrierBuyDelay or 15) + 5 then
		for _, team in ipairs(Config.TeamOrder) do
			if ShipService.teamShipState("Battleship", team) == "None" and humans(team) == 0 then ShipService.botPurchase("Battleship", team) end
		end
	end
	for _, slot in ipairs(slots) do
		local st = slot.state
		if slot.disabled then
			continue
		elseif st and not st.model.Parent then
			-- модель бота удалили в обход смерти (Died не придёт): освобождаем слот, иначе он занят навсегда
			despawnSlot(slot)
			slot.respawnAt = now + B.RespawnTime
		elseif st then
			-- бот, который должен сидеть, но не сидит (корабль утонул, самолёт пропал) — пересоздать
			local hum = st.hum
			if slot.role ~= "infantry" and hum and hum.Health > 0 and not hum.SeatPart and now - (st.spawnedAt or now) > 4 then
				st.unseatedT = st.unseatedT or now
				if now - st.unseatedT > 5 then hum.Health = 0 end
			elseif st then
				st.unseatedT = nil
			end
			-- бот в запасной роли: своя техника появилась — возвращаем его на место
			if slot.role ~= slot.baseRole and CREW_ROLE[slot.baseRole] and now - (st.spawnedAt or now) > 15 then
				local cur = slot.role
				slot.role = slot.baseRole
				local ready = canSpawn(slot)
				slot.role = cur
				if ready then
					local ship = slot.ship
					if ship and ship.Parent then ShipService.remove(ship) end
					slot.ship = nil
					bySlotBot[st.model] = nil
					slot.state = nil
					if st.model.Parent then st.model:Destroy() end
					slot.role = slot.baseRole
					slot.respawnAt = now + 1
				end
			end
		elseif not slot.spawning and now >= slot.respawnAt then
			local personal = slot.role == "gbCaptain" or slot.role == "subCaptain"
			if personal and harborBusy(slot.team, now) then
				slot.respawnAt = now + 4
			elseif canSpawn(slot) then
				slot.waitSince = nil
				task.spawn(spawnSlot, slot)
			elseif CREW_ROLE[slot.role] then
				-- свою технику (авианосец/линкор) ждём недолго, потом — в самолёт, на катер, подлодку или в пехоту
				slot.waitSince = slot.waitSince or now
				if now - slot.waitSince > 6 then
					local fb = pickFallback(slot)
					slot.waitSince = nil
					if fb then
						slot.role = fb
						task.spawn(spawnSlot, slot)
					else
						slot.respawnAt = now + 5
					end
				end
			end
		end
	end
end

function BotService.init()
	if not B or not B.Enabled then return end
	if B.StudioOnly and not RunService:IsStudio() then return end
	refreshShore()
	folder = Instance.new("Folder")
	-- игрок занял место бота: убрать его сразу, а не на следующем такте
	local function requota() task.defer(applyQuota, os.clock()) end
	Players.PlayerAdded:Connect(function(p) p:GetPropertyChangedSignal("Team"):Connect(requota) end)
	for _, p in ipairs(Players:GetPlayers()) do p:GetPropertyChangedSignal("Team"):Connect(requota) end
	Players.PlayerRemoving:Connect(function() task.delay(0.5, applyQuota, os.clock() + 0.5) end)
	folder.Name = "Bots"
	folder.Parent = workspace
	buildSlots()
	startT = os.clock()

	local manageAcc, thinkAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		manageAcc += dt
		if manageAcc >= 1 then
			manageAcc = 0
			manage(now)
		end
		thinkAcc += dt
		if thinkAcc < 0.1 then return end
		thinkAcc = 0
		local enemies = collectEnemies()
		for _, slot in ipairs(slots) do
			local st = slot.state
			if st and st.hum and st.hum.Health > 0 and now >= st.nextThink and st.model.Parent then
				local role = slot.role
				st.nextThink = now + (role == "pilot" and 0.12 or 0.25)
				local foes = enemies[other(slot.team)]
				local ok, err = pcall(function()
					if role == "infantry" then
						thinkInfantry(st, foes, now)
					elseif role == "carrierGunner" or role == "baseGunner" or role == "bsGunner" then
						thinkGunner(st, foes, now)
					elseif SHIP_ROLE[role] then
						thinkShip(st, foes, now)
					elseif role == "captain" then
						thinkCaptain(st, now)
					elseif role == "pilot" then
						thinkPilot(st, foes, now)
					end
				end)
				if not ok then warn("[BotService] " .. role .. ": " .. tostring(err)) end
			end
		end
	end)
end

return BotService
