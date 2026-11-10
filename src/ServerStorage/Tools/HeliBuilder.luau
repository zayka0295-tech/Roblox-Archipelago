-- Конструктор шаблона вертолёта ServerStorage.Vehicles.Helicopter (запускается в Studio один раз, в игре не нужен).
-- Лёгкий транспортно-боевой вертолёт в духе 1950-х: остеклённая кабина, сдвинутая назад боковая дверь,
-- хвостовая балка с килем и хвостовым винтом, двухлопастный несущий винт на мачте, полозья.
-- Оси как у самолётов: вперёд = −Z, вверх = +Y, корень Root в центре кабины; низ полозьев — на GearHeight ниже.
-- Устройство для PlaneService/PlaneClient как у самолётов: Root (FlightAtt, FlightAlign, FlightDrive),
-- PilotSeat (PlaneSeat), GunMuzzle, детали TeamPaint. Винты — Motor6D RotorMotor / TailRotorMotor
-- (атрибуты BaseC0, SpinAxis, SpinRate — их крутит PlaneClient). Место пассажира — Seat PassengerSeat.
--   require(game.ServerStorage.Tools.HeliBuilder).build()  -- заменяет старый шаблон
local H = {}

local rgb = Color3.fromRGB
local BODY = rgb(62, 76, 98)       -- корпус: та же сине-серая гамма, что у самолётов
local BODY_D = rgb(52, 64, 84)     -- панели, дверь
local DARK = rgb(38, 40, 44)       -- металл: мачта, полозья, ствол
local BLADE = rgb(25, 25, 25)
local GLASS = rgb(150, 200, 225)
local WHITE = rgb(235, 235, 235)
local TEAM = rgb(163, 162, 165)    -- перекрашивается в цвет команды (TeamPaint)
local METAL, SMOOTH, GLASSM = Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Glass
local CYL = Enum.PartType.Cylinder
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- ось цилиндра (X) — вдоль Z
local UP = CFrame.Angles(0, 0, math.pi / 2)      -- ось цилиндра — вверх

H.GEAR = 6

function H.build()
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local parts = {}
	local function part(name, size, cf, color, mat, opts, cls)
		local p = Instance.new(cls or "Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat or METAL
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Anchored = false
		p.Massless = true
		for k, v in pairs(opts or {}) do
			if k == "TeamPaint" or k == "NightGen" then p:SetAttribute(k, v) else p[k] = v end
		end
		p.Parent = m
		table.insert(parts, p)
		return p
	end
	local function deco(name, size, cf, color, mat, opts)
		opts = opts or {}
		opts.CanCollide = false
		return part(name, size, cf, color, mat, opts)
	end
	local function cyl(name, len, dia, cf, color, mat, opts)
		opts = opts or {}
		opts.Shape = CYL
		return part(name, Vector3.new(len, dia, dia), cf, color, mat, opts)
	end
	-- стержень между двумя точками (трубы полозьев, стойки)
	local function rod(name, a, b, dia, color)
		local d = b - a
		return part(name, Vector3.new(dia, dia, d.Magnitude), CFrame.lookAt((a + b) / 2, b), color, METAL, {CanCollide = false})
	end

	local root = part("Root", Vector3.new(3, 3, 3), CFrame.new(), BODY, SMOOTH, {
		Transparency = 1, CanCollide = false, Massless = false,
		CustomPhysicalProperties = PhysicalProperties.new(12, 0.3, 0, 1, 1),
	})
	m.PrimaryPart = root

	------------------------------------------------ кабина
	-- пол, крыша, стенки: внутри видно пилота и пассажира (дверь слева сдвинута назад)
	part("Floor", Vector3.new(7.6, 0.6, 16), CFrame.new(0, -3, -1), BODY_D)
	part("Belly", Vector3.new(7, 0.8, 14), CFrame.new(0, -3.6, -0.5), BODY)
	part("Fuselage", Vector3.new(7.6, 0.6, 12), CFrame.new(0, 3, 1), BODY)       -- крыша
	part("RightWall", Vector3.new(0.4, 5.4, 12), CFrame.new(3.6, 0, 1), BODY)
	part("LeftWallRear", Vector3.new(0.4, 5.4, 4), CFrame.new(-3.6, 0, 5), BODY)
	part("LeftPillar", Vector3.new(0.4, 5.4, 1.4), CFrame.new(-3.6, 0, -4.3), BODY)
	part("BackWall", Vector3.new(7.6, 6.6, 0.4), CFrame.new(0, 0, 7), BODY)
	-- сдвижная дверь: откатана назад по рельсам, поверх задней части борта
	part("Door", Vector3.new(0.3, 5.2, 4.4), CFrame.new(-3.95, -0.1, 4.6), BODY_D)
	deco("DoorWindow", Vector3.new(0.12, 1.6, 2.4), CFrame.new(-4.12, 1.0, 4.6), GLASS, GLASSM, {Transparency = 0.3})
	deco("DoorRail", Vector3.new(0.25, 0.25, 11), CFrame.new(-3.95, 2.75, 1.5), DARK)
	deco("DoorRail", Vector3.new(0.25, 0.25, 11), CFrame.new(-3.95, -2.75, 1.5), DARK)
	-- окна правого борта
	for _, z in ipairs({0, 4}) do
		deco("Window", Vector3.new(0.12, 1.6, 2.4), CFrame.new(3.82, 1.0, z), GLASS, GLASSM, {Transparency = 0.3})
	end
	-- носовая часть и остекление
	part("Nose", Vector3.new(7.2, 2.6, 4), CFrame.new(0, -1.6, -7), BODY)
	cyl("NoseCap", 7.2, 3.6, CFrame.new(0, -1.2, -9) * CFrame.Angles(0, 0, 0), BODY, METAL, {})
	deco("NoseStripe", Vector3.new(7.3, 0.6, 4.1), CFrame.new(0, -2.3, -7), TEAM, SMOOTH, {TeamPaint = true})
	deco("Dash", Vector3.new(6.4, 0.8, 1.2), CFrame.new(0, -0.2, -7.4), DARK)
	local slope = math.atan2(3.3, 4)
	deco("Windshield", Vector3.new(7.2, 0.25, 5.2), CFrame.new(0, 1.35, -7) * CFrame.Angles(-slope, 0, 0), GLASS, GLASSM, {Transparency = 0.45})
	deco("WindshieldFrame", Vector3.new(0.35, 0.4, 5.3), CFrame.new(0, 1.4, -7) * CFrame.Angles(-slope, 0, 0), DARK)
	for _, s in ipairs({-1, 1}) do
		-- боковое стекло кабины — клин по скосу лобового (высокий край сзади, к носу сходит на нет), не выступает
		part("SideGlass", Vector3.new(0.2, 3.3, 4), CFrame.new(s * 3.6, 1.35, -7), GLASS, GLASSM, {Transparency = 0.45, CanCollide = false}, "WedgePart")
		deco("CanopyPillar", Vector3.new(0.45, 0.45, 5.4), CFrame.new(s * 3.55, 1.35, -7) * CFrame.Angles(-slope, 0, 0), DARK)
		deco("ChinWindow", Vector3.new(2.4, 0.15, 1.6), CFrame.new(s * 1.8, -2.95, -8), GLASS, GLASSM, {Transparency = 0.3})
	end
	-- опознавательные знаки на бортах
	-- (цилиндр осью X — поперёк борта); слева — на откатанной двери
	for _, pos in ipairs({Vector3.new(3.86, -1.4, 2), Vector3.new(-4.16, -1.4, 4.6)}) do
		local s = math.sign(pos.X)
		deco("RoundelRing", Vector3.new(0.12, 2.8, 2.8), CFrame.new(pos), WHITE, SMOOTH, {Shape = CYL})
		deco("Roundel", Vector3.new(0.12, 1.9, 1.9), CFrame.new(pos + Vector3.new(s * 0.04, 0, 0)), TEAM, SMOOTH, {Shape = CYL, TeamPaint = true})
	end
	-- сиденья: пилот справа спереди, пассажир на скамье сзади лицом к открытой двери
	local seat = part("PilotSeat", Vector3.new(2.4, 0.6, 2.4), CFrame.new(1.6, -2.4, -4.2), DARK, SMOOTH, {CanTouch = false}, "Seat") -- садятся только кнопкой
	seat:SetAttribute("PlaneSeat", true)
	deco("SeatBack", Vector3.new(2.4, 2.6, 0.4), CFrame.new(1.6, -1.0, -2.9), DARK, SMOOTH)
	deco("CopilotSeat", Vector3.new(2.4, 0.6, 2.4), CFrame.new(-1.6, -2.4, -4.2), DARK, SMOOTH)
	deco("SeatBack", Vector3.new(2.4, 2.6, 0.4), CFrame.new(-1.6, -1.0, -2.9), DARK, SMOOTH)
	deco("Stick", Vector3.new(0.25, 1.6, 0.25), CFrame.new(1.6, -1.8, -5.6), DARK)
	local pseat = part("PassengerSeat", Vector3.new(2.4, 0.6, 2.4), CFrame.new(1.4, -2.4, 3.2) * CFrame.Angles(0, math.pi / 2, 0), DARK, SMOOTH, {CanTouch = false}, "Seat")
	pseat:SetAttribute("PassengerSeat", true)
	deco("Bench", Vector3.new(1.2, 2.8, 5.6), CFrame.new(3.0, -1.0, 3.2), BODY_D, SMOOTH)

	------------------------------------------------ двигатель, мачта, несущий винт
	part("EngineHousing", Vector3.new(5, 2.4, 8), CFrame.new(0, 4.4, 2), BODY)
	part("EngineFairing", Vector3.new(4, 1.6, 3), CFrame.new(0, 4.0, -3.2), BODY)
	deco("Intake", Vector3.new(5.1, 1.2, 1.4), CFrame.new(0, 4.6, -1.2), DARK)
	cyl("Exhaust", 2, 1.6, CFrame.new(0, 4.6, 6.6) * ALONG_Z, DARK, METAL, {CanCollide = false})
	cyl("Mast", 2.4, 0.8, CFrame.new(0, 6.6, 0) * UP, DARK, METAL, {CanCollide = false})
	deco("Swashplate", Vector3.new(2.2, 0.4, 2.2), CFrame.new(0, 6.0, 0), DARK)
	local hub = part("RotorHub", Vector3.new(1.4, 0.8, 1.4), CFrame.new(0, 8, 0), DARK, METAL, {CanCollide = false})
	local blades = {
		deco("RotorBlade", Vector3.new(19.5, 0.22, 1.5), CFrame.new(10.4, 8.1, 0), BLADE, SMOOTH),
		deco("RotorBlade", Vector3.new(19.5, 0.22, 1.5), CFrame.new(-10.4, 8.1, 0), BLADE, SMOOTH),
		deco("BladeTip", Vector3.new(1.2, 0.24, 1.52), CFrame.new(19.6, 8.1, 0), TEAM, SMOOTH, {TeamPaint = true}),
		deco("BladeTip", Vector3.new(1.2, 0.24, 1.52), CFrame.new(-19.6, 8.1, 0), TEAM, SMOOTH, {TeamPaint = true}),
		deco("StabBar", Vector3.new(0.2, 0.2, 6), CFrame.new(0, 8.5, 0), DARK),
		deco("StabWeight", Vector3.new(0.5, 0.5, 0.8), CFrame.new(0, 8.5, 3), DARK),
		deco("StabWeight", Vector3.new(0.5, 0.5, 0.8), CFrame.new(0, 8.5, -3), DARK),
	}

	------------------------------------------------ хвостовая балка, киль, хвостовой винт
	part("TailBoom", Vector3.new(3.4, 3, 10), CFrame.new(0, 1.6, 11.8), BODY)
	part("TailBoom2", Vector3.new(2.4, 2.2, 8), CFrame.new(0, 2.0, 20.6), BODY)
	deco("TailBand", Vector3.new(3.5, 3.1, 1.4), CFrame.new(0, 1.6, 15), TEAM, SMOOTH, {TeamPaint = true})
	part("Stabilizer", Vector3.new(8, 0.3, 2), CFrame.new(0, 1.6, 19), BODY)
	for _, s in ipairs({-1, 1}) do
		deco("StabTip", Vector3.new(1, 0.34, 2.04), CFrame.new(s * 3.6, 1.6, 19), TEAM, SMOOTH, {TeamPaint = true})
		deco("NavLight", Vector3.new(0.5, 0.5, 0.5), CFrame.new(s * 4.25, 1.6, 19), s < 0 and rgb(255, 40, 30) or rgb(40, 255, 90), Enum.Material.Neon, {NightGen = true})
	end
	local finTilt = CFrame.Angles(math.rad(22), 0, 0) -- верх киля отклонён назад
	part("Fin", Vector3.new(0.5, 6, 3), CFrame.new(0, 4.6, 25.2) * finTilt, BODY)
	deco("FinStripe", Vector3.new(0.56, 1.2, 3.04), CFrame.new(0, 6.4, 25.95) * finTilt, TEAM, SMOOTH, {TeamPaint = true})
	part("TailSkid", Vector3.new(0.3, 2.2, 0.3), CFrame.new(0, 0.4, 24.2) * CFrame.Angles(math.rad(25), 0, 0), DARK, METAL, {CanCollide = false})
	local tailPos = Vector3.new(0.75, 6.4, 26.4)
	local thub = cyl("TailHub", 0.8, 0.7, CFrame.new(tailPos), DARK, METAL, {CanCollide = false})
	local tblades = {
		deco("TailBlade", Vector3.new(0.18, 6, 0.7), CFrame.new(tailPos + Vector3.new(0.3, 0, 0)), BLADE, SMOOTH),
		deco("TailBladeTip", Vector3.new(0.2, 0.6, 0.72), CFrame.new(tailPos + Vector3.new(0.3, 2.75, 0)), TEAM, SMOOTH, {TeamPaint = true}),
		deco("TailBladeTip", Vector3.new(0.2, 0.6, 0.72), CFrame.new(tailPos + Vector3.new(0.3, -2.75, 0)), TEAM, SMOOTH, {TeamPaint = true}),
	}

	------------------------------------------------ полозья
	local gy = -H.GEAR + 0.35
	for _, s in ipairs({-1, 1}) do
		local x = s * 4.3
		cyl("Skid", 15, 0.7, CFrame.new(x, gy, 0) * ALONG_Z, DARK, METAL, {})
		rod("SkidTip", Vector3.new(x, gy, -7.5), Vector3.new(x, gy + 1.2, -9.2), 0.7, DARK)
		for _, z in ipairs({-4, 4}) do
			rod("SkidStrut", Vector3.new(s * 2.8, -3.8, z), Vector3.new(x, gy, z + (z < 0 and 0.6 or -0.6)), 0.55, DARK)
		end
	end
	for _, z in ipairs({-4, 4}) do
		deco("CrossTube", Vector3.new(5.6, 0.55, 0.55), CFrame.new(0, -3.9, z), DARK)
	end

	------------------------------------------------ пулемёт (стреляет пилот, как у самолётов)
	deco("GunMount", Vector3.new(1.4, 0.8, 1.6), CFrame.new(4.2, -2.4, -5), DARK)
	cyl("GunBarrel", 4, 0.45, CFrame.new(4.6, -2.4, -7.2) * ALONG_Z, DARK, METAL, {CanCollide = false})
	deco("AmmoBox", Vector3.new(0.9, 1.0, 1.4), CFrame.new(4.6, -2.9, -4.6), rgb(70, 75, 50))
	deco("GunMuzzle", Vector3.new(0.6, 0.6, 0.6), CFrame.new(4.6, -2.4, -9.3), DARK)

	------------------------------------------------ сварка, полётные силы, винты
	for _, p in ipairs(parts) do
		if p ~= root and p ~= hub and p ~= thub and not table.find(blades, p) and not table.find(tblades, p) then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, p
			w.Parent = p
		end
	end
	for _, b in ipairs(blades) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hub, b
		w.Parent = b
	end
	for _, b in ipairs(tblades) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = thub, b
		w.Parent = b
	end
	local function motor(name, part1, c0, axis, rate)
		local mt = Instance.new("Motor6D")
		mt.Name = name
		mt.Part0, mt.Part1 = root, part1
		mt.C0 = c0
		mt:SetAttribute("BaseC0", c0)
		mt:SetAttribute("SpinAxis", axis)
		mt:SetAttribute("SpinRate", rate)
		mt.Parent = root
	end
	motor("RotorMotor", hub, CFrame.new(0, 8, 0), "Y", 0.6)
	motor("TailRotorMotor", thub, CFrame.new(tailPos), "X", 1.2)

	local att = Instance.new("Attachment")
	att.Name = "FlightAtt"
	att.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "FlightAlign"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 3375000064
	ao.Responsiveness = 40
	ao.Enabled = false
	ao.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "FlightDrive"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 33750000
	lv.Enabled = false
	lv.Parent = root

	m:SetAttribute("IsPlane", true)
	m:SetAttribute("GearHeight", H.GEAR)
	m:SetAttribute("IsHeli", true)

	local vehicles = game:GetService("ServerStorage"):FindFirstChild("Vehicles")
	if vehicles then
		local old = vehicles:FindFirstChild("Helicopter")
		if old then old:Destroy() end
		m.Parent = vehicles
	end
	return m
end

return H
