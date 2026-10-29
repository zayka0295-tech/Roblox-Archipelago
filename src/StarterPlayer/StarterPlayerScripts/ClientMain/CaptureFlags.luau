-- Флаги захвата на островах: высота = прогресс захвата (CapturePoint.Control, -1..1),
-- цвет = команда, в чью сторону прогресс. В нейтрали флаг спущен и белый.
-- Полотнище из полос Cloth1..N колышется волной (только локально, сервер не грузим).
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local NEAR = 1200
local NEUTRAL = Color3.fromRGB(225, 225, 225)
local WIND = math.rad(20)   -- куда дует ветер (поворот вокруг вертикали)
local RAISE_SPEED = 2       -- насколько быстро флаг догоняет нужную высоту

return function(ctx)
	local Teams = ctx.Config.Teams
	local flags = {} -- [модель] = состояние

	local function add(m)
		if flags[m] or not m:IsA("Model") then return end
		local pole = m:FindFirstChild("Pole")
		local point = m.Parent and m.Parent:FindFirstChild("Capture") and m.Parent.Capture:FindFirstChild("CapturePoint")
		if not pole or not point then return end
		local cloth = {}
		for i = 1, m:GetAttribute("Segments") or 8 do
			local c = m:FindFirstChild("Cloth" .. i)
			if c then table.insert(cloth, c) end
			end
		flags[m] = {
			point = point, cloth = cloth,
			x = pole.Position.X, z = pole.Position.Z,
			w = m:GetAttribute("Width") or 14, low = m:GetAttribute("Low") or 18, high = m:GetAttribute("High") or 38,
			y = m:GetAttribute("Low") or 18, phase = math.random() * 10,
		}
	end
	for _, m in ipairs(CollectionService:GetTagged("CaptureFlag")) do add(m) end
	CollectionService:GetInstanceAddedSignal("CaptureFlag"):Connect(function(m) task.defer(add, m) end)
	CollectionService:GetInstanceRemovedSignal("CaptureFlag"):Connect(function(m) flags[m] = nil end)

	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for m, f in pairs(flags) do
			if not m.Parent then flags[m] = nil continue end
			local control = f.point:GetAttribute("Control") or 0
			local k = math.clamp(math.abs(control), 0, 1)
			local team = control > 0 and "Blue" or control < 0 and "Red" or nil
			local col = (team and k > 0.02 and Teams[team]) and Teams[team].Color or NEUTRAL
			local targetY = f.low + (f.high - f.low) * k
			f.y += (targetY - f.y) * math.min(1, dt * RAISE_SPEED)
			if (Vector3.new(f.x, f.y, f.z) - camPos).Magnitude > NEAR then continue end
			-- волна бежит от древка к краю, амплитуда растёт к свободному краю; порывы — через шум
			local gust = 0.75 + 0.35 * math.noise(clock * 0.3, f.phase)
			local base = CFrame.new(f.x, f.y, f.z) * CFrame.Angles(0, WIND + math.noise(clock * 0.15, f.phase, 2) * 0.35, 0)
			local n = #f.cloth
			local segW = f.w / n
			local cf = base * CFrame.new(0.4, 0, 0)
			for i, c in ipairs(f.cloth) do
				local u = (i - 0.5) / n
				local ang = math.sin(clock * 4.2 * gust - u * 5 + f.phase) * 0.45 * u * gust
				cf = cf * CFrame.Angles(0, ang / n * 2.2, 0)
				local center = cf * CFrame.new(segW / 2, -math.abs(ang) * 0.4 * u, 0)
				c.CFrame = center
				c.Color = col
				cf = cf * CFrame.new(segW, 0, 0)
			end
		end
	end)
	return {}
end
