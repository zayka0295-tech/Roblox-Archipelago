-- Конструктор кораблей и морских башен. Корабль: нос = +Z, пивот на ватерлинии.
-- Башня: вперёд = -Z базового CFrame; схема TurretPivot→Yoke→GunBody (как у зениток).
local N = {}

local CYL_UP = CFrame.Angles(0, 0, math.pi / 2)
local CYL_FWD = CFrame.Angles(0, math.pi / 2, 0)
N.CYL_UP, N.CYL_FWD = CYL_UP, CYL_FWD

function N.part(parent, name, size, cf, color, mat, shape, opts)
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
local P = N.part

-- половина клиновидного носа (в плане), sx = ±1
function N.bowHalf(parent, name, h, w, l, y, zBack, color, mat, sx)
	local up = sx > 0 and Vector3.new(1, 0, 0) or Vector3.new(-1, 0, 0)
	local right = sx > 0 and Vector3.new(0, 1, 0) or Vector3.new(0, -1, 0)
	local w2 = Instance.new("WedgePart")
	w2.Name = name
	w2.Size = Vector3.new(h, w, l)
	w2.CFrame = CFrame.fromMatrix(Vector3.new(sx * w / 2, y, zBack + l / 2), right, up, Vector3.new(0, 0, -1))
	w2.Color = color
	w2.Material = mat or Enum.Material.Metal
	w2.TopSurface = Enum.SurfaceType.Smooth
	w2.BottomSurface = Enum.SurfaceType.Smooth
	w2.Parent = parent
	return w2
end

local function seat(parent, name, cf, attrs)
	local s = Instance.new("Seat")
	s.Name = name
	s.Size = Vector3.new(2, 0.6, 2)
	s.CFrame = cf
	s.Color = Color3.fromRGB(40, 43, 48)
	s.Material = Enum.Material.Metal
	s.TopSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(attrs or {}) do s:SetAttribute(k, v) end
	s.Parent = parent
	return s
end
N.seat = seat

------------------------------------------------------------------ башни
function N.turret(parent, baseCF, opts)
	local style = opts.style or "heavy"
	local body = opts.color or Color3.fromRGB(120, 126, 134)
	local dark = Color3.fromRGB(42, 45, 50)
	local m = Instance.new("Model")
	m.Name = opts.name or "Turret"
	local yawParts, gunParts = {}, {}
	local yawOff, pitchOff, c1z, pivotY

	if style == "heavy" then
		P(m, "Pedestal", Vector3.new(3, 18, 18), baseCF * CFrame.new(0, 1.5, 0) * CYL_UP, dark, Enum.Material.Metal, Enum.PartType.Cylinder)
		P(m, "Ring", Vector3.new(0.6, 18.6, 18.6), baseCF * CFrame.new(0, 3.2, 0) * CYL_UP, body, Enum.Material.Metal, Enum.PartType.Cylinder)
		pivotY, yawOff, pitchOff, c1z = 3.5, Vector3.new(0, 1, 0), Vector3.new(0, 3.2, -6), 0.5
	else
		P(m, "Pedestal", Vector3.new(1.6, 5, 5), baseCF * CFrame.new(0, 0.8, 0) * CYL_UP, dark, Enum.Material.Metal, Enum.PartType.Cylinder)
		pivotY, yawOff, pitchOff, c1z = 1.6, Vector3.new(0, 0.8, 0), Vector3.new(0, 1.4, -0.6), 0.6
	end
	local pivot = P(m, "TurretPivot", Vector3.new(1, 1, 1), baseCF * CFrame.new(0, pivotY, 0), body, Enum.Material.SmoothPlastic, nil,
		{Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false})
	local Y = baseCF * CFrame.new(0, pivotY, 0) * CFrame.new(yawOff)
	local yoke = P(m, "Yoke", Vector3.new(1, 1, 1), Y, body, Enum.Material.SmoothPlastic, nil,
		{Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false})
	local G = Y * CFrame.new(pitchOff) * CFrame.new(0, 0, -c1z)
	local gun

	if style == "heavy" then
		table.insert(yawParts, P(m, "House", Vector3.new(15, 7, 17), Y * CFrame.new(0, 3.5, 1.5), body))
		table.insert(yawParts, P(m, "HouseRoof", Vector3.new(15.4, 0.6, 17.4), Y * CFrame.new(0, 7.3, 1.5), Color3.fromRGB(100, 106, 114)))
		table.insert(yawParts, P(m, "RangeFinder", Vector3.new(16, 1.4, 1.4), Y * CFrame.new(0, 6, 8.5), dark))
		table.insert(yawParts, P(m, "GunnerShield", Vector3.new(3.2, 1.8, 0.3), Y * CFrame.new(0, 8.5, 3.6), dark))
		gun = P(m, "GunBody", Vector3.new(11, 3.6, 3), G, dark)
		local names = {"Muzzle", "Muzzle2", "Muzzle3"}
		for i, x in ipairs({-3.4, 0, 3.4}) do
			table.insert(gunParts, P(m, "Barrel", Vector3.new(24, 1.5, 1.5), G * CFrame.new(x, 0, -13.5) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}))
			table.insert(gunParts, P(m, names[i], Vector3.new(1.6, 1.9, 1.9), G * CFrame.new(x, 0, -25.8) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}))
		end
		if opts.seat ~= false then
			local s = seat(m, "TurretSeat", Y * CFrame.new(0, 7.9, 6), {Turret = true})
			table.insert(yawParts, s)
			table.insert(yawParts, P(m, "SeatBack", Vector3.new(2, 2.2, 0.4), Y * CFrame.new(0, 9, 7.2), dark))
			local pr = Instance.new("ProximityPrompt")
			pr.Name = "TurretPrompt"
			pr.ActionText = "Man turret"
			pr.ObjectText = "Main battery"
			pr.HoldDuration = 0.3
			pr.MaxActivationDistance = 16
			pr.RequiresLineOfSight = false
			pr.Parent = m.Pedestal
		end
	else
		table.insert(yawParts, P(m, "YokeDisk", Vector3.new(0.6, 4.4, 4.4), Y * CYL_UP, body, Enum.Material.Metal, Enum.PartType.Cylinder))
		table.insert(yawParts, P(m, "Shield", Vector3.new(4.2, 3, 0.4), Y * CFrame.new(0, 1.7, -1.6), body))
		table.insert(yawParts, P(m, "Cheek", Vector3.new(0.4, 2.4, 2.4), Y * CFrame.new(1.6, 1.4, -0.4), body))
		table.insert(yawParts, P(m, "Cheek", Vector3.new(0.4, 2.4, 2.4), Y * CFrame.new(-1.6, 1.4, -0.4), body))
		gun = P(m, "GunBody", Vector3.new(1.6, 1.4, 2.4), G, dark)
		table.insert(gunParts, P(m, "Barrel", Vector3.new(8, 0.55, 0.55), G * CFrame.new(0, 0, -5) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}))
		table.insert(gunParts, P(m, "Muzzle", Vector3.new(0.9, 0.8, 0.8), G * CFrame.new(0, 0, -9.2) * CYL_FWD, dark, Enum.Material.Metal, Enum.PartType.Cylinder, {CanCollide = false}))
	end

	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
		end
	end
	for _, p in ipairs(yawParts) do
		p:SetAttribute("TurretMoving", true)
		local w = Instance.new("WeldConstraint"); w.Part0 = yoke; w.Part1 = p; w.Parent = p
	end
	for _, p in ipairs(gunParts) do
		p:SetAttribute("TurretMoving", true)
		local w = Instance.new("WeldConstraint"); w.Part0 = gun; w.Part1 = p; w.Parent = p
	end
	yoke:SetAttribute("TurretMoving", true)
	gun:SetAttribute("TurretMoving", true)
	local ym = Instance.new("Motor6D")
	ym.Name = "YawMotor"; ym.Part0 = pivot; ym.Part1 = yoke
	ym.C0 = CFrame.new(yawOff); ym.C1 = CFrame.new()
	ym.Parent = pivot
	local pm = Instance.new("Motor6D")
	pm.Name = "PitchMotor"; pm.Part0 = yoke; pm.Part1 = gun
	pm.C0 = CFrame.new(pitchOff); pm.C1 = CFrame.new(0, 0, c1z)
	pm.Parent = yoke

	m:SetAttribute("WeaponType", style == "heavy" and "Heavy" or "Medium")
	m:SetAttribute("ShipTurret", true)
	m.PrimaryPart = m.Pedestal
	m.Parent = parent
	return m
end

------------------------------------------------------------------ сборка корабля
function N.finalize(m)
	local hull = m:FindFirstChild("Hull")
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= hull then
			d.Anchored = false
			d.Massless = true
			if not d:GetAttribute("TurretMoving") and not d:FindFirstChildOfClass("WeldConstraint") then
				local w = Instance.new("WeldConstraint"); w.Part0 = hull; w.Part1 = d; w.Parent = d
			end
		end
	end
	hull.Anchored = false
	hull.RootPriority = 127
	local att = Instance.new("Attachment"); att.Name = "CtrlAtt"; att.Parent = hull
	local ao = Instance.new("AlignOrientation")
	ao.Name = "HelmAlign"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 40
	ao.Parent = hull
	local lv = Instance.new("LinearVelocity")
	lv.Name = "HelmDrive"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hull
	m.PrimaryPart = m:FindFirstChild("Pivot") or hull
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return m
end

function N.pivotPart(m)
	return P(m, "Pivot", Vector3.new(1, 1, 1), CFrame.new(), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, nil,
		{Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false})
end

function N.helmAccess(m, pos, exitPos, label)
	local a = P(m, "HelmAccess", Vector3.new(2.4, 3.6, 1.6), CFrame.new(pos), Color3.fromRGB(40, 44, 52))
	P(m, "HelmAccessScreen", Vector3.new(2, 1.8, 0.3), CFrame.new(pos + Vector3.new(0, 0.6, -0.85)), Color3.fromRGB(70, 200, 255), Enum.Material.Neon, nil, {CanCollide = false})
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "HelmPrompt"
	pr.ActionText = "Take the helm"
	pr.ObjectText = label or "Bridge"
	pr.HoldDuration = 0.3
	pr.MaxActivationDistance = 12
	pr.RequiresLineOfSight = false
	pr.Parent = a
	P(m, "HelmExit", Vector3.new(2, 1, 2), CFrame.new(exitPos), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, nil,
		{Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false})
	return a
end

return N
