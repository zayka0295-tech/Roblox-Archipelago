-- Турели и башни: зенитки на базах и авианосцах (пули), главный калибр линкора и пушка катера (снаряды).
-- Занять, навести, стрелять — решает сервер. Тип оружия — атрибут WeaponType модели башни.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local CombatService = require(Services.CombatService)
local ProjectileService = require(Services.ProjectileService)
local Notifier = require(Services.Notifier)
local AntiCheat = require(Services.AntiCheatService)
local Guard = require(Services.RemoteGuard)

local TC = Config.Combat.Turret
local TurretService = {}
local turrets = {} -- [модель турели] = состояние

local function teamOf(st)
	if st.owner then return st.owner:GetAttribute("Team") end
	return st.model:GetAttribute("Team")
end

local function charOf(actor)
	if not actor then return nil end
	return actor:IsA("Player") and actor.Character or actor
end

local function eject(st)
	local weld = st.seat and st.seat:FindFirstChild("SeatWeld")
	if weld then weld:Destroy() end
end

-- параметры оружия: зенитка (пули) или снарядное орудие
local function weaponOf(model)
	local wt = model:GetAttribute("WeaponType")
	local W = wt and Config.Weapons and Config.Weapons[wt]
	if W then
		return W, true
	end
	return {TurnSpeed = TC.TurnSpeed, MinPitch = TC.MinPitch, MaxPitch = TC.MaxPitch, Cooldown = TC.Cooldown}, false
end

-- owner: корабль, на котором стоит башня (nil — зенитка базы)
local function setup(model, owner)
	if turrets[model] then return end
	local seat = model:FindFirstChild("TurretSeat")
	local pivot = model:FindFirstChild("TurretPivot")
	local yoke = model:FindFirstChild("Yoke")
	local gun = model:FindFirstChild("GunBody")
	local prompt = model:FindFirstChild("Pedestal") and model.Pedestal:FindFirstChild("TurretPrompt")
	if not (pivot and yoke and gun) then
		warn("[TurretService] incomplete turret " .. model:GetFullName())
		return
	end
	local yawM, pitchM = pivot:FindFirstChild("YawMotor"), yoke:FindFirstChild("PitchMotor")
	local W, projectile = weaponOf(model)
	local muzzles = {}
	for _, n in ipairs({"Muzzle", "Muzzle2", "Muzzle3"}) do
		local mz = model:FindFirstChild(n)
		if mz then table.insert(muzzles, mz) end
	end
	local st = {
		model = model, owner = owner, seat = seat, pivot = pivot, gun = gun,
		yawM = yawM, pitchM = pitchM,
		yawBase = yawM and yawM.C0.Position or Vector3.new(0, 1, 0),
		pitchBase = pitchM and pitchM.C0.Position or Vector3.new(0, 3.5, 0),
		W = W, projectile = projectile, muzzles = muzzles,
		exit = model:FindFirstChild("TurretExit"),
		yaw = 0, pitch = math.rad(projectile and 0 or 10), tYaw = 0, tPitch = math.rad(projectile and 0 or 10),
		firing = false, lastShot = 0, shotN = 0, gunner = nil, gunnerHum = nil,
	}
	turrets[model] = st

	if seat and prompt then
		prompt.Triggered:Connect(function(player)
			if not AntiCheat.atPrompt(player, prompt) then return end
			if TeamService.getTeamName(player) ~= teamOf(st) then
				Notifier.send(player, "This is an enemy gun", "error")
				return
			end
			if seat.Occupant then
				-- бот уступает место игроку
				if seat.Occupant.Parent and seat.Occupant.Parent:GetAttribute("IsBot") then
					local w = seat:FindFirstChild("SeatWeld")
					if w then w:Destroy() end
					task.wait(0.1)
				else
					Notifier.send(player, "Seat already taken", "error")
					return
				end
			end
			-- за время ожидания корабль с башней могли потопить/убрать — не переносим к удалённому креслу
			if seat.Occupant or not seat:IsDescendantOf(workspace) or TeamService.getTeamName(player) ~= teamOf(st) then return end
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 or hum.SeatPart or player:GetAttribute("State") ~= "Deployed" then return end
			AntiCheat.grace(player)
			char:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
			seat:Sit(hum)
		end)

		local function onOccupant()
			local hum = seat.Occupant
			if hum then
				local player = Players:GetPlayerFromCharacter(hum.Parent) or (hum.Parent:GetAttribute("IsBot") and hum.Parent) or nil
				if not player or TeamService.getTeamName(player) ~= teamOf(st) or player:GetAttribute("State") ~= "Deployed" then
					eject(st)
					return
				end
				st.gunner, st.gunnerHum = player, hum
				local hull = owner and owner:FindFirstChild("Hull")
				if hull then
					pcall(function()
						if hull:CanSetNetworkOwnership() then hull:SetNetworkOwner(nil) end
					end)
				end
			else
				local prev = st.gunnerHum
				st.gunner, st.gunnerHum, st.firing = nil, nil, false
				if prev and prev.Parent and prev.Health > 0 and st.exit then
					task.delay(0.15, function()
						if prev.Parent and not prev.SeatPart and st.exit.Parent then
							prev.Parent:PivotTo(st.exit.CFrame + Vector3.new(0, 3, 0))
						end
					end)
				end
			end
		end
		st.onOccupant = onOccupant
		seat:GetPropertyChangedSignal("Occupant"):Connect(onOccupant)
		-- кто-то уже сел до подключения (корабль только появился) — подхватываем сразу
		if seat.Occupant then onOccupant() end
	end
	model:SetAttribute("TurretActive", true)
end

local function attachShip(ship)
	for _, c in ipairs(ship:GetChildren()) do
		if c:IsA("Model") and (c:GetAttribute("CarrierTurret") or c:GetAttribute("ShipTurret")) then
			setup(c, ship)
		end
	end
end

local function turnToward(cur, target, maxStep)
	local d = (target - cur + math.pi) % (2 * math.pi) - math.pi
	if math.abs(d) <= maxStep then return target end
	return cur + math.sign(d) * maxStep
end

local function trunnionOf(st)
	return (st.pivot.CFrame * CFrame.new(st.yawBase) * CFrame.Angles(0, st.yaw, 0) * CFrame.new(st.pitchBase)).Position
end

-- навести на точку: для снарядов — угол возвышения по баллистике (низкая траектория)
local function aimAt(st, target)
	local from = trunnionOf(st)
	local dirW = target - from
	if dirW.Magnitude < 1 then return end
	local d = st.pivot.CFrame:VectorToObjectSpace(dirW.Unit)
	st.tYaw = math.atan2(-d.X, -d.Z)
	local pitch
	if st.projectile and st.W.Ballistic then
		local v, g = st.W.ShellSpeed, st.W.Gravity
		local x = Vector3.new(dirW.X, 0, dirW.Z).Magnitude
		local y = dirW.Y
		local disc = v ^ 4 - g * (g * x * x + 2 * y * v * v)
		if disc >= 0 and x > 0.5 then
			pitch = math.atan((v * v - math.sqrt(disc)) / (g * x))
		else
			pitch = math.rad(45) -- дальше максимальной дальности
		end
	else
		pitch = math.asin(math.clamp(d.Y, -1, 1))
	end
	st.tPitch = math.clamp(pitch, math.rad(st.W.MinPitch), math.rad(st.W.MaxPitch))
	st.aimPoint = target
end

local function fire(st)
	local ignore = {st.owner or st.model}
	local gc = charOf(st.gunner)
	if gc then table.insert(ignore, gc) end
	if st.projectile then
		-- залп из всех стволов
		for _, mz in ipairs(st.muzzles) do
			local s = math.rad(st.W.Spread or 0.5)
			local dir = (CFrame.lookAt(Vector3.zero, st.gun.CFrame.LookVector) * CFrame.Angles(math.random() * 2 * s - s, math.random() * 2 * s - s, 0)).LookVector
			ProjectileService.launch(mz.Position, dir * st.W.ShellSpeed, st.gunner, st.W, ignore)
		end
		return
	end
	local muzzle = st.muzzles[(st.shotN % math.max(1, #st.muzzles)) + 1] or st.gun
	st.shotN += 1
	local origin = muzzle.Position
	local dir = st.gun.CFrame.LookVector * TC.Range
	local params = RaycastParams.new()
	params.CollisionGroup = "Weapons" -- оружие видит и грузовые суда
	params.FilterType = Enum.RaycastFilterType.Exclude
	local fx = workspace:FindFirstChild("Effects")
	if fx then table.insert(ignore, fx) end
	params.FilterDescendantsInstances = ignore
	local res = workspace:Raycast(origin, dir, params)
	CombatService.tracer(origin, res and res.Position or origin + dir, nil, "AA")
	-- у стрелка-игрока урон приходит от его проверенных попаданий (TurretHit) — по тому, что он видел в прицеле
	if res and not (st.gunner and st.gunner:IsA("Player")) then
		CombatService.applyHit(st.gunner, res.Instance, TC.Damage, nil, "AA", res.Position)
	end
end

------------------------------------------------------------------ API
-- бот: точка цели и желание стрелять (огонь только когда ствол почти на цели)
function TurretService.botAim(model, target, wantFire)
	local st = turrets[model]
	if not st or not st.gunner or st.gunner:IsA("Player") then return end
	aimAt(st, target)
	local look = st.gun.CFrame.LookVector
	local want = st.projectile and look or (target - st.gun.Position).Unit
	st.firing = wantFire == true and (st.projectile or look:Dot(want) > math.cos(math.rad(6)))
end

-- орудие без своего кресла (пушка катера): стреляет тот, кто сидит в указанном кресле
function TurretService.assignGunner(model, actor, hum, controlSeat)
	local st = turrets[model]
	if not st then return end
	st.gunner, st.gunnerHum, st.seat = actor, hum, controlSeat
end

function TurretService.clearGunner(model)
	local st = turrets[model]
	if st then st.gunner, st.gunnerHum, st.firing = nil, nil, false end
end

function TurretService.attachShip(ship)
	attachShip(ship)
end

function TurretService.getAll()
	return turrets
end

function TurretService.init()
	for _, d in ipairs(workspace.Map.Teams:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("BaseTurret") then
			setup(d, nil)
		end
	end
	for _, fname in ipairs({"Carriers", "Vessels"}) do
		local folder = workspace.Map:FindFirstChild(fname)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = fname
			folder.Parent = workspace.Map
		end
		folder.ChildAdded:Connect(function(c)
			task.defer(attachShip, c)
		end)
		for _, c in ipairs(folder:GetChildren()) do attachShip(c) end
	end

	local inputT = setmetatable({}, {__mode = "k"}) -- [игрок] = время последнего ввода (до перебора турелей: спам не грузит сервер)
	local lastFire = setmetatable({}, {__mode = "k"}) -- [игрок] = огонь в последнем принятом пакете
	ReplicatedStorage.Remotes:WaitForChild("TurretInput").OnServerEvent:Connect(function(player, target, firing)
		if typeof(target) ~= "Vector3" or not (target.Magnitude < 1e5) then return end -- отсекает NaN/inf в любой координате
		local now = os.clock()
		local fire = firing == true
		-- частые пакеты отбрасываем, но смену огня — нет (иначе отпущенная гашетка «залипала» до следующего пакета)
		if now - (inputT[player] or 0) < 0.02 then
			if fire == lastFire[player] or not Guard.bucket(player, "TurretToggle", 20, 6) then return end
		end
		inputT[player] = now
		lastFire[player] = fire
		for _, st in pairs(turrets) do
			if st.gunner == player then
				aimAt(st, target)
				if st.firing and firing ~= true then st.firingEnd = now end
				st.firing = firing == true
				return
			end
		end
	end)

	-- попадание зенитки, которое увидел стрелок (см. CombatService.checkClientHit). Ствол на сервере следит
	-- за его прицелом, поэтому допуск по углу небольшой
	ReplicatedStorage.Remotes:WaitForChild("TurretHit").OnServerEvent:Connect(function(player, part, hitPos)
		-- лимит и тип — до перебора турелей: спам от не-стрелка не гоняет цикл (клиент шлёт не чаще темпа зенитки)
		if typeof(part) ~= "Instance" or typeof(hitPos) ~= "Vector3" then return end
		if not Guard.bucket(player, "TurretHit", 1 / TC.Cooldown * 1.15, 4) then return end
		for _, st in pairs(turrets) do
			if st.gunner == player then
				if st.projectile then return end
				if not st.firing and os.clock() - (st.firingEnd or 0) > 0.5 then return end
				local gun = st.gun
				if not CombatService.checkClientHit(gun.Position, part, hitPos, TC.Range + 40, gun.CFrame.LookVector, 15) then return end
				if part:IsDescendantOf(st.owner or st.model) then return end
				CombatService.applyHit(player, part, TC.Damage, nil, "AA", hitPos)
				return
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for model, st in pairs(turrets) do
			if not model.Parent then
				turrets[model] = nil
			else
				-- стрелок умер, встал или его персонаж удалён (вышел из игры) — турель свободна
				if st.gunnerHum and (not st.gunnerHum.Parent or st.gunnerHum.Health <= 0 or (st.seat and st.gunnerHum.SeatPart ~= st.seat)) then
					local hadSeat = model:FindFirstChild("TurretSeat") ~= nil
					st.gunner, st.gunnerHum, st.firing = nil, nil, false
					if hadSeat then
						local w = st.seat and st.seat:FindFirstChild("SeatWeld")
						if w then w:Destroy() end
					end
				end
				if not st.gunner and st.onOccupant and st.seat and st.seat.Occupant then
					st.onOccupant()
				end
				local step = math.rad(st.W.TurnSpeed) * dt
				local ny = turnToward(st.yaw, st.tYaw, step)
				local np = turnToward(st.pitch, st.tPitch, step)
				-- по сети шлём только реальный поворот
				if math.abs(ny - (st.sentYaw or 1e9)) > 0.002 and st.yawM then
					st.yawM.C0 = CFrame.new(st.yawBase) * CFrame.Angles(0, ny, 0)
					st.sentYaw = ny
				end
				if math.abs(np - (st.sentPitch or 1e9)) > 0.002 and st.pitchM then
					st.pitchM.C0 = CFrame.new(st.pitchBase) * CFrame.Angles(np, 0, 0)
					st.sentPitch = np
				end
				st.yaw, st.pitch = ny, np
				if st.firing and st.gunner and now - st.lastShot >= st.W.Cooldown then
					-- снарядные орудия стреляют, только когда башня довернула на цель
					local dy = math.abs((ny - st.tYaw + math.pi) % (2 * math.pi) - math.pi)
					local tol = math.rad(st.W.AimTolerance or 3)
					local ready = not st.projectile or (dy < tol and math.abs(np - st.tPitch) < tol)
					if ready then
						st.lastShot = now
						fire(st)
					end
				end
			end
		end
	end)
end

return TurretService
