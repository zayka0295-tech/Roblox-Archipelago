-- Анимация баз на клиенте (сервер не грузим):
--   RadarSpin  — модель-головка РЛС, крутится вокруг PrimaryPart со скоростью атрибута Speed (рад/с)
--   Searchlight — лампа прожектора на вышке, плавно водит пятно по территории внутри забора
-- Анимируем только то, что близко к камере.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local NEAR = 1500
local SWEEP_YAW = math.rad(65)   -- насколько прожектор отворачивает от направления на центр базы
local REACH = {60, 200}           -- дальность пятна от вышки, мин/макс
local SWEEP_RATE = 0.12          -- скорость «блуждания» пятна

return function(ctx)
	local radars = {} -- [модель] = исходный CFrame оси (false — детали ещё не подгружены)
	local lamps = {}  -- [лампа] = {pos, baseYaw, lens, lensOff, seed}

	local function addRadar(m)
		-- со стримингом тег приходит раньше деталей: ось запомним, когда появится PrimaryPart
		if m:IsA("Model") and radars[m] == nil then radars[m] = m.PrimaryPart and m.PrimaryPart.CFrame or false end
	end
	local function addLamp(p)
		if not p:IsA("BasePart") then return end
		local mn, mx = p:GetAttribute("AreaMin"), p:GetAttribute("AreaMax")
		local pos = p.Position
		local center = (mn and mx) and (mn + mx) / 2 or pos + p.CFrame.LookVector * 50
		local lens = p.Parent and p.Parent:FindFirstChild("Lens")
		-- луч прожектора движется каждый кадр: с тенями движок пересчитывает их карты постоянно и при
		-- нехватке бюджета теней (их на базе ~20) тени и свет по всей базе мигают. Движущемуся свету тени не нужны
		for _, part in ipairs({p, lens}) do
			for _, l in ipairs(part:GetDescendants()) do
				if l:IsA("Light") then l.Shadows = false end
			end
		end
		lamps[p] = {
			pos = pos,
			baseYaw = math.atan2(center.X - pos.X, center.Z - pos.Z),
			ground = mn and mn.Y or pos.Y - 20,
			lens = lens,
			lensOff = lens and p.CFrame:ToObjectSpace(lens.CFrame) or nil,
			seed = p:GetAttribute("Seed") or 0,
		}
	end
	for _, m in ipairs(CollectionService:GetTagged("RadarSpin")) do addRadar(m) end
	for _, p in ipairs(CollectionService:GetTagged("Searchlight")) do addLamp(p) end
	CollectionService:GetInstanceAddedSignal("RadarSpin"):Connect(function(m) task.defer(addRadar, m) end)
	CollectionService:GetInstanceAddedSignal("Searchlight"):Connect(function(p) task.defer(addLamp, p) end)
	CollectionService:GetInstanceRemovedSignal("RadarSpin"):Connect(function(m) radars[m] = nil end)
	CollectionService:GetInstanceRemovedSignal("Searchlight"):Connect(function(p) lamps[p] = nil end)

	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for m, axis in pairs(radars) do
			if not axis and m.PrimaryPart then
				axis = m.PrimaryPart.CFrame
				radars[m] = axis
			end
			if axis and m.Parent and m.PrimaryPart and (axis.Position - camPos).Magnitude < NEAR then
				m:PivotTo(axis * CFrame.Angles(0, clock * (m:GetAttribute("Speed") or 0.7), 0))
			end
		end
		for p, s in pairs(lamps) do
			if p.Parent and (s.pos - camPos).Magnitude < NEAR then
				-- точка на земле: угол и дальность плавно блуждают (шум Перлина, у каждой вышки свой)
				local t = clock * SWEEP_RATE
				local yaw = s.baseYaw + math.noise(t, s.seed, 0.3) * 2 * SWEEP_YAW
				local k = math.clamp(0.5 + math.noise(s.seed, t * 0.8, 1.7) * 1.4, 0, 1)
				local dist = REACH[1] + (REACH[2] - REACH[1]) * k
				local target = Vector3.new(s.pos.X + math.sin(yaw) * dist, s.ground, s.pos.Z + math.cos(yaw) * dist)
				local cf = CFrame.lookAt(s.pos, target)
				p.CFrame = cf
				if s.lens and s.lens.Parent then s.lens.CFrame = cf * s.lensOff end
			end
		end
	end)
	return {}
end
