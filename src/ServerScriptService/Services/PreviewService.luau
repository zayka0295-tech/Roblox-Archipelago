-- Мини-модели техники для меню ангара и верфи (ViewportFrame на клиенте): копии шаблонов
-- из ServerStorage без скриптов, связей и света — в ReplicatedStorage.VehiclePreviews[тип].
-- Исключения — карточки выбора точки появления: настоящие острова — Terrain, который ViewportFrame не показывает,
-- поэтому строим игрушечные модели из деталей: Base — база команды, CentralIsland — центральный форт
-- с аэродромом (детали TeamPaint клиент красит в цвет команды). Island — прежний игрушечный остров.
-- Parachute — купол-крыло с ранцем для военного базара (BazaarUI).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local PreviewService = {}

-- что оставляем: детали и их внешний вид
local KEEP = {"BasePart", "Model", "Folder", "DataModelMesh", "Decal", "SurfaceAppearance"}
local function keep(d)
	for _, c in ipairs(KEEP) do
		if d:IsA(c) then return true end
	end
	return false
end

local function strip(template, name)
	local m = template:Clone()
	m.Name = name
	local desc = m:GetDescendants()
	for i = #desc, 1, -1 do
		local d = desc[i]
		if d.Parent and not keep(d) then d:Destroy() end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return m
end

-- мини-остров базы: вода, песок, трава, полоса с самолётом, ангар, вышка, причал, деревья, флаг
local function buildIsland()
	local m = Instance.new("Model")
	m.Name = "Island"
	local function p(props, teamPaint)
		local x = Instance.new("Part")
		x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch = true, false, false, false
		x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		x.Material = Enum.Material.SmoothPlastic
		for k, v in pairs(props) do x[k] = v end
		if teamPaint then x:SetAttribute("TeamPaint", true) end
		x.Parent = m
		return x
	end
	local up = CFrame.Angles(0, 0, math.rad(90)) -- цилиндр осью вверх
	local function disc(name, y, h, d, color)
		return p({Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, d, d), CFrame = CFrame.new(0, y, 0) * up, Color = color})
	end
	disc("Water", -1, 1, 120, Color3.fromRGB(40, 110, 170))
	disc("Shallows", -0.6, 1, 92, Color3.fromRGB(70, 170, 200))
	disc("Sand", 0, 2, 80, Color3.fromRGB(226, 205, 150))
	disc("Grass", 0.6, 2, 70, Color3.fromRGB(96, 160, 72))
	local top = 1.6
	local grey = Color3.fromRGB(200, 205, 215)
	-- взлётная полоса с разметкой и самолётом
	p({Name = "Runway", Size = Vector3.new(10, 0.3, 54), CFrame = CFrame.new(-12, top + 0.15, 2), Color = Color3.fromRGB(58, 62, 70)})
	for i = -4, 4 do
		p({Name = "Stripe", Size = Vector3.new(0.8, 0.32, 3), CFrame = CFrame.new(-12, top + 0.17, 2 + i * 5.5), Color = Color3.new(1, 1, 1)})
	end
	local jet = CFrame.new(-12, top + 1.2, 14)
	p({Name = "PlaneBody", Size = Vector3.new(1.4, 1.2, 7), CFrame = jet, Color = grey})
	p({Name = "PlaneWing", Size = Vector3.new(9, 0.3, 2), CFrame = jet * CFrame.new(0, 0, 0.5), Color = grey}, true)
	p({Name = "PlaneTail", Size = Vector3.new(3.5, 0.3, 1.2), CFrame = jet * CFrame.new(0, 0, 3), Color = grey})
	p({Name = "PlaneFin", Size = Vector3.new(0.3, 1.8, 1.2), CFrame = jet * CFrame.new(0, 1, 3), Color = grey}, true)
	-- ангар с полукруглой крышей
	p({Name = "Hangar", Size = Vector3.new(12, 5, 10), CFrame = CFrame.new(4, top + 2.5, -12), Color = Color3.fromRGB(150, 156, 166)})
	p({Name = "HangarRoof", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10.4, 12, 12), CFrame = CFrame.new(4, top + 5, -12) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(120, 126, 138)})
	p({Name = "HangarDoor", Size = Vector3.new(8, 4.4, 0.3), CFrame = CFrame.new(4, top + 2.2, -6.9), Color = Color3.fromRGB(60, 64, 72)})
	p({Name = "HangarStripe", Size = Vector3.new(12.2, 1, 10.2), CFrame = CFrame.new(4, top + 4, -12), Color = Color3.fromRGB(200, 200, 200)}, true)
	-- диспетчерская вышка
	p({Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(12, 3, 3), CFrame = CFrame.new(16, top + 6, -2) * up, Color = Color3.fromRGB(225, 225, 225)})
	p({Name = "TowerCab", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 5.6, 5.6), CFrame = CFrame.new(16, top + 12.6, -2) * up, Color = Color3.fromRGB(90, 180, 230), Material = Enum.Material.Glass, Transparency = 0.15})
	p({Name = "TowerRoof", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 6.4, 6.4), CFrame = CFrame.new(16, top + 14.3, -2) * up, Color = Color3.fromRGB(70, 74, 82)})
	-- склады
	p({Name = "Depot", Size = Vector3.new(6, 3, 5), CFrame = CFrame.new(12, top + 1.5, 12), Color = Color3.fromRGB(176, 140, 96)})
	p({Name = "Depot2", Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(19, top + 2, 10), Color = Color3.fromRGB(110, 120, 96)})
	-- причал
	p({Name = "Dock", Size = Vector3.new(4, 0.6, 18), CFrame = CFrame.new(22, 0.5, 30) * CFrame.Angles(0, math.rad(-35), 0), Color = Color3.fromRGB(130, 96, 60), Material = Enum.Material.WoodPlanks})
	-- деревья
	for _, t in ipairs({{-26, -16}, {-22, -24}, {24, -18}, {28, 4}, {-28, 14}, {-2, 26}, {6, 28}}) do
		p({Name = "Trunk", Size = Vector3.new(0.8, 4, 0.8), CFrame = CFrame.new(t[1], top + 2, t[2]), Color = Color3.fromRGB(110, 76, 44)})
		p({Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), CFrame = CFrame.new(t[1], top + 5, t[2]), Color = Color3.fromRGB(60, 130, 56)})
	end
	-- флаг команды
	p({Name = "FlagPole", Size = Vector3.new(0.4, 12, 0.4), CFrame = CFrame.new(-2, top + 6, -2), Color = Color3.fromRGB(230, 230, 230)})
	p({Name = "Flag", Size = Vector3.new(0.2, 3, 5), CFrame = CFrame.new(-2, top + 10.5, 0.6), Color = Color3.fromRGB(200, 200, 200)}, true)
	return m
end

-- общая «лепка» игрушечных моделей
local function maker(m)
	local function p(props, teamPaint)
		local x = Instance.new("Part")
		x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch = true, false, false, false
		x.TopSurface, x.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		x.Material = Enum.Material.SmoothPlastic
		for k, v in pairs(props) do x[k] = v end
		if teamPaint then x:SetAttribute("TeamPaint", true) end
		x.Parent = m
		return x
	end
	return p
end
local UP = CFrame.Angles(0, 0, math.rad(90)) -- цилиндр осью вверх
local function tree(p, x, z, top)
	p({Name = "Trunk", Size = Vector3.new(0.8, 4, 0.8), CFrame = CFrame.new(x, top + 2, z), Color = Color3.fromRGB(110, 76, 44)})
	p({Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), CFrame = CFrame.new(x, top + 5, z), Color = Color3.fromRGB(60, 130, 56)})
end
local function plane(p, cf)
	local grey = Color3.fromRGB(200, 205, 215)
	p({Name = "PlaneBody", Size = Vector3.new(1.4, 1.2, 7), CFrame = cf, Color = grey})
	p({Name = "PlaneWing", Size = Vector3.new(9, 0.3, 2), CFrame = cf * CFrame.new(0, 0, 0.5), Color = grey}, true)
	p({Name = "PlaneTail", Size = Vector3.new(3.5, 0.3, 1.2), CFrame = cf * CFrame.new(0, 0, 3), Color = grey})
	p({Name = "PlaneFin", Size = Vector3.new(0.3, 1.8, 1.2), CFrame = cf * CFrame.new(0, 1, 3), Color = grey}, true)
end

-- мини-база команды: суша с полосой, площадь с эмблемой, казармы, ангар, вышки, забор, флаг
local function buildBase()
	local m = Instance.new("Model")
	m.Name = "Base"
	local p = maker(m)
	local top = 1
	p({Name = "Water", Size = Vector3.new(120, 1, 90), CFrame = CFrame.new(0, -0.6, 0), Color = Color3.fromRGB(40, 110, 170)})
	p({Name = "Sand", Size = Vector3.new(104, 1.4, 76), CFrame = CFrame.new(0, 0, 0), Color = Color3.fromRGB(226, 205, 150)})
	p({Name = "Grass", Size = Vector3.new(98, 1.6, 70), CFrame = CFrame.new(0, 0.2, 0), Color = Color3.fromRGB(96, 160, 72)})
	-- площадь и эмблема команды
	p({Name = "Plaza", Size = Vector3.new(26, 0.3, 26), CFrame = CFrame.new(10, top + 0.15, 0), Color = Color3.fromRGB(150, 154, 162)})
	p({Name = "Emblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 9, 9), CFrame = CFrame.new(10, top + 0.32, 0) * UP, Color = Color3.fromRGB(200, 200, 200)}, true)
	for _, z in ipairs({-8, 8}) do
		for _, x in ipairs({2, 10, 18}) do
			p({Name = "SpawnPad", Size = Vector3.new(2.4, 0.35, 2.4), CFrame = CFrame.new(x, top + 0.33, z), Color = Color3.fromRGB(200, 200, 200)}, true)
		end
	end
	-- казармы: четыре корпуса с полосой цвета команды
	for _, b in ipairs({{12, -24}, {28, -24}, {12, 24}, {28, 24}}) do
		p({Name = "Barracks", Size = Vector3.new(13, 4, 6), CFrame = CFrame.new(b[1], top + 2, b[2]), Color = Color3.fromRGB(80, 96, 88)})
		p({Name = "BarracksRoof", Size = Vector3.new(13.6, 0.5, 6.6), CFrame = CFrame.new(b[1], top + 4.25, b[2]), Color = Color3.fromRGB(46, 52, 62)})
		p({Name = "BarracksStripe", Size = Vector3.new(13.7, 0.5, 6.7), CFrame = CFrame.new(b[1], top + 3.7, b[2]), Color = Color3.fromRGB(200, 200, 200)}, true)
	end
	-- большой ангар техники
	p({Name = "Hangar", Size = Vector3.new(12, 7, 22), CFrame = CFrame.new(-30, top + 3.5, 4), Color = Color3.fromRGB(70, 82, 100)})
	p({Name = "HangarRoof", Size = Vector3.new(13, 0.6, 23), CFrame = CFrame.new(-30, top + 7.3, 4), Color = Color3.fromRGB(46, 52, 62)})
	p({Name = "HangarStripe", Size = Vector3.new(13.1, 0.6, 23.1), CFrame = CFrame.new(-30, top + 6.6, 4), Color = Color3.fromRGB(200, 200, 200)}, true)
	-- взлётная полоса с самолётом
	p({Name = "Runway", Size = Vector3.new(70, 0.3, 8), CFrame = CFrame.new(-8, top + 0.15, -30), Color = Color3.fromRGB(58, 62, 70)})
	for i = -5, 5 do
		p({Name = "Stripe", Size = Vector3.new(3, 0.32, 0.6), CFrame = CFrame.new(-8 + i * 6, top + 0.17, -30), Color = Color3.new(1, 1, 1)})
	end
	plane(p, CFrame.new(-30, top + 1.2, -30) * CFrame.Angles(0, math.rad(-90), 0))
	-- вышки по углам и забор
	for _, w in ipairs({{-44, -32}, {44, -32}, {-44, 32}, {44, 32}}) do
		p({Name = "Tower", Size = Vector3.new(0.6, 9, 0.6), CFrame = CFrame.new(w[1], top + 4.5, w[2]), Color = Color3.fromRGB(46, 52, 62)})
		p({Name = "TowerCab", Size = Vector3.new(3.4, 2, 3.4), CFrame = CFrame.new(w[1], top + 9.6, w[2]), Color = Color3.fromRGB(60, 70, 66)})
	end
	for _, f in ipairs({{0, -33.5, 88, 0.3}, {0, 33.5, 88, 0.3}, {-44.5, 0, 0.3, 67}, {44.5, 0, 0.3, 67}}) do
		p({Name = "Fence", Size = Vector3.new(f[3], 2, f[4]), CFrame = CFrame.new(f[1], top + 1, f[2]), Color = Color3.fromRGB(150, 160, 170), Transparency = 0.4})
	end
	for _, t in ipairs({{-14, 22}, {-20, 26}, {40, -4}, {38, 8}}) do tree(p, t[1], t[2], top) end
	p({Name = "FlagPole", Size = Vector3.new(0.4, 13, 0.4), CFrame = CFrame.new(10, top + 6.5, 0), Color = Color3.fromRGB(230, 230, 230)})
	p({Name = "Flag", Size = Vector3.new(0.2, 3, 5), CFrame = CFrame.new(10, top + 11.5, 2.6), Color = Color3.fromRGB(200, 200, 200)}, true)
	return m
end

-- мини-центральный остров: форт со стенами и башней, аэродром с двумя полукруглыми ангарами, контейнеры
local function buildCentral()
	local m = Instance.new("Model")
	m.Name = "CentralIsland"
	local p = maker(m)
	local function disc(name, y, h, d, color)
		return p({Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, d, d), CFrame = CFrame.new(0, y, 0) * UP, Color = color})
	end
	disc("Water", -1, 1, 124, Color3.fromRGB(40, 110, 170))
	disc("Shallows", -0.6, 1, 96, Color3.fromRGB(70, 170, 200))
	disc("Sand", 0, 2, 84, Color3.fromRGB(226, 205, 150))
	disc("Grass", 0.6, 2, 76, Color3.fromRGB(96, 160, 72))
	local top = 1.6
	-- форт: восьмиугольник стен, двор, башня
	disc("FortYard", top + 0.1, 0.3, 30, Color3.fromRGB(160, 164, 172))
	for i = 0, 7 do
		local a = math.rad(i * 45 + 22.5)
		p({Name = "Wall", Size = Vector3.new(13, 3, 1.2), CFrame = CFrame.new(math.cos(a) * 16, top + 1.5, math.sin(a) * 16 - 4) * CFrame.Angles(0, -a + math.pi / 2, 0), Color = Color3.fromRGB(130, 134, 142)})
	end
	p({Name = "Tower", Size = Vector3.new(3, 12, 3), CFrame = CFrame.new(-3, top + 6, -4), Color = Color3.fromRGB(80, 90, 104)})
	p({Name = "TowerCab", Size = Vector3.new(6, 2.4, 6), CFrame = CFrame.new(-3, top + 13, -4), Color = Color3.fromRGB(40, 48, 60)})
	p({Name = "TowerGlass", Size = Vector3.new(6.2, 1, 6.2), CFrame = CFrame.new(-3, top + 13, -4), Color = Color3.fromRGB(90, 180, 230), Material = Enum.Material.Glass})
	p({Name = "FlagPole", Size = Vector3.new(0.4, 10, 0.4), CFrame = CFrame.new(4, top + 5, -4), Color = Color3.fromRGB(230, 230, 230)})
	p({Name = "Flag", Size = Vector3.new(0.2, 2.6, 4.4), CFrame = CFrame.new(4, top + 8.8, -1.8), Color = Color3.fromRGB(200, 200, 200)}, true)
	for i, c in ipairs({Color3.fromRGB(150, 60, 50), Color3.fromRGB(60, 90, 120), Color3.fromRGB(70, 110, 70)}) do
		p({Name = "Container", Size = Vector3.new(2.2, 2.2, 5), CFrame = CFrame.new(-10 + i * 2.4, top + 1.1, 4), Color = c})
	end
	-- аэродром у южного берега
	p({Name = "Runway", Size = Vector3.new(56, 0.3, 7), CFrame = CFrame.new(0, top + 0.15, 22), Color = Color3.fromRGB(58, 62, 70)})
	for i = -4, 4 do
		p({Name = "Stripe", Size = Vector3.new(3, 0.32, 0.5), CFrame = CFrame.new(i * 6, top + 0.17, 22), Color = Color3.new(1, 1, 1)})
	end
	plane(p, CFrame.new(-20, top + 1.2, 22) * CFrame.Angles(0, math.rad(-90), 0))
	for _, x in ipairs({-22, -14}) do
		p({Name = "Hangar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 7, 7), CFrame = CFrame.new(x, top, 13) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(215, 218, 222)})
	end
	for _, t in ipairs({{-28, -10}, {-24, -18}, {26, -12}, {30, 2}, {22, -22}}) do tree(p, t[1], t[2], top) end
	return m
end

-- парашют для витрины базара: купол-крыло (секции по дуге, через одну — цвет команды), стропы, ранец с лямками
local function buildParachute()
	local m = Instance.new("Model")
	m.Name = "Parachute"
	local p = maker(m)
	local white, dark = Color3.fromRGB(236, 236, 230), Color3.fromRGB(25, 25, 25)
	local CELLS, SPAN, CHORD, R, TOP = 9, 19, 6.5, 15, 15
	local step = SPAN / CELLS / R
	local left, right = Vector3.new(-1.1, 4.2, 0), Vector3.new(1.1, 4.2, 0)
	local function line(a, b, color, w)
		p({Name = "Line", Size = Vector3.new(w or 0.08, w or 0.08, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = color or Color3.fromRGB(210, 210, 205)})
	end
	for i = 1, CELLS do
		local a = (i - (CELLS + 1) / 2) * step
		local cell = CFrame.new(math.sin(a) * R, TOP + math.cos(a) * R - R, 0) * CFrame.Angles(0, 0, -a)
		p({Name = "Cell", Size = Vector3.new(SPAN / CELLS + 0.08, 0.9, CHORD), CFrame = cell, Color = white, Material = Enum.Material.Fabric}, i % 2 == 1)
		p({Name = "Intake", Size = Vector3.new(SPAN / CELLS - 0.25, 0.55, 0.12), CFrame = cell * CFrame.new(0, -0.05, -CHORD / 2 - 0.02), Color = dark})
		local riser = a < 0 and left or right
		line((cell * CFrame.new(0, -0.45, -CHORD / 2 + 0.6)).Position, riser)
		line((cell * CFrame.new(0, -0.45, CHORD / 2 - 0.8)).Position, riser)
	end
	-- ранец: контейнер, клапан, вытяжное кольцо, лямки; свободные концы от плеч к стропам
	local olive = Color3.fromRGB(74, 82, 60)
	p({Name = "Container", Size = Vector3.new(1.9, 2.1, 0.9), CFrame = CFrame.new(0, 0.4, 0.5), Color = olive, Material = Enum.Material.Fabric})
	p({Name = "Flap", Size = Vector3.new(1.95, 0.5, 0.95), CFrame = CFrame.new(0, 1.25, 0.52), Color = olive:Lerp(Color3.new(0, 0, 0), 0.25), Material = Enum.Material.Fabric})
	p({Name = "Ripcord", Size = Vector3.new(0.3, 0.3, 0.2), CFrame = CFrame.new(0.75, -0.2, 1), Color = Color3.fromRGB(220, 60, 40)})
	for _, s in ipairs({-1, 1}) do
		p({Name = "Strap", Size = Vector3.new(0.22, 2.2, 0.12), CFrame = CFrame.new(s * 0.55, 0.4, -0.1), Color = Color3.fromRGB(35, 35, 35)})
		line(Vector3.new(s * 0.75, 1.5, 0.1), s < 0 and left or right, Color3.fromRGB(40, 40, 40), 0.22)
		p({Name = "Toggle", Size = Vector3.new(0.35, 0.5, 0.35), CFrame = CFrame.new(s * 1.15, 3.6, -0.15), Color = Color3.fromRGB(230, 120, 30)})
	end
	return m
end

function PreviewService.init()
	local folder = Instance.new("Folder")
	folder.Name = "VehiclePreviews"
	local sources = {Carrier = ServerStorage.Ships:FindFirstChild("AircraftCarrier")}
	for kind, P in pairs(Config.Planes) do
		sources[kind] = ServerStorage.Vehicles:FindFirstChild(P.Model or kind)
	end
	for kind in pairs(Config.Ships) do
		sources[kind] = ServerStorage.Ships:FindFirstChild(kind)
	end
	for kind, template in pairs(sources) do
		if template then strip(template, kind).Parent = folder end
	end
	buildIsland().Parent = folder
	buildBase().Parent = folder
	buildCentral().Parent = folder
	buildParachute().Parent = folder
	folder.Parent = ReplicatedStorage
end

return PreviewService
