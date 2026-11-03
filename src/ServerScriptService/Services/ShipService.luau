-- Корабли: линкоры (командные, до лимита на команду), катера и подлодки (личные, без лимита).
-- Покупка на верфи, появление у своего причала, управление с мостика, погружение подлодки,
-- урон, потопление: взрыв → крен и медленное погружение → исчезновение под дном.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local CombatService = require(Services.CombatService)
local CarrierService = require(Services.CarrierService)
local TurretService = require(Services.TurretService)
local SinkFx = require(Services.SinkFx)
local Notifier = require(Services.Notifier)
local AbandonTimer = require(Services.AbandonTimer)
local TreasuryService = require(Services.TreasuryService)
local Guard = require(Services.RemoteGuard)
local AntiCheat = require(Services.AntiCheatService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")

local ShipService = {}
local capFail -- объявлена ниже (лимиты техники), используется при покупке
local crewed, selfDestruct -- пустая техника (см. ShipService.remove)
local ships = {}      -- [модель] = состояние (живые и тонущие)
local teamShips = {}  -- [тип][команда] = {active = {модели}, sinking = {модели}, donated = {модели сверх лимита}, busy,
--                      reservedBy, reservedUntil — бронь причала покупателем доната (окно оплаты → выдача)}
local personal = {}   -- [владелец][тип] = {модели}

local function isPlayer(x) return typeof(x) == "Instance" and x:IsA("Player") end
local function moveToward(v, t, step)
	if v < t then return math.min(v + step, t) end
	return math.max(v - step, t)
end
local function fail(msg) return {ok = false, msg = msg} end
local function nameOf(actor)
	if isPlayer(actor) then return actor.DisplayName end
	return actor and (actor:GetAttribute("DisplayName") or actor.Name) or "?"
end

local function folder()
	local f = workspace.Map:FindFirstChild("Vessels")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Vessels"
		f.Parent = workspace.Map
	end
	return f
end

local function serverOwn(root)
	pcall(function()
		if root:CanSetNetworkOwnership() then root:SetNetworkOwner(nil) end
	end)
end

local function prune(list)
	for i = #list, 1, -1 do
		if not list[i].Parent then table.remove(list, i) end
	end
	return list
end

local function slotOf(kind, team)
	return teamShips[kind] and teamShips[kind][team]
end

-- причал забронирован другим покупателем доната (не player) и бронь ещё действует
local function reservedByOther(t, player)
	local by = t and t.reservedBy
	return by ~= nil and by ~= player and by.Parent ~= nil and os.clock() < (t.reservedUntil or 0)
end

local function publishTeam(kind, team)
	local t = slotOf(kind, team)
	if not t then return end
	prune(t.active)
	prune(t.sinking)
	GameState:SetAttribute(("Ship_%s_%s_Active"):format(kind, team), #t.active)
	GameState:SetAttribute(("Ship_%s_%s_Sinking"):format(kind, team), #t.sinking)
	GameState:SetAttribute(("Ship_%s_%s_Limit"):format(kind, team), Config.Ships[kind].TeamLimit or 1)
end

local function publishPersonal(owner)
	if not owner or not owner.Parent then return end
	local p = personal[owner] or {}
	for kind, cfg in pairs(Config.Ships) do
		if not cfg.Team then
			owner:SetAttribute("Owns_" .. kind, #prune(p[kind] or {}))
		end
	end
end

local function berthOf(team, kind)
	local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
	return base and base.Zones:FindFirstChild("Berth_" .. kind)
end

local function berthCF(team, kind)
	local berth = berthOf(team, kind)
	if not berth then return nil end
	local look = berth.CFrame.LookVector
	local pos = Vector3.new(berth.Position.X, 0, berth.Position.Z)
	return CFrame.lookAt(pos, pos - Vector3.new(look.X, 0, look.Z))
end

local function berthFree(cf, size)
	local ov = OverlapParams.new()
	ov.FilterType = Enum.RaycastFilterType.Include
	ov.FilterDescendantsInstances = {folder(), workspace.Map:FindFirstChild("Carriers")}
	return #workspace:GetPartBoundsInBox(cf, size, ov) == 0
end

------------------------------------------------------------------ мель и препятствия
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Include
blockParams.IgnoreWater = true
local hullParams = OverlapParams.new()
hullParams.FilterType = Enum.RaycastFilterType.Include
local SUB_HEIGHT = 25 -- от киля до верха рубки с перископом

-- сколько точек корпуса упираются в мель или препятствие.
-- Погружённая подлодка проходит под кораблями: их проверяем только в объёме её корпуса (от киля до рубки).
local function countBlocked(st, pivotPos, yaw, keelY)
	local submerged = st.cfg.CanDive and (st.depth or 0) > 2
	local list = {workspace.Terrain}
	for _, n in ipairs({"Teams", "Neutral", "Nature"}) do
		local f = workspace.Map:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	local hulls = {}
	local carriers = workspace.Map:FindFirstChild("Carriers")
	if carriers then table.insert(submerged and hulls or list, carriers) end
	for other in pairs(ships) do
		if other ~= st.model and other.Parent then table.insert(submerged and hulls or list, other) end
	end
	blockParams.FilterDescendantsInstances = list
	hullParams.FilterDescendantsInstances = hulls
	local rot = CFrame.Angles(0, yaw, 0)
	local n = 0
	for _, p in ipairs(st.points) do
		local w = pivotPos + rot:VectorToWorldSpace(p)
		local r = workspace:Raycast(Vector3.new(w.X, keelY + 90, w.Z), Vector3.new(0, -180, 0), blockParams)
		local hit = r and r.Position.Y > keelY - 1
		if not hit and submerged and #hulls > 0 then
			hit = #workspace:GetPartBoundsInBox(CFrame.new(w.X, keelY + SUB_HEIGHT / 2, w.Z), Vector3.new(2, SUB_HEIGHT, 2), hullParams) > 0
		end
		if hit then n += 1 end
	end
	return n
end

local function makePoints(cfg)
	local pts = {}
	local half, hb = cfg.Length / 2, cfg.Beam / 2
	local step = math.max(8, cfg.Length / 8)
	for z = -half + 4, half - 6, step do
		table.insert(pts, Vector3.new(hb, 0, z))
		table.insert(pts, Vector3.new(-hb, 0, z))
	end
	table.insert(pts, Vector3.new(0, 0, half))
	return pts
end

------------------------------------------------------------------ экипаж
local function releaseDriver(st)
	local prevHum = st.driverHum
	st.driver, st.driverHum = nil, nil
	st.throttle, st.steer, st.vertical = 0, 0, 0
	st.model:SetAttribute("Driver", "")
	if st.aimTurret then TurretService.clearGunner(st.aimTurret) end
	if isPlayer(st.owner) and st.boardPrompt then st.boardPrompt.Enabled = true end
	st.abandonT = os.clock()
	local exit = st.model:FindFirstChild("HelmExit")
	if prevHum and prevHum.Parent and prevHum.Health > 0 then
		task.delay(0.15, function()
			if prevHum.Parent and not prevHum.SeatPart then
				local cf = exit and exit.CFrame or (st.root.CFrame * CFrame.new(st.cfg.Beam / 2 + 3, 6, 0))
				prevHum.Parent:PivotTo(cf + Vector3.new(0, 3, 0))
			end
		end)
	end
end

local function canDrive(st, actor)
	if not actor or actor:GetAttribute("State") ~= "Deployed" then return false end
	if TeamService.getTeamName(actor) ~= st.team then return false end
	-- личный корабль игрока может взять любой игрок его команды (пока штурвал свободен);
	-- бот водит только свой
	if not st.cfg.Team and actor ~= st.owner and not (isPlayer(actor) and isPlayer(st.owner)) then return false end
	return true
end

local function sitAt(seat, player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.SeatPart then return end
	AntiCheat.grace(player)
	char:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
	seat:Sit(hum)
end

local function setupHelm(st)
	local m = st.model
	local seat = m:FindFirstChild("HelmSeat")
	st.seat = seat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if st.dead then return end
		local hum = seat.Occupant
		if not hum then
			if st.driverHum then releaseDriver(st) end
			return
		end
		local char = hum.Parent
		local actor = Players:GetPlayerFromCharacter(char) or (char:GetAttribute("IsBot") and char) or nil
		if not canDrive(st, actor) then
			local w = seat:FindFirstChild("SeatWeld")
			if w then w:Destroy() end
			return
		end
		st.driver, st.driverHum, st.abandonT = actor, hum, nil
		m:SetAttribute("Driver", nameOf(actor))
		if st.boardPrompt then st.boardPrompt.Enabled = false end
		if st.aimTurret then TurretService.assignGunner(st.aimTurret, actor, hum, seat) end
		serverOwn(st.root)
	end)
	-- вход: у линкора — пульт «Мостик»; у личных — кнопка на корпусе для владельца
	local access = m:FindFirstChild("HelmAccess")
	local prompt = access and access:FindFirstChild("HelmPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BoardPrompt"
		prompt.ActionText = "Take the helm"
		prompt.ObjectText = st.cfg.DisplayName
		prompt.HoldDuration = 0.25
		prompt.MaxActivationDistance = 18
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = st.root
		st.boardPrompt = prompt
	end
	prompt.Triggered:Connect(function(player)
		if st.dead or not AntiCheat.atPrompt(player, prompt) then return end
		if TeamService.getTeamName(player) ~= st.team then
			Notifier.send(player, "This is an enemy ship", "error")
			return
		end
		if not st.cfg.Team and player ~= st.owner and not isPlayer(st.owner) then
			Notifier.send(player, "This is someone else's ship", "error")
			return
		end
		if seat.Occupant then
			if seat.Occupant.Parent and seat.Occupant.Parent:GetAttribute("IsBot") then
				local w = seat:FindFirstChild("SeatWeld")
				if w then w:Destroy() end
				task.wait(0.1)
			else
				Notifier.send(player, "There is already a captain at the helm", "error")
				return
			end
		end
		-- после ожидания всё могло измениться: корабль потоплен, место занято, игрок ушёл
		if st.dead or seat.Occupant or player:GetAttribute("State") ~= "Deployed" then return end
		if TeamService.getTeamName(player) ~= st.team then return end
		sitAt(seat, player)
	end)
end

------------------------------------------------------------------ появление
-- donor — игрок, купивший командный корабль за донат: корабль вне TeamLimit (список donated)
local function spawnShip(kind, team, owner, donor)
	local cfg = Config.Ships[kind]
	local cf = berthCF(team, kind)
	assert(cf, "missing berth Berth_" .. kind)

	local m = ServerStorage.Ships[kind]:Clone()
	m.Name = ("%s_%s%s"):format(kind, team, owner and ("_" .. owner.Name) or "")
	local tcol = Config.Teams[team].Color
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("TeamPaint") then d.Color = tcol end
	end
	m:SetAttribute("IsVessel", true)
	m:SetAttribute("Team", team)
	m:SetAttribute("ShipType", kind)
	m:SetAttribute("DisplayName", cfg.DisplayName)
	m:SetAttribute("MaxSpeed", cfg.MaxSpeed)
	m:SetAttribute("MaxReverseSpeed", cfg.MaxReverseSpeed)
	m:SetAttribute("CanDive", cfg.CanDive == true)
	m:SetAttribute("Health", cfg.MaxHealth)
	m:SetAttribute("MaxHealth", cfg.MaxHealth)
	m:SetAttribute("Speed", 0)
	m:SetAttribute("Setpoint", 0)
	m:SetAttribute("Depth", 0)
	m:SetAttribute("Driver", "")
	if owner and owner:IsA("Player") then m:SetAttribute("OwnerId", owner.UserId) end
	m:PivotTo(cf)
	m.Parent = folder()

	local root = m.Hull
	serverOwn(root)
	local _, yaw = cf:ToOrientation()
	local st = {
		model = m, kind = kind, cfg = cfg, team = team, owner = owner, root = root,
		ao = root.HelmAlign, lv = root.HelmDrive, pivotPart = m:FindFirstChild("Pivot"),
		yaw = yaw, rootY0 = root.Position.Y, keelBelowRoot = root.Position.Y + cfg.Draft,
		speed = 0, setpoint = 0, throttle = 0, steer = 0, vertical = 0, depth = 0,
		health = cfg.MaxHealth, points = makePoints(cfg), pub = 0,
		-- если в новый корабль так никто и не сел — тот же таймер пустой техники (+30 с на дорогу до мостика)
		abandonT = os.clock() + 30,
	}
	st.ao.CFrame = CFrame.Angles(0, yaw, 0)
	local seatAttr = m:FindFirstChild("HelmSeat") and m.HelmSeat:GetAttribute("AimTurret")
	if seatAttr then st.aimTurret = m:FindFirstChild(seatAttr) end
	ships[m] = st
	TurretService.attachShip(m)
	setupHelm(st)
	-- трапы: из воды на палубу (подняться может любой — в т.ч. абордаж)
	for _, plat in ipairs(m:GetChildren()) do
		local pr = plat.Name == "LadderPlatform" and plat:FindFirstChild("BoardPrompt")
		local target = plat:GetAttribute("DeckTarget")
		if pr and target then
			AntiCheat.ladder(pr, plat, 18, function() return m:GetPivot() * CFrame.new(target), plat end,
				function() return not st.dead end)
		end
	end
	if cfg.Team and donor then
		st.donor = donor
		m:SetAttribute("Donated", true)
		table.insert(slotOf(kind, team).donated, m)
	elseif cfg.Team then
		table.insert(slotOf(kind, team).active, m)
		publishTeam(kind, team)
	elseif owner then
		personal[owner] = personal[owner] or {}
		personal[owner][kind] = personal[owner][kind] or {}
		table.insert(personal[owner][kind], m)
		publishPersonal(owner)
	end
	return m, st
end

------------------------------------------------------------------ покупка
local teamBuyT = {} -- [UserId] = os.clock() последней покупки командного корабля из казны (переживает перезаход)

function ShipService.requestPurchase(player, kind)
	local cfg = Config.Ships[kind]
	if not cfg then return fail("Unknown ship") end
	if not Guard.allow(player, "BuyShip") then return fail("Too many requests, please wait") end
	local team = TeamService.getTeamName(player)
	if not team or player:GetAttribute("State") ~= "Deployed" then return fail("Choose a team and deploy first") end
	local term = workspace.Map.Teams[team .. "Base"].Shipyard:FindFirstChild("ShipTerminal")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not term or not hrp or not hum or hum.Health <= 0 or (hrp.Position - term.Position).Magnitude > Config.Carrier.TerminalMaxDistance then
		return fail("Go to your team's shipyard terminal")
	end

	local tslot
	if cfg.Team then
		local vip = player:GetAttribute("VIP") == true
		local rank = player:GetAttribute("Rank") or 1
		if cfg.MinRank and not vip and rank < cfg.MinRank then
			local need = Config.Ranks.List[cfg.MinRank]
			return fail(("%s from the treasury: %s rank or VIP required"):format(cfg.DisplayName, need and need.Name or ("rank " .. cfg.MinRank)))
		end
		local last = teamBuyT[player.UserId]
		if cfg.BuyCooldown and last and os.clock() - last < cfg.BuyCooldown then
			return fail(("You can buy another %s from the treasury in %d s"):format(cfg.DisplayName:lower(), math.ceil(cfg.BuyCooldown - (os.clock() - last))))
		end
		tslot = slotOf(kind, team)
		if tslot.busy then return fail("Purchase already in progress") end
		if reservedByOther(tslot, player) then return fail("The berth is reserved for a bonus ship being purchased — try again in a minute") end
		local limit = cfg.TeamLimit or 1
		local n = #prune(tslot.active) + #prune(tslot.sinking)
		if n >= limit then
			if #tslot.sinking > 0 and #tslot.active < limit then
				return fail(("%s is still sinking — wait until it goes down"):format(cfg.DisplayName))
			end
			return fail(("Team limit: %d %s"):format(limit, cfg.DisplayName:lower()))
		end
	end

	if not cfg.Team then
		local why = capFail(kind, team, player)
		if why then return fail(why) end
	end
	local cf = berthCF(team, kind)
	if not cf or not berthFree(cf, Vector3.new(cfg.Beam + 4, 20, cfg.Length + 6)) then
		return fail("Berth occupied — wait for the ship to leave")
	end

	if tslot then
		-- командный корабль — из казны
		tslot.busy = true
		if not TreasuryService.spend(team, cfg.Price) then
			tslot.busy = false
			return fail(("Team treasury has %d of %d — capture islands, their cargo ships fill the treasury"):format(TreasuryService.get(team), cfg.Price))
		end
	else
		local paid, why = DataService.spendGold(player, cfg.Price)
		if not paid then
			if why == "NotEnough" then
				return fail(("Not enough gold: need %d, you have %d"):format(cfg.Price, DataService.get(player, "Gold") or 0))
			elseif why == "Syncing" then
				return fail("Your saved data is still loading — purchases are paused for a moment")
			end
			return fail("Player data not loaded yet")
		end
	end

	local ok, model, st = pcall(spawnShip, kind, team, not cfg.Team and player or nil)
	if tslot then tslot.busy = false end
	if not ok then
		if cfg.Team then TreasuryService.refund(team, cfg.Price) else DataService.addGold(player, cfg.Price, true) end -- возврат, без VIP
		warn("[ShipService] " .. tostring(model))
		return fail("Construction failed, money refunded")
	end
	if cfg.Team then
		teamBuyT[player.UserId] = os.clock()
		Notifier.team(team, ("%s bought a %s from the treasury (−%d)! Captain to the bridge, gunners to the turrets."):format(player.DisplayName, cfg.DisplayName:lower(), cfg.Price), "success")
	else
		task.spawn(DataService.save, player)
	end
	if cfg.Team then
	else
		sitAt(st.seat, player) -- личный корабль: сразу за штурвал
	end
	return {ok = true, msg = cfg.DisplayName .. " is at the berth, ready to sail"}
end

------------------------------------------------------------------ донат (DonateShipService)
local function donatedBy(kind, team, player)
	local n = 0
	for _, m in ipairs(prune(slotOf(kind, team).donated)) do
		local st = ships[m]
		if st and not st.dead and st.donor == player then n += 1 end
	end
	return n
end

-- можно ли сейчас выдать донатный командный корабль: nil — да, иначе причина
function ShipService.donateFail(kind, team, player)
	local cfg, dc = Config.Ships[kind], Config.DonateShips and Config.DonateShips[kind]
	local t = cfg and cfg.Team and dc and slotOf(kind, team)
	if not t then return "Unknown ship" end
	if reservedByOther(t, player) then
		return ("Another player is buying a bonus %s right now — try again in a minute"):format(cfg.DisplayName:lower())
	end
	if #prune(t.donated) >= (dc.ExtraPerTeam or 1) then
		return ("Your team already has %d bonus %ss afloat — try later"):format(dc.ExtraPerTeam or 1, cfg.DisplayName:lower())
	end
	if donatedBy(kind, team, player) >= (dc.PerPlayer or 1) then
		return ("Your %s is still afloat"):format(cfg.DisplayName:lower())
	end
	local cf = berthCF(team, kind)
	if not cf or not berthFree(cf, Vector3.new(cfg.Beam + 4, 20, cfg.Length + 6)) then
		return "Berth occupied — wait a few seconds for the ship to leave"
	end
	return nil
end

-- спустить донатный корабль у верфи team: модель, состояние (st.seat — штурвал) или nil, причина
function ShipService.donateSpawn(player, kind, team)
	local why = ShipService.donateFail(kind, team, player)
	if why then return nil, why end
	local ok, model, st = pcall(spawnShip, kind, team, nil, player)
	if not ok then
		warn("[ShipService] " .. tostring(model))
		return nil, "Construction failed"
	end
	ShipService.releaseDonate(kind, team, player)
	Notifier.team(team, ("%s launched a bonus %s! Gunners to the turrets."):format(player.DisplayName, Config.Ships[kind].DisplayName:lower()), "success")
	return model, st
end

-- забронировать причал для доната на seconds (или продлить свою бронь); false — занят другим
function ShipService.reserveDonate(kind, team, player, seconds)
	local t = slotOf(kind, team)
	if not t or reservedByOther(t, player) then return false end
	t.reservedBy, t.reservedUntil = player, os.clock() + seconds
	return true
end

function ShipService.releaseDonate(kind, team, player)
	local t = slotOf(kind, team)
	if t and t.reservedBy == player then t.reservedBy, t.reservedUntil = nil, 0 end
end

-- живые корабли типа kind у команды / личные корабли владельца
function ShipService.teamCount(kind, team)
	local n = 0
	for _, st in pairs(ships) do
		if not st.dead and st.kind == kind and st.team == team then n += 1 end
	end
	return n
end
local function ownedCount(owner)
	local n = 0
	for _, st in pairs(ships) do
		if not st.dead and st.owner == owner and not st.cfg.Team then n += 1 end
	end
	return n
end
local TEAM_CAP = {Gunboat = "GunboatsPerTeam", Submarine = "SubmarinesPerTeam"}
capFail = function(kind, team, owner)
	local L = Config.Limits or {}
	local key = TEAM_CAP[kind]
	if key and L[key] and ShipService.teamCount(kind, team) >= L[key] then
		return ("Team limit: %d × %s"):format(L[key], Config.Ships[kind].DisplayName:lower())
	end
	if owner and L.PersonalShipsPerPlayer and ownedCount(owner) >= L.PersonalShipsPerPlayer then
		return ("You already have %d personal ships afloat — that's the limit"):format(L.PersonalShipsPerPlayer)
	end
	return nil
end

------------------------------------------------------------------ урон и потопление
local function forget(st)
	ships[st.model] = nil
	if st.cfg.Team then
		local t = slotOf(st.kind, st.team)
		if t then
			for _, list in ipairs({t.active, t.sinking, t.donated}) do
				for i = #list, 1, -1 do
					if list[i] == st.model then table.remove(list, i) end
				end
			end
			publishTeam(st.kind, st.team)
		end
	elseif st.owner and personal[st.owner] and personal[st.owner][st.kind] then
		local list = personal[st.owner][st.kind]
		for i = #list, 1, -1 do
			if list[i] == st.model then table.remove(list, i) end
		end
		if isPlayer(st.owner) then
			publishPersonal(st.owner)
		else
			-- бот: каждый респаун — новая модель; пустую запись убираем, иначе они копятся часами
			local empty = true
			for _, l in pairs(personal[st.owner]) do
				if #l > 0 then empty = false break end
			end
			if empty then personal[st.owner] = nil end
		end
	end
end

-- убрать сразу (без потопления): брошенный корабль, выход владельца
function ShipService.remove(model)
	local st = ships[model]
	if st then
		st.dead = true
		forget(st)
	end
	model:Destroy()
end

-- кто-то сидит в корабле (у орудия, на любом месте)
function crewed(model)
	for _, s in ipairs(model:GetDescendants()) do
		if (s:IsA("Seat") or s:IsA("VehicleSeat")) and s.Occupant then return true end
	end
	return false
end

-- пустой корабль самоуничтожается: взрыв без урона, без наград и без «тонет» (место в лимите сразу свободно)
function selfDestruct(st)
	local e = Instance.new("Explosion")
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.BlastRadius = math.max(12, (st.cfg.Beam or 10))
	e.Position = st.root.Position
	e.Parent = workspace
	if isPlayer(st.owner) and st.owner.Parent then
		Notifier.send(st.owner, ("Your %s self-destructed: nobody aboard for %d s"):format(st.cfg.DisplayName:lower(), Config.ShipAbandonDespawn or 120), "info")
	end
	ShipService.remove(st.model)
end

local function sink(st, killer)
	if st.dead then return end
	st.dead = true
	-- корабль игрока (личный или с игроком за штурвалом) — полная награда; иначе как за бота.
	-- Запоминаем до того, как экипаж снимается с мест.
	local humanShip = isPlayer(st.owner) or isPlayer(st.driver)
	local m = st.model
	m:SetAttribute("IsVessel", false)
	m:SetAttribute("Sinking", true)
	-- экипаж гибнет вместе с кораблём
	for _, s in ipairs(m:GetDescendants()) do
		if s:IsA("Seat") and s.Occupant then
			local char = s.Occupant.Parent
			local actor = Players:GetPlayerFromCharacter(char) or (char:GetAttribute("IsBot") and char) or nil
			local w = s:FindFirstChild("SeatWeld")
			if w then w:Destroy() end
			if actor then CombatService.creditKill(killer, actor) end
		end
	end
	if st.aimTurret then TurretService.clearGunner(st.aimTurret) end
	-- командный корабль: из «на воде» в «тонет» (пока тонет — новый не купить)
	if st.cfg.Team then
		local t = slotOf(st.kind, st.team)
		for i = #t.active, 1, -1 do
			if t.active[i] == m then table.remove(t.active, i) end
		end
		-- донатный линкор вне лимита: тонущий не мешает покупке на верфи
		if not st.donor then table.insert(t.sinking, m) end
		publishTeam(st.kind, st.team)
		Notifier.team(st.team, ("Your %s was sunk!"):format(st.cfg.DisplayName:lower()), "error")
	elseif st.owner then
		Notifier.send(st.owner, ("Your %s was sunk!"):format(st.cfg.DisplayName:lower()), "error")
	end
	local kt = killer and TeamService.getTeamName(killer)
	if kt and kt ~= st.team and st.kind == "Battleship" then
		TreasuryService.add(kt, Config.Treasury.BattleshipSinkBonus or 0, "enemy battleship sunk")
	end
	if killer and isPlayer(killer) and kt ~= st.team then
		local R = Config.Economy.Rewards or {}
		local tbl = humanShip and R.ShipSink or R.BotShipSink
		local reward = (tbl and tbl[st.kind]) or math.floor((st.cfg.Price or 0) * 0.5)
		if reward > 0 then
			DataService.addGold(killer, reward)
			Notifier.send(killer, ("Enemy %s sunk! +%d gold"):format(st.cfg.DisplayName, reward), "success")
		end
		require(script.Parent.RankService).award(killer, "Sink", humanShip and 1 or 0.5, st.kind)
	end

	task.spawn(function()
		-- взрывы, крен на борт и медленное погружение (сквозь дно — без столкновений)
		local big = st.cfg.Team
		if not SinkFx.run(m, {explosions = big and 5 or 3, radius = big and 22 or 14, width = st.cfg.Beam, length = st.cfg.Length * 0.8,
			ao = st.ao, lv = st.lv, root = st.root, yaw = st.yaw, pitch = 10, roll = 22, speed = 3.5, floor = -95, timeout = 50,
			noCollide = true}) then return end
		forget(st)
		if m.Parent then m:Destroy() end
		if st.cfg.Team then
			Notifier.team(st.team, ("%s has sunk — the shipyard can build a new one"):format(st.cfg.DisplayName), "info")
		end
	end)
end

function ShipService.damage(model, amount, attacker)
	local st = ships[model]
	if not st or st.dead then return end
	local at = attacker and TeamService.getTeamName(attacker)
	if at and at == st.team and not Config.Combat.FriendlyFire then return end
	st.health = math.max(0, st.health - amount)
	model:SetAttribute("Health", math.floor(st.health))
	if st.health <= 0 then sink(st, attacker) end
end

------------------------------------------------------------------ движение
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.IgnoreWater = true

local function step(st, dt)
	local cfg = st.cfg
	if st.driverHum and (st.driverHum.Health <= 0 or st.driverHum.SeatPart ~= st.seat) then
		if st.driverHum.Health <= 0 then
			local w = st.seat:FindFirstChild("SeatWeld")
			if w then w:Destroy() end
		end
		releaseDriver(st)
	end

	-- подлодка: воздух тратится только глубже перископной, восполняется на поверхности
	local maxSpeed = cfg.MaxSpeed
	if cfg.CanDive then
		local airMax = cfg.Air or 90
		st.air = st.air or airMax
		if st.depth > (cfg.PeriscopeDepth or 8) then
			st.air = math.max(0, st.air - dt)
		elseif st.depth < 1 then
			st.air = math.min(airMax, st.air + dt * (cfg.AirRefillRate or 3))
		end
		if st.air <= 0 and not st.forceSurface then
			st.forceSurface = true
			if st.driver and st.driver:IsA("Player") then Notifier.send(st.driver, "Out of air — emergency surfacing!", "error") end
		elseif st.forceSurface and st.air >= airMax * 0.25 then
			st.forceSurface = false
		end
		if st.forceSurface then st.vertical = 1 end
		if st.depth > 4 then maxSpeed = cfg.SubmergedSpeed or cfg.MaxSpeed end
		st.setpoint = math.min(st.setpoint, maxSpeed)
	end

	if st.driver then
		if st.throttle ~= 0 then
			st.setpoint = math.clamp(st.setpoint + st.throttle * cfg.Acceleration * dt, -cfg.MaxReverseSpeed, maxSpeed)
		end
	else
		st.setpoint = moveToward(st.setpoint, 0, cfg.Acceleration * dt)
	end
	st.speed = moveToward(st.speed, st.setpoint, cfg.Acceleration * dt)

	local prevYaw = st.yaw
	local newYaw = st.yaw
	if st.driver and st.steer ~= 0 then
		local factor = math.max(cfg.MinTurnFactor, math.abs(st.speed) / cfg.MaxSpeed)
		newYaw = st.yaw - st.steer * math.rad(cfg.TurnRate) * factor * dt
	end
	local function fwdOf(y) return CFrame.Angles(0, y, 0):VectorToWorldSpace(Vector3.zAxis) end

	local root = st.root
	local pos = root.Position
	local pivotPos = st.pivotPart and st.pivotPart.Position or pos

	-- глубина (подлодка)
	local targetY = st.rootY0
	if cfg.CanDive then
		if (st.driver or st.forceSurface) and st.vertical ~= 0 then
			st.depth = math.clamp(st.depth - st.vertical * cfg.DiveRate * dt, 0, cfg.DiveDepth)
		end
		-- не ниже дна
		floorParams.FilterDescendantsInstances = {workspace.Terrain, workspace.Map:FindFirstChild("Seabed")}
		local fl = workspace:Raycast(pos, Vector3.new(0, -200, 0), floorParams)
		local floorY = fl and fl.Position.Y or -88
		local maxDepth = math.max(0, st.rootY0 - (floorY + (st.keelBelowRoot - st.rootY0) + 4))
		st.depth = math.min(st.depth, maxDepth)
		targetY = st.rootY0 - st.depth
	end
	local keelY = pos.Y - (st.keelBelowRoot - st.rootY0)

	local vel = fwdOf(newYaw) * st.speed
	local ahead = pos + vel * 3
	if (math.abs(ahead.X) > Config.Carrier.BoundsX and ahead.X * vel.X > 0) or (math.abs(ahead.Z) > Config.Carrier.BoundsZ and ahead.Z * vel.Z > 0) then
		st.speed, st.setpoint = 0, 0
		vel = Vector3.zero
	end

	if vel.Magnitude > 0.05 or newYaw ~= prevYaw then
		local cur = countBlocked(st, pivotPos, prevYaw, keelY)
		local look = vel.Magnitude > 0.05 and vel.Unit * math.max(6, math.abs(st.speed) * 0.6) or Vector3.zero
		local nxt = countBlocked(st, pivotPos + look, newYaw, keelY)
		if nxt > 0 and nxt >= cur then
			local straightOk = false
			if newYaw ~= prevYaw and vel.Magnitude > 0.05 then
				local v2 = fwdOf(prevYaw) * st.speed
				local s2 = countBlocked(st, pivotPos + v2.Unit * math.max(6, math.abs(st.speed) * 0.6), prevYaw, keelY)
				if s2 == 0 or s2 < cur then
					straightOk, newYaw, vel = true, prevYaw, v2
				end
			end
			if not straightOk then
				local rotOnly = newYaw ~= prevYaw and countBlocked(st, pivotPos, newYaw, keelY) or math.huge
				if rotOnly > 0 and rotOnly >= cur then newYaw = prevYaw end
				st.speed, st.setpoint = 0, 0
				vel = Vector3.zero
				if st.driver and os.clock() - (st.groundNote or 0) > 4 then
					st.groundNote = os.clock()
					Notifier.send(st.driver, "Shallows or obstacle! Reverse or turn away.", "error")
				end
			end
		end
	end
	st.yaw = newYaw
	local vyMax = cfg.CanDive and cfg.DiveRate * 1.5 or 20
	local vy = math.clamp((targetY - pos.Y) * (cfg.CanDive and 1.5 or 4), -vyMax, vyMax)
	st.lv.VectorVelocity = vel + Vector3.new(0, vy, 0)
	st.ao.CFrame = CFrame.Angles(0, st.yaw, 0)

	st.pub += dt
	if st.pub >= 0.2 then
		st.pub = 0
		st.model:SetAttribute("Speed", math.floor(st.speed + 0.5))
		st.model:SetAttribute("Setpoint", math.floor(st.setpoint + 0.5))
		if cfg.CanDive then
			st.model:SetAttribute("Depth", math.floor(st.depth + 0.5))
			st.model:SetAttribute("Air", math.floor((st.air or 0) / (cfg.Air or 90) * 100 + 0.5))
		end
	end
end

------------------------------------------------------------------ для ботов
-- командный корабль от бота-командира, бесплатно — казну игроков боты не тратят
-- (если на воде нет ни одного; BotService зовёт только для команды без живых игроков)
function ShipService.botPurchase(kind, team)
	local cfg = Config.Ships[kind]
	local t = cfg and cfg.Team and slotOf(kind, team)
	if not t or t.busy or reservedByOther(t, nil) then return false end
	if #prune(t.active) + #prune(t.sinking) >= (cfg.TeamLimit or 1) then return false end
	local cf = berthCF(team, kind)
	if not cf or not berthFree(cf, Vector3.new(cfg.Beam + 4, 20, cfg.Length + 6)) then return false end
	t.busy = true
	local ok, model = pcall(spawnShip, kind, team, nil)
	t.busy = false
	if not ok then
		warn("[ShipService] " .. tostring(model))
		return false
	end
	Notifier.team(team, ("Bot commander launched a %s"):format(cfg.DisplayName:lower()), "success")
	return true
end

-- личный корабль бота: появляется у причала, бот сразу за штурвалом
function ShipService.botSpawnPersonal(bot, team, kind)
	local cfg = Config.Ships[kind]
	if not cfg or cfg.Team then return nil end
	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	if capFail(kind, team, nil) then return nil end
	local cf = berthCF(team, kind)
	if not cf or not berthFree(cf, Vector3.new(cfg.Beam + 4, 20, cfg.Length + 6)) then return nil end
	local ok, model, st = pcall(spawnShip, kind, team, bot)
	if not ok then
		warn("[ShipService] " .. tostring(model))
		return nil
	end
	bot:PivotTo(st.seat.CFrame + Vector3.new(0, 3, 0))
	st.seat:Sit(hum)
	return model
end

-- первый живой командный корабль (для ботов-экипажа)
function ShipService.teamShip(kind, team)
	local t = slotOf(kind, team)
	if not t then return nil end
	for _, m in ipairs(prune(t.active)) do
		local st = ships[m]
		if st and not st.dead then return m end
	end
	return nil
end

-- "None" — на воде и на дне пусто, можно спускать новый
function ShipService.teamShipState(kind, team)
	local t = slotOf(kind, team)
	if not t then return "None" end
	if #prune(t.active) > 0 then return "Active" end
	if #prune(t.sinking) > 0 then return "Sinking" end
	return "None"
end

function ShipService.botDrive(model, bot, throttle, steer, vertical)
	local st = ships[model]
	if not st or st.dead or st.driver ~= bot then return end
	st.throttle = math.clamp(throttle, -1, 1)
	st.steer = math.clamp(steer, -1, 1)
	st.vertical = math.clamp(vertical or 0, -1, 1)
end

function ShipService.getState(model)
	return ships[model]
end

function ShipService.getAll()
	return ships
end

-- командные корабли (из казны, не за донат), которые уберёт новый раунд — живые и тонущие
function ShipService.roundResetModels()
	local list = {}
	for m, st in pairs(ships) do
		if st.cfg.Team and not st.donor then table.insert(list, m) end
	end
	return list
end

-- новый раунд: командные корабли из казны убираем сразу (без взрывов и наград). Донатные остаются.
-- Игроков с палубы RoundService уже перенёс на базу.
function ShipService.resetTeamShips()
	for m, st in pairs(ships) do
		if st.cfg.Team and not st.donor then
			st.dead = true
			if st.aimTurret then TurretService.clearGunner(st.aimTurret) end
			forget(st)
			if m.Parent then m:Destroy() end
		end
	end
end

function ShipService.init()
	for kind, cfg in pairs(Config.Ships) do
		if cfg.Team then
			teamShips[kind] = {}
			for _, team in ipairs(Config.TeamOrder) do
				teamShips[kind][team] = {active = {}, sinking = {}, donated = {}, busy = false}
				publishTeam(kind, team)
			end
		end
	end
	CombatService.onVesselHit = ShipService.damage

	Remotes:WaitForChild("BuyShip").OnServerInvoke = function(player, kind)
		if kind == "Carrier" then return CarrierService.requestPurchase(player) end
		if type(kind) ~= "string" then return fail("Unknown ship") end
		return ShipService.requestPurchase(player, kind)
	end

	Remotes:WaitForChild("ShipControl").OnServerEvent:Connect(function(player, throttle, steer, stop, vertical)
		if type(throttle) ~= "number" or type(steer) ~= "number" or throttle ~= throttle or steer ~= steer then return end
		if not Guard.bucket(player, "ShipControl", 30, 15) then return end -- клиент шлёт до 20/с
		for _, st in pairs(ships) do
			if st.driver == player and not st.dead then
				st.throttle = math.clamp(throttle, -1, 1)
				st.steer = math.clamp(steer, -1, 1)
				if type(vertical) == "number" and vertical == vertical then st.vertical = math.clamp(vertical, -1, 1) end
				if stop == true then st.setpoint = 0 end
				return
			end
		end
	end)

	Players.PlayerAdded:Connect(publishPersonal)
	Players.PlayerRemoving:Connect(function(p)
		for _, list in pairs(personal[p] or {}) do
			for _, model in ipairs(list) do
				local st = ships[model]
				-- корабль уже ведёт другой игрок — оставляем ему (исчезнет, когда опустеет)
				if model.Parent and st and not st.dead and not (st.driver and st.driver ~= p) then ShipService.remove(model) end
			end
		end
		personal[p] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for model, st in pairs(ships) do
			if not model.Parent then
				forget(st)
			elseif not st.dead then
				step(st, dt)
				-- в корабле никого (ни у штурвала, ни у орудий) дольше ShipAbandonDespawn — самоуничтожение:
				-- освобождает место в лимите команды и разгружает сервер. Перед этим владельцу — предупреждения
				-- (AbandonTimer), поэтому экипаж у орудий проверяем заранее (раз в секунду, когда пора предупреждать)
				local despawn = Config.ShipAbandonDespawn or 120
				if not st.driver and st.abandonT and now - st.abandonT > despawn - Config.AbandonWarn[1] - 1
					and now - (st.crewCheckT or 0) > 1 then
					st.crewCheckT = now
					if crewed(model) then st.abandonT = now end
				end
				AbandonTimer.check(st, st.cfg.DisplayName:lower(), despawn, now)
				if not st.driver and st.abandonT and now - st.abandonT > despawn then
					if crewed(model) then
						st.abandonT = now
					else
						selfDestruct(st)
					end
				end
			end
		end
	end)
end

return ShipService
