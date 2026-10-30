-- Грузовые вертолёты нефтяных платформ (Config.Helis). Пока платформа (Config.Islands с IsRig) у команды,
-- с её вертолётной площадки (HeliPad) взлетает вертолёт с контейнером под брюхом, летит на площадку своей базы
-- (Decor.Helipad), ставит контейнер у края площадки (ContainerDrop), получает выплату и возвращается за новым.
-- Быстрее грузовых судов, но его можно сбить: модель помечена IsCargo, урон приходит через CombatService.onCargoHit.
-- Платформа сменила владельца — рейс отменяется: вертолёт улетает к платформе и исчезает; у нового владельца
-- вертолёт появится через RespawnDelay. Модель двигает сервер (детали закреплены), скорость для проверки
-- попаданий выставляется деталям вручную.
-- Лестницы платформ: кнопка «Climb» у воды поднимает на палубу (как трапы кораблей).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local CaptureService = require(Services.CaptureService)
local TreasuryService = require(Services.TreasuryService)
local Notifier = require(Services.Notifier)
local AntiCheat = require(Services.AntiCheatService)

local HeliService = {}
local H = Config.Helis
local routes = {} -- [id острова] = {def, pad, heli, nextAt}
local folder
local GEAR = 8.9      -- от корня вертолёта до низа полозьев
local CONTAINER_SCALE = 0.7

local function isPlayer(x) return typeof(x) == "Instance" and x:IsA("Player") end

------------------------------------------------------------------ модель
-- все детали в осях корня: вперёд = −Z, вверх = +Y. Возвращает модель и список {деталь, смещение, винт?}
local function buildHeli(team)
	local m = Instance.new("Model")
	m.Name = "CargoHeli_" .. team
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local rgb = Color3.fromRGB
	local body = team == "Blue" and rgb(70, 84, 64) or rgb(132, 116, 84)
	local stripe = Config.Teams[team].Color
	local parts = {}
	local function add(name, offset, size, color, mat, props, spin)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanTouch = false
		p.Size = size
		p.Color = color
		p.Material = mat or Enum.Material.Metal
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		p.Parent = m
		table.insert(parts, {part = p, offset = offset, spin = spin})
		return p
	end
	local root = add("Root", CFrame.new(), Vector3.new(2, 2, 2), body, nil, {Transparency = 1, CanCollide = false})
	m.PrimaryPart = root
	add("Body", CFrame.new(0, 0, 0), Vector3.new(7, 6, 15), body)
	add("Nose", CFrame.new(0, -0.6, -8.4), Vector3.new(6.4, 4.6, 2.4), body)
	add("Cockpit", CFrame.new(0, 1, -8.6) * CFrame.Angles(math.rad(-25), 0, 0), Vector3.new(6, 3, 2.2), rgb(60, 110, 150), Enum.Material.Glass, {Transparency = 0.25})
	add("Stripe", CFrame.new(0, 0.4, 0), Vector3.new(7.08, 1, 15.08), stripe, Enum.Material.SmoothPlastic)
	add("Engine", CFrame.new(0, 3.6, 1.5), Vector3.new(4, 1.6, 7), body:Lerp(rgb(0, 0, 0), 0.2))
	add("TailBoom", CFrame.new(0, 1.4, 13), Vector3.new(1.8, 1.8, 12), body)
	add("TailFin", CFrame.new(0, 3.6, 18.6), Vector3.new(0.4, 4.4, 2.6), body)
	add("TailWing", CFrame.new(0, 1.6, 17.6), Vector3.new(5, 0.3, 1.6), body)
	add("Mast", CFrame.new(0, 5, 0), Vector3.new(0.9, 1.6, 0.9), rgb(40, 40, 40))
	-- несущий винт (вращается вокруг мачты): две лопасти крест-накрест
	for i = 0, 1 do
		add("Blade", CFrame.new(0, 5.8, 0), Vector3.new(36, 0.25, 1.4), rgb(30, 30, 32), Enum.Material.SmoothPlastic, {CanCollide = false}, {axis = "Y", angle = i * 90})
	end
	-- рулевой винт
	for i = 0, 1 do
		add("TailBlade", CFrame.new(0.5, 3.6, 18.6), Vector3.new(0.2, 5, 0.6), rgb(30, 30, 32), Enum.Material.SmoothPlastic, {CanCollide = false}, {axis = "X", angle = i * 90})
	end
	-- высокие полозья: контейнер висит под брюхом между ними
	for _, s in ipairs({-1, 1}) do
		add("Skid", CFrame.new(s * 4.2, -GEAR + 0.3, -1), Vector3.new(0.5, 0.5, 15), rgb(40, 40, 40))
		for _, z in ipairs({-5, 4}) do
			add("Strut", CFrame.new(s * 3.9, -5.9, z) * CFrame.Angles(0, 0, math.rad(s * 6)), Vector3.new(0.4, 6, 0.4), rgb(40, 40, 40))
		end
	end
	for _, p in ipairs(parts) do
		p.part:SetAttribute("HeliPart", true)
	end
	m:SetAttribute("IsCargo", true)
	m:SetAttribute("Team", team)
	m:SetAttribute("CargoType", "Heli")
	m:SetAttribute("MaxHealth", H.Health)
	m:SetAttribute("Health", H.Health)
	return m, parts
end

-- контейнер (копия модели игры, уменьшенная) — ставится под брюхо
local function makeContainer()
	local c = ServerStorage.Ships.CargoContainer:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true d.CanTouch = false end
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end
	end
	c:ScaleTo(CONTAINER_SCALE)
	return c
end

------------------------------------------------------------------ полёт
local function padTop(pad)
	return pad.Position + Vector3.new(0, pad.Size.X / 2, 0) -- диск: цилиндр лежит осью X вверх
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- поставить модель: корень в pos, курс yaw, наклон pitch; винты крутятся (angle)
local function place(h)
	local cf = CFrame.new(h.pos) * CFrame.Angles(0, h.yaw, 0) * CFrame.Angles(h.pitch, 0, h.roll or 0)
	local list, cfs = {}, {}
	for _, p in ipairs(h.parts) do
		local off = p.offset
		if p.spin then
			local a = h.rotor + math.rad(p.spin.angle)
			off = p.spin.axis == "Y" and off * CFrame.Angles(0, a, 0) or off * CFrame.Angles(a * 2.5, 0, 0)
		end
		table.insert(list, p.part)
		table.insert(cfs, cf * off)
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	local vel = h.vel or Vector3.zero
	for _, p in ipairs(list) do p.AssemblyLinearVelocity = vel end
	if h.container and h.container.Parent == h.model then
		h.container:PivotTo(cf * CFrame.new(0, -5.9, 0))
	end
end

local function baseHelipad(team)
	local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
	local pad = base and base.Decor:FindFirstChild("Helipad")
	return pad and pad:FindFirstChild("HeliPad"), pad and pad:FindFirstChild("ContainerDrop")
end

-- выплата за доставленный контейнер — как у грузовых судов
local function payout(route, team)
	TreasuryService.add(team, H.Reward, nil)
	for _, p in ipairs(Players:GetPlayers()) do
		if TeamService.getTeamName(p) == team then
			if H.PersonalShare <= 0 or DataService.addGold(p, H.PersonalShare) then
				Notifier.send(p, ("Helicopter cargo from %s delivered · treasury +%d · you +%d"):format(route.def.Name, H.Reward, H.PersonalShare), "success")
			end
			if p:GetAttribute("State") == "Deployed" then require(Services.RankService).award(p, "Delivery") end
		end
	end
	ReplicatedStorage.GameState:SetAttribute("LastDelivery", ("%s → %s · treasury +%d"):format(route.def.Name, team, H.Reward))
end

-- доставленный контейнер остаётся у площадки на ContainerLife сек.
local function dropContainer(h, drop)
	local c = h.container
	h.container = nil
	if not c then return end
	if not drop then c:Destroy() return end
	local slots = drop:GetAttribute("Used") or 0
	local x = ((slots % 3) - 1) * 7.5
	drop:SetAttribute("Used", slots + 1)
	local cf, sz = c:GetBoundingBox()
	local off = c:GetPivot().Position - cf.Position -- опорная точка контейнера не в центре рамки
	local spot = (drop.CFrame * CFrame.new(x, 0, 0)).Position
	local center = Vector3.new(spot.X, drop.Position.Y + drop.Size.Y / 2 + sz.Y / 2, spot.Z)
	c:PivotTo(CFrame.new(center + off) * drop.CFrame.Rotation)
	c.Parent = drop.Parent
	task.delay(H.ContainerLife, function()
		if c.Parent then c:Destroy() end
		drop:SetAttribute("Used", math.max(0, (drop:GetAttribute("Used") or 1) - 1))
	end)
end

local function spawnHeli(route, team)
	local m, parts = buildHeli(team)
	local top = padTop(route.pad)
	local yawToBase = 0
	local bpad = baseHelipad(team)
	if bpad then
		local d = flat(bpad.Position - top)
		yawToBase = math.atan2(-d.X, -d.Z)
	end
	local h = {
		route = route, team = team, model = m, parts = parts, health = H.Health,
		pos = top + Vector3.new(0, GEAR, 0), yaw = yawToBase, pitch = 0, rotor = 0, rotorSpeed = 0,
		phase = "Load", t = 0,
	}
	h.container = makeContainer()
	h.container.Parent = m
	m.Parent = folder
	place(h)
	route.heli = h
	CaptureService.setExtraStatus(route.def.Id, "Helicopter loading…")
	return h
end

local function removeHeli(route)
	local h = route.heli
	route.heli = nil
	if h and h.model.Parent then h.model:Destroy() end
end

-- сбит: падает с вращением и взрывается у воды / земли
local function shootDown(h, killer)
	if h.dead then return end
	h.dead = true
	h.model:SetAttribute("IsCargo", false)
	h.model:SetAttribute("State", "Destroyed")
	local route = h.route
	if isPlayer(killer) and TeamService.getTeamName(killer) ~= h.team then
		if H.KillReward > 0 then
			DataService.addGold(killer, H.KillReward)
			Notifier.send(killer, ("Enemy cargo helicopter shot down! +%d gold"):format(H.KillReward), "success")
		end
		require(Services.RankService).award(killer, "CargoKill")
	end
	Notifier.team(h.team, ("Cargo helicopter from %s was shot down, cargo lost"):format(route.def.Name), "error")
	route.heli = nil
	route.nextAt = os.clock() + H.RespawnDelay
	CaptureService.setExtraStatus(route.def.Id, "Helicopter lost")
	local smoke = Instance.new("Fire")
	smoke.Size = 12
	smoke.Color = Color3.fromRGB(255, 120, 40)
	smoke.SecondaryColor = Color3.fromRGB(40, 40, 40)
	smoke.Parent = h.model:FindFirstChild("Engine") or h.model.PrimaryPart
	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Exclude
	ground.FilterDescendantsInstances = {folder}
	ground.IgnoreWater = false
	task.spawn(function()
		local vy = 0
		while h.model.Parent do
			local dt = RunService.Heartbeat:Wait()
			vy = math.max(vy - 60 * dt, -90)
			h.pos += Vector3.new(0, vy * dt, 0) + flat(h.vel or Vector3.zero) * dt * 0.5
			h.yaw += dt * 4
			h.roll = math.min((h.roll or 0) + dt * 0.4, 0.6)
			h.rotor += dt * 10
			h.vel = Vector3.new(0, vy, 0)
			place(h)
			local hit = workspace:Raycast(h.pos, Vector3.new(0, -GEAR - 2, 0), ground)
			if hit or h.pos.Y < 1 then break end
		end
		local e = Instance.new("Explosion")
		e.BlastPressure = 0
		e.DestroyJointRadiusPercent = 0
		e.BlastRadius = 18
		e.Position = h.pos
		e.Parent = workspace
		if h.container then h.container:Destroy() end
		h.model:Destroy()
	end)
end

function HeliService.damage(model, amount, attacker)
	for _, route in pairs(routes) do
		local h = route.heli
		if h and h.model == model and not h.dead then
			local at = attacker and TeamService.getTeamName(attacker)
			if at and at == h.team and not Config.Combat.FriendlyFire then return true end
			h.health = math.max(0, h.health - amount)
			model:SetAttribute("Health", math.floor(h.health))
			if h.health <= 0 then shootDown(h, attacker) end
			return true
		end
	end
	return false
end

-- шаг полёта к точке: вверх до Altitude, по прямой, вниз на площадку. true — прибыл
local function flyTo(h, top, dt)
	local alt = H.Altitude
	local target = top + Vector3.new(0, GEAR, 0)
	local d = flat(target - h.pos)
	local dist = d.Magnitude
	if dist > 3 then
		if h.pos.Y < alt - 1 and dist > 40 then
			-- набор высоты (над площадкой — вертикально)
			h.vel = Vector3.new(0, H.Climb, 0)
			h.pos += h.vel * dt
			h.pitch += (0 - h.pitch) * math.min(1, dt * 3)
			return false
		end
		-- курс на цель
		local want = math.atan2(-d.X, -d.Z)
		local diff = (want - h.yaw + math.pi) % (2 * math.pi) - math.pi
		local maxTurn = math.rad(H.TurnRate) * dt
		h.yaw += math.clamp(diff, -maxTurn, maxTurn)
		local speed = math.min(H.Speed, dist * 0.8 + 6)
		local step = math.min(dist, speed * dt)
		local dy = (math.max(alt, target.Y) - h.pos.Y)
		h.vel = d.Unit * speed + Vector3.new(0, math.clamp(dy, -H.Descend, H.Climb), 0)
		h.pos += d.Unit * step + Vector3.new(0, math.clamp(dy, -H.Descend, H.Climb) * dt, 0)
		h.pitch += (math.rad(-10) * (speed / H.Speed) - h.pitch) * math.min(1, dt * 2)
		return false
	end
	-- над площадкой: снижение
	h.pos = Vector3.new(target.X, h.pos.Y, target.Z)
	h.pitch += (0 - h.pitch) * math.min(1, dt * 3)
	if h.pos.Y > target.Y + 0.05 then
		local v = h.pos.Y - target.Y > 20 and H.Descend or math.max(3, (h.pos.Y - target.Y) * 0.8)
		h.vel = Vector3.new(0, -v, 0)
		h.pos = Vector3.new(h.pos.X, math.max(target.Y, h.pos.Y - v * dt), h.pos.Z)
		return false
	end
	h.vel = Vector3.zero
	return true
end

local function step(route, dt)
	local def = route.def
	local owner = CaptureService.getOwner(def.Id)
	local h = route.heli
	if h and h.dead then return end
	if not Config.Teams[owner] then
		-- нейтральная платформа: вертолёта нет (улетевший — улетает)
		if h and h.phase ~= "Leave" then h.phase = "Leave" end
	elseif h and h.team ~= owner and h.phase ~= "Leave" then
		h.phase = "Leave"
		Notifier.team(h.team, ("%s lost — the helicopter is returning without cargo"):format(def.Name), "error")
	end
	if not h then
		if Config.Teams[owner] and os.clock() >= (route.nextAt or 0) and baseHelipad(owner) then
			spawnHeli(route, owner)
		end
		return
	end
	-- винт: раскручивается в полёте, на земле при погрузке еле вращается
	local spinTarget = (h.phase == "Load" or h.phase == "Unload") and 4 or 22
	h.rotorSpeed += (spinTarget - h.rotorSpeed) * math.min(1, dt * 1.5)
	h.rotor = (h.rotor + h.rotorSpeed * dt) % (2 * math.pi)
	local rigTop = padTop(route.pad)
	if h.phase == "Load" then
		h.t += dt
		h.vel = Vector3.zero
		if h.t >= H.LoadTime then
			h.phase, h.t = "ToBase", 0
			CaptureService.setExtraStatus(def.Id, "Helicopter en route to base")
		end
	elseif h.phase == "ToBase" then
		local bpad, drop = baseHelipad(h.team)
		if not bpad then h.phase = "Leave" return end
		if flyTo(h, padTop(bpad), dt) then
			h.phase, h.t = "Unload", 0
			dropContainer(h, drop)
			payout(route, h.team)
		end
	elseif h.phase == "Unload" then
		h.t += dt
		if h.t >= H.UnloadTime then
			h.phase = "ToRig"
			CaptureService.setExtraStatus(def.Id, "Helicopter returning")
		end
	elseif h.phase == "ToRig" then
		if flyTo(h, rigTop, dt) then
			h.phase, h.t = "Load", 0
			h.container = makeContainer()
			h.container.Parent = h.model
			CaptureService.setExtraStatus(def.Id, "Helicopter loading…")
		end
	elseif h.phase == "Leave" then
		if flyTo(h, rigTop, dt) then
			removeHeli(route)
			route.nextAt = os.clock() + 5
			CaptureService.setExtraStatus(def.Id, "")
		end
	end
	if route.heli == h then place(h) end
end

-- лестницы платформ: кнопка у воды — подъём на палубу (ClimbOffset — от площадки к палубе)
local function hookLadders(rig)
	for _, plat in ipairs(rig:GetChildren()) do
		local pr = plat.Name == "LadderPlatform" and plat:FindFirstChild("BoardPrompt")
		local offset = plat:GetAttribute("ClimbOffset")
		if pr and offset then
			pr.Triggered:Connect(function(player)
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hum or hum.Health <= 0 or not hrp or hum.SeatPart then return end
				if (hrp.Position - plat.Position).Magnitude > 18 then return end
				AntiCheat.grace(player)
				char:PivotTo(plat.CFrame * CFrame.new(offset))
			end)
		end
	end
end

function HeliService.init()
	folder = Instance.new("Folder")
	folder.Name = "Helis"
	folder.Parent = workspace.Map
	for _, def in ipairs(Config.Islands) do
		if def.IsRig then
			local rig = workspace.Map.Neutral:FindFirstChild(def.Outpost)
			local pad = rig and rig:FindFirstChild("HeliPad", true)
			if pad then
				routes[def.Id] = {def = def, pad = pad, nextAt = 0}
				hookLadders(rig)
			else
				warn("[HeliService] no helipad at " .. def.Outpost)
			end
		end
	end
	-- урон по вертолётам — через тот же вызов, что и по грузовым судам
	local prev = CombatService.onCargoHit
	CombatService.onCargoHit = function(model, amount, attacker)
		if HeliService.damage(model, amount, attacker) then return end
		if prev then prev(model, amount, attacker) end
	end
	RunService.Heartbeat:Connect(function(dt)
		for _, route in pairs(routes) do
			local ok, err = pcall(step, route, dt)
			if not ok then warn("[HeliService] " .. tostring(err)) end
		end
	end)
end

-- только для тестов в Studio: сразу отправить вертолёт платформы id на базу
function HeliService.devDepart(id)
	local route = routes[id]
	local h = route and route.heli
	if h and h.phase == "Load" then h.t = H.LoadTime end
	return h ~= nil
end

return HeliService
