-- Вид от первого лица: настоящее оружие и руки персонажа висят у самой камеры и выглядят огромными,
-- поэтому от первого лица их прячем (только на своём экране) и рисуем перед камерой копию оружия
-- и держащие его руки персонажа. От бедра — справа внизу, при прицеливании (ПКМ) — по центру, прицел на линии глаза.
local RunService = game:GetService("RunService")

-- где рукоять оружия относительно камеры
local HIP = CFrame.new(1.0, -1.5, -2.4) * CFrame.Angles(0, math.rad(5), 0)
local AIM_Z = -1.3           -- рукоять при прицеливании: на сколько впереди камеры
-- при прицеливании кончик мушки (самая высокая точка передней части ствола) — ровно в перекрестье

-- перезарядка (фаза 0..1): магазин уходит вниз и возвращается, граната РПГ вдвигается спереди
local function ramp(x, a, b) return math.clamp((x - a) / (b - a), 0, 1) end
local function smooth(t) return t * t * (3 - 2 * t) end
local function magOut(r) return smooth(ramp(r, 0.12, 0.4)) * (1 - smooth(ramp(r, 0.62, 0.86))) end

------------------------------------------------------------------ руки от первого лица
-- Копии рук персонажа (R15: плечо, предплечье, кисть; R6: рука целиком) с его рубашкой-формой держат копию оружия:
-- правая — за рукоять (Tool.Grip), левая — за цевьё. Плечи — у нижнего края экрана, локти ставит двухзвенная IK.
-- плечи в осях камеры — под нижним краем экрана (угол вниз больше половины поля зрения), чтобы обрезов рук не было видно
local SHOULDER = {Right = Vector3.new(0.6, -2.0, -0.8), Left = Vector3.new(-0.3, -2.2, -1.4)}
local MAX_ARM_SCALE = 1.6 -- руки копии можно удлинить, чтобы дотянуться до цевья длинного оружия
local ARM_WIDTH, HAND_WIDTH = 0.55, 0.45 -- толщина копии рук и кистей от исходной
local POLE = {Right = Vector3.new(0.7, -1, 0.3), Left = Vector3.new(-0.7, -1, 0.3)} -- куда смотрит локоть
local R15_ARM = {"UpperArm", "LowerArm", "Hand"}
local KEEP = {SurfaceAppearance = true, SpecialMesh = true, Decal = true}

local function cloneLimb(src)
	local c = src:Clone()
	for _, ch in ipairs(c:GetChildren()) do
		if not KEEP[ch.ClassName] then ch:Destroy() end
	end
	c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow, c.Massless = true, false, false, false, false, true
	c.LocalTransparencyModifier = 0
	c.Transparency = 0
	return c
end

-- деталь от точки top до точки bottom (ось Y детали вдоль конечности, как у R15/R6), боком к камере
local function segmentCF(top, bottom, camRight)
	local up = top - bottom
	if up.Magnitude < 1e-3 then up = Vector3.yAxis end
	up = up.Unit
	local x = camRight - up * camRight:Dot(up)
	if x.Magnitude < 1e-3 then x = up:Cross(Vector3.zAxis) end
	return CFrame.fromMatrix((top + bottom) / 2, x.Unit, up)
end

-- двухзвенная IK: локоть для плеча s, запястья w, длин a и b и направления локтя pole
local function elbowPos(s, w, a, b, pole)
	local d = w - s
	local len = math.clamp(d.Magnitude, 1e-3, a + b - 1e-3)
	local dir = d.Unit
	local along = (a * a - b * b + len * len) / (2 * len)
	local h = math.sqrt(math.max(0, a * a - along * along))
	local side = pole - dir * pole:Dot(dir)
	side = side.Magnitude > 1e-3 and side.Unit or Vector3.yAxis
	return s + dir * along + side * h
end

return function(ctx)
	local player = ctx.player
	local gunState = ctx.gunState
	local vm, vmTool -- модель-копия и для какого инструмента она собрана
	local hidden = {} -- детали настоящего оружия, спрятанные на своём экране
	local aim, kick, bob = 0, 0, 0

	local addedConn -- новые детали настоящего оружия (если сервер что-то добавит) — тоже прятать

	local function clear()
		gunState.vmMuzzleCF = nil
		if vm then vm:Destroy() vm = nil end
		vmTool = nil
		if addedConn then addedConn:Disconnect() addedConn = nil end
		for p in pairs(hidden) do if p.Parent then p.LocalTransparencyModifier = 0 end end
		table.clear(hidden)
	end

	local function build(tool, char)
		clear()
		local handle = tool:FindFirstChild("Handle")
		if not handle then return end
		vm = Instance.new("Model")
		vm.Name = "Viewmodel"
		local parts = {}
		local real = {} -- все детали настоящего оружия (прячем их каждый кадр без GetDescendants)
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(real, d) end
			if d:IsA("BasePart") and d.Transparency < 1 then
				local c = d:Clone()
				for _, ch in ipairs(c:GetChildren()) do
					if ch:IsA("JointInstance") or ch:IsA("WeldConstraint") or ch:IsA("Attachment") then ch:Destroy() end
				end
				c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
				c.Parent = vm
				parts[#parts + 1] = {c, handle.CFrame:ToObjectSpace(d.CFrame), d}
			end
		end
		-- мушка: самая высокая точка передней половины оружия (по углам габаритов деталей, в осях рукояти)
		local muzzle = tool:FindFirstChild("Muzzle")
		local muzzleRel = muzzle and handle.CFrame:ToObjectSpace(muzzle.CFrame) or CFrame.new(0, 0.4, -2.5)
		local frontZ = muzzleRel.Z * 0.5
		local sight = nil
		for _, e in ipairs(parts) do
			local rel, s = e[2], e[1].Size / 2
			for _, c in ipairs({Vector3.new(s.X, s.Y, s.Z), Vector3.new(-s.X, s.Y, s.Z), Vector3.new(s.X, -s.Y, s.Z), Vector3.new(s.X, s.Y, -s.Z), Vector3.new(-s.X, -s.Y, s.Z), Vector3.new(-s.X, s.Y, -s.Z), Vector3.new(s.X, -s.Y, -s.Z), Vector3.new(-s.X, -s.Y, -s.Z)}) do
				local q = rel * c
				if q.Z < frontZ and (not sight or q.Y > sight) then sight = q.Y end
			end
		end
		-- руки: копии конечностей персонажа; рубашка (форма команды) ложится на них через Humanoid в модели
		local arms = {}
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			local r15 = hum.RigType == Enum.HumanoidRigType.R15
			for _, side in ipairs({"Right", "Left"}) do
				local segs = {}
				if r15 then
					for _, n in ipairs(R15_ARM) do
						local src = char:FindFirstChild(side .. n)
						if not src then segs = nil break end
						local c = cloneLimb(src)
						c.Parent = vm
						table.insert(segs, c)
					end
				else
					local src = char:FindFirstChild(side .. " Arm")
					if src then
						local c = cloneLimb(src)
						c.Parent = vm
						segs = {c}
					else
						segs = nil
					end
				end
				if segs then arms[side] = segs end
			end
			if next(arms) then
				local vh = Instance.new("Humanoid")
				vh.RigType = hum.RigType
				vh.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				vh.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				vh.EvaluateStateMachine = false
				vh.Parent = vm
				for _, cls in ipairs({"Shirt", "BodyColors"}) do
					local o = char:FindFirstChildOfClass(cls)
					if o then o:Clone().Parent = vm end
				end
			end
		end
		-- где руки держат оружие (в осях рукояти): правая — точка хвата Tool.Grip, левая — цевьё на полпути к дулу
		local grip = tool.Grip.Position
		local fore = grip:Lerp(muzzleRel.Position, 0.5) + Vector3.new(0, -0.12, 0)
		-- рука короче, чем расстояние от плеча до хвата от бедра, — копию увеличиваем (одинаково для обеих рук)
		local need = 1
		for side, segs in pairs(arms) do
			local reach = #segs == 3 and (segs[1].Size.Y + segs[2].Size.Y) * 0.95 * 0.98 or segs[1].Size.Y
			local hold = side == "Right" and grip or fore
			local d = ((HIP * CFrame.new(hold)).Position - SHOULDER[side]).Magnitude
			need = math.max(need, d / reach)
		end
		-- у самой камеры руки персонажа толстые и закрывают оружие — копию делаем тоньше
		local k = math.min(need, MAX_ARM_SCALE)
		for _, segs in pairs(arms) do
			for i, p in ipairs(segs) do
				local w = (#segs == 3 and i == 3) and HAND_WIDTH or ARM_WIDTH
				p.Size = Vector3.new(p.Size.X * w, p.Size.Y * k, p.Size.Z * w)
			end
		end
		vm.Parent = workspace.CurrentCamera
		vmTool = {tool = tool, parts = parts, real = real, sight = sight or (muzzleRel.Y + 0.2), muzzleRel = muzzleRel,
			arms = arms, hold = {Right = grip, Left = fore}}
		addedConn = tool.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then table.insert(real, d) end
		end)
	end

	RunService:BindToRenderStep("GunViewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local tool = gunState.tool
		local char = player.Character
		if not (gunState.firstPerson and tool and tool.Parent and char) then
			if vm or next(hidden) then clear() end
			return
		end
		if not vmTool or vmTool.tool ~= tool then build(tool, char) end
		if not vmTool then return end
		-- настоящее оружие на своём экране не показываем (у остальных оно на месте)
		for _, d in ipairs(vmTool.real) do
			hidden[d] = true
			d.LocalTransparencyModifier = 1
		end
		local camCF = workspace.CurrentCamera.CFrame
		aim += ((gunState.aiming and 1 or 0) - aim) * math.min(1, dt * 14)
		kick += ((gunState.kick or 0) - kick) * math.min(1, dt * 30)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local moving = hum and hum.MoveDirection.Magnitude > 0.1 and hum.FloorMaterial ~= Enum.Material.Air
		bob = moving and (bob + dt * 9) or bob * (1 - math.min(1, dt * 6))
		local sway = moving and (1 - aim * 0.8) or 0
		-- рукоять: от бедра справа или по центру под прицелом; толчок отдачи назад и вверх
		local aimCF = CFrame.new(0, -vmTool.sight, AIM_Z)
		local base = HIP:Lerp(aimCF, aim)
		local off = CFrame.new(math.sin(bob) * 0.04 * sway, math.abs(math.cos(bob)) * 0.05 * sway, kick * 0.18) * CFrame.Angles(math.rad(kick * 2.5), 0, 0)
		-- перезарядка: оружие наклоняется и опускается
		local r = gunState.reload
		local rs = r and math.sin(math.pi * r) or 0
		local rel = CFrame.new(-0.15 * rs, -0.35 * rs, 0.15 * rs) * CFrame.Angles(math.rad(14) * rs, 0, math.rad(32) * rs)
		local gunCF = camCF * base * off * rel
		gunState.vmMuzzleCF = gunCF * vmTool.muzzleRel -- вспышка и трассер выстрела от первого лица — отсюда
		local m = r and magOut(r) or 0
		for _, e in ipairs(vmTool.parts) do
			local p, prel, src = e[1], e[2], e[3]
			local t = src.Parent and src.Transparency or 1 -- граната РПГ пропадает после выстрела и здесь
			local shift = CFrame.identity
			if r and src.Name == "Mag" then
				shift = CFrame.new(0, -1.3 * m, 0.25 * m)
				if m > 0.85 then t = 1 end
			elseif r and src.Name == "Warhead" then
				-- новая граната: появляется спереди и вдвигается в трубу
				local k = smooth(ramp(r, 0.45, 0.9))
				t = r < 0.45 and 1 or 0
				shift = CFrame.new(0, -0.6 * (1 - k), -1.6 * (1 - k))
			end
			p.CFrame = gunCF * shift * prel
			p.Transparency = t
		end
		-- руки держат копию оружия
		local camRight = camCF.RightVector
		for side, segs in pairs(vmTool.arms) do
			local target = gunCF * vmTool.hold[side]
			local s = camCF * SHOULDER[side]
			local pole = camCF:VectorToWorldSpace(POLE[side])
			if #segs == 3 then
				local upper, lower, hand = segs[1], segs[2], segs[3]
				local a, b, hl = upper.Size.Y * 0.95, lower.Size.Y * 0.95, hand.Size.Y
				-- кисть центром на точке хвата; запястье — на полкисти ближе к плечу
				local w = target - (target - s).Unit * (hl * 0.5)
				-- рука короче, чем нужно до оружия — плечо подтягиваем к оружию (оно всё равно за краем экрана)
				local reach = (a + b) * 0.98
				if (w - s).Magnitude > reach then s = w - (w - s).Unit * reach end
				local e = elbowPos(s, w, a, b, pole)
				upper.CFrame = segmentCF(s, e, camRight)
				lower.CFrame = segmentCF(e, w, camRight)
				hand.CFrame = segmentCF(w, w + (w - e).Unit * hl, camRight)
			else
				local arm = segs[1]
				local len = arm.Size.Y
				if (target - s).Magnitude > len then s = target - (target - s).Unit * len end
				local dir = (target - s).Unit
				arm.CFrame = segmentCF(target - dir * len, target, camRight)
			end
		end
	end)
	player.CharacterRemoving:Connect(clear)
	return {}
end
