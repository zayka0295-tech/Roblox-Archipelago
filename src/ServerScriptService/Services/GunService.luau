-- Ручное оружие пехоты: автоматы (луч от головы к точке прицела) и РПГ (ракета по баллистике).
-- Клиент (GunClient) только целится и просит выстрел (Fire) и перезарядку (GunReload);
-- патроны, темп и урон считает сервер. Патроны — атрибуты инструмента Ammo / Reserve / Reloading.
-- РПГ покупается на оружейном стенде своей базы (деталь с тегом WeaponRack и подсказкой BuyPrompt).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local CombatService = require(Services.CombatService)
local ProjectileService = require(Services.ProjectileService)
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local Notifier = require(Services.Notifier)
local Homing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Homing"))

local GunService = {}
local lastShot = {}
local safeWarned = {} -- когда последний раз предупреждали о безопасной зоне
local HitMarker

local function gunOf(tool)
	return tool and Config.Guns[tool:GetAttribute("Gun") or tool.Name]
end

-- с оружием в руках всегда первое лицо (GunClient), и персонаж повёрнут туда же, куда камера.
-- Выстрел вбок или назад от того, куда он смотрит, — чит («стрельба на 360°»). Запас на касание края
-- экрана на телефоне и на то, что поворот тела доходит до сервера с небольшой задержкой.
local MAX_YAW = math.cos(math.rad(80))
-- попадание, которое засчитывает клиент (hitPart), — строже: иначе «silent aim» бьёт любого в секторе 160°
local CLIENT_HIT_YAW = math.cos(math.rad(45))
local function facing(hrp, aim, limit)
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 3 then return true end -- стрельба почти отвесно или вупор
	local lv = hrp.CFrame.LookVector
	local fl = Vector3.new(lv.X, 0, lv.Z)
	if fl.Magnitude < 0.01 then return true end
	return fl.Unit:Dot(flat.Unit) >= (limit or MAX_YAW)
end

-- выдать оружие игроку (в рюкзак), с полным магазином
function GunService.give(player, key)
	local gun = Config.Guns[key]
	local weapons = ServerStorage:FindFirstChild("Weapons")
	local template = gun and weapons and weapons:FindFirstChild(key)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not gun or not template or not backpack then return nil end
	local tool = template:Clone()
	tool:SetAttribute("Gun", key)
	tool:SetAttribute("Ammo", gun.Mag)
	tool:SetAttribute("Reloading", false)
	if gun.Reserve then tool:SetAttribute("Reserve", gun.Reserve) end
	tool.Parent = backpack
	return tool
end

local function hasGun(player, key)
	for _, holder in ipairs({player.Character, player:FindFirstChildOfClass("Backpack")}) do
		if holder then
			for _, t in ipairs(holder:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("Gun") == key then return true end
			end
		end
	end
	return false
end

------------------------------------------------------------------ C4
-- Заряд бросают (по дуге, сервер считает полёт) — прилипает к тому, во что попал: к движущейся детали сваркой
-- (едет с кораблём), к неподвижной — закреплён; в воде тонет. Одновременно (в полёте и прилипших) не больше
-- MaxActive; подрыв всех — Remotes.GunAlt (F / BOOM). Погиб — заряды обезврежены (пропадают).
local charges = {} -- [игрок] = {char, list}
local chargeParams = RaycastParams.new()
chargeParams.FilterType = Enum.RaycastFilterType.Exclude
chargeParams.CollisionGroup = "Weapons"

local function clearCharges(player)
	local c = charges[player]
	charges[player] = nil
	if player.Parent then player:SetAttribute("C4Placed", 0) end
	for _, p in ipairs(c and c.list or {}) do
		if p.Parent then p:Destroy() end
	end
end

local THROW_SPEED, THROW_UP, THROW_G = 75, 16, 110 -- бросок: ~45 студов по ровному
local thrown = {} -- заряды в полёте: {p, pos, vel, player, c, char, t}

local function newCharge(cf)
	local p = Instance.new("Part")
	p.Name = "C4Charge"
	p.Size = Vector3.new(1.1, 0.42, 0.75)
	p.Color = Color3.fromRGB(204, 180, 124)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.CFrame = cf
	local led = Instance.new("Part")
	led.Name = "Led"
	led.Shape = Enum.PartType.Ball
	led.Size = Vector3.new(0.2, 0.2, 0.2)
	led.Material = Enum.Material.Neon
	led.Color = Color3.fromRGB(255, 40, 40)
	led.CanCollide, led.CanQuery, led.CanTouch, led.CastShadow, led.Massless = false, false, false, false, true
	led.CFrame = cf * CFrame.new(0.3, 0.25, 0)
	led.Parent = p
	local lw = Instance.new("WeldConstraint")
	lw.Part0, lw.Part1 = p, led
	lw.Parent = led
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 40, 40), 5, 1
	light.Parent = led
	p.Parent = workspace:FindFirstChild("Effects") or workspace
	return p
end

-- заряд долетел: прилипает к поверхности res
local function stick(e, res)
	local n = res.Normal
	local right = n:Cross(math.abs(n.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis).Unit
	local p = e.p
	p.CFrame = CFrame.fromMatrix(res.Position + n * 0.22, right, n)
	local target = res.Instance
	if target:IsA("BasePart") and not target.Anchored then
		p.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = target, p
		w.Parent = p
	end
	table.insert(e.c.list, p)
	e.player:SetAttribute("C4Placed", #e.c.list)
end

local function throwCharge(player, char, head, aim, gun, tool)
	local c = charges[player]
	if c and c.char ~= char then
		clearCharges(player)
		c = nil
	end
	if c and #c.list + c.flying >= (gun.MaxActive or 3) then
		Notifier.send(player, ("%d charges out — press F (BOOM) to detonate"):format(#c.list + c.flying), "error")
		return false
	end
	if not c then
		c = {char = char, list = {}, flying = 0}
		charges[player] = c
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Once(function()
				if charges[player] == c then clearCharges(player) end
			end)
		end
	end
	local dir = aim.Unit
	local start = head.Position + dir * 1.5
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local inherit = hrp and hrp.AssemblyLinearVelocity * 0.5 or Vector3.zero
	c.flying += 1
	table.insert(thrown, {p = newCharge(CFrame.lookAt(start, start + dir)), pos = start, vel = dir * THROW_SPEED + Vector3.new(0, THROW_UP, 0) + inherit,
		player = player, c = c, char = char, t = 0})
	return true
end

game:GetService("RunService").Heartbeat:Connect(function(dt)
	local fx = workspace:FindFirstChild("Effects")
	for i = #thrown, 1, -1 do
		local e = thrown[i]
		e.t += dt
		local nv = e.vel + Vector3.new(0, -THROW_G * dt, 0)
		local np = e.pos + (e.vel + nv) * 0.5 * dt
		local done, keep = false, false
		if charges[e.player] ~= e.c or not e.p.Parent then
			done = true -- взорвали / погиб, пока летел
		else
			chargeParams.FilterDescendantsInstances = fx and {e.char, fx} or {e.char}
			local res = workspace:Raycast(e.pos, np - e.pos, chargeParams)
			local kind = res and CombatService.resolveHit(res.Instance)
			if res and kind ~= "player" and kind ~= "bot" then
				stick(e, res)
				done, keep = true, true
			elseif np.Y < -2 or e.t > 5 then
				done = true -- утонул / улетел
			else
				e.pos, e.vel = np, nv
				e.p.CFrame = CFrame.lookAt(np, np + nv) * CFrame.Angles(e.t * 9, 0, 0)
			end
		end
		if done then
			table.remove(thrown, i)
			if e.c then e.c.flying = math.max(0, e.c.flying - 1) end
			if not keep and e.p.Parent then e.p:Destroy() end
		end
	end
end)

-- захват цели управляемой ракетой: клиент сообщает, на ком начал захват (или nil — цель потеряна)
local locks = {} -- [игрок] = {model, t}
local function onLock(player, model)
	if model == nil then
		locks[player] = nil
	elseif typeof(model) == "Instance" and model:IsA("Model") then
		local cur = locks[player]
		if not cur or cur.model ~= model then locks[player] = {model = model, t = os.clock()} end
	end
end

local lastAlt = {}
local function detonate(player)
	local t = os.clock()
	if lastAlt[player] and t - lastAlt[player] < 0.5 then return end
	lastAlt[player] = t
	local c = charges[player]
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not c or #c.list == 0 or c.char ~= char or not hum or hum.Health <= 0 then return end
	charges[player] = nil
	local gun = Config.Guns.C4
	player:SetAttribute("C4Placed", 0)
	for i, p in ipairs(c.list) do
		task.delay((i - 1) * 0.12, function()
			if not p.Parent then return end
			local pos = p.Position
			p:Destroy()
			ProjectileService.blast(pos, player, {Damage = gun.Damage, SplashRadius = gun.SplashRadius, Class = gun.Class})
		end)
	end
end

-- hitPart — деталь, в которую попал клиент (по тому, что видит игрок); сервер проверяет её (checkClientHit),
-- а если не прошла или нет — считает попадание своим лучом
local function onFire(player, target, hitPart)
	if typeof(target) ~= "Vector3" or not (target.Magnitude < 1e5) then return end -- отсекает NaN/inf
	if player:GetAttribute("State") ~= "Deployed" then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head")
	local tool = char and char:FindFirstChildOfClass("Tool")
	local gun = gunOf(tool)
	if not hum or hum.Health <= 0 or not head or not gun or hum.SeatPart then return end
	local t = os.clock()
	if lastShot[player] and t - lastShot[player] < 60 / gun.RPM * 0.8 then return end
	if tool:GetAttribute("Reloading") then return end
	local ammo = tool:GetAttribute("Ammo") or 0
	if ammo <= 0 then return end
	-- в лобби оружие выключено; на своей базе стрелять можно, но урон пройдёт только по врагам внутри зоны (CombatService)
	local zone = CombatService.zoneAt(head.Position)
	if zone == "Lobby" or zone == "Any" then
		if not safeWarned[player] or t - safeWarned[player] > 4 then
			safeWarned[player] = t
			Notifier.send(player, "You're protected here — weapons are disabled", "safe")
		end
		return
	end
	-- из своей защищённой зоны ракетами нельзя: игрока там не убить, а он бы безнаказанно обстреливал технику
	if gun.Rocket and zone ~= nil and zone == TeamService.getTeamName(player) then
		if not safeWarned[player] or t - safeWarned[player] > 4 then
			safeWarned[player] = t
			Notifier.send(player, "Rockets are disabled inside your protected base", "safe")
		end
		return
	end
	-- направление проверяем до того, как списать патрон и запустить перезарядку ствола
	local muzzle = tool:FindFirstChild("Muzzle") or tool:FindFirstChild("Handle")
	local from = head.Position
	if gun.Rocket then
		from = muzzle and muzzle.Position or head.Position
		if (from - head.Position).Magnitude > 8 then from = head.Position end
	end
	local aim = target - from
	if aim.Magnitude < (gun.Rocket and 1 or 0.5) then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and not facing(hrp, aim) then return end
	-- управляемая ракета: цель — та, на которой клиент начал захват (Remotes.GunLock), если с начала захвата прошло
	-- LockTime и она всё ещё в конусе прицела (с запасом на пинг); иначе без наведения
	local lockModel, lockPart
	if gun.Homing then
		local rec = locks[player]
		if rec and os.clock() - rec.t >= (gun.LockTime or 0) - 0.35 then
			lockPart = Homing.check(rec.model, gun.Homing, from, aim.Unit, TeamService.getTeamName(player), gun.LockRange, (gun.LockCone or 12) + 6)
			lockModel = lockPart and rec.model or nil
		end
		if gun.RequireLock and not lockModel then
			if not safeWarned[player] or t - safeWarned[player] > 2 then
				safeWarned[player] = t
				Notifier.send(player, "No target locked — keep an enemy aircraft in the sight", "error")
			end
			return
		end
	end
	if gun.Charge then
		if not throwCharge(player, char, head, aim, gun, tool) then return end
		lastShot[player] = t
		tool:SetAttribute("Ammo", ammo - 1)
		if ammo - 1 <= 0 then task.delay(0.4, function() if tool.Parent then tool:Destroy() end end) end
		return
	end
	lastShot[player] = t
	tool:SetAttribute("Ammo", ammo - 1)

	if gun.Rocket then
		local d = aim
		local W = {Damage = gun.Damage, SplashRadius = gun.SplashRadius, Gravity = gun.Gravity, Class = gun.Class}
		if gun.Homing then
			W.Speed, W.TurnRate, W.Life, W.Proximity = gun.Speed, gun.TurnRate, gun.Life, gun.Proximity
			ProjectileService.launchMissile(from, d.Unit, player, W, {char}, lockModel, lockPart, gun.Homing)
		else
			ProjectileService.launch(from, d.Unit * gun.ShellSpeed, player, W, {char})
		end
		-- граната улетела — труба пустая до перезарядки
		local wh = tool:FindFirstChild("Warhead")
		if wh then wh.Transparency = 1 end
		-- ракеты кончились — трубу выбрасываем
		if ammo - 1 <= 0 and (tool:GetAttribute("Reserve") or 0) <= 0 then
			task.delay(0.8, function() if tool.Parent then tool:Destroy() end end)
		end
		return
	end

	local origin = from
	if gun.Pellets then
		-- Дробь: клиент присылает, во что попала каждая дробина ({деталь, точка, …}). Каждую проверяем отдельно:
		-- дальность, сектор от линии прицела (разлёт с запасом), голова — только если точка у головы, не сквозь стены
		local hits = typeof(hitPart) == "table" and hitPart or {}
		local cone = math.cos(math.rad(gun.Hip * 2 + 4))
		local facingOk = not hrp or facing(hrp, aim, CLIENT_HIT_YAW)
		local marked = false
		for i = 1, math.min(#hits, gun.Pellets * 2), 2 do
			local part, pos = hits[i], hits[i + 1]
			if facingOk and typeof(part) == "Instance" and part:IsA("BasePart") and not part:IsDescendantOf(char)
				and typeof(pos) == "Vector3" and (pos - origin).Magnitude > 0.5 and aim.Unit:Dot((pos - origin).Unit) >= cone
				and (part.Name ~= "Head" or (pos - part.Position).Magnitude <= 2 + part.AssemblyLinearVelocity.Magnitude * 0.3)
				and CombatService.checkClientHit(origin, part, pos, gun.Range + 20) then
				local kind, applied = CombatService.applyHit(player, part, gun.Damage, nil, gun.Class, pos)
				if (kind == "player" or kind == "bot") and applied then marked = true end
			end
		end
		CombatService.tracer(muzzle and muzzle.Position or origin, origin + aim.Unit * math.min(aim.Magnitude, gun.Range), player.UserId, gun.Sound)
		if marked then HitMarker:FireClient(player, false) end
		return
	end
	-- попадание глазами игрока: цель на сервере уже сдвинулась на пинг, серверный луч бы промахнулся
	if typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") and not hitPart:IsDescendantOf(char)
		and (not hrp or facing(hrp, aim, CLIENT_HIT_YAW))
		and CombatService.checkClientHit(origin, hitPart, target, gun.Range + 20) then
		local ok = true
		if hitPart.Name == "Head" then
			-- голова (×1,5 урона) — только если точка действительно у головы, а не где-то на теле
			ok = (target - hitPart.Position).Magnitude <= 2 + hitPart.AssemblyLinearVelocity.Magnitude * 0.3
		end
		if ok then
			CombatService.tracer(muzzle and muzzle.Position or origin, target, player.UserId, gun.Sound)
			-- маркер — только если урон прошёл (не по своим, не по защищённым в безопасной зоне)
			local kind, applied = CombatService.applyHit(player, hitPart, gun.Damage, nil, gun.Class, target)
			if (kind == "player" or kind == "bot") and applied then
				HitMarker:FireClient(player, hitPart.Name == "Head")
			end
			return
		end
	end
	local dir = aim.Unit * gun.Range
	local params = RaycastParams.new()
	params.CollisionGroup = "Weapons" -- оружие видит и грузовые суда
	params.FilterType = Enum.RaycastFilterType.Exclude
	local fx = workspace:FindFirstChild("Effects")
	params.FilterDescendantsInstances = fx and {char, fx} or {char}
	local res = workspace:Raycast(origin, dir, params)
	-- свой трассер стрелок рисует сам (без задержки), остальным — с сервера
	CombatService.tracer(muzzle and muzzle.Position or origin, res and res.Position or origin + dir, player.UserId, gun.Sound)
	if res then
		local kind, applied = CombatService.applyHit(player, res.Instance, gun.Damage, nil, gun.Class, res.Position)
		if (kind == "player" or kind == "bot") and applied then
			HitMarker:FireClient(player, res.Instance.Name == "Head")
		end
	end
end

local function onReload(player)
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	local gun = gunOf(tool)
	if not gun or tool:GetAttribute("Reloading") then return end
	local ammo = tool:GetAttribute("Ammo") or 0
	if ammo >= gun.Mag then return end
	if gun.Reserve and (tool:GetAttribute("Reserve") or 0) <= 0 then return end
	tool:SetAttribute("Reloading", true)
	task.delay(gun.Reload, function()
		if not tool.Parent then return end
		local need = gun.Mag - (tool:GetAttribute("Ammo") or 0)
		if gun.Reserve then
			local take = math.min(need, tool:GetAttribute("Reserve") or 0)
			tool:SetAttribute("Reserve", (tool:GetAttribute("Reserve") or 0) - take)
			need = take
		end
		tool:SetAttribute("Ammo", (tool:GetAttribute("Ammo") or 0) + need)
		tool:SetAttribute("Reloading", false)
		local wh = tool:FindFirstChild("Warhead")
		if wh and (tool:GetAttribute("Ammo") or 0) > 0 then wh.Transparency = 0 end
	end)
end

-- наклон прицела стрелка — атрибутами на персонаже, чтобы другие клиенты рисовали хват (GunPose)
local lastAim = {}
local function onAim(player, pitch, aiming)
	if typeof(pitch) ~= "number" or pitch ~= pitch then return end
	local t = os.clock()
	if lastAim[player] and t - lastAim[player] < 0.05 then return end
	lastAim[player] = t
	local char = player.Character
	if not char then return end
	char:SetAttribute("AimPitch", math.floor(math.clamp(pitch, -1.4, 1.4) * 100 + 0.5) / 100)
	char:SetAttribute("Aiming", aiming == true)
end

-- оружейный стенд: покупка за личное золото
local function setupRack(part)
	local prompt = part:FindFirstChild("BuyPrompt")
	local key = part:GetAttribute("Gun")
	local gun = key and Config.Guns[key]
	if not prompt or not gun or not gun.Price then return end
	prompt.Triggered:Connect(function(player)
		local team = TeamService.getTeamName(player)
		if part:GetAttribute("Team") and part:GetAttribute("Team") ~= team then
			Notifier.send(player, "This is the enemy armory", "error")
			return
		end
		if player:GetAttribute("State") ~= "Deployed" then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		-- мёртвому не продаём: оружие ушло бы в рюкзак, который пропадёт с персонажем
		if not hrp or not hum or hum.Health <= 0 or (hrp.Position - part.Position).Magnitude > 20 then return end
		if not player:FindFirstChildOfClass("Backpack") then return end
		if hasGun(player, key) then
			Notifier.send(player, ("You already have an %s"):format(gun.DisplayName), "error")
			return
		end
		local paid, why = DataService.spendGold(player, gun.Price)
		if not paid then
			if why == "NotEnough" then
				Notifier.send(player, ("Not enough gold: %d needed, you have %d"):format(gun.Price, DataService.get(player, "Gold") or 0), "error")
			elseif why == "Syncing" then
				Notifier.send(player, "Your saved data is still loading — purchases are paused for a moment", "error")
			end
			return
		end
		if not GunService.give(player, key) then
			DataService.addGold(player, gun.Price, true) -- не выдали (нет шаблона/рюкзака) — возвращаем ровно списанное
			return
		end
		Notifier.send(player, ("%s purchased · −%d gold"):format(gun.DisplayName, gun.Price), "success")
	end)
end

function GunService.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	HitMarker = Remotes:WaitForChild("HitMarker")
	Remotes:WaitForChild("Fire").OnServerEvent:Connect(onFire)
	Remotes:WaitForChild("GunReload").OnServerEvent:Connect(onReload)
	Remotes:WaitForChild("GunAim").OnServerEvent:Connect(onAim)
	local alt = Remotes:FindFirstChild("GunAlt")
	if not alt then
		alt = Instance.new("RemoteEvent")
		alt.Name = "GunAlt"
		alt.Parent = Remotes
	end
	alt.OnServerEvent:Connect(detonate) -- подрыв C4
	local lockRemote = Remotes:FindFirstChild("GunLock")
	if not lockRemote then
		lockRemote = Instance.new("RemoteEvent")
		lockRemote.Name = "GunLock"
		lockRemote.Parent = Remotes
	end
	lockRemote.OnServerEvent:Connect(onLock)
	for _, p in ipairs(CollectionService:GetTagged("WeaponRack")) do setupRack(p) end
	CollectionService:GetInstanceAddedSignal("WeaponRack"):Connect(setupRack)
	Players.PlayerRemoving:Connect(function(p) lastShot[p] = nil lastAim[p] = nil safeWarned[p] = nil lastAlt[p] = nil locks[p] = nil clearCharges(p) end)
end

return GunService
