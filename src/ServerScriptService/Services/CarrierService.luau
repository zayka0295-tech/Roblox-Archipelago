-- Командные авианосцы: покупка, управление с мостика, урон, уничтожение и восстановление
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local Notifier = require(Services.Notifier)
local TreasuryService = require(Services.TreasuryService)
local Guard = require(Services.RemoteGuard)
local AntiCheat = require(Services.AntiCheatService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local C = Config.Carrier

local CarrierService = {}
local states = {} -- [команда] = {state, health, model, ..., reservedBy, reservedUntil — бронь покупателем доната}
local countBlocked

-- авианосец забронирован другим покупателем доната (не player) и бронь ещё действует
local function reservedByOther(s, player)
	local by = s and s.reservedBy
	return by ~= nil and by ~= player and by.Parent ~= nil and os.clock() < (s.reservedUntil or 0)
end

local function now()
	return workspace:GetServerTimeNow()
end

local function publish(team)
	local s = states[team]
	GameState:SetAttribute("Carrier_" .. team, s.state)
	GameState:SetAttribute("Carrier_" .. team .. "_Health", math.floor(s.health))
	GameState:SetAttribute("Carrier_" .. team .. "_MaxHealth", C.MaxHealth)
	GameState:SetAttribute("Carrier_" .. team .. "_CooldownEnd", s.cooldownEnd)
end

local function baseFolder(team)
	return workspace.Map.Teams:FindFirstChild(team .. "Base")
end

local function carriersFolder()
	local f = workspace.Map:FindFirstChild("Carriers")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Carriers"
		f.Parent = workspace.Map
	end
	return f
end

local function fail(msg)
	return {ok = false, msg = msg}
end

local function moveToward(v, target, step)
	if v < target then return math.min(v + step, target) end
	return math.max(v - step, target)
end

-- корабль считает только сервер: клиент не может его телепортировать
local function serverOwn(root)
	pcall(function()
		if root:CanSetNetworkOwnership() then
			root:SetNetworkOwner(nil)
		end
	end)
end

function CarrierService.isActive(team)
	local s = states[team]
	return s ~= nil and s.state == "Active" and s.model ~= nil and s.model.Parent ~= nil
end

function CarrierService.getSpawnPoints(team)
	if not CarrierService.isActive(team) then return nil end
	return states[team].points
end

function CarrierService.status(team)
	local s = states[team]
	if not s then return false, "No team selected" end
	if s.state == "Active" then return true end
	if s.state == "Sinking" or s.state == "Destroyed" then
		return false, "Carrier is sinking · a new one after it goes down"
	end
	return false, ("Carrier not purchased · %d from treasury at the shipyard"):format(Config.Economy.CarrierPrice)
end

------------------------------------------------------------------ капитан
local function releaseDriver(team)
	local s = states[team]
	local prevHum = s.driverHum
	s.driver, s.driverHum = nil, nil
	if s.ctrl then
		s.ctrl.throttle, s.ctrl.steer = 0, 0
	end
	if s.model then s.model:SetAttribute("Driver", "") end
	-- вернуть бывшего капитана на палубу
	local exit = s.model and s.model:FindFirstChild("HelmExit")
	if prevHum and prevHum.Parent and prevHum.Health > 0 and exit then
		task.delay(0.15, function()
			if prevHum.Parent and not prevHum.SeatPart then
				prevHum.Parent:PivotTo(exit.CFrame + Vector3.new(0, 3, 0))
			end
		end)
	end
end

local function onOccupantChanged(team, model, seat)
	local s = states[team]
	if s.model ~= model then return end
	local hum = seat.Occupant
	if not hum then
		if s.driverHum then releaseDriver(team) end
		return
	end
	local player = Players:GetPlayerFromCharacter(hum.Parent) or (hum.Parent:GetAttribute("IsBot") and hum.Parent) or nil
	if not player or TeamService.getTeamName(player) ~= team or player:GetAttribute("State") ~= "Deployed" then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then weld:Destroy() end
		return
	end
	s.driver, s.driverHum = player, hum
	local name = player:IsA("Player") and player.DisplayName or (player:GetAttribute("DisplayName") or player.Name)
	model:SetAttribute("Driver", name)
	serverOwn(model.Hull)
	if player:IsA("Player") then
		Notifier.team(team, name .. " took the carrier's helm", "info")
	end
end

local function setupHelm(team, model)
	local s = states[team]
	local seat = model:FindFirstChild("HelmSeat")
	local access = model:FindFirstChild("HelmAccess")
	local prompt = access and access:FindFirstChild("HelmPrompt")
	if not seat or not prompt then
		warn("[CarrierService] template has no HelmSeat/HelmPrompt")
		return
	end
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupantChanged(team, model, seat)
	end)
	-- трапы: из воды на палубу (подняться может любой игрок, в т.ч. противник — абордаж)
	for _, plat in ipairs(model:GetChildren()) do
		local board = plat.Name == "LadderPlatform" and plat:FindFirstChild("BoardPrompt")
		if board then
			local sx = plat:GetAttribute("BoardSide") or 1
			board.Triggered:Connect(function(player)
				if s.model ~= model or s.state ~= "Active" then return end
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hum or hum.Health <= 0 or not hrp or hum.SeatPart then return end
				if (hrp.Position - plat.Position).Magnitude > 16 then return end
				local hull = model:FindFirstChild("Hull")
				if not hull then return end
				AntiCheat.moveTo(player, char, hull.CFrame * CFrame.new(sx * 36, 20, -110) * CFrame.Angles(0, sx > 0 and math.pi / 2 or -math.pi / 2, 0), hull)
			end)
		end
	end
	prompt.Triggered:Connect(function(player)
		if s.model ~= model or s.state ~= "Active" or not AntiCheat.atPrompt(player, prompt) then return end
		if TeamService.getTeamName(player) ~= team then
			Notifier.send(player, "This is the enemy carrier", "error")
			return
		end
		if seat.Occupant then
			-- бот-капитан уступает штурвал игроку
			if seat.Occupant.Parent and seat.Occupant.Parent:GetAttribute("IsBot") then
				local w = seat:FindFirstChild("SeatWeld")
				if w then w:Destroy() end
				task.wait(0.1)
			else
				Notifier.send(player, "Already at the helm: " .. (s.driver and s.driver:IsA("Player") and s.driver.DisplayName or "another player"), "error")
				return
			end
		end
		-- после ожидания всё могло измениться: авианосец потоплен, штурвал занят, игрок сменил команду
		if s.model ~= model or s.state ~= "Active" or seat.Occupant or TeamService.getTeamName(player) ~= team then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.SeatPart or player:GetAttribute("State") ~= "Deployed" then return end
		AntiCheat.grace(player)
		char:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
		seat:Sit(hum)
	end)
end

------------------------------------------------------------------ постройка
local function spawnCarrier(team)
	local template = ServerStorage.Ships:FindFirstChild("AircraftCarrier")
	assert(template, "missing template ServerStorage.Ships.AircraftCarrier")
	local anchor = baseFolder(team).Zones.CarrierAnchor
	local tcfg = Config.Teams[team]

	local m = template:Clone()
	m.Name = team .. "Carrier"
	m:SetAttribute("Team", team)
	m:SetAttribute("IsCarrier", true)
	m:SetAttribute("Speed", 0)
	m:SetAttribute("Setpoint", 0)
	m:SetAttribute("Driver", "")
	local points = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("TeamPaint") then
			d.Color = tcfg.Color
		end
		if d:IsA("SpawnLocation") then
			d.Enabled = false
			d.Duration = 0
			d.TeamColor = tcfg.BrickColor
			table.insert(points, d)
		end
	end
	local zone = m:FindFirstChild("SafeZone")
	if zone then zone:SetAttribute("Team", team) end
	local label = m:FindFirstChild("DeckLabel")
	if label and label:FindFirstChild("DeckGui") then
		label.DeckGui.DeckText.Text = string.upper(tcfg.DisplayName) .. " FLEET"
	end

	local _, yaw = anchor.CFrame:ToOrientation()
	m:PivotTo(CFrame.new(anchor.Position.X, C.WaterlineY, anchor.Position.Z) * CFrame.Angles(0, yaw, 0))
	m.Parent = carriersFolder()

	local root = m.Hull
	serverOwn(root)
	local ctrl = {
		root = root,
		ao = root.HelmAlign,
		lv = root.HelmDrive,
		yaw = yaw,
		rootY = root.Position.Y,
		speed = 0,
		setpoint = 0,
		throttle = 0,
		steer = 0,
		pub = 0,
	}
	ctrl.ao.CFrame = CFrame.Angles(0, yaw, 0)
	return m, points, ctrl
end

function CarrierService.requestPurchase(player)
	if not Guard.allow(player, "BuyCarrier") then return fail("Too many requests, please wait") end
	local team = TeamService.getTeamName(player)
	if not team or player:GetAttribute("State") ~= "Deployed" then
		return fail("Choose a team and deploy first")
	end

	local term = baseFolder(team).Shipyard:FindFirstChild("ShipTerminal")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not term or not hrp or not hum or hum.Health <= 0
		or (hrp.Position - term.Position).Magnitude > C.TerminalMaxDistance then
		return fail("Go to your team's shipyard terminal")
	end

	local s = states[team]
	if s.busy then return fail("Another player is already purchasing") end
	if reservedByOther(s, player) then return fail("A player is buying a carrier for the team right now — try again in a minute") end
	if s.state == "Active" then return fail("Your team's carrier is already afloat") end
	if s.state == "Sinking" or s.state == "Destroyed" then
		return fail("The carrier is still sinking — buy a new one once it goes down")
	end
	local wait = (s.cooldownEnd or 0) - os.time()
	if wait > 0 then return fail(("The shipyard can build a new carrier in %d s"):format(wait)) end

	local price = Config.Economy.CarrierPrice
	s.busy = true
	if not TreasuryService.spend(team, price) then
		s.busy = false
		return fail(("Team treasury has %d of %d — capture islands, their cargo ships fill the treasury"):format(TreasuryService.get(team), price))
	end

	local ok, model, points, ctrl = pcall(spawnCarrier, team)
	if not ok then
		TreasuryService.refund(team, price)
		s.busy = false
		warn("[CarrierService] " .. tostring(model))
		return fail("Ship construction failed, treasury refunded")
	end

	s.model, s.points, s.ctrl = model, points, ctrl
	s.state = "Active"
	s.health = C.MaxHealth
	s.busy = false
	s.donated = false
	setupHelm(team, model)
	publish(team)
	Notifier.team(team, ("%s bought a carrier from the treasury (−%d)! You can spawn on its deck; the captain takes the helm on the bridge."):format(player.DisplayName, price), "success")
	return {ok = true, msg = "Carrier built and available to the whole team"}
end

------------------------------------------------------------------ урон
function CarrierService.damage(team, amount, attacker)
	local s = states[team]
	if not s or s.state ~= "Active" then return end
	s.health = math.max(0, s.health - amount)
	publish(team)
	if s.health <= 0 then
		CarrierService.destroy(team, attacker)
	end
end

function CarrierService.destroy(team, attacker)
	local s = states[team]
	if not s or s.state ~= "Active" then return end
	local model, ctrl = s.model, s.ctrl
	s.driver, s.driverHum = nil, nil
	-- пока тонет — новый не купить (авианосец один на команду)
	s.state = "Sinking"
	s.model, s.points, s.ctrl = nil, nil, nil
	s.health = 0
	s.cooldownEnd = os.time() + (C.RebuyCooldown or 0) -- новый — не раньше чем через RebuyCooldown после гибели
	publish(team)

	for _, p in ipairs(Players:GetPlayers()) do
		if TeamService.getTeamName(p) == team and p:GetAttribute("SpawnChoice") == "Carrier" then
			p:SetAttribute("SpawnChoice", "Base")
		end
	end
	Notifier.team(team, "Your carrier was destroyed! Spawn switched to base.", "error")

	local reward = Config.Economy.CarrierDestroyReward or 0
	local attackerTeam = attacker and typeof(attacker) == "Instance" and TeamService.getTeamName(attacker)
	if attackerTeam and attackerTeam ~= team then
		TreasuryService.add(attackerTeam, Config.Treasury.CarrierDestroyBonus or 0, "enemy carrier destroyed")
	end
	if attacker and typeof(attacker) == "Instance" and attacker:IsA("Player") and attacker.Parent then
		local at = TeamService.getTeamName(attacker)
		if at and at ~= team then
			if reward > 0 then
				DataService.addGold(attacker, reward)
				Notifier.send(attacker, ("Enemy carrier destroyed! +%d gold"):format(reward), "success")
			end
			require(script.Parent.RankService).award(attacker, "CarrierKill")
		end
	end

	if not model then
		s.state = "None"
		publish(team)
		return
	end
	model:SetAttribute("IsCarrier", false)
	model:SetAttribute("Sinking", true)
	s.sinkModel = model
	-- экипаж в креслах гибнет вместе с кораблём
	local CombatService = require(Services.CombatService)
	for _, seat in ipairs(model:GetDescendants()) do
		if seat:IsA("Seat") and seat.Occupant then
			local char = seat.Occupant.Parent
			local actor = Players:GetPlayerFromCharacter(char) or (char:GetAttribute("IsBot") and char) or nil
			local w = seat:FindFirstChild("SeatWeld")
			if w then w:Destroy() end
			if actor then CombatService.creditKill(attacker, actor) end
		end
	end

	task.spawn(function()
		-- серия взрывов по палубе
		for _ = 1, 7 do
			if not model.Parent then break end
			local e = Instance.new("Explosion")
			e.BlastPressure = 0
			e.DestroyJointRadiusPercent = 0
			e.BlastRadius = 30
			e.Position = (model:GetPivot() * CFrame.new(math.random(-30, 30), 20, math.random(-140, 140))).Position
			e.Parent = workspace
			task.wait(0.35)
		end
		if model.Parent and ctrl then
			-- крен и медленное погружение; сквозь дно — без столкновений
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.CanCollide = false end
			end
			ctrl.ao.Responsiveness = 2
			ctrl.ao.CFrame = CFrame.Angles(0, ctrl.yaw, 0) * CFrame.Angles(math.rad(8), 0, math.rad(18))
			ctrl.lv.VectorVelocity = Vector3.new(0, -3, 0)
			local t0 = os.clock()
			while model.Parent and ctrl.root.Position.Y > -60 and os.clock() - t0 < 45 do
				task.wait(0.5)
			end
		end
		if model.Parent then model:Destroy() end
		-- новый раунд мог уже убрать его и спустить новый — тогда состояние не трогаем
		if s.sinkModel ~= model then return end
		s.sinkModel = nil
		s.state = "None"
		publish(team)
		Notifier.team(team, "The carrier has sunk — the shipyard can build a new one.", "info")
	end)
end

-- модели авианосцев, которые уберёт новый раунд (живые не за донат и тонущие)
function CarrierService.roundResetModels()
	local list = {}
	for _, s in pairs(states) do
		if s.model and not s.donated then table.insert(list, s.model) end
		if s.sinkModel then table.insert(list, s.sinkModel) end
	end
	return list
end

-- новый раунд: авианосцы из казны убираем сразу (без взрывов и наград), кулдаун сбрасываем.
-- Купленный за Robux остаётся. Игроков с палубы RoundService уже перенёс на базу.
function CarrierService.resetAll()
	for team, s in pairs(states) do
		if s.model and not s.donated then
			local model = s.model
			s.driver, s.driverHum = nil, nil
			s.model, s.points, s.ctrl = nil, nil, nil
			s.state, s.health = "None", 0
			model:Destroy()
		end
		if s.sinkModel then
			local m = s.sinkModel
			s.sinkModel = nil
			if m.Parent then m:Destroy() end
			if s.state ~= "Active" then s.state, s.health = "None", 0 end
		end
		s.cooldownEnd = 0
		publish(team)
		if s.state ~= "Active" then
			for _, p in ipairs(Players:GetPlayers()) do
				if TeamService.getTeamName(p) == team and p:GetAttribute("SpawnChoice") == "Carrier" then
					p:SetAttribute("SpawnChoice", "Base")
				end
			end
		end
	end
end

------------------------------------------------------------------ для ботов
-- бот-командир спускает авианосец команде БЕСПЛАТНО: казна — деньги игроков, боты её не тратят.
-- BotService зовёт это только для команды без живых игроков (иначе покупку решают игроки)
function CarrierService.botPurchase(team)
	local s = states[team]
	if not s or s.busy or s.state ~= "None" or reservedByOther(s, nil) then return false end
	s.busy = true
	local ok, model, points, ctrl = pcall(spawnCarrier, team)
	s.busy = false
	if not ok then
		warn("[CarrierService] " .. tostring(model))
		return false
	end
	s.model, s.points, s.ctrl = model, points, ctrl
	s.state = "Active"
	s.health = C.MaxHealth
	setupHelm(team, model)
	publish(team)
	Notifier.team(team, "Bot commander launched a carrier", "success")
	return true
end

------------------------------------------------------------------ донат (DonateShipService)
-- авианосец один на команду: за донат — только когда его нет (вместо казны). nil — можно, иначе причина
function CarrierService.donateFail(team, player)
	local s = states[team]
	if not s then return "Unknown team" end
	if s.busy then return "Another player is already purchasing" end
	if reservedByOther(s, player) then return "Another player is buying a carrier right now — try again in a minute" end
	if s.state == "Active" then return "This team's carrier is already afloat — spawn on its deck!" end
	if s.state ~= "None" then return "The carrier is still sinking — try again once it goes down" end
	return nil
end

-- спустить авианосец без казны: модель или nil, причина
function CarrierService.donateSpawn(player, team)
	local why = CarrierService.donateFail(team, player)
	if why then return nil, why end
	local s = states[team]
	s.busy = true
	local ok, model, points, ctrl = pcall(spawnCarrier, team)
	s.busy = false
	if not ok then
		warn("[CarrierService] " .. tostring(model))
		return nil, "Construction failed"
	end
	s.model, s.points, s.ctrl = model, points, ctrl
	s.state = "Active"
	s.health = C.MaxHealth
	s.donated = true -- куплен за Robux: новый раунд его не убирает
	CarrierService.releaseDonate(team, player)
	setupHelm(team, model)
	publish(team)
	Notifier.team(team, ("%s launched a carrier for the team! You can spawn on its deck."):format(player.DisplayName), "success")
	return model
end

-- забронировать авианосец для доната на seconds (или продлить свою бронь); false — занят другим
function CarrierService.reserveDonate(team, player, seconds)
	local s = states[team]
	if not s or reservedByOther(s, player) then return false end
	s.reservedBy, s.reservedUntil = player, os.clock() + seconds
	return true
end

function CarrierService.releaseDonate(team, player)
	local s = states[team]
	if s and s.reservedBy == player then s.reservedBy, s.reservedUntil = nil, 0 end
end

-- руль и ход от бота-капитана
function CarrierService.botDrive(team, bot, throttle, steer)
	local s = states[team]
	if not s or s.driver ~= bot or not s.ctrl then return end
	s.ctrl.throttle = math.clamp(throttle, -1, 1)
	s.ctrl.steer = math.clamp(steer, -1, 1)
end

function CarrierService.getInfo(team)
	local s = states[team]
	if not s then return nil end
	return {state = s.state, model = s.model, ctrl = s.ctrl, driver = s.driver, cooldownEnd = s.cooldownEnd}
end

-- только для тестов в Studio
function CarrierService.devSetpoint(team, value)
	local s = states[team]
	if s and s.ctrl then
		s.ctrl.setpoint = math.clamp(value, -C.MaxReverseSpeed, C.MaxSpeed)
		s.devHold = value ~= 0
	end
end

------------------------------------------------------------------ мель
-- точки контура (относительно корпуса): днище — проверка глубины, края палубы — препятствия выше воды
local HULL_PTS, DECK_PTS = {}, {}
for z = -150, 150, 50 do
	table.insert(HULL_PTS, Vector3.new(28, 0, z))
	table.insert(HULL_PTS, Vector3.new(-28, 0, z))
end
table.insert(HULL_PTS, Vector3.new(14, 0, 175))
table.insert(HULL_PTS, Vector3.new(-14, 0, 175))
table.insert(HULL_PTS, Vector3.new(0, 0, 200))
for _, z in ipairs({-165, -100, 0, 100, 165}) do
	table.insert(DECK_PTS, Vector3.new(43, 0, z))
	table.insert(DECK_PTS, Vector3.new(-43, 0, z))
end
table.insert(DECK_PTS, Vector3.new(0, 0, 205))

local obstacleParams = RaycastParams.new()
obstacleParams.FilterType = Enum.RaycastFilterType.Include
obstacleParams.IgnoreWater = true

countBlocked = function(s, pos, yaw)
	local list = {workspace.Terrain}
	for _, n in ipairs({"Teams", "Neutral", "Nature", "Vessels"}) do
		local f = workspace.Map:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	for _, other in pairs(states) do
		if other ~= s and other.model then table.insert(list, other.model) end
	end
	obstacleParams.FilterDescendantsInstances = list
	local rot = CFrame.Angles(0, yaw, 0)
	local rootY = s.ctrl.rootY
	local keelLimit = rootY - 14  -- днище на rootY - 13, нужен запас 1 студ
	local deckLimit = rootY + 12  -- низ палубы на rootY + 13
	local n = 0
	local function probe(p, limit)
		local w = pos + rot:VectorToWorldSpace(p)
		local r = workspace:Raycast(Vector3.new(w.X, rootY + 70, w.Z), Vector3.new(0, -140, 0), obstacleParams)
		if r and r.Position.Y > limit then n += 1 end
	end
	for _, p in ipairs(HULL_PTS) do probe(p, keelLimit) end
	for _, p in ipairs(DECK_PTS) do probe(p, deckLimit) end
	return n
end

------------------------------------------------------------------ движение
local function step(s, dt)
	local c = s.ctrl
	if not c or not c.root.Parent then return end

	if s.driverHum and (s.driverHum.SeatPart == nil or s.driverHum.Health <= 0) then
		-- капитан пропал без события (смерть/выход)
		local seat = s.model:FindFirstChild("HelmSeat")
		local w = seat and seat:FindFirstChild("SeatWeld")
		if w and s.driverHum.Health <= 0 then w:Destroy() end
		local team = s.model:GetAttribute("Team")
		releaseDriver(team)
	end

	if s.driver then
		if c.throttle ~= 0 then
			c.setpoint = math.clamp(c.setpoint + c.throttle * C.Acceleration * dt, -C.MaxReverseSpeed, C.MaxSpeed)
		end
	elseif not s.devHold then
		c.setpoint = moveToward(c.setpoint, 0, C.Acceleration * dt) -- без капитана корабль останавливается
	end
	c.speed = moveToward(c.speed, c.setpoint, C.Acceleration * dt)

	local prevYaw = c.yaw
	local newYaw = c.yaw
	if s.driver and c.steer ~= 0 then
		local factor = math.max(C.MinTurnFactor, math.abs(c.speed) / C.MaxSpeed)
		newYaw = c.yaw - c.steer * math.rad(C.TurnRate) * factor * dt
	end

	local pos = c.root.Position
	local function fwdOf(yaw)
		return CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.zAxis)
	end
	local vel = fwdOf(newYaw) * c.speed

	-- границы карты
	local ahead = pos + vel * 3
	if (math.abs(ahead.X) > C.BoundsX and ahead.X * vel.X > 0) or (math.abs(ahead.Z) > C.BoundsZ and ahead.Z * vel.Z > 0) then
		c.speed, c.setpoint = 0, 0
		vel = Vector3.zero
	end

	-- мель и препятствия: корабль не может заехать на сушу, пирс или чужой корабль
	if vel.Magnitude > 0.05 or newYaw ~= prevYaw then
		local cur = countBlocked(s, pos, prevYaw)
		local look = vel.Magnitude > 0.05 and vel.Unit * math.max(10, math.abs(c.speed) * 0.8) or Vector3.zero
		local nxt = countBlocked(s, pos + look, newYaw)
		if nxt > 0 and nxt >= cur then
			local straightOk = false
			if newYaw ~= prevYaw and vel.Magnitude > 0.05 then
				-- без поворота: прямо вперёд/назад
				local v2 = fwdOf(prevYaw) * c.speed
				local look2 = v2.Unit * math.max(10, math.abs(c.speed) * 0.8)
				local straight = countBlocked(s, pos + look2, prevYaw)
				if straight == 0 or straight < cur then
					straightOk = true
					newYaw = prevYaw
					vel = v2
				end
			end
			if not straightOk then
				-- хотя бы повернуть на месте
				local rotOnly = newYaw ~= prevYaw and countBlocked(s, pos, newYaw) or math.huge
				if rotOnly > 0 and rotOnly >= cur then
					newYaw = prevYaw
				end
				c.speed, c.setpoint = 0, 0
				vel = Vector3.zero
				if s.driver and os.clock() - (s.groundNote or 0) > 4 then
					s.groundNote = os.clock()
					Notifier.send(s.driver, "Shallows or obstacle! Reverse or turn away.", "error")
				end
			end
		end
	end
	c.yaw = newYaw
	local rot = CFrame.Angles(0, c.yaw, 0)
	local vy = math.clamp((c.rootY - pos.Y) * 4, -20, 20)
	c.lv.VectorVelocity = vel + Vector3.new(0, vy, 0)
	c.ao.CFrame = rot

	c.pub += dt
	if c.pub >= 0.2 then
		c.pub = 0
		s.model:SetAttribute("Speed", math.floor(c.speed + 0.5))
		s.model:SetAttribute("Setpoint", math.floor(c.setpoint + 0.5))
	end
end

function CarrierService.init()
	local OpenShop = Remotes:WaitForChild("OpenShop")
	for _, team in ipairs(Config.TeamOrder) do
		states[team] = {state = "None", health = 0, cooldownEnd = 0, busy = false}
		publish(team)
		local base = baseFolder(team)
		local term = base and base:FindFirstChild("Shipyard") and base.Shipyard:FindFirstChild("ShipTerminal")
		local prompt = term and term:FindFirstChild("ShopPrompt")
		if prompt then
			prompt.ObjectText = "Shipyard"
			prompt.Triggered:Connect(function(player)
				if TeamService.getTeamName(player) ~= team then
					Notifier.send(player, "This is the other team's shipyard", "error")
					return
				end
				OpenShop:FireClient(player, team)
			end)
		else
			warn("[CarrierService] no shipyard terminal for " .. team)
		end
	end
	Remotes:WaitForChild("BuyCarrier").OnServerInvoke = CarrierService.requestPurchase

	-- команды штурвала: принимаются только от того, кто сидит в кресле своей команды
	Remotes:WaitForChild("ShipControl").OnServerEvent:Connect(function(player, throttle, steer, stop)
		if type(throttle) ~= "number" or type(steer) ~= "number" or throttle ~= throttle or steer ~= steer then return end
		if not Guard.bucket(player, "CarrierControl", 30, 15) then return end -- клиент шлёт до 20/с
		local team = TeamService.getTeamName(player)
		local s = team and states[team]
		if not s or s.state ~= "Active" or s.driver ~= player or not s.ctrl then return end
		s.ctrl.throttle = math.clamp(throttle, -1, 1)
		s.ctrl.steer = math.clamp(steer, -1, 1)
		if stop == true then s.ctrl.setpoint = 0 end
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, s in pairs(states) do
			if s.state == "Active" and s.ctrl then
				step(s, dt)
			end
		end
	end)
end

return CarrierService
