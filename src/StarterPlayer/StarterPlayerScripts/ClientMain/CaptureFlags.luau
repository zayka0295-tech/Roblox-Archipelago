-- Флаги захвата на островах: высота = прогресс захвата (CapturePoint.Control, -1..1),
-- цвет и герб = команда, в чью сторону прогресс. В нейтрали флаг спущен, белый, без герба.
-- Полотнище строится локально из тонких полос (старые Cloth1..N из карты прячутся).
-- Форма ткани считается заново каждый кадр как кривая (бегущая волна от древка к краю),
-- а не накоплением поворотов — поэтому флаг не мотает целиком, как доску.
-- Герб = картинка Icons.Teams[команда], разрезанная по полосам через SurfaceGui.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Icons = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("Icons"))

local NEAR = 1200
local NEUTRAL = Color3.fromRGB(230, 230, 225)
local WIND = math.rad(20)   -- куда дует ветер (поворот вокруг вертикали)
local RAISE_SPEED = 2       -- насколько быстро флаг догоняет нужную высоту
local SEGS = 20             -- полос в полотнище (больше = плавнее волна)
local PPS = 24              -- пикселей на стад для герба

-- холст во всё полотнище, сдвинутый так, чтобы в полосе была видна её часть
local function buildCanvas(parent, wPx, hPx, xOff)
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromOffset(wPx, hPx)
	canvas.Position = UDim2.fromOffset(xOff, 0)
	canvas.Parent = parent
	local d = hPx * 0.8
	local img = Instance.new("ImageLabel")
	img.Name = "Crest"
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromOffset(d, d)
	img.ScaleType = Enum.ScaleType.Fit
	img.Visible = false
	img.Parent = canvas
	return canvas
end

local function paint(canvas, team)
	local id = team and Icons.Teams[team]
	canvas.Crest.Visible = id ~= nil
	canvas.Crest.Image = id or ""
end

return function(ctx)
	local Teams = ctx.Config.Teams
	local flags = {} -- [модель] = состояние

	local function add(m)
		if flags[m] or not m:IsA("Model") then return end
		local pole = m:FindFirstChild("Pole")
		local point = m.Parent and m.Parent:FindFirstChild("Capture") and m.Parent.Capture:FindFirstChild("CapturePoint")
		if not pole or not point then return end
		local w = m:GetAttribute("Width") or 14
		local h = nil
		for i = 1, m:GetAttribute("Segments") or 8 do
			local c = m:FindFirstChild("Cloth" .. i)
			if c and c:IsA("BasePart") then
				h = h or c.Size.Y
				c.LocalTransparencyModifier = 1
				c.Transparency = 1
			end
		end
		h = h or 8
		local segW = w / SEGS
		local folder = Instance.new("Folder")
		folder.Name = "LocalCloth"
		folder.Parent = m
		local cloth, canvases = {}, {}
		for i = 1, SEGS do
			local p = Instance.new("Part")
			p.Name = "Seg" .. i
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = true
			p.Material = Enum.Material.Fabric
			p.Size = Vector3.new(segW * 1.06, h, 0.05) -- чуть шире, чтобы на изгибах не было щелей
			p.Color = NEUTRAL
			p.Parent = folder
			for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
				local g = Instance.new("SurfaceGui")
				g.Face = face
				g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				g.PixelsPerStud = PPS
				g.LightInfluence = 1
				g.ClipsDescendants = true
				g.Parent = p
				-- с лицевой стороны +X полосы слева, с тыльной — справа
				local idx = face == Enum.NormalId.Front and (SEGS - i) or (i - 1)
				table.insert(canvases, buildCanvas(g, w * PPS, h * PPS, -idx * segW * PPS))
			end
			cloth[i] = p
		end
		flags[m] = {
			point = point, cloth = cloth, canvases = canvases, folder = folder, team = false,
			x = pole.Position.X, z = pole.Position.Z, r = math.min(pole.Size.X, pole.Size.Y, pole.Size.Z) / 2, -- древко — повёрнутый цилиндр, берём толщину
			w = w, h = h,
			low = m:GetAttribute("Low") or 18, high = m:GetAttribute("High") or 38,
			y = m:GetAttribute("Low") or 18, phase = math.random() * 10,
		}
	end
	for _, m in ipairs(CollectionService:GetTagged("CaptureFlag")) do add(m) end
	CollectionService:GetInstanceAddedSignal("CaptureFlag"):Connect(function(m) task.defer(add, m) end)
	CollectionService:GetInstanceRemovedSignal("CaptureFlag"):Connect(function(m)
		local f = flags[m]
		if f then f.folder:Destroy() end
		flags[m] = nil
	end)

	-- поперечное смещение ткани в точке u (0 у древка .. 1 на краю)
	local function wave(u, t, gust, ph)
		local amp = (0.05 + 0.85 * u ^ 1.3) * gust
		return math.sin(u * 7.5 - t * 6 * gust + ph) * amp
			+ math.sin(u * 13 - t * 9.5 + ph * 1.7) * 0.12 * u
	end

	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for m, f in pairs(flags) do
			if not m.Parent then flags[m] = nil continue end
			local control = f.point:GetAttribute("Control") or 0
			local k = math.clamp(math.abs(control), 0, 1)
			local team = (k > 0.02) and (control > 0 and "Blue" or "Red") or nil
			if team and not Teams[team] then team = nil end
			local col = team and Teams[team].Color or NEUTRAL
			if f.team ~= (team or "") then
				f.team = team or ""
				for _, c in ipairs(f.cloth) do c.Color = col end
				for _, cv in ipairs(f.canvases) do paint(cv, team) end
			end
			local targetY = f.low + (f.high - f.low) * k
			f.y += (targetY - f.y) * math.min(1, dt * RAISE_SPEED)
			if (Vector3.new(f.x, f.y, f.z) - camPos).Magnitude > NEAR then continue end

			-- общее направление почти постоянно (лишь лёгкий дрейф ветра), всё движение — в ткани
			local gust = 0.85 + 0.2 * math.noise(clock * 0.2, f.phase)
			local base = CFrame.new(f.x, f.y, f.z) * CFrame.Angles(0, WIND + math.noise(clock * 0.04, f.phase, 2) * 0.06, 0)
			local n = #f.cloth
			local segW = f.w / n
			-- точки кромок полос в локальных координатах (X — от древка, Z — поперёк),
			-- длина каждой полосы сохраняется, поэтому в складках флаг чуть «укорачивается»
			local px, pz = f.r, 0
			for i, c in ipairs(f.cloth) do
				local u = i / n
				local nz = wave(u, clock, gust, f.phase)
				local dz = math.clamp(nz - pz, -segW * 0.9, segW * 0.9)
				local dx = math.sqrt(segW * segW - dz * dz)
				local nx = px + dx
				local sag = -u * u * 0.35 * (1.1 - gust) -- лёгкое провисание края при слабом ветре
				local mid = base * Vector3.new((px + nx) / 2, sag, (pz + pz + dz) / 2)
				local look = base:VectorToWorldSpace(Vector3.new(dx, 0, dz))
				-- X полосы смотрит вдоль ткани
				c.CFrame = CFrame.fromMatrix(mid, look.Unit, Vector3.yAxis)
				px, pz = nx, pz + dz
			end
		end
	end)
	return {}
end
