-- Артиллерийские снаряды: летят по баллистике (гравитация), взрываются при попадании или в воде,
-- наносят урон по площади (люди, боты, самолёты, корабли). Полёт считает сервер, клиенты рисуют.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent
local CombatService = require(Services.CombatService)
local Homing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Homing"))

local ProjectileService = {}
local ShellFx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShellFx")
local shells = {}
local MAX_LIFE = 15

-- эффекты выстрелов: залп (несколько снарядов за один шаг) уходит клиентам одним пакетом
-- {o, v, g, cls, ...}; одиночный снаряд — как раньше (ShotFx понимает оба вида). Class — звук выстрела.
local pendingFx = {}
local function flushFx()
	local n = #pendingFx
	if n == 4 then
		ShellFx:FireAllClients(pendingFx[1], pendingFx[2], pendingFx[3], pendingFx[4] or nil)
	elseif n > 4 then
		ShellFx:FireAllClients(pendingFx)
	end
	pendingFx = {}
end
local function queueFx(origin, velocity, gravity, class)
	if #pendingFx == 0 then task.defer(flushFx) end
	-- false вместо nil: дыра в массиве обрезала бы пакет
	table.insert(pendingFx, origin) table.insert(pendingFx, velocity)
	table.insert(pendingFx, gravity) table.insert(pendingFx, class or false)
end

function ProjectileService.launch(origin, velocity, attacker, W, ignore)
	-- список исключений собираем один раз (раньше — копия на каждый снаряд каждый кадр)
	local ex = ignore and table.clone(ignore) or {}
	local fx = workspace:FindFirstChild("Effects")
	if fx then table.insert(ex, fx) end
	table.insert(shells, {pos = origin, vel = velocity, attacker = attacker, W = W, ignore = ex, t = 0})
	queueFx(origin, velocity, W.Gravity, W.Class)
end

local function explode(pos, s, directInst)
	local W = s.W
	local e = Instance.new("Explosion")
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.BlastRadius = W.SplashRadius * 0.6
	e.Position = pos
	e.Parent = workspace

	-- каждая цель получает урон один раз, чем ближе к центру — тем больше
	local targets = {}
	local function consider(part)
		local kind, model = CombatService.resolveHit(part)
		if not kind or not model then return end
		local d = (part.Position - pos).Magnitude
		local cur = targets[model]
		if not cur or d < cur.d then targets[model] = {part = part, d = d} end
	end
	local ov = OverlapParams.new()
	ov.CollisionGroup = "Weapons" -- оружие видит и грузовые суда
	ov.FilterType = Enum.RaycastFilterType.Exclude
	local fx = workspace:FindFirstChild("Effects")
	ov.FilterDescendantsInstances = fx and {fx} or {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, W.SplashRadius, ov)) do
		consider(part)
	end
	if directInst then
		local kind, model = CombatService.resolveHit(directInst)
		if kind and model then targets[model] = {part = directInst, d = 0} end
	end
	-- людей за стеной / под крышей осколки не достают: луч от места взрыва по неподвижной застройке.
	-- Точка взрыва лежит на поверхности — луч начинаем чуть отступив туда, откуда прилетел снаряд.
	local back = s.vel.Magnitude > 0.1 and -s.vel.Unit or Vector3.yAxis
	local from = pos + back * 1.5
	for model, t in pairs(targets) do
		local kind = CombatService.resolveHit(t.part)
		local covered = t.d > 0 and (kind == "player" or kind == "bot")
			and CombatService.wallBetween(from, t.part.Position, model, 0.5)
		if not covered then
			local f = 1 - math.clamp(t.d / W.SplashRadius, 0, 1) * 0.7
			CombatService.applyHit(s.attacker, t.part, W.Damage * f, nil, W.Class, pos)
		end
	end
end

------------------------------------------------------------------ управляемые ракеты (Javelin, Игла)
-- Летят по прямой с постоянной скоростью и доворачивают на цель (с упреждением) не быстрее TurnRate °/с.
-- Цель пропала (сбита, утонула) или её не было — дальше по инерции с гравитацией W.Gravity.
-- Взрыв: попадание лучом, неконтактный взрыватель (W.Proximity), вода или конец полёта (W.Life).
-- Ракету видно всем: деталь в Effects, которую двигает сервер (их единицы, ballistics ShellFx тут не годится).
local missiles = {}
local missileParams = RaycastParams.new()
missileParams.CollisionGroup = "Weapons"
missileParams.FilterType = Enum.RaycastFilterType.Exclude

local function missileBody(origin, dir, kind)
	local p = Instance.new("Part")
	p.Name = "Missile"
	p.Size = Vector3.new(0.45, 0.45, 2.2)
	p.Color = kind == "Air" and Color3.fromRGB(70, 82, 60) or Color3.fromRGB(86, 96, 70)
	p.Material = Enum.Material.Metal
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.CFrame = CFrame.lookAt(origin, origin + dir)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.2, 1.1)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.2, 1.1)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime, trail.MinLength, trail.LightEmission = 1.4, 0.2, 0.4
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(210, 210, 210))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 5)
	trail.Parent = p
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 170, 80), 12, 2
	light.Parent = p
	local s = Instance.new("Sound")
	s.SoundId = "rbxasset://sounds/Rocket shot.wav"
	s.Volume, s.RollOffMaxDistance = 1, 600
	s.Parent = p
	p.Parent = workspace:FindFirstChild("Effects") or workspace
	s:Play()
	return p
end

-- dir — направление пуска; target / targetPart — захваченная цель (или nil); kind — Homing ("Naval" / "Air")
function ProjectileService.launchMissile(origin, dir, attacker, W, ignore, target, targetPart, kind)
	local ex = ignore and table.clone(ignore) or {}
	local fx = workspace:FindFirstChild("Effects")
	if fx then table.insert(ex, fx) end
	table.insert(missiles, {pos = origin, vel = dir.Unit * W.Speed, attacker = attacker, W = W, ignore = ex, t = 0,
		target = target, part = targetPart, kind = kind, body = missileBody(origin, dir, kind)})
end

local function stepMissiles(dt)
	for i = #missiles, 1, -1 do
		local m = missiles[i]
		m.t += dt
		local W = m.W
		if m.target and m.part and m.part.Parent and Homing.alive(m.target, m.kind) then
			local dir = m.vel.Unit
			local tp = m.part.Position
			local lead = math.clamp((tp - m.pos).Magnitude / W.Speed, 0, 2)
			local want = tp + m.part.AssemblyLinearVelocity * lead - m.pos
			if want.Magnitude > 0.1 then
				want = want.Unit
				local maxA = math.rad(W.TurnRate or 60) * dt
				local ang = math.acos(math.clamp(dir:Dot(want), -1, 1))
				if ang <= maxA then
					dir = want
				else
					local axis = dir:Cross(want)
					dir = (CFrame.fromAxisAngle(axis.Magnitude > 1e-6 and axis.Unit or Vector3.yAxis, maxA) * dir).Unit
				end
			end
			m.vel = dir * W.Speed
		else
			m.target = nil
			m.vel += Vector3.new(0, -(W.Gravity or 0) * dt, 0)
		end
		local newPos = m.pos + m.vel * dt
		missileParams.FilterDescendantsInstances = m.ignore
		local res = workspace:Raycast(m.pos, newPos - m.pos, missileParams)
		local at, direct
		if res then
			at, direct = res.Position, res.Instance
		elseif m.target and W.Proximity and (m.part.Position - newPos).Magnitude <= W.Proximity then
			at, direct = newPos, m.part
		elseif newPos.Y < 0 then
			at = Vector3.new(newPos.X, 0, newPos.Z)
		elseif m.t > (W.Life or 10) then
			at = newPos
		end
		if at then
			table.remove(missiles, i)
			m.body:Destroy()
			local ok, err = pcall(explode, at, m, direct)
			if not ok then warn("[ProjectileService] " .. tostring(err)) end
		else
			m.pos = newPos
			m.body.CFrame = CFrame.lookAt(newPos, newPos + m.vel)
		end
	end
end

-- взрыв в точке без снаряда (заряд C4)
function ProjectileService.blast(pos, attacker, W)
	explode(pos, {vel = Vector3.zero, attacker = attacker, W = W}, nil)
end

function ProjectileService.init()
	local params = RaycastParams.new()
	params.CollisionGroup = "Weapons" -- оружие видит и грузовые суда
	params.FilterType = Enum.RaycastFilterType.Exclude
	RunService.Heartbeat:Connect(function(dt)
		stepMissiles(dt)
		for i = #shells, 1, -1 do
			local s = shells[i]
			s.t += dt
			local newVel = s.vel + Vector3.new(0, -s.W.Gravity * dt, 0)
			local newPos = s.pos + (s.vel + newVel) * 0.5 * dt
			params.FilterDescendantsInstances = s.ignore
			local res = workspace:Raycast(s.pos, newPos - s.pos, params)
			-- ошибка в уроне одного снаряда (обработчик техники и т.п.) не должна обрывать полёт остальных в этом кадре
			if res then
				table.remove(shells, i)
				local ok, err = pcall(explode, res.Position, s, res.Instance)
				if not ok then warn("[ProjectileService] " .. tostring(err)) end
			elseif newPos.Y < 0 then
				table.remove(shells, i)
				local ok, err = pcall(explode, Vector3.new(newPos.X, 0, newPos.Z), s, nil) -- всплеск в воде
				if not ok then warn("[ProjectileService] " .. tostring(err)) end
			elseif s.t > MAX_LIFE then
				table.remove(shells, i)
			else
				s.pos, s.vel = newPos, newVel
			end
		end
	end)
end

return ProjectileService
