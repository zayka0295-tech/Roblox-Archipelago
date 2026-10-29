-- Помощники для сборки объектов из Parts (используются только в Studio при построении мира)
local B = {}

function B.part(parent, name, size, cf, color, material, opts)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.fromRGB(120, 122, 128)
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		for k, v in pairs(opts) do p[k] = v end
	end
	p.Parent = parent
	return p
end

-- вертикальный цилиндр: cf задаёт центр
function B.cyl(parent, name, height, diameter, cf, color, material, opts)
	local p = B.part(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), color, material, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function B.zone(parent, name, size, cf, attrs)
	local p = B.part(parent, name, size, cf, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic,
		{Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false})
	for k, v in pairs(attrs or {}) do p:SetAttribute(k, v) end
	return p
end

function B.billboard(adornee, text, color, offY, width)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(width or 260, 56)
	bb.StudsOffset = Vector3.new(0, offY or 8, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 2500
	bb.Adornee = adornee
	bb.Parent = adornee
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color or Color3.new(1, 1, 1)
	tl.TextStrokeTransparency = 0
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.Parent = bb
	return bb
end

function B.surfaceText(part, face, text, color, font)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	sg.Parent = part
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color or Color3.new(1, 1, 1)
	tl.Font = font or Enum.Font.GothamBold
	tl.TextScaled = true
	tl.Parent = sg
	return sg
end

function B.lamp(parent, cf)
	local pole = B.part(parent, "LampPole", Vector3.new(1, 14, 1), cf * CFrame.new(0, 7, 0), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
	local bulb = B.part(parent, "LampBulb", Vector3.new(3, 1, 3), cf * CFrame.new(0, 14.5, 0), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, {CanCollide = false})
	local l = Instance.new("PointLight")
	l.Range = 48
	l.Brightness = 1.2
	l.Color = Color3.fromRGB(255, 232, 190)
	l.Parent = bulb
	return pole
end

return B
