-- Артиллерийские снаряды: летят по баллистике (гравитация), взрываются при попадании или в воде,
-- наносят урон по площади (люди, боты, самолёты, корабли). Полёт считает сервер, клиенты рисуют.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent
local CombatService = require(Services.CombatService)

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

function ProjectileService.init()
	local params = RaycastParams.new()
	params.CollisionGroup = "Weapons" -- оружие видит и грузовые суда
	params.FilterType = Enum.RaycastFilterType.Exclude
	RunService.Heartbeat:Connect(function(dt)
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
