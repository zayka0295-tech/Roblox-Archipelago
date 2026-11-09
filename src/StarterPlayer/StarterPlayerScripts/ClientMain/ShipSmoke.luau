-- Дым из труб кораблей (только локально — сервер и сеть не нагружаем).
-- Эмиттер ставится на срез трубы (деталь FunnelTop, иначе Funnel) у всех судов на воде.
-- Частицы живут в мире, поэтому на ходу шлейф сам тянется за кораблём; чем быстрее ход — тем гуще дым.
-- Тонущий корабль дымит своим SinkFx — обычный дым гасим.
local RunService = game:GetService("RunService")

local FOLDERS = {"Vessels", "Carriers", "Cargo"}
local IDLE_RATE, FULL_RATE = 5, 22

local function topOf(part)
	-- срез трубы: верх детали по мировой вертикали (цилиндр может быть повёрнут осью вверх)
	local up = math.abs(part.CFrame.XVector.Y) * part.Size.X + math.abs(part.CFrame.YVector.Y) * part.Size.Y
		+ math.abs(part.CFrame.ZVector.Y) * part.Size.Z
	return part.Position + Vector3.new(0, up / 2 + 0.3, 0)
end

local function makeEmitter(part)
	local att = Instance.new("Attachment")
	att.Name = "SmokeAtt"
	att.Parent = part
	-- ось X вложения — мировая вертикаль (эмиттер бьёт вдоль неё), как бы ни был повёрнут цилиндр трубы
	att.WorldCFrame = CFrame.new(topOf(part)) * CFrame.Angles(0, 0, math.rad(90))
	local width = math.min(part.Size.Y, part.Size.Z, part.Size.X > 2 and part.Size.X or math.huge)
	local e = Instance.new("ParticleEmitter")
	e.Name = "FunnelSmoke"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.EmissionDirection = Enum.NormalId.Right -- вдоль X вложения = вверх
	e.Color = ColorSequence.new(Color3.fromRGB(70, 70, 72), Color3.fromRGB(140, 140, 145))
	e.LightInfluence = 0.9
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, width * 0.45),
		NumberSequenceKeypoint.new(0.4, width * 0.9),
		NumberSequenceKeypoint.new(1, width * 1.8),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(4, 6)
	e.Speed = NumberRange.new(5, 8)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Acceleration = Vector3.new(0, 1.5, 0) -- тёплый дым поднимается
	e.Drag = 0.6
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Rate = IDLE_RATE
	e.Parent = att
	return e
end

return function(ctx)
	local ships = {} -- [модель] = {эмиттеры}

	local function add(m)
		if ships[m] or not m:IsA("Model") then return end
		local list = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "FunnelTop" then table.insert(list, makeEmitter(d)) end
		end
		if #list == 0 then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Funnel" then table.insert(list, makeEmitter(d)) end
			end
		end
		if #list > 0 then ships[m] = list end
	end

	local function watch(folder)
		for _, m in ipairs(folder:GetChildren()) do task.defer(add, m) end
		folder.ChildAdded:Connect(function(m) task.defer(add, m) end)
		folder.ChildRemoved:Connect(function(m) ships[m] = nil end)
	end
	local map = workspace:WaitForChild("Map")
	for _, n in ipairs(FOLDERS) do
		local f = map:FindFirstChild(n)
		if f then watch(f) end
	end
	map.ChildAdded:Connect(function(f)
		if table.find(FOLDERS, f.Name) then watch(f) end
	end)

	-- густота по ходу: раз в 0,25 с (атрибут Speed сервер обновляет 5 раз в секунду)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then return end
		acc = 0
		for m, list in pairs(ships) do
			if not m.Parent then ships[m] = nil continue end
			local sinking = m:GetAttribute("Sinking") == true or m:GetAttribute("State") == "Sunk"
			local max = m:GetAttribute("MaxSpeed") or 30
			local k = math.clamp(math.abs(m:GetAttribute("Speed") or 0) / math.max(max, 1), 0, 1)
			local rate = sinking and 0 or (IDLE_RATE + (FULL_RATE - IDLE_RATE) * k)
			for _, e in ipairs(list) do e.Rate = rate end
		end
	end)
	return {}
end
