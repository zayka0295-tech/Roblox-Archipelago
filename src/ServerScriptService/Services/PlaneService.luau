-- Самолёты: вызов с терминала (игрок) или ботом, полёт, стрельба, бомбы, урон, крушения.
-- Игрок-пилот управляет физикой сам (сетевое владение); бот-пилот летит на сервере (botFly).
-- Типы — Config.Planes (Fighter, Bomber): параметры самолёта — st.cfg. У бомбардировщика сзади турель
-- (TurretService, как башни кораблей): стрелок садится кнопкой у самолёта и гибнет вместе с ним.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local CarrierService = require(Services.CarrierService)
local CombatService = require(Services.CombatService)
local Notifier = require(Services.Notifier)
local AbandonTimer = require(Services.AbandonTimer)
local Guard = require(Services.RemoteGuard)
local AntiCheat = require(Services.AntiCheatService)
local TurretService = require(Services.TurretService)
local ProjectileService = require(Services.ProjectileService)
local CaptureService = require(Services.CaptureService)

local PlaneService = {}
local Bombs = Config.Bombs
local planes = {}   -- [модель] = состояние
local byOwner = {}  -- [игрок или бот] = модель
local lastSpawn = {}

local function isPlayer(x) return typeof(x) == "Instance" and x:IsA("Player") end
local function charOf(actor)
	if not actor then return nil end
	if isPlayer(actor) then return actor.Character end
	return actor
end

local function folder()
	local f = workspace.Map:FindFirstChild("Planes")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Planes"
		f.Parent = workspace.Map
	end
	return f
end

local function setOwner(root, player)
	pcall(function()
		if root:CanSetNetworkOwnership() then root:SetNetworkOwner(player) end
	end)
end

-- бомбы на борту: атрибут для приборов пилота и бомба под фюзеляжем истребителя (HungBomb)
local function setBombs(st, n)
	st.bombs = n
	st.model:SetAttribute("Bombs", n)
	for _, p in ipairs(st.model:GetChildren()) do
		if p.Name == "HungBomb" and p:IsA("BasePart") then p.Transparency = n > 0 and 0 or 1 end
	end
end

-- кто-то сидит на месте, кроме пилотского (стрелок бомбардировщика)
local function crewSeats(st)
	local list = {}
	for _, s in ipairs(st.model:GetDescendants()) do
		if s:IsA("Seat") and s ~= st.seat and s.Occupant then table.insert(list, s) end
	end
	return list
end

------------------------------------------------------------------ уничтожение
local function destroyPlane(model, killer, reason)
	local st = planes[model]
	if not st or st.dead then return end
	st.dead = true
	planes[model] = nil
	if byOwner[st.owner] == model then byOwner[st.owner] = nil end

	local root = st.root
	local e = Instance.new("Explosion")
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.BlastRadius = 18
	e.Position = root.Position
	e.Parent = workspace

	local pilot, hum = st.pilot, st.pilotHum
	local credit = killer
	if not credit and st.lastHitBy and os.clock() - st.lastHitT < Config.Combat.KillCreditWindow then
		credit = st.lastHitBy
	end
	if hum and hum.Parent and hum.Health > 0 and pilot then
		local w = st.seat:FindFirstChild("SeatWeld")
		if w then w:Destroy() end
		CombatService.creditKill(credit, pilot)
	end
	-- стрелок гибнет вместе с самолётом (при замене самолёта — просто высаживается)
	for _, s in ipairs(crewSeats(st)) do
		local char = s.Occupant.Parent
		local actor = Players:GetPlayerFromCharacter(char) or (char:GetAttribute("IsBot") and char) or nil
		local w = s:FindFirstChild("SeatWeld")
		if w then w:Destroy() end
		if actor and reason ~= "replaced" then CombatService.creditKill(credit, actor) end
	end
	-- вызвал новый самолёт — старый просто исчезает, без сообщения «разбился» и взрыва
	if reason == "replaced" then
		e:Destroy()
		if st.prompt then st.prompt:Destroy() end
		model:Destroy()
		return
	end
	Notifier.send(st.owner, reason == "shot" and "Your plane was shot down!" or "The plane crashed", "error")
	-- личная награда тому, кто сбил вражеский самолёт
	local shooter = killer or (st.lastHitBy and os.clock() - (st.lastHitT or 0) < Config.Combat.KillCreditWindow and st.lastHitBy)
	local R = Config.Economy.Rewards or {}
	local rw = (st.isBot and R.BotPlaneKill or R.PlaneKill) or 0 -- самолёт бота — маленькая награда
	if st.kind == "Bomber" then rw = math.floor(rw * 1.5) end -- бомбардировщик крепче и опаснее
	if reason == "shot" and isPlayer(shooter) and shooter.Parent and TeamService.getTeamName(shooter) ~= st.team and rw > 0 then
		DataService.addGold(shooter, rw)
		Notifier.send(shooter, ("Enemy plane shot down! +%d gold"):format(rw), "success")
	end
	if reason == "shot" and isPlayer(shooter) and shooter.Parent and TeamService.getTeamName(shooter) ~= st.team then
		require(script.Parent.RankService).award(shooter, "PlaneKill", (st.isBot and 0.5 or 1) * (st.kind == "Bomber" and 1.5 or 1))
	end

	setOwner(root, nil)
	root.FlightAlign.Enabled = false
	root.FlightDrive.Enabled = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Massless = false
			d.CanCollide = d.Size.Magnitude > 3
			d.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(10, 40), math.random(-30, 30))
			d.Color = d.Color:Lerp(Color3.fromRGB(30, 30, 30), 0.6)
		end
	end
	model:SetAttribute("IsPlane", false)
	if st.prompt then st.prompt:Destroy() end
	Debris:AddItem(model, 6)
end

function PlaneService.damage(model, amount, attacker)
	local st = planes[model]
	if not st or st.dead then return end
	local at = attacker and TeamService.getTeamName(attacker)
	if at and at == st.team and not Config.Combat.FriendlyFire then return end
	st.health = math.max(0, st.health - amount)
	st.lastHitBy, st.lastHitT = attacker, os.clock()
	model:SetAttribute("Health", math.floor(st.health))
	if st.health <= 0 then
		destroyPlane(model, attacker, "shot")
	end
end

------------------------------------------------------------------ вызов
-- аэродром на острове (Config.IslandAirfield): определение острова и модель Airstrip в его аутпосте
local function airfieldIsland()
	local id = Config.IslandAirfield and Config.IslandAirfield.Island
	for _, def in ipairs(Config.Islands) do
		if def.Id == id then return def end
	end
	return nil
end
local function airstrip()
	local def = airfieldIsland()
	local outpost = def and workspace.Map.Neutral:FindFirstChild(def.Outpost)
	return outpost and outpost:FindFirstChild("Airstrip")
end

local function spawnCFrame(team, where, carrier, P)
	P = P or Config.Planes.Fighter
	local marker
	if where == "Carrier" then
		marker = carrier and carrier:FindFirstChild("PlaneSpawn")
	else
		-- на базе (и на аэродроме острова) несколько стартовых позиций на пороге ВПП: берём свободную
		local zones
		if where == "Island" then
			local strip = airstrip()
			zones = strip and strip:FindFirstChild("Zones")
		else
			local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
			zones = base and base:FindFirstChild("Zones")
		end
		local list = {}
		for _, z in ipairs(zones and zones:GetChildren() or {}) do
			if z.Name:match("^PlaneSpawn") then table.insert(list, z) end
		end
		table.sort(list, function(x, y) return x.Name < y.Name end)
		local ov = OverlapParams.new()
		ov.FilterType = Enum.RaycastFilterType.Include
		ov.FilterDescendantsInstances = {folder()}
		for _, z in ipairs(list) do
			if #workspace:GetPartBoundsInBox(z.CFrame, P.SpawnBox or Vector3.new(36, 14, 34), ov) == 0 then
				marker = z
				break
			end
		end
		marker = marker or list[1]
	end
	if not marker then return nil end
	local gear = ServerStorage.Vehicles[P.Model or "Fighter"]:GetAttribute("GearHeight") or 6.2
	local ignore = {folder(), marker}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then table.insert(ignore, bots) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(marker.Position + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
	local y = (hit and hit.Position.Y or marker.Position.Y) + gear + 0.2
	local look = marker.CFrame.LookVector
	local pos = Vector3.new(marker.Position.X, y, marker.Position.Z)
	return CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z))
end

local function runwayFree(cf, ownerActor, size)
	local ov = OverlapParams.new()
	ov.FilterType = Enum.RaycastFilterType.Include
	ov.FilterDescendantsInstances = {folder()}
	local mine = byOwner[ownerActor]
	for _, p in ipairs(workspace:GetPartBoundsInBox(cf, (size or Vector3.new(36, 14, 34)) + Vector3.new(4, 0, 2), ov)) do
		if not (mine and p:IsDescendantOf(mine)) then return false end
	end
	return true
end

-- кто может сесть за штурвал: владелец, а в самолёт игрока — и любой игрок его команды (бот летает только на своём)
local function canPilot(st, actor)
	if actor == st.owner then return true end
	return isPlayer(actor) and isPlayer(st.owner) and TeamService.getTeamName(actor) == st.team
		and actor:GetAttribute("State") == "Deployed"
end

-- самолёт, которым игрок сейчас управляет (свой или взятый у союзника)
local function flownBy(player)
	local m = byOwner[player]
	local st = m and planes[m]
	if st and st.pilot == player then return m, st end
	for model, s in pairs(planes) do
		if s.pilot == player then return model, s end
	end
	return nil
end

local function setupSeat(model, st)
	st.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if st.dead then return end
		local hum = st.seat.Occupant
		local root = st.root
		if hum then
			local char = hum.Parent
			local actor = Players:GetPlayerFromCharacter(char) or (char:GetAttribute("IsBot") and char) or nil
			if not actor or not canPilot(st, actor) then
				local w = st.seat:FindFirstChild("SeatWeld")
				if w then w:Destroy() end
				return
			end
			st.pilot, st.pilotHum, st.abandonT = actor, hum, nil
			if st.prompt then st.prompt.Enabled = false end
			root.FlightAlign.CFrame = root.CFrame.Rotation
			root.FlightDrive.VectorVelocity = root.AssemblyLinearVelocity
			root.FlightAlign.Enabled = true
			root.FlightDrive.Enabled = true
			model:SetAttribute("EngineOn", true)
			setOwner(root, isPlayer(actor) and actor or nil)
		else
			st.pilot, st.pilotHum, st.firing = nil, nil, false
			st.abandonT = os.clock()
			if st.prompt and isPlayer(st.owner) then st.prompt.Enabled = true end
			root.FlightAlign.Enabled = false
			root.FlightDrive.Enabled = false
			model:SetAttribute("EngineOn", false)
			setOwner(root, nil)
		end
	end)
end

local function makePlane(ownerActor, team, cf, kind)
	kind = Config.Planes[kind] and kind or "Fighter"
	local P = Config.Planes[kind]
	local mine = byOwner[ownerActor]
	local old = mine and planes[mine]
	if old and old.pilot and old.pilot ~= ownerActor then
		-- на старом сейчас летает союзник — не выдёргиваем его, просто отвязываем
		byOwner[ownerActor] = nil
	elseif mine then
		destroyPlane(mine, nil, "replaced")
	end
	local model = ServerStorage.Vehicles[P.Model or kind]:Clone()
	model.Name = kind .. "_" .. ownerActor.Name
	local tcol = Config.Teams[team].Color
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("TeamPaint") then d.Color = tcol end
	end
	model:SetAttribute("Team", team)
	model:SetAttribute("PlaneType", kind)
	model:SetAttribute("Health", P.MaxHealth)
	model:SetAttribute("MaxHealth", P.MaxHealth)
	model:SetAttribute("EngineOn", false)
	model:SetAttribute("BotPilot", not isPlayer(ownerActor))
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = "Planes" end
	end
	model:PivotTo(cf)
	model.Parent = folder()

	local st = {
		model = model, owner = ownerActor, team = team, root = model.Root, seat = model.PilotSeat,
		health = P.MaxHealth, muzzles = {}, shotN = 0, lastShot = 0, firing = false,
		isBot = not isPlayer(ownerActor), speed = 0, bank = 0, ai = nil,
		cfg = P, kind = kind, bombs = 0,
	}
	setBombs(st, P.Bombs or 0)
	for _, d in ipairs(model:GetChildren()) do
		if d.Name == "GunMuzzle" then table.insert(st.muzzles, d) end
	end
	planes[model] = st
	byOwner[ownerActor] = model
	setupSeat(model, st)
	-- выпрыгнул в воздухе (пилот или стрелок) — парашют военного базара, если куплен
	for _, s in ipairs(model:GetDescendants()) do
		if s:IsA("Seat") or s:IsA("VehicleSeat") then
			local last
			s:GetPropertyChangedSignal("Occupant"):Connect(function()
				local hum = s.Occupant
				if hum then
					last = Players:GetPlayerFromCharacter(hum.Parent)
				elseif last then
					local p = last
					last = nil
					if not st.dead and p.Parent then require(script.Parent.CargoDropService).bailOut(p) end
				end
			end)
		end
	end
	-- турель стрелка (бомбардировщик) — как башни кораблей
	TurretService.attachShip(model)

	-- вернуться в свой самолёт по E
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "Board plane"
	prompt.ObjectText = P.DisplayName
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = model:FindFirstChild("Fuselage") or st.root
	st.prompt = prompt
	prompt.Triggered:Connect(function(player)
		if st.dead or not planes[model] then return end
		if not canPilot(st, player) then
			Notifier.send(player, TeamService.getTeamName(player) ~= st.team and "This is an enemy plane" or "This is someone else's plane", "error")
			return
		end
		if st.seat.Occupant then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.SeatPart or player:GetAttribute("State") ~= "Deployed" then return end
		AntiCheat.grace(player)
		char:PivotTo(st.seat.CFrame + Vector3.new(0, 3, 0))
		st.seat:Sit(hum)
	end)
	setOwner(st.root, isPlayer(ownerActor) and ownerActor or nil)
	return model, st
end

-- true — самолёт выдан (причины отказа игрок видит в уведомлении)
function PlaneService.requestSpawn(player, team, where, carrier, kind)
	kind = Config.Planes[kind] and kind or "Fighter"
	local P = Config.Planes[kind]
	if TeamService.getTeamName(player) ~= team then
		Notifier.send(player, "This is the other team's terminal", "error")
		return false
	end
	if player:GetAttribute("State") ~= "Deployed" then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.SeatPart then return false end
	local now = os.clock()
	if lastSpawn[player] and now - lastSpawn[player] < P.SpawnCooldown then
		Notifier.send(player, ("Plane is getting ready · %d s"):format(math.ceil(P.SpawnCooldown - (now - lastSpawn[player]))), "error")
		return false
	end
	if where == "Carrier" and not CarrierService.isActive(team) then return false end
	if where == "Island" then
		local def = airfieldIsland()
		if not def or CaptureService.getOwner(def.Id) ~= team then
			Notifier.send(player, "Your team doesn't hold this island — the airfield is closed", "error")
			return false
		end
	end
	local cf = spawnCFrame(team, where, carrier, P)
	if not cf then
		Notifier.send(player, "Takeoff point not found", "error")
		return false
	end
	if not runwayFree(cf, player, P.SpawnBox) then
		Notifier.send(player, "Runway is occupied by another plane", "error")
		return false
	end
	local cap = Config.Limits and Config.Limits.PlanesPerTeam or 99
	if PlaneService.teamCount(team, player) >= cap then
		Notifier.send(player, ("%d team planes are already airborne — that's the limit"):format(cap), "error")
		return false
	end
	local bcap = kind == "Bomber" and Config.Limits and Config.Limits.BombersPerTeam
	if bcap and PlaneService.teamCount(team, player, "Bomber") >= bcap then
		Notifier.send(player, ("%d team bombers are already airborne — that's the limit"):format(bcap), "error")
		return false
	end
	local paid, why = DataService.spendGold(player, P.Price)
	if not paid then
		Notifier.send(player, why == "NotEnough" and ("Requires %d gold"):format(P.Price)
			or why == "Syncing" and "Your saved data is still loading — purchases are paused for a moment"
			or "Data is still loading", "error")
		return false
	end
	lastSpawn[player] = now
	local model, st = makePlane(player, team, cf, kind)
	AntiCheat.grace(player)
	char:PivotTo(st.seat.CFrame + Vector3.new(0, 3, 0))
	st.seat:Sit(hum)
	Notifier.send(player, P.DisplayName .. " ready · W — throttle, mouse — heading, LMB — fire, E — drop bomb", "success")
	return true
end

-- самолёт для бота-пилота (бесплатно); true если вызван
-- живые самолёты команды (кроме своего — его заменит новый); kind — только этого типа
function PlaneService.teamCount(team, exceptOwner, kind)
	local n = 0
	for model, st in pairs(planes) do
		if model.Parent and not st.dead and st.team == team and st.owner ~= exceptOwner and (not kind or st.kind == kind) then n += 1 end
	end
	return n
end

function PlaneService.spawnForBot(bot, team, where, carrier)
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	if PlaneService.teamCount(team, bot) >= (Config.Limits and Config.Limits.PlanesPerTeam or 99) then return false end
	local cf = spawnCFrame(team, where, carrier, Config.Planes.Fighter)
	if not cf or not runwayFree(cf, bot, Config.Planes.Fighter.SpawnBox) then return false end
	local model, st = makePlane(bot, team, cf, "Fighter")
	st.ai = {throttle = 1, aim = cf.LookVector, firing = false}
	bot:PivotTo(st.seat.CFrame + Vector3.new(0, 3, 0))
	st.seat:Sit(hum)
	return true
end

function PlaneService.planeOf(actor)
	local m = byOwner[actor]
	return m, m and planes[m]
end

-- тихо убрать самолёт (бот ушёл с сервера — его место занял игрок)
function PlaneService.removeOf(actor)
	local m = byOwner[actor]
	if not m then return end
	planes[m] = nil
	byOwner[actor] = nil
	m:Destroy()
end

function PlaneService.setBotInput(actor, input)
	local m = byOwner[actor]
	local st = m and planes[m]
	if st and st.isBot then st.ai = input end
end

function PlaneService.getAll()
	return planes
end

------------------------------------------------------------------ полёт бота (на сервере)
local function rotateToward(a, b, maxAng)
	local d = math.clamp(a:Dot(b), -1, 1)
	local ang = math.acos(d)
	if ang <= maxAng or ang < 1e-4 then return b end
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then axis = Vector3.yAxis end
	return (CFrame.fromAxisAngle(axis.Unit, maxAng) * a).Unit
end

local function botFly(st, dt)
	local P = st.cfg
	local ai = st.ai or {throttle = 0, aim = st.root.CFrame.LookVector}
	local root, model = st.root, st.model
	local cf = root.CFrame
	local fwd = cf.LookVector
	local pos = root.Position
	local gear = model:GetAttribute("GearHeight") or 6.2

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {model, charOf(st.pilot)}
	local ground = workspace:Raycast(pos, Vector3.new(0, -(gear + 2.5), 0), params)
	local onGround = ground ~= nil and ground.Material ~= Enum.Material.Water
	local groundVel = Vector3.zero
	if onGround and ground.Instance:IsA("BasePart") then
		local gv = ground.Instance:GetVelocityAtPosition(ground.Position)
		groundVel = Vector3.new(gv.X, 0, gv.Z)
	end

	local throttle = math.clamp(ai.throttle or 1, 0, 1)
	local target = throttle * P.MaxSpeed
	local speed = st.speed
	if speed < target then speed = math.min(target, speed + P.Acceleration * dt) else speed = math.max(target, speed - P.Acceleration * 0.5 * dt) end
	if not onGround then speed -= fwd.Y * 22 * dt end
	speed = math.clamp(speed, 0, P.MaxSpeed * 1.35)
	st.speed = speed

	local aimDir = (ai.aim and ai.aim.Magnitude > 0.01) and ai.aim.Unit or fwd
	if pos.Y > P.MaxAltitude - 60 and aimDir.Y > 0 then
		aimDir = Vector3.new(aimDir.X, 0, aimDir.Z).Unit
	end
	if pos.Y > P.MaxAltitude and aimDir.Y > -0.4 then
		aimDir = Vector3.new(aimDir.X, -0.4, aimDir.Z).Unit
	end
	local newFwd, vel
	if onGround and speed < P.TakeoffSpeed then
		local flatF = Vector3.new(fwd.X, 0, fwd.Z)
		flatF = flatF.Magnitude > 0.01 and flatF.Unit or -Vector3.zAxis
		if ground.Instance:IsA("BasePart") then
			local w = ground.Instance.AssemblyAngularVelocity.Y
			if math.abs(w) > 1e-4 then flatF = CFrame.Angles(0, w * dt, 0):VectorToWorldSpace(flatF) end
		end
		local stance = math.rad(10) * (1 - math.clamp(speed / (P.TakeoffSpeed * 0.8), 0, 1))
		newFwd = (flatF * math.cos(stance) + Vector3.yAxis * math.sin(stance)).Unit
		vel = flatF * speed + Vector3.new(0, (ground.Position.Y + gear - pos.Y) * 6, 0) + groundVel
	else
		local control = math.clamp((speed - P.StallSpeed * 0.6) / (P.TakeoffSpeed - P.StallSpeed * 0.6), 0.25, 1)
		if pos.Y > P.MaxAltitude - 60 then control = math.max(control, 0.8) end
		newFwd = rotateToward(fwd, aimDir, math.rad(P.TurnRate) * 0.85 * dt * control)
		if onGround and newFwd.Y < 0 then newFwd = Vector3.new(newFwd.X, 0, newFwd.Z).Unit end
		vel = newFwd * speed
		if not onGround and speed < P.StallSpeed then
			vel += Vector3.new(0, -(P.StallSpeed - speed) * 1.6, 0)
		end
		if onGround then
			vel = Vector3.new(vel.X, math.max(vel.Y, (ground.Position.Y + gear - pos.Y) * 6), vel.Z) + groundVel
		end
	end

	if pos.Y > P.MaxAltitude - 20 and vel.Y > 0 then
		vel = Vector3.new(vel.X, 0, vel.Z) -- жёсткий потолок
	end
	local flatN = Vector3.new(newFwd.X, 0, newFwd.Z)
	local flatA = Vector3.new(aimDir.X, 0, aimDir.Z)
	local targetBank = 0
	if not onGround and flatN.Magnitude > 0.05 and flatA.Magnitude > 0.05 then
		flatN, flatA = flatN.Unit, flatA.Unit
		targetBank = math.clamp(math.atan2(flatN:Cross(flatA).Y, flatN:Dot(flatA)) * 2.2, -math.rad(P.MaxBank), math.rad(P.MaxBank))
	end
	local maxRoll = math.rad(P.RollRate) * dt
	st.bank += math.clamp(targetBank - st.bank, -maxRoll, maxRoll)
	local right = newFwd:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then right = cf.RightVector end
	right = right.Unit
	local up = right:Cross(newFwd).Unit
	root.FlightAlign.CFrame = CFrame.lookAt(Vector3.zero, newFwd, CFrame.fromAxisAngle(newFwd, -st.bank) * up)
	root.FlightDrive.VectorVelocity = vel
	st.firing = ai.firing == true
	st.onGround = onGround
end

------------------------------------------------------------------ стрельба
local function fire(st)
	local muzzle = st.muzzles[(st.shotN % #st.muzzles) + 1]
	st.shotN += 1
	if not muzzle then return end
	local P = st.cfg
	local origin = muzzle.Position
	local converge = st.root.Position + st.root.CFrame.LookVector * 300
	local dir = (converge - origin).Unit * P.GunRange
	local params = RaycastParams.new()
	params.CollisionGroup = "Weapons" -- оружие видит и грузовые суда
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {st.model}
	local pc = charOf(st.pilot)
	if pc then table.insert(ignore, pc) end
	local fx = workspace:FindFirstChild("Effects")
	if fx then table.insert(ignore, fx) end
	params.FilterDescendantsInstances = ignore
	local res = workspace:Raycast(origin, dir, params)
	-- пилот-игрок рисует свои пули сам (без задержки), остальным — с сервера
	CombatService.tracer(origin, res and res.Position or origin + dir, isPlayer(st.pilot) and st.pilot.UserId or nil, "PlaneGun")
	-- у пилота-игрока урон приходит от его проверенных попаданий (PlaneHit): серверная копия его
	-- самолёта отстаёт на пинг, и в вираже её луч уходит мимо того, что пилот видит в прицеле
	if res and not isPlayer(st.pilot) then
		CombatService.applyHit(st.pilot, res.Instance, P.GunDamage, nil, "PlaneGun", res.Position)
	end
end

------------------------------------------------------------------ цикл
local crashParams = RaycastParams.new()
crashParams.FilterType = Enum.RaycastFilterType.Exclude
crashParams.IgnoreWater = true
crashParams.RespectCanCollide = true -- надписи и декор без коллизии не считаются препятствием

local function step(dt)
	local now = os.clock()
	for model, st in pairs(planes) do
		local P = st.cfg
		if not model.Parent or not st.root.Parent then
			planes[model] = nil
			if byOwner[st.owner] == model then byOwner[st.owner] = nil end
			continue
		end
		if st.pilotHum and (st.pilotHum.Health <= 0 or st.pilotHum.SeatPart ~= st.seat) then
			-- пилот погиб в кабине: мотор глохнет, самолёт неуправляем
			st.pilot, st.pilotHum, st.firing = nil, nil, false
			st.abandonT = st.abandonT or now
			st.root.FlightAlign.Enabled = false
			st.root.FlightDrive.Enabled = false
			model:SetAttribute("EngineOn", false)
			setOwner(st.root, nil)
			local w = st.seat:FindFirstChild("SeatWeld")
			if w then w:Destroy() end
			if st.prompt and isPlayer(st.owner) then st.prompt.Enabled = true end
		end
		-- стрелок ждёт пилота — самолёт не брошен
		if not st.pilot and st.abandonT and #crewSeats(st) > 0 then st.abandonT = now end
		AbandonTimer.check(st, P.DisplayName:lower(), P.AbandonDespawn, now)
		if not st.pilot and st.abandonT and now - st.abandonT > P.AbandonDespawn then
			-- пустой самолёт самоуничтожается: взрыв без урона и наград
			planes[model] = nil
			if byOwner[st.owner] == model then byOwner[st.owner] = nil end
			local e = Instance.new("Explosion")
			e.BlastPressure = 0
			e.DestroyJointRadiusPercent = 0
			e.BlastRadius = 14
			e.Position = st.root.Position
			e.Parent = workspace
			if isPlayer(st.owner) and st.owner.Parent then
				Notifier.send(st.owner, ("Your plane self-destructed: nobody aboard for %d s"):format(P.AbandonDespawn), "info")
			end
			model:Destroy()
			continue
		end

		if st.isBot and st.pilot then
			botFly(st, dt)
		end

		local root = st.root
		local vel = root.AssemblyLinearVelocity
		local speed = vel.Magnitude

		-- античит и защита от «подброса»: скорость выше физически возможной или телепорт = потеря самолёта
		local limit = P.MaxSpeed * 1.8
		st.overT = speed > limit and (st.overT or 0) + dt or 0
		local jumped = st.lastPos and (root.Position - st.lastPos).Magnitude > limit * dt + 40
		st.lastPos = root.Position
		-- скорость выше шлёт сам клиент (можно подделать нулём), а скачок за кадр не ловит мелкие шаги
		-- по 40 студов каждый кадр. Поэтому ещё и путь за секунду по реальным позициям (с запасом на лаг)
		if not st.winT or not st.winPos then
			st.winT, st.winPos = now, root.Position
		elseif now - st.winT >= 1 then
			if (root.Position - st.winPos).Magnitude > limit * (now - st.winT) + 60 then jumped = true end
			st.winT, st.winPos = now, root.Position
		end
		if st.overT > 0.3 or jumped then
			if isPlayer(st.pilot) then
				warn(("[PlaneService] suspicious plane movement %s (speed %.0f)"):format(st.pilot.Name, speed))
			end
			destroyPlane(model, nil, "crash")
			continue
		end
		if math.abs(root.Position.X) > 4800 or math.abs(root.Position.Z) > 2450 or root.Position.Y > 1200 then
			destroyPlane(model, nil, "crash")
			continue
		end
		if root.Position.Y < 0.5 then
			destroyPlane(model, nil, "crash")
			continue
		end
		if speed > P.CrashSpeed then
			local ignore = {model}
			local pc = charOf(st.pilot)
			if pc then table.insert(ignore, pc) end
			local fx = workspace:FindFirstChild("Effects")
			if fx then table.insert(ignore, fx) end
			crashParams.FilterDescendantsInstances = ignore
			-- коробка размером с самолёт (размах крыльев, без шасси), сдвигается вдоль скорости
			local hit = workspace:Blockcast(root.CFrame, P.CrashBox or Vector3.new(34, 3, 26), vel.Unit * (speed * dt * 3 + 8), crashParams)
				or workspace:Raycast(root.Position, vel.Unit * (speed * dt * 3 + 10), crashParams)
			local impact = hit and -vel.Unit:Dot(hit.Normal) or 0
			-- лобовой удар — всегда; на большой скорости разбивает и скользящий (посадка — до ~90)
			if hit and (impact > 0.45 or (speed > 90 and impact > 0.12)) then
				local other = hit.Instance:FindFirstAncestorOfClass("Model")
				if other and planes[other] then destroyPlane(other, nil, "crash") end
				destroyPlane(model, nil, "crash")
				continue
			end
		end

		st.gearT = (st.gearT or 0) + dt
		if st.gearT > 0.4 then
			local elapsed = st.gearT
			st.gearT = 0
			local p = RaycastParams.new()
			p.FilterType = Enum.RaycastFilterType.Exclude
			p.FilterDescendantsInstances = {model}
			local gearH = model:GetAttribute("GearHeight") or 6.2
			local g = workspace:Raycast(root.Position, Vector3.new(0, -(gearH + 8), 0), p)
			model:SetAttribute("GearUp", g == nil and speed > P.TakeoffSpeed * 0.8)
			-- перезарядка бомб: стоит на земле или палубе (не на воде)
			local landed = g ~= nil and g.Material ~= Enum.Material.Water and speed < Bombs.RearmMaxSpeed
			if landed and st.bombs < (P.Bombs or 0) then
				st.rearmT = (st.rearmT or 0) + elapsed
				if st.rearmT >= Bombs.RearmTime then
					st.rearmT = 0
					setBombs(st, st.bombs + 1)
				end
			else
				st.rearmT = 0
			end
		end

		if st.firing and st.pilot and now - st.lastShot >= P.GunCooldown then
			local zone = CombatService.zoneAt(root.Position)
			if not (zone == "Lobby" or zone == "Any" or zone == st.team) then
				st.lastShot = now
				fire(st)
			end
		end
	end
end

------------------------------------------------------------------ бомбы
local bombParams = RaycastParams.new()
bombParams.FilterType = Enum.RaycastFilterType.Exclude
bombParams.IgnoreWater = false
local function finiteVec(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e5
end

-- сброс бомбы пилотом. origin/vel — точка и скорость самолёта у пилота (серверная копия отстаёт на пинг);
-- принимаем, если они рядом с серверными. nil — сброшена, иначе причина.
function PlaneService.dropBomb(actor, origin, vel)
	local model, st = flownBy(actor)
	if not st or st.dead or st.pilot ~= actor then return "NoPlane" end
	if (st.bombs or 0) <= 0 then return "Empty" end
	local now = os.clock()
	if now - (st.lastBomb or 0) < Bombs.DropInterval then return "Wait" end
	local root = st.root
	local zone = CombatService.zoneAt(root.Position)
	if zone == "Lobby" or zone == "Any" or zone == st.team then return "Safe" end
	local pc = charOf(st.pilot)
	bombParams.FilterDescendantsInstances = pc and {model, pc} or {model}
	local gearH = model:GetAttribute("GearHeight") or 6.2
	if workspace:Raycast(root.Position, Vector3.new(0, -(gearH + Bombs.MinHeight), 0), bombParams) then return "Low" end
	local bay = model:FindFirstChild("BombBay")
	local from = bay and bay.Position or root.Position - root.CFrame.UpVector * 3
	local v = root.AssemblyLinearVelocity
	local sv = v.Magnitude
	if finiteVec(origin) and (origin - from).Magnitude < 25 + sv * 0.4 then from = origin end
	if finiteVec(vel) and (vel - v).Magnitude < 40 and vel.Magnitude < st.cfg.MaxSpeed * 1.5 then v = vel end
	st.lastBomb = now
	setBombs(st, st.bombs - 1)
	local W = {Damage = Bombs.Damage, SplashRadius = Bombs.SplashRadius, Gravity = Bombs.Gravity, Class = "Bomb"}
	ProjectileService.launch(from, v, st.pilot, W, pc and {model, pc} or {model})
	return nil
end

local BOMB_MSG = {
	Empty = "No bombs left — land and stop to rearm",
	Safe = "Can't drop bombs over your own base",
	Low = "Too low to drop bombs",
}

function PlaneService.init()
	-- терминал открывает меню ангара (HangarUI, как верфь); выбор самолёта — Remotes.BuyPlane.
	-- Сервер помнит, у какого терминала игрок открыл меню, и выдаёт самолёт только рядом с ним
	local OpenHangar = ReplicatedStorage.Remotes:WaitForChild("OpenHangar")
	local hangar = {} -- [игрок] = {team, where, carrier, part}
	local function hookTerminal(prompt, label, getTeam, where, carrier)
		local old = prompt.Parent:FindFirstChild("BomberPrompt")
		if old then old:Destroy() end
		prompt.ActionText = "Hangar"
		prompt.ObjectText = label
		prompt.Triggered:Connect(function(player)
			local team = getTeam()
			if not Config.Teams[team] then
				-- нейтральный остров: аэродром закрыт
				local def = airfieldIsland()
				Notifier.send(player, ("Capture point %s to use this airfield"):format(def and def.Letter or ""), "error")
				return
			end
			if TeamService.getTeamName(player) ~= team then
				Notifier.send(player, "This is the other team's terminal", "error")
				return
			end
			hangar[player] = {team = team, where = where, carrier = carrier, part = prompt.Parent}
			OpenHangar:FireClient(player, team, where)
		end)
	end
	for _, team in ipairs(Config.TeamOrder) do
		local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
		local term = base and base.Decor:FindFirstChild("AirTerminal")
		local prompt = term and term:FindFirstChild("PlanePrompt")
		if prompt then
			hookTerminal(prompt, "Air terminal", function() return team end, "Base", nil)
		end
	end
	-- аэродром на острове: самолёты — только команде, которая им владеет
	local strip = airstrip()
	local iterm = strip and strip:FindFirstChild("AirTerminal")
	local iprompt = iterm and iterm:FindFirstChild("PlanePrompt")
	if iprompt then
		local def = airfieldIsland()
		hookTerminal(iprompt, "Airfield " .. (def.Letter or def.Name), function() return CaptureService.getOwner(def.Id) end, "Island", nil)
	end
	local carriers = workspace.Map:WaitForChild("Carriers")
	local function hookCarrier(c)
		local term = c:FindFirstChild("AirTerminal")
		local prompt = term and term:FindFirstChild("PlanePrompt")
		if prompt then
			hookTerminal(prompt, "Deck takeoff", function() return c:GetAttribute("Team") end, "Carrier", c)
		end
	end
	ReplicatedStorage.Remotes:WaitForChild("BuyPlane").OnServerInvoke = function(player, kind)
		if not Guard.allow(player, "BuyPlane") then return {ok = false, msg = "Too fast, please wait"} end
		if type(kind) ~= "string" or not Config.Planes[kind] then return {ok = false, msg = "Unknown plane"} end
		local h = hangar[player]
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not h or not h.part.Parent or not hrp or (hrp.Position - h.part.Position).Magnitude > 25 then
			return {ok = false, msg = "Go to the air terminal"}
		end
		local ok = PlaneService.requestSpawn(player, h.team, h.where, h.carrier, kind)
		if ok then hangar[player] = nil end
		return {ok = ok == true}
	end
	Players.PlayerRemoving:Connect(function(p) hangar[p] = nil end)
	carriers.ChildAdded:Connect(function(c) task.defer(hookCarrier, c) end)
	for _, c in ipairs(carriers:GetChildren()) do hookCarrier(c) end

	CombatService.onPlaneHit = PlaneService.damage

	ReplicatedStorage.Remotes:WaitForChild("PlaneFire").OnServerEvent:Connect(function(player, firing)
		if type(firing) ~= "boolean" then return end
		-- клиент шлёт только смену нажатия; отпускание (false) не режем, чтобы очередь не «залипала»
		if firing and not Guard.bucket(player, "PlaneFire", 20, 10) then return end
		local _, st = flownBy(player)
		if st and st.pilot == player then
			st.firing = firing == true
			if not firing then st.firingEnd = os.clock() end
		end
	end)

	-- попадание пулемёта, которое увидел пилот (см. CombatService.checkClientHit)
	-- сброс бомбы (E / кнопка BOMB)
	local bombNote = {}
	ReplicatedStorage.Remotes:WaitForChild("PlaneBomb").OnServerEvent:Connect(function(player, origin, vel)
		if not Guard.bucket(player, "PlaneBomb", 4, 4) then return end
		local why = PlaneService.dropBomb(player, origin, vel)
		local msg = why and BOMB_MSG[why]
		if msg and os.clock() - (bombNote[player] or 0) > 2 then
			bombNote[player] = os.clock()
			Notifier.send(player, msg, "error")
		end
	end)
	Players.PlayerRemoving:Connect(function(p) bombNote[p] = nil end)

	ReplicatedStorage.Remotes:WaitForChild("PlaneHit").OnServerEvent:Connect(function(player, part, hitPos)
		local model, st = flownBy(player)
		if not st or st.dead or st.pilot ~= player then return end
		local P = st.cfg
		-- стреляет сейчас (или только что отпустил — последние пули ещё в пути)
		if not st.firing and os.clock() - (st.firingEnd or 0) > 0.5 then return end
		-- не чаще темпа пулемёта
		if not Guard.bucket(player, "PlaneHit", 1 / P.GunCooldown * 1.15, 4) then return end
		local root = st.root
		local zone = CombatService.zoneAt(root.Position)
		if zone == "Lobby" or zone == "Any" or zone == st.team then return end
		-- самолёт на сервере отстаёт на пинг: запас по дальности и по углу (в вираже нос уходит вперёд)
		if not CombatService.checkClientHit(root.Position, part, hitPos, P.GunRange + 80, root.CFrame.LookVector, 35) then return end
		if part:IsDescendantOf(model) then return end
		CombatService.applyHit(player, part, P.GunDamage, nil, "PlaneGun", hitPos)
	end)

	Players.PlayerRemoving:Connect(function(p)
		local model = byOwner[p]
		if model then
			byOwner[p] = nil
			local st = planes[model]
			-- на нём летает союзник — оставляем (исчезнет, когда опустеет)
			if not (st and st.pilot and st.pilot ~= p) then
				planes[model] = nil
				model:Destroy()
			end
		end
		lastSpawn[p] = nil
	end)

	RunService.Heartbeat:Connect(step)
end

return PlaneService
