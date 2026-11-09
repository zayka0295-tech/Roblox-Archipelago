-- Столкновения морской техники: импульсная физика твёрдых тел на плоскости воды.
--
-- Почему не встроенные столкновения Roblox: корабли ведут LinearVelocity/AlignOrientation с бесконечной
-- силой, поэтому два корпуса либо упираются друг в друга как в стену, либо дрожат и застревают — масса
-- не играет никакой роли. Поэтому корабли друг с другом встроенно не сталкиваются (группа «Vessels»),
-- а контакт корпусов решает этот модуль:
--   * корпус = ориентированный прямоугольник (по габаритам модели) + диапазон высот (киль..верх);
--   * пересечение — SAT, точка контакта — углы одного корпуса внутри другого;
--   * импульс по нормали с учётом масс, моментов инерции и плеча (корабль от удара в борт разворачивает),
--     трение по касательной небольшое — борта скользят друг по другу;
--   * выталкивание из перекрытия — ограниченной скоростью (без телепортов и рывков).
-- Результат удара уходит в контроллер корабля: продольная часть — в его ход (st.speed, дальше движок
-- и инерция сами возвращают к заданной скорости), поперечная и вращение — в «снос» (ext/spin), который
-- гасится сопротивлением воды. Контроллер добавляет снос к своей скорости через NavalPhysics.drift.
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local NavalPhysics = {}

local GROUP = "Vessels"
local RESTITUTION = 0.15   -- упругость удара корпусов (сталь в воде — почти неупругий удар)
local FRICTION = 0.12      -- трение борт о борт: мало, корпуса скользят
local SLOP = 0.4           -- допустимое перекрытие, студ
local BIAS = 0.35          -- доля перекрытия, выталкиваемая за секунду (×1/dt)
local MAX_BIAS = 7         -- предел скорости выталкивания, студ/с
local MAX_EXT = 45         -- предел скорости сноса, студ/с
local MAX_SPIN = math.rad(25)
local SHRINK = 0.94        -- габариты модели чуть больше корпуса (стволы, трапы)

local bodies = {} -- [модель] = тело

local function fwdOf(yaw) return Vector3.new(math.sin(yaw), 0, math.cos(yaw)) end
local function rightOf(yaw) return Vector3.new(math.cos(yaw), 0, -math.sin(yaw)) end
-- скалярное «плечо» вокруг вертикали: τ = r × F (компонента Y), согласовано с ω×r = (ω·r.z, 0, −ω·r.x)
local function cross(r, v) return r.Z * v.X - r.X * v.Z end
local function spinVel(w, r) return Vector3.new(w * r.Z, 0, -w * r.X) end

local function setGroup(d)
	if d:IsA("BasePart") and d.CollisionGroup == "Default" then d.CollisionGroup = GROUP end
end

-- spec: root (корневая деталь), mass (т), getYaw(), getSpeed()/setSpeed(v) — продольный ход контроллера
-- (без setSpeed весь импульс уходит в снос), isFixed() — неподвижен (у причала), isActive() — участвует
function NavalPhysics.register(model, spec)
	local root = spec.root
	local yaw = spec.getYaw()
	-- габариты корпуса в осях курса (X — поперёк, Z — вдоль) по твёрдым видимым деталям:
	-- невидимые зоны (SafeZone, триггеры), детали без столкновений и трапы за бортом (LadderPlatform) не в счёт
	local frame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and d.Transparency < 0.95 and not d:FindFirstAncestor("LadderPlatform")
			and d.Name ~= "LadderPlatform" then
			local h = d.Size / 2
			for _, s in ipairs({Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
				Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1)}) do
				local p = frame:PointToObjectSpace(d.CFrame:PointToWorldSpace(h * s))
				lo, hi = lo:Min(p), hi:Max(p)
			end
		end
	end
	if lo.X == math.huge then lo, hi = -root.Size / 2, root.Size / 2 end
	local size = hi - lo
	local mid = (hi + lo) / 2
	local rel = Vector3.new(0, mid.Y, 0)
	local loc = Vector3.new(mid.X, 0, mid.Z)
	local length = size.Z * SHRINK
	local beam = size.X * SHRINK
	local mass = spec.mass or 1000
	local b = {
		model = model, root = root, mass = mass, invMass = 1 / mass,
		invI = 1 / (mass * (length * length + beam * beam) / 12),
		hl = length / 2, hb = beam / 2, offset = loc,
		bottom = rel.Y - size.Y / 2, top = rel.Y + size.Y / 2, -- относительно root.Y
		radius = math.sqrt(length * length + beam * beam) / 2,
		getYaw = spec.getYaw, getSpeed = spec.getSpeed, setSpeed = spec.setSpeed,
		isFixed = spec.isFixed, isActive = spec.isActive,
		ext = Vector3.zero, spin = 0,
	}
	bodies[model] = b
	for _, d in ipairs(model:GetDescendants()) do setGroup(d) end
	b.conn = model.DescendantAdded:Connect(setGroup)
	return b
end

function NavalPhysics.unregister(model)
	local b = bodies[model]
	if b then
		if b.conn then b.conn:Disconnect() end
		bodies[model] = nil
	end
end

-- снос от столкновений для контроллера: (горизонтальная скорость, скорость поворота рад/с).
-- Заодно гасит его сопротивлением воды: поперёк корпуса вода тормозит сильно, тяжёлые суда — медленнее
function NavalPhysics.drift(model, dt)
	local b = bodies[model]
	if not b then return Vector3.zero, 0 end
	local yaw = b.getYaw()
	local f = fwdOf(yaw)
	local along = b.ext:Dot(f)
	local side = b.ext - f * along
	local heavy = math.clamp(b.mass / 20000, 0, 1) -- 0 — катер, 1 — линкор и тяжелее
	along *= math.exp(-(0.9 - 0.4 * heavy) * dt)
	side *= math.exp(-(1.6 - 0.8 * heavy) * dt)
	b.ext = f * along + side
	b.spin *= math.exp(-(1.8 - 0.6 * heavy) * dt)
	if b.ext.Magnitude < 0.02 then b.ext = Vector3.zero end
	if math.abs(b.spin) < 1e-4 then b.spin = 0 end
	return b.ext, b.spin
end

function NavalPhysics.get(model) return bodies[model] end

------------------------------------------------------------------ решатель
local function snapshot(b)
	local yaw = b.getYaw()
	local f, r = fwdOf(yaw), rightOf(yaw)
	local rp = b.root.Position
	b.f, b.r = f, r
	b.c = Vector3.new(rp.X, 0, rp.Z) + r * b.offset.X + f * b.offset.Z
	b.y0, b.y1 = rp.Y + b.bottom, rp.Y + b.top
	b.v = f * (b.getSpeed and b.getSpeed() or 0) + b.ext
	b.fixed = b.isFixed and b.isFixed() or false
	b.im = b.fixed and 0 or b.invMass
	b.ii = b.fixed and 0 or b.invI
end

local function inside(p, b)
	local d = p - b.c
	return math.abs(d:Dot(b.f)) <= b.hl + 0.05 and math.abs(d:Dot(b.r)) <= b.hb + 0.05
end

local function corners(b)
	local F, R = b.f * b.hl, b.r * b.hb
	return {b.c + F + R, b.c + F - R, b.c - F + R, b.c - F - R}
end

-- SAT двух прямоугольников: нормаль (от A к B), глубина, точка контакта
local function collide(A, B)
	local d = B.c - A.c
	local best, n = math.huge, nil
	for _, ax in ipairs({A.f, A.r, B.f, B.r}) do
		local ra = A.hl * math.abs(A.f:Dot(ax)) + A.hb * math.abs(A.r:Dot(ax))
		local rb = B.hl * math.abs(B.f:Dot(ax)) + B.hb * math.abs(B.r:Dot(ax))
		local dist = d:Dot(ax)
		local o = ra + rb - math.abs(dist)
		if o <= 0 then return nil end
		if o < best then best, n = o, (dist >= 0 and ax or -ax) end
	end
	local sum, cnt = Vector3.zero, 0
	for _, p in ipairs(corners(A)) do if inside(p, B) then sum += p cnt += 1 end end
	for _, p in ipairs(corners(B)) do if inside(p, A) then sum += p cnt += 1 end end
	local cp = cnt > 0 and sum / cnt or (A.c + d * 0.5)
	return n, best, cp
end

local function applyDV(b, dv, dw)
	if b.fixed then return end
	b.v += dv
	if b.setSpeed then
		local along = dv:Dot(b.f)
		b.setSpeed(b.getSpeed() + along)
		b.ext += dv - b.f * along
	else
		b.ext += dv
	end
	if b.ext.Magnitude > MAX_EXT then b.ext = b.ext.Unit * MAX_EXT end
	b.spin = math.clamp(b.spin + dw, -MAX_SPIN, MAX_SPIN)
end

local function resolve(A, B, dt)
	local n, depth, cp = collide(A, B)
	if not n then return end
	local ra, rb = cp - A.c, cp - B.c
	local va = A.v + spinVel(A.spin, ra)
	local vb = B.v + spinVel(B.spin, rb)
	local rel = vb - va
	local vn = rel:Dot(n)
	local bias = math.min(MAX_BIAS, BIAS * math.max(0, depth - SLOP) / math.max(dt, 1 / 240))
	-- уже расходятся быстрее, чем нужно для выталкивания — не трогаем
	if vn >= bias then return end
	local can, cbn = cross(ra, n), cross(rb, n)
	local denom = A.im + B.im + can * can * A.ii + cbn * cbn * B.ii
	if denom <= 0 then return end
	local j = (-(1 + RESTITUTION) * math.min(vn, 0) + math.max(0, bias - math.max(vn, 0))) / denom
	-- трение по касательной (ограничено конусом Кулона)
	local t = rel - n * vn
	local jt = 0
	if t.Magnitude > 1e-3 then
		t = t.Unit
		local cat, cbt = cross(ra, t), cross(rb, t)
		local dt2 = A.im + B.im + cat * cat * A.ii + cbt * cbt * B.ii
		jt = math.clamp(-rel:Dot(t) / dt2, -FRICTION * j, FRICTION * j)
	else
		t = Vector3.zero
	end
	local P = n * j + t * jt
	applyDV(A, -P * A.im, -cross(ra, P) * A.ii)
	applyDV(B, P * B.im, cross(rb, P) * B.ii)
end

local function step(dt)
	local list = {}
	for m, b in pairs(bodies) do
		if not m.Parent or not b.root.Parent then
			NavalPhysics.unregister(m)
		elseif not b.isActive or b.isActive() then
			snapshot(b)
			table.insert(list, b)
		end
	end
	-- несколько проходов: при контакте трёх и более кораблей импульсы успевают разойтись по цепочке
	for _ = 1, 3 do
		for i = 1, #list - 1 do
			local A = list[i]
			for k = i + 1, #list do
				local B = list[k]
				if (A.fixed and B.fixed) or A.y1 < B.y0 or B.y1 < A.y0 then continue end
				local d = B.c - A.c
				local rr = A.radius + B.radius
				if d.X * d.X + d.Z * d.Z > rr * rr then continue end
				resolve(A, B, dt)
			end
		end
	end
end

function NavalPhysics.init()
	pcall(function() PhysicsService:RegisterCollisionGroup(GROUP) end)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(GROUP, "Cargo", false) end)
	RunService.Heartbeat:Connect(step)
end

return NavalPhysics
