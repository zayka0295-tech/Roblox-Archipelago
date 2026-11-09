-- Морская логистика: у каждого острова своё грузовое судно. Остров под контролем команды
-- отправляет судно на её базу; кран ставит 2 контейнера на грузовик, грузовик везёт их по дороге
-- в ангар базы — и только тогда команда получает золото. Судно и грузовик можно уничтожить — груз пропадает.
-- Сервер — единственный источник истины (движение, разгрузка, выплаты).
--
-- Состояния судна: Docked → ToBase → (Queued) → Unloading → ToIsland → Docked; Sunk — потоплено.
-- Empty — судна нет: остров ничей. После захвата судно появляется у причала и сразу грузится.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local CombatService = require(Services.CombatService)
local CaptureService = require(Services.CaptureService)
local Notifier = require(Services.Notifier)
local TreasuryService = require(Services.TreasuryService)
local SinkFx = require(Services.SinkFx)
local NavalPhysics = require(Services.NavalPhysics)

local LogisticsService = {}
local L = Config.Logistics
local NEUTRAL_COLOR = Color3.fromRGB(200, 200, 200)
local CONTAINER_COLORS = {
	Color3.fromRGB(190, 70, 40), Color3.fromRGB(40, 110, 170), Color3.fromRGB(60, 130, 70),
	Color3.fromRGB(200, 150, 40), Color3.fromRGB(120, 125, 135), Color3.fromRGB(150, 45, 60),
}

local routes = {}    -- [острова Id] = состояние рейса
local bases = {}     -- [команда] = {crane, berth, slots, yard, busy, queue}
local deliverySeq = 0
local paidDeliveries = {} -- [id] = true — защита от повторной выплаты
local trucks = {} -- [модель грузовика] = состояние

-- стоянка грузовика под краном и маршрут до ангара (в координатах синих; у красных — поворот на 180°).
-- На площади маршрут объезжает мачту сирены в центре дороги.
local TRUCK_BAY = {pos = Vector3.new(-2302, 0, -40), look = Vector3.new(0, 0, 1)}
local TRUCK_ROUTE = {
	Vector3.new(-2302, 0, 0), Vector3.new(-2700, 0, 0), Vector3.new(-2840, 0, 0), Vector3.new(-2862, 0, 26),
	Vector3.new(-2914, 0, 26), Vector3.new(-2936, 0, 0), Vector3.new(-3300, 0, 0), Vector3.new(-3378, 0, 0),
}
-- по чему едет грузовик (дороги, площадь, пол ангара, земля) — без фонарей, шлагбаумов и крыш
local GROUND_NAMES = {MainRoad = true, CrossRoad = true, HangarRoad = true, Plaza = true, TeamEmblem = true, Apron = true, HangarFloor = true, Quay = true}
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

local function folder()
	local f = workspace.Map:FindFirstChild("Cargo")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Cargo"
		f.Parent = workspace.Map
	end
	return f
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function yawOf(dir) return math.atan2(dir.X, dir.Z) end -- Ry(yaw)*Z = dir
local function fwdOf(yaw) return Vector3.new(math.sin(yaw), 0, math.cos(yaw)) end

------------------------------------------------------------------ навигационная сетка моря и A*
local NAV = {cell = 50, x0 = -4600, z0 = -2400, nx = 184, nz = 96, ok = nil, ready = false}

local function cellIndex(i, j) return j * NAV.nx + i end
local function cellCenter(i, j) return Vector3.new(NAV.x0 + (i + 0.5) * NAV.cell, 0, NAV.z0 + (j + 0.5) * NAV.cell) end
local function cellOf(p)
	return math.floor((p.X - NAV.x0) / NAV.cell), math.floor((p.Z - NAV.z0) / NAV.cell)
end
local function navigable(i, j)
	if i < 0 or j < 0 or i >= NAV.nx or j >= NAV.nz then return false end
	return NAV.ok[cellIndex(i, j)] == true
end

local function buildNav()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list = {workspace.Terrain}
	for _, n in ipairs({"Teams", "Neutral", "Seabed"}) do
		local f = workspace.Map:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = true
	local function deep(x, z)
		local r = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -300, 0), params)
		return not r or r.Position.Y < -15
	end
	NAV.ok = {}
	local count = 0
	for j = 0, NAV.nz - 1 do
		for i = 0, NAV.nx - 1 do
			local c = cellCenter(i, j)
			local ok = deep(c.X, c.Z) and deep(c.X + 26, c.Z) and deep(c.X - 26, c.Z) and deep(c.X, c.Z + 26) and deep(c.X, c.Z - 26)
			NAV.ok[cellIndex(i, j)] = ok
			count += 1
			if count % 1500 == 0 then task.wait() end
		end
	end
	NAV.ready = true
end

local function nearestNav(p)
	local ci, cj = cellOf(p)
	if navigable(ci, cj) then return ci, cj end
	for r = 1, 12 do
		local best, bd
		for i = ci - r, ci + r do
			for j = cj - r, cj + r do
				if (math.abs(i - ci) == r or math.abs(j - cj) == r) and navigable(i, j) then
					local d = (cellCenter(i, j) - flat(p)).Magnitude
					if not bd or d < bd then best, bd = {i, j}, d end
				end
			end
		end
		if best then return best[1], best[2] end
	end
	return ci, cj
end

local function lineClear(a, b)
	local d = flat(b - a)
	local n = math.max(1, math.ceil(d.Magnitude / 15))
	for k = 0, n do
		local p = a + d * (k / n)
		local i, j = cellOf(p)
		if not navigable(i, j) then return false end
	end
	return true
end

-- очередь с приоритетом (двоичная куча) для A*: раньше минимум искался перебором всего списка,
-- и один поиск держал сервер десятки миллисекунд
local function heapPush(h, pri, id)
	local n = #h.p + 1
	h.p[n], h.v[n] = pri, id
	while n > 1 do
		local parent = n // 2
		if h.p[parent] <= h.p[n] then break end
		h.p[parent], h.p[n] = h.p[n], h.p[parent]
		h.v[parent], h.v[n] = h.v[n], h.v[parent]
		n = parent
	end
end
local function heapPop(h)
	local n = #h.p
	if n == 0 then return nil end
	local pri, id = h.p[1], h.v[1]
	h.p[1], h.v[1] = h.p[n], h.v[n]
	h.p[n], h.v[n] = nil, nil
	n -= 1
	local k = 1
	while true do
		local l, r, m = k * 2, k * 2 + 1, k
		if l <= n and h.p[l] < h.p[m] then m = l end
		if r <= n and h.p[r] < h.p[m] then m = r end
		if m == k then break end
		h.p[k], h.p[m] = h.p[m], h.p[k]
		h.v[k], h.v[m] = h.v[m], h.v[k]
		k = m
	end
	return id, pri
end

-- пути по клеткам уже найденные (острова и базы неподвижны — маршруты повторяются)
local pathCache = {}
local pathCacheN = 0

-- путь по морю между двумя точками (список точек, без старта)
local function findPath(from, to)
	local si, sj = nearestNav(from)
	local gi, gj = nearestNav(to)
	local start, goal = cellIndex(si, sj), cellIndex(gi, gj)
	local cacheKey = start .. ">" .. goal
	local cached = pathCache[cacheKey]
	if cached then
		local pts = table.clone(cached)
		table.insert(pts, flat(to))
		return pts
	end
	local open = {p = {}, v = {}}
	heapPush(open, 0, start)
	local g = {[start] = 0}
	local came = {}
	local closed = {}
	local function h(i, j) return math.sqrt((i - gi) ^ 2 + (j - gj) ^ 2) end
	local iterations = 0
	while true do
		local cur = heapPop(open)
		if not cur then break end
		iterations += 1
		if iterations > 40000 then break end
		if cur == goal then break end
		if closed[cur] then continue end -- устаревшая запись в куче (узел уже разобран дешевле)
		closed[cur] = true
		local ci, cj = cur % NAV.nx, math.floor(cur / NAV.nx)
		for di = -1, 1 do
			for dj = -1, 1 do
				if di ~= 0 or dj ~= 0 then
					local ni, nj = ci + di, cj + dj
					if navigable(ni, nj) and (di == 0 or dj == 0 or (navigable(ci + di, cj) and navigable(ci, cj + dj))) then
						local nid = cellIndex(ni, nj)
						if not closed[nid] then
							local cost = g[cur] + ((di ~= 0 and dj ~= 0) and 1.414 or 1)
							if not g[nid] or cost < g[nid] then
								g[nid] = cost
								heapPush(open, cost + h(ni, nj), nid)
								came[nid] = cur
							end
						end
					end
				end
			end
		end
	end
	if not came[goal] and start ~= goal then
		return {to} -- не нашли: прямо (судно не сталкивается с миром)
	end
	local cells = {}
	local c = goal
	while c do
		table.insert(cells, 1, cellCenter(c % NAV.nx, math.floor(c / NAV.nx)))
		c = came[c]
	end
	-- сглаживание: оставляем только точки поворота с прямой видимостью
	-- (от центра стартовой клетки: так путь можно хранить в кэше для любой точки этой клетки)
	local pts = {}
	local anchor = cellCenter(si, sj)
	local k = 1
	while k <= #cells do
		local far = k
		for q = #cells, k, -1 do
			if lineClear(anchor, cells[q]) then far = q break end
		end
		table.insert(pts, cells[far])
		anchor = cells[far]
		k = far + 1
	end
	-- старт возвратного рейса — любая клетка, где судно застала потеря острова: кэш не должен расти без конца
	pathCacheN += 1
	if pathCacheN > 400 then
		table.clear(pathCache)
		pathCacheN = 1
	end
	pathCache[cacheKey] = table.clone(pts)
	table.insert(pts, flat(to))
	return pts
end

-- только для тестов в Studio: замерить поиск пути (без кэша)
function LogisticsService.devPathTime(from, to)
	if not NAV.ready then buildNav() end
	local saved = pathCache
	pathCache = {}
	local t0 = os.clock()
	local pts = findPath(from, to)
	local dt = os.clock() - t0
	pathCache = saved
	return dt, #pts
end

------------------------------------------------------------------ контейнеры
local function makeContainer()
	local c = ServerStorage.Ships.CargoContainer:Clone()
	local col = CONTAINER_COLORS[math.random(1, #CONTAINER_COLORS)]
	c.Body.Color = col
	for _, d in ipairs(c:GetChildren()) do
		if d:IsA("BasePart") and (d.Name == "Rib" or d.Name == "Doors") then d.Color = col:Lerp(Color3.new(0, 0, 0), 0.25) end
	end
	return c
end

local function loadContainers(st)
	for i = 1, 2 do
		if not (st.containers[i] and st.containers[i].Parent) then
			local slot = st.model:FindFirstChild("ContainerSlot" .. i)
			local c = makeContainer()
			c.Name = "Container" .. i
			c:PivotTo(slot.CFrame * CFrame.new(0, 3.65, 0))
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = false
					d.Massless = true
					d.CollisionGroup = "Cargo"
				end
			end
			local w = Instance.new("WeldConstraint")
			w.Name = "ShipWeld"
			w.Part0 = st.root
			w.Part1 = c.Body
			w.Parent = c.Body
			c.Parent = st.model
			st.containers[i] = c
		end
	end
end

------------------------------------------------------------------ судно
local function paint(st, team)
	local col = team ~= "Neutral" and Config.Teams[team].Color or NEUTRAL_COLOR
	for _, d in ipairs(st.model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("TeamPaint") then d.Color = col end
	end
	st.model:SetAttribute("Team", team)
end

local function spawnShip(route)
	local dock = route.dock
	local look = dock.CFrame.LookVector
	local pos = Vector3.new(dock.Position.X, 0, dock.Position.Z)
	local cf = CFrame.lookAt(pos, pos - Vector3.new(look.X, 0, look.Z))
	local m = ServerStorage.Ships.CargoShip:Clone()
	m.Name = "Cargo_" .. route.id
	m:SetAttribute("IsCargo", true)
	m:SetAttribute("IslandId", route.id)
	m:SetAttribute("Health", L.ShipHealth)
	m:SetAttribute("MaxHealth", L.ShipHealth)
	m:SetAttribute("State", "Docked")
	m:PivotTo(cf)
	m.Parent = folder()
	local root = m.Hull
	pcall(function() root:SetNetworkOwner(nil) end)
	local st = {
		model = m, root = root, ao = root.HelmAlign, lv = root.HelmDrive,
		yaw = yawOf(look), y0 = root.Position.Y, containers = {}, health = L.ShipHealth,
		team = "Neutral", path = nil, pi = 1, finalYaw = nil, arrived = true, speed = 0,
	}
	st.ao.CFrame = CFrame.Angles(0, st.yaw, 0)
	-- в столкновениях: в пути толкается по массе, у причала (разгрузка краном) — неподвижен.
	-- Скорость судно каждый кадр берёт из маршрута, поэтому весь толчок уходит в снос (без setSpeed)
	NavalPhysics.register(m, {
		root = root, mass = L.ShipMass,
		getYaw = function() return st.yaw end,
		getSpeed = function() return st.speed end,
		isFixed = function() return st.arrived or not st.path end,
		isActive = function() return not st.dead end,
	})
	route.ship = st
	route.state = "Docked"
	route.departAt = nil
	paint(st, "Neutral")
	return st
end

local function setState(route, s)
	route.state = s
	if route.ship then route.ship.model:SetAttribute("State", s) end
end

-- остров стал ничьим, пока судно у причала: судно убираем, новое — после следующего захвата
local function despawnShip(route)
	local st = route.ship
	if st then
		st.dead = true
		if st.model.Parent then st.model:Destroy() end
	end
	route.ship = nil
	route.departAt = nil
	route.state = "Empty"
end

local function goTo(st, pts, finalDir)
	st.path, st.pi, st.arrived = pts, 1, false
	st.finalYaw = finalDir and yawOf(finalDir) or nil
end

------------------------------------------------------------------ кран
local function smooth(t) return t * t * (3 - 2 * t) end
local function lerpAngle(a, b, t)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

local function craneApply(base)
	local cr = base.craneState
	local slewCF = CFrame.new(base.mastTop) * CFrame.Angles(0, cr.theta, 0)
	base.parts.SlewRoot.CFrame = slewCF
	local tcf = slewCF * CFrame.new(cr.r, -1.2, 0)
	base.parts.Trolley.CFrame = tcf
	local tp = tcf.Position
	local spY = cr.sY
	base.parts.Spreader.CFrame = CFrame.new(tp.X, spY, tp.Z) * CFrame.Angles(0, cr.spYaw, 0)
	local hookY = spY + 1.5
	base.parts.HookBlock.CFrame = CFrame.new(tp.X, hookY, tp.Z)
	local top, bottom = tp.Y - 0.75, hookY + 1.1
	local len = math.max(0.5, top - bottom)
	base.parts.Cable.Size = Vector3.new(0.25, len, 0.25)
	base.parts.Cable.CFrame = CFrame.new(tp.X, bottom + len / 2, tp.Z)
	if cr.carry and cr.carry.Parent then
		cr.carry:PivotTo(base.parts.Spreader.CFrame * CFrame.new(0, -3.9, 0))
	end
end

-- плавно перевести кран в новое положение за dur секунд (вызывать из корутины)
local function craneMove(base, target, dur, abort)
	local cr = base.craneState
	local from = {theta = cr.theta, r = cr.r, sY = cr.sY, spYaw = cr.spYaw}
	local t0 = os.clock()
	while true do
		if abort and abort() then return false end
		local k = math.min(1, (os.clock() - t0) / dur)
		local e = smooth(k)
		cr.theta = lerpAngle(from.theta, target.theta or from.theta, e)
		cr.r = from.r + ((target.r or from.r) - from.r) * e
		cr.sY = from.sY + ((target.sY or from.sY) - from.sY) * e
		cr.spYaw = lerpAngle(from.spYaw, target.spYaw or from.spYaw, e)
		craneApply(base)
		if k >= 1 then return true end
		RunService.Heartbeat:Wait()
	end
end

local function aimFor(base, cf)
	local p = cf.Position
	local d = Vector3.new(p.X - base.mastTop.X, 0, p.Z - base.mastTop.Z)
	local look = cf.LookVector
	return {
		theta = math.atan2(-d.Z, d.X),
		r = math.clamp(d.Magnitude, 8, base.maxR or 98),
		spYaw = math.atan2(-look.X, -look.Z),
	}
end

-- разгрузка: 2 контейнера с судна на склад; возвращает true, если все контейнеры на складе
local function unload(base, route, st)
	local per = (L.UnloadTime or 12) / 2
	local a, b = per * 0.25, per * 1 / 6
	local travelY = 32
	local function aborted() return st.dead or not st.model.Parent end
	for i = 1, 2 do
		local c = st.containers[i]
		if c and c.Parent then
			-- к контейнеру на судне
			local tgt = aimFor(base, c.Body.CFrame)
			tgt.sY = travelY
			if not craneMove(base, tgt, a, aborted) then return false end
			if not craneMove(base, {sY = c.Body.Position.Y + 3.9}, b, aborted) then return false end
			-- зацепили
			local w = c.Body:FindFirstChild("ShipWeld")
			if w then w:Destroy() end
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = d == c.Body
					d.CollisionGroup = "Default"
				end
			end
			c.Parent = base.yardFolder
			st.containers[i] = nil
			base.craneState.carry = c
			if not craneMove(base, {sY = travelY}, b, nil) then return false end
			-- на грузовик на стоянке (если его уже уничтожили — подаётся новый)
			local truck = LogisticsService._bayTruck(base)
			local slot = truck.model:FindFirstChild("ContainerSlot" .. i)
			local place = slot.CFrame * CFrame.new(0, 3.65, 0)
			local tgt2 = aimFor(base, place)
			tgt2.sY = travelY
			craneMove(base, tgt2, a, nil)
			craneMove(base, {sY = place.Position.Y + 3.9}, b, nil)
			base.craneState.carry = nil
			truck = LogisticsService._bayTruck(base)
			place = truck.model:FindFirstChild("ContainerSlot" .. i).CFrame * CFrame.new(0, 3.65, 0)
			c:PivotTo(place)
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CollisionGroup = "Cargo"
				end
			end
			-- в гнезде уже стоит контейнер прошлой, сорванной разгрузки (судно потопили у крана) — убираем, иначе два в одном месте
			local old = truck.containers[i]
			if old and old ~= c and old.Parent then old:Destroy() end
			c.Parent = truck.model
			truck.containers[i] = c
			craneMove(base, {sY = travelY}, b * 0.6, nil)
		end
	end
	return true
end

-- погрузка: кран острова переносит 2 контейнера с площадки на судно
local function loadShip(cr, route, st)
	local per = (L.LoadTime or 12) / 2
	local a, b = per * 0.25, per * 1 / 6
	local travelY = cr.mastTop.Y - 14
	local function aborted() return st.dead or not st.model.Parent end
	for i = 1, 2 do
		if not (st.containers[i] and st.containers[i].Parent) then
			-- контейнер ждёт на площадке
			local stackSlot = cr.stackSlots[i] or cr.stackSlots[1]
			local c = makeContainer()
			c.Name = "Container" .. i
			c:PivotTo(stackSlot.CFrame * CFrame.new(0, 3.55, 0))
			c.Parent = cr.loadFolder
			local tgt = aimFor(cr, c.Body.CFrame)
			tgt.sY = travelY
			if not craneMove(cr, tgt, a, aborted) then c:Destroy() return false end
			if not craneMove(cr, {sY = c.Body.Position.Y + 3.9}, b, aborted) then c:Destroy() return false end
			cr.craneState.carry = c
			if not craneMove(cr, {sY = travelY}, b, aborted) then cr.craneState.carry = nil c:Destroy() return false end
			-- на палубу, в своё гнездо
			local slot = st.model:FindFirstChild("ContainerSlot" .. i)
			local place = slot.CFrame * CFrame.new(0, 3.65, 0)
			local tgt2 = aimFor(cr, place)
			tgt2.sY = travelY
			if not craneMove(cr, tgt2, a, aborted) then cr.craneState.carry = nil c:Destroy() return false end
			place = slot.CFrame * CFrame.new(0, 3.65, 0) -- судно могло чуть качнуться
			if not craneMove(cr, {sY = place.Position.Y + 3.9}, b, aborted) then cr.craneState.carry = nil c:Destroy() return false end
			cr.craneState.carry = nil
			c:PivotTo(place)
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = false
					d.Massless = true
					d.CollisionGroup = "Cargo"
				end
			end
			local w = Instance.new("WeldConstraint")
			w.Name = "ShipWeld"
			w.Part0 = st.root
			w.Part1 = c.Body
			w.Parent = c.Body
			c.Parent = st.model
			st.containers[i] = c
			craneMove(cr, {sY = travelY}, b * 0.6, nil)
		end
	end
	return true
end

------------------------------------------------------------------ выплата
local function payout(route, delivery)
	if not delivery or paidDeliveries[delivery.id] then return end
	paidDeliveries[delivery.id] = true -- до выплаты: никакая ветка не заплатит дважды
	local mult = route.def.IsCenter and (L.CenterBonusMultiplier or 1) or 1
	local toTreasury = (L.Reward or 0) * mult
	local share = (L.PersonalShare or 0) * mult
	TreasuryService.add(delivery.team, toTreasury, nil)
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if TeamService.getTeamName(p) == delivery.team then
			if share <= 0 or DataService.addGold(p, share) then
				n += 1
				Notifier.send(p, ("Cargo from %s delivered to the hangar · treasury +%d · you +%d"):format(route.def.Name, toTreasury, share), "success")
			end
			if p:GetAttribute("State") == "Deployed" then require(script.Parent.RankService).award(p, "Delivery") end
		end
	end
	ReplicatedStorage.GameState:SetAttribute("LastDelivery", ("%s → %s · treasury +%d, %d players got %d each"):format(route.def.Name, delivery.team, toTreasury, n, share))
end

------------------------------------------------------------------ грузовики: от крана до ангара
local function groundY(p, fallback)
	local r = workspace:Raycast(Vector3.new(p.X, fallback + 6, p.Z), Vector3.new(0, -30, 0), groundParams)
	return r and r.Position.Y or fallback
end

local function spawnTruck(base)
	local m = ServerStorage.Ships.CargoTruck:Clone()
	m.Name = "CargoTruck_" .. base.team
	m:SetAttribute("IsCargo", true)
	m:SetAttribute("IsTruck", true)
	m:SetAttribute("Team", base.team)
	m:SetAttribute("Health", L.TruckHealth or 350)
	m:SetAttribute("MaxHealth", L.TruckHealth or 350)
	m:SetAttribute("State", "Loading")
	local col = Config.Teams[base.team].Color
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("TeamPaint") then d.Color = col end
			d.CollisionGroup = "Cargo"
		end
	end
	local p = base.truckBay.Position
	m:PivotTo(CFrame.new(p.X, groundY(p, 10.6), p.Z) * base.truckBay.Rotation)
	m.Parent = folder()
	local t = {model = m, base = base, team = base.team, health = L.TruckHealth or 350, state = "Loading", containers = {}, wheels = {}, spin = 0}
	-- колёса крутятся при езде: запоминаем их положение относительно корня
	for _, d in ipairs(m:GetChildren()) do
		if d.Name == "Wheel" or d.Name == "Hub" then
			table.insert(t.wheels, {d, m.PrimaryPart.CFrame:ToObjectSpace(d.CFrame)})
		end
	end
	trucks[m] = t
	return t
end

-- грузовик на стоянке (подать новый, если нет или уничтожен)
function LogisticsService._bayTruck(base)
	local t = base.bayTruck
	if not t or t.state ~= "Loading" or not t.model.Parent then
		t = spawnTruck(base)
		base.bayTruck = t
	end
	return t
end

local function setTruckState(t, s)
	t.state = s
	if t.model.Parent then t.model:SetAttribute("State", s) end
end

-- грузовик с контейнерами рейса — в путь
local function dispatchTruck(base, route, delivery)
	local t = base.bayTruck
	if not t or t.state ~= "Loading" or not t.model.Parent then return end
	base.bayTruck = nil
	t.route, t.delivery = route, delivery
	t.path, t.pi = base.truckPath, 1
	setTruckState(t, "Driving")
	Notifier.team(t.team, ("Cargo from %s is on the truck to the hangar — protect it!"):format(route.def.Name), "info")
end

local function destroyTruck(t, killer)
	if t.state == "Destroyed" then return end
	setTruckState(t, "Destroyed")
	local m = t.model
	m:SetAttribute("IsCargo", false)
	if t.base.bayTruck == t then t.base.bayTruck = nil end
	trucks[m] = nil
	if killer and typeof(killer) == "Instance" and killer:IsA("Player") and TeamService.getTeamName(killer) ~= t.team and (L.TruckKillReward or 0) > 0 then
		DataService.addGold(killer, L.TruckKillReward)
		Notifier.send(killer, ("Enemy cargo truck destroyed! +%d gold"):format(L.TruckKillReward), "success")
	end
	if killer and typeof(killer) == "Instance" and killer:IsA("Player") and TeamService.getTeamName(killer) ~= t.team then
		require(script.Parent.RankService).award(killer, "TruckKill")
	end
	if t.delivery then
		Notifier.team(t.team, ("Cargo truck from %s was destroyed, cargo lost"):format(t.route.def.Name), "error")
	end
	t.delivery = nil
	local e = Instance.new("Explosion")
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.BlastRadius = 12
	e.Position = m:GetPivot().Position + Vector3.new(0, 4, 0)
	e.Parent = workspace
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Color = d.Color:Lerp(Color3.fromRGB(25, 25, 25), 0.7) end
	end
	task.delay(6, function() if m.Parent then m:Destroy() end end)
end

local function truckArrive(t)
	setTruckState(t, "Delivered")
	trucks[t.model] = nil
	if t.route and t.delivery then payout(t.route, t.delivery) end
	t.delivery = nil
	task.delay(1.5, function() if t.model.Parent then t.model:Destroy() end end)
end

local function truckStep(t, dt)
	if t.state ~= "Driving" then return end
	local m = t.model
	if not m.Parent then trucks[m] = nil return end
	local cf = m:GetPivot()
	local target = t.path[t.pi]
	local to = Vector3.new(target.X - cf.X, 0, target.Z - cf.Z)
	local dist = to.Magnitude
	if dist < 4 then
		t.pi += 1
		if t.pi > #t.path then truckArrive(t) end
		return
	end
	-- нос модели — -Z (LookVector)
	local want = math.atan2(-to.X, -to.Z)
	local _, yaw = cf:ToOrientation()
	local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
	yaw += math.clamp(diff, -math.rad(75) * dt, math.rad(75) * dt)
	local speed = (L.TruckSpeed or 26) * math.max(0.25, math.cos(math.min(math.abs(diff), math.pi / 2)))
	local fwd = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local step = math.min(speed * dt, dist)
	local p = Vector3.new(cf.X, 0, cf.Z) + fwd * step
	local y = groundY(p, cf.Y)
	m:PivotTo(CFrame.new(p.X, cf.Y + (y - cf.Y) * math.min(1, dt * 8), p.Z) * CFrame.Angles(0, yaw, 0))
	-- колёса (радиус 1.7): верх колеса идёт к носу (-Z)
	t.spin -= step / 1.7
	local rootCF = m.PrimaryPart.CFrame
	for _, w in ipairs(t.wheels) do
		w[1].CFrame = rootCF * w[2] * CFrame.Angles(t.spin, 0, 0)
	end
end

------------------------------------------------------------------ шлагбаумы КПП: поднимаются перед грузовиком и опускаются после
local gates = {}
local GATE_OPEN = math.rad(80)
local GATE_SPEED = math.rad(110) -- градусов в секунду
local GATE_TRIGGER = 45        -- на каком расстоянии от шлагбаума он открыт

local function setupGates()
	for _, base in ipairs(workspace.Map.Teams:GetChildren()) do
		local ck = base:FindFirstChild("Decor") and base.Decor:FindFirstChild("Checkpoint")
		local post = ck and ck:FindFirstChild("BarrierPost")
		if post then
			local arms, sum = {}, Vector3.zero
			for _, p in ipairs(ck:GetChildren()) do
				if p.Name == "BarrierArm" then table.insert(arms, p) sum += p.Position end
			end
			if #arms > 0 then
				local center = sum / #arms
				local hinge = Vector3.new(post.Position.X, arms[1].Position.Y, post.Position.Z)
				-- локальная -Z шарнира смотрит вдоль стрелы: поворот вокруг X на + поднимает её
				local hingeCF = CFrame.lookAt(hinge, Vector3.new(center.X, hinge.Y, center.Z))
				local g = {hingeCF = hingeCF, center = center, angle = 0, parts = {}}
				for _, a in ipairs(arms) do table.insert(g.parts, {a, hingeCF:ToObjectSpace(a.CFrame)}) end
				table.insert(gates, g)
			end
		end
	end
end

local function gatesStep(dt)
	for _, g in ipairs(gates) do
		local open = false
		for m, t in pairs(trucks) do
			if t.state == "Driving" and m.Parent then
				local p = m:GetPivot().Position
				if Vector3.new(p.X - g.center.X, 0, p.Z - g.center.Z).Magnitude < GATE_TRIGGER then open = true break end
			end
		end
		local target = open and GATE_OPEN or 0
		if g.angle ~= target then
			local d = target - g.angle
			g.angle += math.clamp(d, -GATE_SPEED * dt, GATE_SPEED * dt)
			for _, p in ipairs(g.parts) do
				p[1].CFrame = g.hingeCF * CFrame.Angles(g.angle, 0, 0) * p[2]
			end
		end
	end
end

------------------------------------------------------------------ потопление
local function sink(route, st, killer)
	if st.dead then return end
	st.dead = true
	NavalPhysics.unregister(st.model)
	local m = st.model
	m:SetAttribute("IsCargo", false)
	m:SetAttribute("State", "Sunk")
	route.delivery = nil
	for _, base in pairs(bases) do
		if base.busy == route then base.busy = nil end
		for i = #base.queue, 1, -1 do
			if base.queue[i] == route then table.remove(base.queue, i) end
		end
	end
	if killer and typeof(killer) == "Instance" and killer:IsA("Player") and TeamService.getTeamName(killer) ~= st.team and (L.SinkReward or 0) > 0 then
		DataService.addGold(killer, L.SinkReward)
		Notifier.send(killer, ("Enemy cargo ship sunk! +%d gold"):format(L.SinkReward), "success")
	end
	if killer and typeof(killer) == "Instance" and killer:IsA("Player") and TeamService.getTeamName(killer) ~= st.team then
		require(script.Parent.RankService).award(killer, "CargoKill")
	end
	if st.team ~= "Neutral" then
		Notifier.team(st.team, ("Cargo ship from %s was sunk, cargo lost"):format(route.def.Name), "error")
	end
	setState(route, "Sunk")
	route.respawnAt = os.clock() + (L.RespawnDelay or 30)
	task.spawn(function()
		SinkFx.run(m, {explosions = 3, radius = 12, width = 10, length = 40,
			ao = st.ao, lv = st.lv, root = st.root, yaw = st.yaw, pitch = 10, roll = 22, speed = 3.5, floor = -60, timeout = 30})
		if m.Parent then m:Destroy() end
	end)
end

function LogisticsService.damage(model, amount, attacker)
	local t = trucks[model]
	if t then
		local at = attacker and TeamService.getTeamName(attacker)
		if at and at == t.team and not Config.Combat.FriendlyFire then return end
		t.health = math.max(0, t.health - amount)
		model:SetAttribute("Health", math.floor(t.health))
		if t.health <= 0 then destroyTruck(t, attacker) end
		return
	end
	for _, route in pairs(routes) do
		local st = route.ship
		if st and st.model == model and not st.dead then
			if st.team == "Neutral" then return end
			local at = attacker and TeamService.getTeamName(attacker)
			if at and at == st.team and not Config.Combat.FriendlyFire then return end
			st.health = math.max(0, st.health - amount)
			model:SetAttribute("Health", math.floor(st.health))
			if st.health <= 0 then sink(route, st, attacker) end
			return
		end
	end
end

------------------------------------------------------------------ рейсы
local function baseApproach(base) return base.berth.Position + base.seaward * 110 end
local function dockApproach(route) return route.dock.Position + route.dock.CFrame.LookVector * 70 end

local function startToBase(route)
	local st = route.ship
	local base = bases[st.team]
	deliverySeq += 1
	route.delivery = {id = ("%s#%d"):format(route.id, deliverySeq), team = st.team}
	local pts = findPath(st.root.Position, baseApproach(base))
	goTo(st, pts, nil)
	setState(route, "ToBase")
end

local function startToIsland(route)
	local st = route.ship
	local pts = findPath(st.root.Position, dockApproach(route))
	table.insert(pts, flat(route.dock.Position))
	goTo(st, pts, route.dock.CFrame.LookVector)
	setState(route, "ToIsland")
end

local function routeStep(route, now)
	if route.state == "Sunk" and CaptureService.getOwner(route.id) == "Neutral" then
		route.ship = nil
		route.state = "Empty" -- respawnAt сохраняем: перезахват не обходит задержку
	end
	if route.state == "Empty" or route.state == "Sunk" then
		if CaptureService.getOwner(route.id) == "Neutral" then
			CaptureService.setExtraStatus(route.id, "")
			return
		end
		if now < (route.respawnAt or 0) then
			CaptureService.setExtraStatus(route.id, ("Ship sunk · new one in %d s"):format(math.ceil(route.respawnAt - now)))
			return
		end
		spawnShip(route)
	end
	local st = route.ship
	if not st or st.dead then return end
	local owner = CaptureService.getOwner(route.id)

	if route.state == "Docked" then
		if owner == "Neutral" then
			despawnShip(route)
			CaptureService.setExtraStatus(route.id, "")
			return
		end
		if st.team ~= owner then
			st.team = owner
			paint(st, owner)
			route.departAt = now + L.Interval
		end
		local loaded = st.containers[1] and st.containers[1].Parent and st.containers[2] and st.containers[2].Parent
		if not loaded and not route.loading then
			if route.crane then
				route.loading = true
				task.spawn(function()
					local ok, err = pcall(loadShip, route.crane, route, st)
					if not ok then
						warn("[LogisticsService] loading " .. route.id .. ": " .. tostring(err))
						-- контейнер на спредере или ещё на площадке (папка Loading — только для груза этого крана,
						-- а погрузка у причала одна за раз: route.loading) — иначе следующий встанет поверх
						route.crane.craneState.carry = nil
						route.crane.loadFolder:ClearAllChildren()
					end
					route.loading = false
				end)
			else
				loadContainers(st)
			end
		end
		route.departAt = route.departAt or (now + L.Interval)
		local left = math.max(0, math.ceil(route.departAt - now))
		CaptureService.setExtraStatus(route.id, route.loading and "Crane loading containers" or ("Departing for base in %d s"):format(left))
		if loaded and not route.loading and now >= route.departAt and NAV.ready then
			route.departAt = nil
			startToBase(route)
		end
		return
	end

	-- остров потерян в пути
	if (route.state == "ToBase" or route.state == "Queued") and owner ~= st.team and L.LostIslandRule ~= "Complete" then
		local base = bases[st.team]
		for i = #base.queue, 1, -1 do
			if base.queue[i] == route then table.remove(base.queue, i) end
		end
		if base.busy == route then base.busy = nil end
		Notifier.team(st.team, ("%s lost — ship returns without payout"):format(route.def.Name), "error")
		route.delivery = nil
		startToIsland(route)
		return
	end

	if route.state == "ToBase" then
		CaptureService.setExtraStatus(route.id, "Ship heading to base " .. Config.Teams[st.team].DisplayName)
		if st.arrived then
			local base = bases[st.team]
			table.insert(base.queue, route)
			setState(route, "Queued")
		end
	elseif route.state == "Queued" then
		local base = bases[st.team]
		CaptureService.setExtraStatus(route.id, "Waiting to unload at base")
		if not base.busy and base.queue[1] == route then
			table.remove(base.queue, 1)
			base.busy = route
			goTo(st, {flat(base.berth.Position)}, base.berth.CFrame.LookVector)
			setState(route, "Berthing")
		end
	elseif route.state == "Berthing" then
		if st.arrived then
			setState(route, "Unloading")
			local base = bases[st.team]
			CaptureService.setExtraStatus(route.id, "Unloading at base")
			LogisticsService._bayTruck(base) -- грузовик подаётся под кран сразу
			task.spawn(function()
				-- ошибка или гибель судна посреди разгрузки не должны навсегда занять причал базы
				-- (base.busy держит очередь: все следующие суда команды ждали бы вечно)
				local okRun, ok = pcall(unload, base, route, st)
				if not okRun then
					warn("[LogisticsService] unload: " .. tostring(ok))
					-- контейнер, оставшийся на спредере, иначе так и ездил бы за краном
					local carry = base.craneState.carry
					base.craneState.carry = nil
					if carry then carry:Destroy() end
				end
				if base.busy == route then base.busy = nil end
				if st.dead then return end
				-- деньги — не сейчас, а когда грузовик довезёт контейнеры в ангар
				if okRun and ok then dispatchTruck(base, route, route.delivery) end
				route.delivery = nil
				startToIsland(route)
			end)
		end
	elseif route.state == "ToIsland" then
		CaptureService.setExtraStatus(route.id, "Ship returning to the island")
		if st.arrived then
			setState(route, "Docked")
			route.departAt = nil
		end
	end
end

------------------------------------------------------------------ движение судов
local function moveStep(st, dt)
	local pos = st.root.Position
	local vy = math.clamp((st.y0 - pos.Y) * 3, -8, 8)
	if st.arrived or not st.path then
		st.speed = 0
		local body = NavalPhysics.get(st.model)
		if body then body.ext, body.spin = Vector3.zero, 0 end -- у причала снос не копится
		if st.finalYaw then
			st.yaw = lerpAngle(st.yaw, st.finalYaw, math.min(1, dt * 0.8))
		end
		st.lv.VectorVelocity = Vector3.new(0, vy, 0)
		st.ao.CFrame = CFrame.Angles(0, st.yaw, 0)
		return
	end
	local target = st.path[st.pi]
	local to = flat(target - pos)
	local dist = to.Magnitude
	local last = st.pi == #st.path
	if dist < (last and 3 or 22) then
		if last then
			st.arrived = true
			st.lv.VectorVelocity = Vector3.new(0, vy, 0)
			return
		end
		st.pi += 1
		return
	end
	local want = yawOf(to.Unit)
	local diff = (want - st.yaw + math.pi) % (2 * math.pi) - math.pi
	local maxTurn = math.rad(L.TurnRate or 30) * dt
	st.yaw += math.clamp(diff, -maxTurn, maxTurn)
	local cruise = L.ShipSpeed
	local speed = cruise * math.max(0.2, math.cos(math.min(math.abs(diff), math.pi / 2)))
	if last then speed = math.min(speed, dist * 0.5 + 2) end
	st.speed = speed
	-- снос от столкновений; дальше судно само возвращается на маршрут (курс — на следующую точку)
	local ext, spin = NavalPhysics.drift(st.model, dt)
	st.yaw += spin * dt
	st.lv.VectorVelocity = fwdOf(st.yaw) * speed + ext + Vector3.new(0, vy, 0)
	st.ao.CFrame = CFrame.Angles(0, st.yaw, 0)
end

------------------------------------------------------------------ API
-- новый раунд: грузовые суда (в пути и у причалов), очереди причалов и грузовики с грузом убираем —
-- груз прошлого раунда в казну нового не попадёт
function LogisticsService.resetAll()
	for id, route in pairs(routes) do
		if route.ship then despawnShip(route) end
		route.delivery, route.respawnAt, route.state = nil, nil, "Empty"
		CaptureService.setExtraStatus(id, "")
	end
	for _, base in pairs(bases) do
		table.clear(base.queue)
		base.busy = nil
		base.bayTruck = nil
	end
	for m, t in pairs(trucks) do
		trucks[m] = nil
		t.delivery, t.state = nil, "Destroyed"
		if m.Parent then m:Destroy() end
	end
	table.clear(paidDeliveries) -- все доставки прошлого раунда отменены
end

function LogisticsService.getShips()
	local list = {}
	for _, route in pairs(routes) do
		local st = route.ship
		if st and not st.dead and st.model.Parent then table.insert(list, st) end
	end
	return list
end

-- только для тестов в Studio: отправить судно немедленно
function LogisticsService.devDepartNow(id)
	local route = routes[id]
	if route and route.state == "Docked" and route.ship and route.ship.team ~= "Neutral" then
		route.departAt = os.clock()
		return true
	end
	return false
end

function LogisticsService.devState()
	local t = {}
	for id, r in pairs(routes) do
		t[id] = {state = r.state, team = r.ship and r.ship.team, pos = r.ship and r.ship.root.Position, delivery = r.delivery and r.delivery.id}
	end
	return t
end

function LogisticsService.init()
	CombatService.onCargoHit = LogisticsService.damage
	-- базы: кран, причал, склад
	for _, team in ipairs(Config.TeamOrder) do
		local b = workspace.Map.Teams:FindFirstChild(team .. "Base")
		local crane = b and b.Shipyard:FindFirstChild("CargoCrane")
		local berth = b and b.Zones:FindFirstChild("Berth_Cargo")
		local yardModel = b and b.Shipyard:FindFirstChild("ContainerYard")
		if crane and berth and yardModel then
			local slots = {}
			for i = 1, (L.YardSlots or 6) do
				local s = yardModel:FindFirstChild("YardSlot" .. i)
				if s then table.insert(slots, s) end
			end
			local yardFolder = Instance.new("Folder")
			yardFolder.Name = "Containers"
			yardFolder.Parent = yardModel
			local mastTop = crane.SlewRoot.Position -- из детали: верно и после переноса модели
			local foot = crane.Footing.Position
			local seaward = flat(berth.Position - foot).Unit
			local base = {
				team = team, crane = crane, berth = berth, slots = slots, yard = {}, yardFolder = yardFolder,
				nextSlot = 0, queue = {}, busy = nil, mastTop = mastTop, seaward = seaward, maxR = 98,
				parts = {
					SlewRoot = crane.SlewRoot, Trolley = crane.Trolley, HookBlock = crane.HookBlock,
					Cable = crane.Cable, Spreader = crane.Spreader,
				},
				craneState = {theta = math.atan2(-seaward.Z, seaward.X), r = 40, sY = 32, spYaw = 0},
			}
			-- стоянка и маршрут грузовика для этой базы
			local s = team == "Red" and -1 or 1
			local bp = Vector3.new(TRUCK_BAY.pos.X * s, 0, TRUCK_BAY.pos.Z * s)
			base.truckBay = CFrame.lookAt(bp, bp + TRUCK_BAY.look * s)
			base.truckPath = {}
			for _, p in ipairs(TRUCK_ROUTE) do table.insert(base.truckPath, Vector3.new(p.X * s, 0, p.Z * s)) end
			bases[team] = base
			craneApply(base)
		else
			warn("[LogisticsService] missing crane/berth/yard at base " .. team)
		end
	end
	-- острова: по одному судну у каждого причала
	for _, def in ipairs(Config.Islands) do
		local outpost = workspace.Map.Neutral:FindFirstChild(def.Outpost)
		local dock = outpost and outpost:FindFirstChild("Capture") and outpost.Capture:FindFirstChild("Dock")
		if dock then
			local route = {id = def.Id, def = def, dock = dock, state = "Empty"}
			local cap = outpost.Capture
			local ic = cap:FindFirstChild("CargoCrane")
			local stack = cap:FindFirstChild("ContainerStack")
			if ic and stack then
				local lf = Instance.new("Folder")
				lf.Name = "Loading"
				lf.Parent = stack
				local cr = {
					mastTop = ic.SlewRoot.Position, maxR = ic:GetAttribute("MaxReach") or 70,
					parts = {SlewRoot = ic.SlewRoot, Trolley = ic.Trolley, HookBlock = ic.HookBlock, Cable = ic.Cable, Spreader = ic.Spreader},
					stackSlots = {stack:FindFirstChild("StackSlot1"), stack:FindFirstChild("StackSlot2")},
					loadFolder = lf,
				}
				local toShip = flat(dock.Position - cr.mastTop)
				cr.craneState = {theta = math.atan2(-toShip.Z, toShip.X), r = 40, sY = cr.mastTop.Y - 14, spYaw = 0}
				craneApply(cr)
				route.crane = cr
			end
			routes[def.Id] = route -- судно появится после захвата (routeStep)
		end
	end
	task.spawn(buildNav)
	-- поверхности, по которым ездят грузовики
	local ground = {workspace.Terrain}
	for _, d in ipairs(workspace.Map.Teams:GetDescendants()) do
		if d:IsA("BasePart") and GROUND_NAMES[d.Name] then table.insert(ground, d) end
	end
	groundParams.FilterDescendantsInstances = ground
	setupGates()

	-- смена владельца у причала — перекраска сразу
	CaptureService.OwnerChanged.Event:Connect(function(id, owner)
		local route = routes[id]
		if route and route.state == "Docked" and route.ship and not route.ship.dead then
			if owner == "Neutral" then
				despawnShip(route)
				CaptureService.setExtraStatus(id, "")
			else
				route.ship.team = owner
				paint(route.ship, owner)
				route.departAt = os.clock() + L.Interval
			end
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, route in pairs(routes) do
			local st = route.ship
			if st and not st.dead and st.model.Parent then moveStep(st, dt) end
		end
		for _, t in pairs(trucks) do truckStep(t, dt) end
		gatesStep(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			local now = os.clock()
			for _, route in pairs(routes) do
				local ok, err = pcall(routeStep, route, now)
				if not ok then warn("[LogisticsService] " .. route.id .. ": " .. tostring(err)) end
			end
		end
	end)
end

return LogisticsService
