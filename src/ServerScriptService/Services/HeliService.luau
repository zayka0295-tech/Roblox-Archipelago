-- Грузовые вертолёты нефтяных платформ (Config.Helis): тяжёлый двухвинтовой транспортник с контейнером на тросах.
-- Пока платформа (Config.Islands с IsRig) у команды, вертолёт зависает над её вертолётной площадкой (HeliPad),
-- подхватывает контейнер, летит на базу (Decor.Helipad) и прямо в воздухе, не садясь, сбрасывает его
-- в зону выгрузки (ContainerDrop) и сразу улетает за новым; выплата — когда контейнер упадёт на землю.
-- Быстрее грузовых судов, но его можно сбить: модель помечена IsCargo, урон — через CombatService.onCargoHit.
-- Платформа сменила владельца — рейс отменяется: вертолёт улетает к платформе и исчезает; у нового владельца
-- вертолёт появится через RespawnDelay. Модель двигает сервер (детали закреплены), скорость для проверки
-- попаданий выставляется деталям вручную. Контейнер висит отвесно и раскачивается от разгона.
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
local HOOK = Vector3.new(0, -4.8, 2) -- крюк под брюхом (в осях вертолёта)
local CABLE = 16                       -- длина тросов
local CONT_H = 7.4                     -- высота контейнера
local HANG = -HOOK.Y + CABLE + CONT_H  -- от корня вертолёта до низа контейнера: на этой высоте он зависает над площадкой
local DROP_SLOTS = {-14, 0, 14}        -- места в зоне выгрузки базы (вдоль её оси X)

local function isPlayer(x) return typeof(x) == "Instance" and x:IsA("Player") end

------------------------------------------------------------------ модель
-- все детали в осях корня: вперёд = −Z, вверх = +Y. Возвращает модель и список {деталь, смещение, винт?}
local function buildHeli(team)
	local m = Instance.new("Model")
	m.Name = "CargoHeli_" .. team
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local rgb = Color3.fromRGB
	local body = team == "Blue" and rgb(84, 92, 70) or rgb(150, 132, 98)
	local patch = body:Lerp(rgb(0, 0, 0), 0.25)
	local dark = rgb(36, 38, 40)
	local stripe = Config.Teams[team].Color
	local cyl = Enum.PartType.Cylinder
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
	-- фюзеляж
	add("Body", CFrame.new(0, 0, 1), Vector3.new(10, 9, 30), body)
	add("BodyTop", CFrame.new(0, 4.9, 1), Vector3.new(8, 0.8, 30), body)
	add("Patch", CFrame.new(0, -1.5, -4), Vector3.new(10.06, 4, 8), patch)
	add("Patch", CFrame.new(0, 1.8, 8), Vector3.new(10.06, 3.2, 7), patch)
	add("Stripe", CFrame.new(0, -3.2, 1), Vector3.new(10.08, 1.2, 30.08), stripe, Enum.Material.SmoothPlastic)
	add("Nose", CFrame.new(0, -0.8, -16), Vector3.new(9.2, 7, 4), body)
	add("NoseTip", CFrame.new(0, -1.6, -18.6), Vector3.new(8, 4.6, 1.6), body)
	add("Cockpit", CFrame.new(0, 2.2, -17.2) * CFrame.Angles(math.rad(-35), 0, 0), Vector3.new(8.6, 3.4, 2.6), rgb(55, 95, 130), Enum.Material.Glass, {Transparency = 0.2})
	add("Ramp", CFrame.new(0, 1.2, 18.4) * CFrame.Angles(math.rad(18), 0, 0), Vector3.new(9.6, 6.4, 4), body)
	for _, s in ipairs({-1, 1}) do
		-- окна по бортам
		for z = -10, 10, 4 do
			add("Window", CFrame.new(s * 5.02, 1.6, z), Vector3.new(0.1, 1.4, 1.4), rgb(40, 60, 80), Enum.Material.Glass)
		end
		-- подвесные баки вдоль бортов
		add("Sponson", CFrame.new(s * 6.2, -2.6, 1), Vector3.new(2.6, 3.2, 18), body)
		add("SponsonCap", CFrame.new(s * 6.2, -2.6, -8.6) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(2.6, 3.2, 3.2), body, nil, {Shape = cyl})
	end
	-- пилоны винтов: задний выше (как у тандемных вертолётов)
	add("FrontPylon", CFrame.new(0, 6, -13), Vector3.new(3.6, 2.6, 6), body)
	add("RearPylon", CFrame.new(0, 7.4, 13.5), Vector3.new(5, 5.6, 9), body)
	for _, s in ipairs({-1, 1}) do
		add("Engine", CFrame.new(s * 4.4, 6.4, 11) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(8, 2.8, 2.8), patch, nil, {Shape = cyl})
		add("Exhaust", CFrame.new(s * 4.4, 6.4, 15.2) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.6, 2, 2), dark, nil, {Shape = cyl})
	end
	add("FrontHub", CFrame.new(0, 7.8, -13) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(1.4, 1.8, 1.8), dark, nil, {Shape = cyl})
	add("RearHub", CFrame.new(0, 10.8, 14) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(1.4, 1.8, 1.8), dark, nil, {Shape = cyl})
	-- два несущих винта по три лопасти, вращаются навстречу друг другу
	for i = 0, 2 do
		add("Blade", CFrame.new(0, 8.4, -13), Vector3.new(22, 0.3, 1.8), dark, Enum.Material.SmoothPlastic, {CanCollide = false}, {angle = i * 120, dir = 1, radial = 11})
		add("Blade", CFrame.new(0, 11.4, 14), Vector3.new(22, 0.3, 1.8), dark, Enum.Material.SmoothPlastic, {CanCollide = false}, {angle = i * 120 + 60, dir = -1, radial = 11})
	end
	-- шасси: четыре колеса
	for _, w in ipairs({{-3, -10}, {3, -10}, {-5.6, 10}, {5.6, 10}}) do
		add("Strut", CFrame.new(w[1], -5, w[2]), Vector3.new(0.5, 2.4, 0.5), dark)
		add("Wheel", CFrame.new(w[1], -6.2, w[2]), Vector3.new(1, 2, 2), rgb(25, 25, 25), Enum.Material.Rubber, {Shape = cyl})
	end
	add("Hook", CFrame.new(HOOK), Vector3.new(1, 1, 1), dark)
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

-- контейнер (копия модели игры) и четыре троса к крюку
local function makeContainer(h)
	local c = ServerStorage.Ships.CargoContainer:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true d.CanTouch = false end
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end
	end
	local cf, sz = c:GetBoundingBox()
	h.contOff = c:GetPivot().Position - cf.Position -- опорная точка не в центре рамки
	h.contSize = sz
	c.Parent = h.model
	h.container = c
	h.cables = {}
	for i = 1, 4 do
		local p = Instance.new("Part")
		p.Name = "Cable"
		p.Anchored = true
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.Size = Vector3.new(0.18, 0.18, CABLE)
		p.Color = Color3.fromRGB(30, 30, 30)
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = h.model
		h.cables[i] = p
	end
	h.sway = Vector3.zero
	h.placeDirty = true -- новый контейнер и тросы нужно поставить под крюк
end
local function removeCables(h)
	for _, p in ipairs(h.cables or {}) do p:Destroy() end
	h.cables = nil
end

------------------------------------------------------------------ полёт
local function padTop(pad)
	return pad.Position + Vector3.new(0, pad.Size.X / 2, 0) -- диск: цилиндр лежит осью X вверх
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- поставить модель: корень в pos, курс yaw, наклон pitch; винты крутятся. Контейнер висит отвесно под крюком
-- и отстаёт при разгоне (sway)
local function place(h, dt)
	local cf = CFrame.new(h.pos) * CFrame.Angles(0, h.yaw, 0) * CFrame.Angles(h.pitch, 0, h.roll or 0)
	local vel = h.vel or Vector3.zero
	local hasCont = h.container and h.container.Parent == h.model
	local want
	if hasCont then
		-- раскачка: груз отстаёт от разгона и плавно возвращается под крюк
		want = -Vector3.new(vel.X, 0, vel.Z) * 0.06
		if want.Magnitude > 5 then want = want.Unit * 5 end
		h.sway += (want - h.sway) * math.min(1, dt * 1.2)
		if want == Vector3.zero and h.sway.Magnitude < 0.01 then h.sway = Vector3.zero end
	end
	-- висит на месте (погрузка): корпус, контейнер и тросы не двигаются — по сети шлём только винты
	local still = h.lastCF == cf and not h.placeDirty and vel == h.appliedVel and (not hasCont or h.sway == Vector3.zero)
	h.lastCF, h.placeDirty = cf, false
	local list, cfs = {}, {}
	for _, p in ipairs(h.parts) do
		if p.spin or not still then
			local off = p.offset
			if p.spin then
				off = off * CFrame.Angles(0, (h.rotor + math.rad(p.spin.angle)) * p.spin.dir, 0) * CFrame.new(p.spin.radial, 0, 0)
			end
			table.insert(list, p.part)
			table.insert(cfs, cf * off)
		end
	end
	if hasCont and not still then
		local hook = (cf * CFrame.new(HOOK)).Position
		local ccf = CFrame.new(hook + h.sway - Vector3.new(0, CABLE + CONT_H / 2, 0)) * CFrame.Angles(0, h.yaw, 0)
		h.container:PivotTo(ccf + h.contOff)
		local sx, sz = h.contSize.X / 2 - 0.4, h.contSize.Z / 2 - 0.6
		for i, c in ipairs(h.cables or {}) do
			local corner = (ccf * CFrame.new((i <= 2 and -1 or 1) * sx, CONT_H / 2, (i % 2 == 0 and -1 or 1) * sz)).Position
			c.Size = Vector3.new(0.18, 0.18, (corner - hook).Magnitude)
			table.insert(list, c)
			table.insert(cfs, CFrame.lookAt((hook + corner) / 2, corner))
		end
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- скорость деталей (для упреждения попаданий) — только когда она изменилась
	if not still then
		for _, p in ipairs(list) do p.AssemblyLinearVelocity = vel end
		h.appliedVel = vel
	end
end

-- площадки базы: Decor.Helipad.Pad1..Pad4 (сетка 2×2, у каждой PadBase + диск HeliPad), зона выгрузки ContainerDrop
local function basePads(helipad)
	local pads = {}
	for i = 1, 16 do
		local m = helipad:FindFirstChild("Pad" .. i)
		if not m then break end
		table.insert(pads, m)
	end
	return pads
end

local function baseHelipad(team)
	local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
	local helipad = base and base.Decor:FindFirstChild("Helipad")
	if not helipad then return nil, nil end
	local first = basePads(helipad)[1]
	return first and first:FindFirstChild("HeliPad"), helipad:FindFirstChild("ContainerDrop")
end

-- выплата за доставленный контейнер — как у грузовых судов
local epoch = 0 -- номер раунда для выплат: контейнер, сброшенный в прошлом раунде, не платит в новом

local function payout(route, team, ep)
	if ep and ep ~= epoch then return end
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

-- место выгрузки на базе: очередное из DROP_SLOTS (верх зоны выгрузки), курс — вдоль её оси Z
local function dropSpot(drop)
	local used = drop:GetAttribute("Used") or 0
	local x = DROP_SLOTS[used % #DROP_SLOTS + 1]
	local p = (drop.CFrame * CFrame.new(x, drop.Size.Y / 2, 0)).Position
	local look = drop.CFrame.LookVector
	return p, math.atan2(-look.X, -look.Z)
end

-- сброс в воздухе: тросы отцепляются, контейнер падает на spot и в падении доворачивает к курсу landYaw
-- (onLanded — когда коснулся земли), затем стоит у площадки ContainerLife сек.
local function dropContainer(h, drop, spot, landYaw, onLanded)
	local c = h.container
	h.container = nil
	removeCables(h)
	if not c then return end
	if not drop then c:Destroy() return end
	drop:SetAttribute("Used", (drop:GetAttribute("Used") or 0) + 1)
	c.Parent = drop.Parent
	local off, yaw = h.contOff, h.yaw
	local pos = c:GetPivot().Position - off -- центр контейнера
	local vel = flat(h.vel or Vector3.zero) * 0.3
	task.spawn(function()
		local floor = spot.Y + CONT_H / 2
		local vy = 0
		while c.Parent and pos.Y > floor do
			local dt = RunService.Heartbeat:Wait()
			vy -= 120 * dt
			yaw += ((landYaw - yaw + math.pi) % (2 * math.pi) - math.pi) * math.min(1, dt * 2)
			-- сносит к месту выгрузки, чтобы контейнер лёг ровно в зону
			local toSpot = flat(spot - pos)
			vel += (toSpot * 2 - vel) * math.min(1, dt * 3)
			pos = Vector3.new(pos.X + vel.X * dt, math.max(floor, pos.Y + vy * dt), pos.Z + vel.Z * dt)
			c:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0) + off)
		end
		if not c.Parent then return end
		c:PivotTo(CFrame.new(Vector3.new(spot.X, floor, spot.Z)) * CFrame.Angles(0, landYaw, 0) + off)
		if onLanded then onLanded() end
		task.wait(H.ContainerLife)
		if c.Parent then c:Destroy() end
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
		pos = top + Vector3.new(0, HANG, 0), yaw = yawToBase, pitch = 0, rotor = 0, rotorSpeed = 0,
		phase = "Load", t = 0,
	}
	makeContainer(h)
	m.Parent = folder
	place(h, 0)
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
	smoke.Size = 14
	smoke.Color = Color3.fromRGB(255, 120, 40)
	smoke.SecondaryColor = Color3.fromRGB(40, 40, 40)
	smoke.Parent = h.model:FindFirstChild("RearPylon") or h.model.PrimaryPart
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
			h.yaw += dt * 3
			h.roll = math.min((h.roll or 0) + dt * 0.4, 0.6)
			h.rotor += dt * 8
			h.vel = Vector3.new(0, vy, 0)
			place(h, dt)
			local hit = workspace:Raycast(h.pos, Vector3.new(0, -(h.container and HANG or 7) - 2, 0), ground)
			if hit or h.pos.Y < 1 then break end
		end
		local e = Instance.new("Explosion")
		e.BlastPressure = 0
		e.DestroyJointRadiusPercent = 0
		e.BlastRadius = 24
		e.Position = h.pos
		e.Parent = workspace
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

-- шаг полёта к точке spot (верх площадки): вверх до Altitude, по прямой, зависание и снижение до высоты
-- подвеса HANG (низ контейнера — на spot) плюс extra. finalYaw — курс над точкой. true — на месте.
-- pass — пролёт без остановки (сброс груза): true, как только вертолёт над точкой
local function flyTo(h, spot, dt, finalYaw, extra, pass)
	local alt = H.Altitude
	local target = spot + Vector3.new(0, HANG + (extra or 0), 0)
	local d = flat(target - h.pos)
	local dist = d.Magnitude
	local maxTurn = math.rad(H.TurnRate) * dt
	if pass and dist < 10 then return true end
	if dist > 2 then
		if h.pos.Y < alt - 1 and dist > 60 then
			-- набор высоты (над площадкой — вертикально)
			h.vel = Vector3.new(0, H.Climb, 0)
			h.pos += h.vel * dt
			h.pitch += (0 - h.pitch) * math.min(1, dt * 3)
			return false
		end
		-- курс на цель (у самой цели — на курс посадки)
		local want = (finalYaw and dist < 30) and finalYaw or math.atan2(-d.X, -d.Z)
		local diff = (want - h.yaw + math.pi) % (2 * math.pi) - math.pi
		h.yaw += math.clamp(diff, -maxTurn, maxTurn)
		local speed = pass and H.Speed or math.min(H.Speed, dist * 0.6 + 4)
		local step = math.min(dist, speed * dt)
		local dy = math.clamp(math.max(alt, target.Y) - h.pos.Y, -H.Descend, H.Climb)
		h.vel = d.Unit * speed + Vector3.new(0, dy, 0)
		h.pos += d.Unit * step + Vector3.new(0, dy * dt, 0)
		h.pitch += (math.rad(-8) * (speed / H.Speed) - h.pitch) * math.min(1, dt * 2)
		return false
	end
	-- над точкой: доворот и снижение
	h.pos = Vector3.new(target.X, h.pos.Y, target.Z)
	h.pitch += (0 - h.pitch) * math.min(1, dt * 3)
	if finalYaw then
		local diff = (finalYaw - h.yaw + math.pi) % (2 * math.pi) - math.pi
		h.yaw += math.clamp(diff, -maxTurn, maxTurn)
	end
	if h.pos.Y > target.Y + 0.05 then
		local v = h.pos.Y - target.Y > 25 and H.Descend or math.max(2.5, (h.pos.Y - target.Y) * 0.7)
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
			-- если постройка упадёт (нет модели контейнера и т.п.) — повтор через 5 с, а не каждый кадр
			route.nextAt = os.clock() + 5
			spawnHeli(route, owner)
		end
		return
	end
	-- винты: в полёте быстро, при погрузке медленнее
	local spinTarget = h.phase == "Load" and 9 or 20
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
		local spot, yaw
		if drop then spot, yaw = dropSpot(drop) else spot = padTop(bpad) end
		-- над зоной выгрузки: сброс на ходу, с высоты перелёта, и сразу обратно
		if flyTo(h, spot, dt, nil, H.Altitude - spot.Y - HANG, true) then
			local team, ep = h.team, epoch
			dropContainer(h, drop, spot, yaw, function() payout(route, team, ep) end)
			h.phase = "ToRig"
			CaptureService.setExtraStatus(def.Id, "Helicopter returning")
		end
	elseif h.phase == "ToRig" then
		-- зависает над площадкой платформы и подхватывает новый контейнер
		if flyTo(h, rigTop, dt) then
			makeContainer(h)
			h.phase, h.t = "Load", 0
			CaptureService.setExtraStatus(def.Id, "Helicopter loading…")
		end
	elseif h.phase == "Leave" then
		if flyTo(h, rigTop, dt) then
			removeHeli(route)
			route.nextAt = os.clock() + 5
			CaptureService.setExtraStatus(def.Id, "")
		end
	end
	if route.heli == h then place(h, dt) end
end

-- лестницы платформ: кнопка у воды — подъём на палубу (ClimbOffset — от площадки к палубе)
local function hookLadders(rig)
	for _, plat in ipairs(rig:GetChildren()) do
		local pr = plat.Name == "LadderPlatform" and plat:FindFirstChild("BoardPrompt")
		local offset = plat:GetAttribute("ClimbOffset")
		if pr and offset then
			AntiCheat.ladder(pr, plat, 18, function() return plat.CFrame * CFrame.new(offset), plat end)
		end
	end
end

-- новый раунд: вертолёты с грузом убираем, выплаты за уже сброшенные контейнеры отменяем
function HeliService.resetAll()
	epoch += 1
	for _, route in pairs(routes) do
		removeHeli(route)
		route.nextAt = 0
		CaptureService.setExtraStatus(route.def.Id, "")
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
	-- площадки базы (PadN) свободны: на них садятся вертолёты игроков
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
