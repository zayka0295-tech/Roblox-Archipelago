-- Спаренная зенитная установка. Вперёд = -Z (LookVector) базового CFrame.
-- functional = false: статичная декорация (всё закреплено), yaw/pitch задают позу.
-- functional = true: незакреплённые детали, поворот через Motor6D (TurretPivot→Yoke→GunBody), кресло стрелка.
local T = {}

local function newPart(parent, name, size, cf, color, mat, shape, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.Metal
	if shape then p.Shape = shape end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(opts or {}) do p[k] = v end
	p.Parent = parent
	return p
end
local CYL_UP = CFrame.Angles(0, 0, math.pi / 2)   -- ось цилиндра вверх
local CYL_FWD = CFrame.Angles(0, math.pi / 2, 0)  -- ось цилиндра вперёд (-Z)

function T.build(parent, baseCF, opts)
	opts = opts or {}
	local body = opts.color or Color3.fromRGB(86, 98, 76)
	local dark = Color3.fromRGB(40, 43, 48)
	local yaw, pitch = opts.yaw or 0, opts.pitch or 0
	local functional = opts.functional == true

	local m = Instance.new("Model")
	m.Name = opts.name or "AATurret"

	-- неподвижное основание
	newPart(m, "Pedestal", Vector3.new(3, 8, 8), baseCF * CFrame.new(0, 1.5, 0) * CYL_UP, dark, Enum.Material.Metal, Enum.PartType.Cylinder)
	newPart(m, "Ring", Vector3.new(1, 9, 9), baseCF * CFrame.new(0, 3.5, 0) * CYL_UP, body, Enum.Material.Metal, Enum.PartType.Cylinder)
	local pivot = newPart(m, "TurretPivot", Vector3.new(1, 1, 1), baseCF * CFrame.new(0, 3.5, 0), body, Enum.Material.SmoothPlastic, nil,
		{Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false})

	-- поворотная часть (рыскание)
	local Y = baseCF * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, yaw, 0)
	local yoke = newPart(m, "Yoke", Vector3.new(1, 1, 1), Y, body, Enum.Material.SmoothPlastic, nil,
		{Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false})
	local yokeParts = {
		newPart(m, "YokeDisk", Vector3.new(1, 8, 8), Y * CYL_UP, body, Enum.Material.Metal, Enum.PartType.Cylinder),
		newPart(m, "YokeArm", Vector3.new(0.8, 4.5, 2.6), Y * CFrame.new(2.7, 2.75, 0), body),
		newPart(m, "YokeArm", Vector3.new(0.8, 4.5, 2.6), Y * CFrame.new(-2.7, 2.75, 0), body),
	}

	-- качающаяся часть (тангаж)
	local G = Y * CFrame.new(0, 3.5, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0, -0.75)
	local gun = newPart(m, "GunBody", Vector3.new(3.6, 3, 4.5), G, body)
	local gunParts = {
		newPart(m, "Barrel", Vector3.new(12, 0.6, 0.6), G * CFrame.new(0.8, 0.3, -8.25) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}),
		newPart(m, "Barrel", Vector3.new(12, 0.6, 0.6), G * CFrame.new(-0.8, 0.3, -8.25) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}),
		newPart(m, "Muzzle", Vector3.new(1.4, 1, 1), G * CFrame.new(0.8, 0.3, -14.6) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}),
		newPart(m, "Muzzle2", Vector3.new(1.4, 1, 1), G * CFrame.new(-0.8, 0.3, -14.6) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}),
		newPart(m, "Shield", Vector3.new(5.6, 2.8, 0.3), G * CFrame.new(0, 0.5, -2.5), body),
		newPart(m, "AmmoDrum", Vector3.new(1.4, 2, 2.2), G * CFrame.new(2.5, 0, 0.4), Color3.fromRGB(70, 74, 60)),
		newPart(m, "Sight", Vector3.new(0.4, 0.9, 0.4), G * CFrame.new(0, 1.95, -1.2), dark, Enum.Material.Metal, nil, {CanCollide = false}),
	}

	local seat
	if functional then
		seat = Instance.new("Seat")
		seat.Name = "TurretSeat"
		seat.Size = Vector3.new(2, 1, 2)
		seat.CFrame = Y * CFrame.new(0, 1, 3.8)
		seat.Color = dark
		seat.Material = Enum.Material.Metal
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat:SetAttribute("Turret", true)
		seat.Parent = m
		table.insert(yokeParts, seat)
		table.insert(yokeParts, newPart(m, "SeatBack", Vector3.new(2, 2.4, 0.4), Y * CFrame.new(0, 2.6, 4.9), dark))

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TurretPrompt"
		prompt.ActionText = "Man turret"
		prompt.ObjectText = "Turret"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = m.Pedestal

		-- всё незакреплённое; вращающиеся части крепятся к своим «узлам»
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.Massless = true
			end
		end
		for _, p in ipairs(yokeParts) do
			p:SetAttribute("TurretMoving", true)
			local w = Instance.new("WeldConstraint")
			w.Part0 = yoke
			w.Part1 = p
			w.Parent = p
		end
		for _, p in ipairs(gunParts) do
			p:SetAttribute("TurretMoving", true)
			local w = Instance.new("WeldConstraint")
			w.Part0 = gun
			w.Part1 = p
			w.Parent = p
		end
		yoke:SetAttribute("TurretMoving", true)
		gun:SetAttribute("TurretMoving", true)

		local yawM = Instance.new("Motor6D")
		yawM.Name = "YawMotor"
		yawM.Part0 = pivot
		yawM.Part1 = yoke
		yawM.C0 = CFrame.new(0, 1, 0) * CFrame.Angles(0, yaw, 0)
		yawM.C1 = CFrame.new()
		yawM.Parent = pivot
		local pitchM = Instance.new("Motor6D")
		pitchM.Name = "PitchMotor"
		pitchM.Part0 = yoke
		pitchM.Part1 = gun
		pitchM.C0 = CFrame.new(0, 3.5, 0) * CFrame.Angles(pitch, 0, 0)
		pitchM.C1 = CFrame.new(0, 0, 0.75)
		pitchM.Parent = yoke
	else
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = true end
		end
	end

	m.PrimaryPart = m.Pedestal
	m.Parent = parent
	return m
end

return T
