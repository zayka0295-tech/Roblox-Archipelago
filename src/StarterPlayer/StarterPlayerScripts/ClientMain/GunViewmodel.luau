-- Вид от первого лица: настоящее оружие и руки персонажа висят у самой камеры и выглядят огромными,
-- поэтому от первого лица их прячем (только на своём экране) и рисуем перед камерой копию оружия
-- (без рук). От бедра — справа внизу, при прицеливании (ПКМ) — по центру, прицел на линии глаза.
local RunService = game:GetService("RunService")

-- где рукоять оружия относительно камеры
local HIP = CFrame.new(1.0, -1.5, -2.4) * CFrame.Angles(0, math.rad(5), 0)
local AIM_Z = -1.3           -- рукоять при прицеливании: на сколько впереди камеры
-- при прицеливании кончик мушки (самая высокая точка передней части ствола) — ровно в перекрестье

-- перезарядка (фаза 0..1): магазин уходит вниз и возвращается, граната РПГ вдвигается спереди
local function ramp(x, a, b) return math.clamp((x - a) / (b - a), 0, 1) end
local function smooth(t) return t * t * (3 - 2 * t) end
local function magOut(r) return smooth(ramp(r, 0.12, 0.4)) * (1 - smooth(ramp(r, 0.62, 0.86))) end

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
		vm.Parent = workspace.CurrentCamera
		vmTool = {tool = tool, parts = parts, real = real, sight = sight or (muzzleRel.Y + 0.2), muzzleRel = muzzleRel}
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
	end)
	player.CharacterRemoving:Connect(clear)
	return {}
end
