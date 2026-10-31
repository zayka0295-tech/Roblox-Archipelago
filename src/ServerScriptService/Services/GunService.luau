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
local function facing(hrp, aim)
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude < 3 then return true end -- стрельба почти отвесно или вупор
	local lv = hrp.CFrame.LookVector
	local fl = Vector3.new(lv.X, 0, lv.Z)
	if fl.Magnitude < 0.01 then return true end
	return fl.Unit:Dot(flat.Unit) >= MAX_YAW
end

-- выдать оружие игроку (в рюкзак), с полным магазином
function GunService.give(player, key)
	local gun = Config.Guns[key]
	local template = ServerStorage.Weapons:FindFirstChild(key)
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
	lastShot[player] = t
	tool:SetAttribute("Ammo", ammo - 1)

	if gun.Rocket then
		local d = aim
		local W = {Damage = gun.Damage, SplashRadius = gun.SplashRadius, Gravity = gun.Gravity, Class = gun.Class}
		ProjectileService.launch(from, d.Unit * gun.ShellSpeed, player, W, {char})
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
	-- попадание глазами игрока: цель на сервере уже сдвинулась на пинг, серверный луч бы промахнулся
	if typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") and not hitPart:IsDescendantOf(char)
		and CombatService.checkClientHit(origin, hitPart, target, gun.Range + 20) then
		local ok = true
		if hitPart.Name == "Head" then
			-- голова (×1,5 урона) — только если точка действительно у головы, а не где-то на теле
			ok = (target - hitPart.Position).Magnitude <= 2 + hitPart.AssemblyLinearVelocity.Magnitude * 0.3
		end
		if ok then
			CombatService.tracer(muzzle and muzzle.Position or origin, target, player.UserId, gun.Sound)
			local kind = CombatService.applyHit(player, hitPart, gun.Damage, nil, gun.Class, target)
			if kind == "player" or kind == "bot" then
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
		local kind = CombatService.applyHit(player, res.Instance, gun.Damage, nil, gun.Class, res.Position)
		if kind == "player" or kind == "bot" then
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
		if not hrp or (hrp.Position - part.Position).Magnitude > 20 then return end
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
		GunService.give(player, key)
		Notifier.send(player, ("%s purchased · −%d gold"):format(gun.DisplayName, gun.Price), "success")
	end)
end

function GunService.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	HitMarker = Remotes:WaitForChild("HitMarker")
	Remotes:WaitForChild("Fire").OnServerEvent:Connect(onFire)
	Remotes:WaitForChild("GunReload").OnServerEvent:Connect(onReload)
	Remotes:WaitForChild("GunAim").OnServerEvent:Connect(onAim)
	for _, p in ipairs(CollectionService:GetTagged("WeaponRack")) do setupRack(p) end
	CollectionService:GetInstanceAddedSignal("WeaponRack"):Connect(setupRack)
	Players.PlayerRemoving:Connect(function(p) lastShot[p] = nil lastAim[p] = nil safeWarned[p] = nil end)
end

return GunService
