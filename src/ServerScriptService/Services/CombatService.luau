-- Стрельба, урон, безопасные зоны, засчитывание убийств. Работает и для игроков, и для ботов.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local CarrierService = require(Services.CarrierService)
local Notifier = require(Services.Notifier)

local CombatService = {}
local Rifle = Config.Combat.Rifle
local ShotFx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShotFx")
local DamageNumbers = ReplicatedStorage.Remotes:WaitForChild("DamageNumbers")
local lastHit = {}     -- [жертва (игрок или бот)] = {attacker, t}
local lastCombat = {}  -- [игрок] = время последнего боя
local lastShot = {}

local fxFolder = workspace:FindFirstChild("Effects") or Instance.new("Folder")
fxFolder.Name = "Effects"
fxFolder.Parent = workspace

local function isPlayer(x)
	return typeof(x) == "Instance" and x:IsA("Player")
end

function CombatService.nameOf(x)
	if isPlayer(x) then return x.DisplayName end
	if typeof(x) == "Instance" then return x:GetAttribute("DisplayName") or x.Name end
	return "?"
end

-- команда безопасной зоны в точке ("Lobby", "Blue", "Red", "Any") или nil
function CombatService.zoneAt(pos)
	for _, z in ipairs(CollectionService:GetTagged(Config.Spawn.SafeZoneTag)) do
		if z:IsA("BasePart") and z:IsDescendantOf(workspace) then
			local lp = z.CFrame:PointToObjectSpace(pos)
			local h = z.Size / 2
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				return z:GetAttribute("Team") or "Any"
			end
		end
	end
	return nil
end

local function protectedZone(zone, team)
	return zone ~= nil and (zone == "Lobby" or zone == "Any" or zone == team)
end

function CombatService.inCombat(player)
	local t = lastCombat[player]
	return t ~= nil and os.clock() - t < Config.Combat.KillCreditWindow
end

-- цифры урона: только стрелявшему игроку, по врагам и их технике. Попадания в одну цель за кадр
-- складываем (дробь очереди, взрыв) и шлём одним пакетом
local dmgQueue = {} -- [игрок] = {[цель] = {pos, amount}}
local function showDamage(attacker, target, pos, amount)
	if not isPlayer(attacker) or not pos or not amount or amount <= 0 then return end
	local q = dmgQueue[attacker]
	if not q then
		q = {}
		dmgQueue[attacker] = q
	end
	local e = q[target]
	if e then
		e.amount += amount
		e.pos = pos
	else
		q[target] = {pos = pos, amount = amount}
	end
end
CombatService.showDamage = showDamage -- для урона мимо applyHit (глубинные бомбы)

-- трассер рисуют клиенты (skipUserId — пилот, который рисует свои пули сам;
-- weaponClass — Rifle / AA / PlaneGun, по нему клиент выбирает звук выстрела)
local shotQueue = {}
function CombatService.tracer(a, b, skipUserId, weaponClass)
	if (b - a).Magnitude < 1 then return end
	local n = #shotQueue
	shotQueue[n + 1] = a
	shotQueue[n + 2] = b
	shotQueue[n + 3] = skipUserId or 0
	shotQueue[n + 4] = weaponClass or ""
end

-- из своей безопасной зоны можно бить только врагов, забежавших в эту же зону (защищённым стрелять наружу нельзя)
local function shotFromOwnZone(attacker, at, victimPos)
	local char = isPlayer(attacker) and attacker.Character or attacker
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local az = hrp and CombatService.zoneAt(hrp.Position)
	return az ~= nil and az == at and CombatService.zoneAt(victimPos) ~= az
end

-- attacker: игрок или бот (модель с атрибутами Team и State)
function CombatService.damagePlayer(attacker, victim, amount)
	if attacker == victim then return false end
	if attacker:GetAttribute("State") ~= "Deployed" or victim:GetAttribute("State") ~= "Deployed" then return false end
	local at, vt = TeamService.getTeamName(attacker), TeamService.getTeamName(victim)
	if not at or not vt then return false end
	if at == vt and not Config.Combat.FriendlyFire then return false end
	local char = victim.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then return false end
	if char:FindFirstChildOfClass("ForceField") then return false end
	if protectedZone(CombatService.zoneAt(hrp.Position), vt) then return false end
	if shotFromOwnZone(attacker, at, hrp.Position) then return false end

	local t = os.clock()
	lastHit[victim] = {attacker = attacker, t = t}
	if isPlayer(attacker) then lastCombat[attacker] = t end
	lastCombat[victim] = t
	hum:TakeDamage(amount)
	return true
end

function CombatService.damageBot(attacker, bot, amount)
	if attacker == bot then return false end
	if isPlayer(attacker) and attacker:GetAttribute("State") ~= "Deployed" then return false end
	local at, vt = TeamService.getTeamName(attacker), bot:GetAttribute("Team")
	if not at or not vt then return false end
	if at == vt and not Config.Combat.FriendlyFire then return false end
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or bot:FindFirstChildOfClass("ForceField") then return false end
	local bhrp = bot:FindFirstChild("HumanoidRootPart")
	if bhrp and shotFromOwnZone(attacker, at, bhrp.Position) then return false end
	lastHit[bot] = {attacker = attacker, t = os.clock()}
	if isPlayer(attacker) then lastCombat[attacker] = os.clock() end
	hum:TakeDamage(amount)
	return true
end

-- во что попали: "player" | "bot" | "plane" | "carrier" | nil, модель, игрок
function CombatService.resolveHit(inst)
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		local p = Players:GetPlayerFromCharacter(model)
		if p then return "player", model, p end
		if model:GetAttribute("IsBot") then return "bot", model end
		if model:GetAttribute("IsPlane") then return "plane", model end
		if model:GetAttribute("IsCarrier") then return "carrier", model end
		if model:GetAttribute("IsVessel") then return "vessel", model end
		if model:GetAttribute("IsCargo") then return "cargo", model end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

------------------------------------------------------------------ попадания, которые определил клиент
-- Игрок видит мир с задержкой на пинг, а сервер видит с задержкой его самого (его самолёт, его персонажа):
-- серверный луч промахивается там, где игрок честно попал. Поэтому попадание определяет клиент
-- (по тому, что на экране), а сервер проверяет правдоподобие: цель настоящая, точка рядом с ней (с запасом на
-- её скорость), в пределах дальности, по направлению ствола (look, maxAngle) и не сквозь сушу и постройки.
-- Темп стрельбы ограничивает тот, кто вызывает (GunService, PlaneService, TurretService).
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include
wallParams.IgnoreWater = true
wallParams.RespectCanCollide = true
local function finiteVec(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e5
end
-- неподвижная застройка для проверки «не сквозь стену» (список пересобираем раз в несколько секунд)
local wallList, wallListT = nil, 0
local function staticWalls()
	if wallList and os.clock() - wallListT < 5 then return wallList end
	local list = {workspace.Terrain}
	local map = workspace:FindFirstChild("Map")
	for _, n in ipairs({"Neutral", "Nature"}) do
		local f = map and map:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	local teams = map and map:FindFirstChild("Teams")
	for _, team in ipairs(Config.TeamOrder) do
		local b = teams and teams:FindFirstChild(team .. "Base")
		local f = b and b:FindFirstChild("Buildings")
		if f then table.insert(list, f) end
	end
	wallList, wallListT = list, os.clock()
	return list
end

-- между a и b есть суша или постройка (части модели model не считаются); slack — допуск у точки b
function CombatService.wallBetween(a, b, model, slack)
	local to = b - a
	local dist = to.Magnitude
	if dist <= 1 then return false end
	wallParams.FilterDescendantsInstances = staticWalls()
	local wall = workspace:Raycast(a, to, wallParams)
	return wall ~= nil and (wall.Position - a).Magnitude < dist - (slack or 1.5)
		and not (model and wall.Instance:IsDescendantOf(model))
end

function CombatService.checkClientHit(origin, part, hitPos, range, look, maxAngle)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then return false end
	if not finiteVec(hitPos) or not finiteVec(origin) then return false end
	local kind, model = CombatService.resolveHit(part)
	if not kind then return false end
	-- точка попадания — на самой детали (с запасом на то, что цель сдвинулась, пока шли данные)
	local slack = part.Size.Magnitude / 2 + part.AssemblyLinearVelocity.Magnitude * 0.35 + 4
	if (hitPos - part.Position).Magnitude > slack then return false end
	local to = hitPos - origin
	local dist = to.Magnitude
	if dist > range then return false end
	if look and dist > 60 and look:Dot(to.Unit) < math.cos(math.rad(maxAngle or 30)) then return false end
	-- не сквозь сушу, островные укрепления и здания баз. Стены неподвижны и у клиента стоят там же,
	-- поэтому допуск маленький (раньше было 6 студов — простреливали того, кто стоит вплотную за стеной).
	-- Корабли и технику сюда не включаем: они движутся, и на сервере стоят не там, где у стрелка.
	return not CombatService.wallBetween(origin, hitPos, model, 1.5)
end

-- общий урон по любой цели; attackerTeam нужен для авианосцев
-- класс цели для таблицы урона
local SHIP_CLASS = {Gunboat = "Light", Submarine = "Light", Battleship = "Heavy"}
local function targetClass(kind, model)
	if kind == "player" or kind == "bot" then return "Infantry" end
	if kind == "plane" then return "Plane" end
	if kind == "cargo" then return "Light" end
	if kind == "carrier" then return "Carrier" end
	if kind == "vessel" then return SHIP_CLASS[model:GetAttribute("ShipType")] or "Light" end
	return nil
end

-- weaponClass: Rifle / AA / PlaneGun / Medium / Heavy (см. Config.Combat.DamageMatrix)
-- hitPos — точка попадания (для цифр урона; без неё — центр детали)
function CombatService.applyHit(attacker, inst, amount, carrierMult, weaponClass, hitPos)
	local kind, model, victim = CombatService.resolveHit(inst)
	local pos = hitPos or inst.Position
	local at = isPlayer(attacker) and TeamService.getTeamName(attacker)
	local function enemy(m) return at and m:GetAttribute("Team") and m:GetAttribute("Team") ~= at end
	local row = weaponClass and Config.Combat.DamageMatrix and Config.Combat.DamageMatrix[weaponClass]
	if row and kind then
		local tc = targetClass(kind, model)
		amount = amount * ((tc and row[tc]) or 1)
		carrierMult = 1 -- множители урона теперь в таблице
		if amount <= 0 then return kind end
	end
	if kind == "player" then
		local dmg = amount
		if inst.Name == "Head" then dmg = math.floor(dmg * 1.5) end
		if CombatService.damagePlayer(attacker, victim, dmg) then showDamage(attacker, model, pos, dmg) end
	elseif kind == "bot" then
		local dmg = amount
		if inst.Name == "Head" then dmg = math.floor(dmg * 1.5) end
		if CombatService.damageBot(attacker, model, dmg) then showDamage(attacker, model, pos, dmg) end
	elseif kind == "plane" then
		if CombatService.onPlaneHit then CombatService.onPlaneHit(model, amount, attacker) end
		if enemy(model) then showDamage(attacker, model, pos, amount) end
	elseif kind == "vessel" then
		if CombatService.onVesselHit then CombatService.onVesselHit(model, amount, attacker) end
		if enemy(model) then showDamage(attacker, model, pos, amount) end
	elseif kind == "cargo" then
		if CombatService.onCargoHit then CombatService.onCargoHit(model, amount, attacker) end
		if enemy(model) then showDamage(attacker, model, pos, amount) end
	elseif kind == "carrier" then
		local ct = model:GetAttribute("Team")
		local att = TeamService.getTeamName(attacker)
		if ct and att and ct ~= att then
			if isPlayer(attacker) then lastCombat[attacker] = os.clock() end
			CarrierService.damage(ct, amount * (carrierMult or 1), attacker)
			showDamage(attacker, model, pos, amount * (carrierMult or 1))
		end
	end
	return kind
end

-- victimIsBot: за бота — только маленькая награда (BotKillReward): без Kills в рейтинге, задания и раунда
-- (иначе их накручивают фармом ботов); за игрока — полная (KillReward) и всё остальное
local function rewardKill(killer, victimName, victimTeam, victimIsBot, victim)
	if not isPlayer(killer) or not killer.Parent then return end
	local kt = TeamService.getTeamName(killer)
	if not kt or kt == victimTeam then return end
	local reward = victimIsBot and (Config.Economy.BotKillReward or 5) or Config.Economy.KillReward
	if not victimIsBot then DataService.increment(killer, "Kills") end
	DataService.addGold(killer, reward)
	if not victimIsBot and CombatService.onKill then CombatService.onKill(killer) end -- задания (QuestService), раунд (RoundService)
	require(script.Parent.RankService).onKill(killer, victim, victimIsBot) -- опыт для ранга
	Notifier.send(killer, ("Enemy %s eliminated · +%d gold"):format(victimName, reward), "success")
end

-- вызывается SpawnService для каждого нового персонажа игрока
function CombatService.trackCharacter(player, char, kind)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	lastHit[player] = nil
	hum.Died:Connect(function()
		if kind == "Lobby" then return end
		DataService.increment(player, "Deaths")
		local hit = lastHit[player]
		lastHit[player] = nil
		if not hit or os.clock() - hit.t > Config.Combat.KillCreditWindow then return end
		local killer = hit.attacker
		if not killer or not killer.Parent or killer == player then return end
		local kt, vt = TeamService.getTeamName(killer), TeamService.getTeamName(player)
		if not kt or not vt or kt == vt then return end
		rewardKill(killer, player.DisplayName, vt, false, player)
		Notifier.send(player, ("Killed by %s"):format(CombatService.nameOf(killer)), "error")
	end)
end

-- вызывается BotService для каждого бота
function CombatService.trackBot(bot)
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	-- бота могут убрать без смерти (его место занял игрок) — не держим ссылку на удалённую модель
	bot.Destroying:Connect(function() lastHit[bot] = nil end)
	hum.Died:Connect(function()
		local hit = lastHit[bot]
		lastHit[bot] = nil
		if not hit or os.clock() - hit.t > Config.Combat.KillCreditWindow then return end
		rewardKill(hit.attacker, CombatService.nameOf(bot), bot:GetAttribute("Team"), true, bot)
	end)
end

-- убийство с засчитыванием (гибель пилота сбитого самолёта)
function CombatService.creditKill(attacker, victim)
	local char = victim and (victim:IsA("Player") and victim.Character or victim)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if attacker and attacker ~= victim then
		lastHit[victim] = {attacker = attacker, t = os.clock()}
	end
	hum.Health = 0
end

function CombatService.init()
	-- выстрелы из ручного оружия (Remotes.Fire) обрабатывает GunService
	-- все выстрелы кадра — одним сетевым пакетом
	game:GetService("RunService").Heartbeat:Connect(function()
		if #shotQueue > 0 then
			local batch = shotQueue
			shotQueue = {}
			ShotFx:FireAllClients(batch)
		end
		if next(dmgQueue) then
			local q = dmgQueue
			dmgQueue = {}
			for player, hits in pairs(q) do
				if player.Parent then
					local list = {}
					for _, e in pairs(hits) do
						table.insert(list, e.pos)
						table.insert(list, math.max(1, math.floor(e.amount + 0.5)))
					end
					DamageNumbers:FireClient(player, list)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastHit[p] = nil
		lastCombat[p] = nil
		lastShot[p] = nil
	end)
end

return CombatService
