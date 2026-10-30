-- Пилотирование: самолёт летит туда, куда смотрит камера (мышь / палец).
-- На телефоне: курс — пальцем по экрану (или зажав FIRE), джойстика нет; круглые кнопки:
-- FIRE, газ +/− и BOMB, выход — прыжок.
-- Бомбы (истребитель — 1, бомбардировщик — 10): E / BOMB — сброс (PlaneBomb), счётчик — атрибут Bombs самолёта,
-- красное кольцо — куда упадёт бомба, если сбросить сейчас (точка сглажена, без рывков).
-- Z / SIGHT — бомбовый прицел: камера под бомбоотсеком смотрит вниз на точку падения, самолёт держит горизонт,
-- мышь / палец — только курс. Параметры самолёта — по типу (PlaneType).
-- Физикой самолёта управляет клиент пилота (сетевое владение). Попадание пулемёта определяет
-- клиент по тому, что видит пилот (PlaneHit), а сервер проверяет его и наносит урон.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local P = Config.Planes.Fighter -- параметры текущего самолёта (см. start)
	local BC = Config.Bombs
	local player = ctx.player
	local Fire = ctx.Remotes:WaitForChild("PlaneFire")
	local HitRemote = ctx.Remotes:WaitForChild("PlaneHit")
	local BombRemote = ctx.Remotes:WaitForChild("PlaneBomb")
	-- луч своих пуль: видит и грузовые суда (группа Weapons), не видит свой самолёт и эффекты
	local shotParams = RaycastParams.new()
	shotParams.FilterType = Enum.RaycastFilterType.Exclude
	shotParams.CollisionGroup = "Weapons"
	-- по чему есть смысл сообщать серверу: люди, боты, техника
	local function damageable(inst)
		local m = inst:FindFirstAncestorOfClass("Model")
		while m do
			if m:FindFirstChildOfClass("Humanoid") or m:GetAttribute("IsBot") or m:GetAttribute("IsPlane") or m:GetAttribute("IsVessel")
				or m:GetAttribute("IsCarrier") or m:GetAttribute("IsCargo") then
				return true
			end
			m = m:FindFirstAncestorOfClass("Model")
		end
		return false
	end
	local gui = UI.screen("PlaneUI", 16)

	------------------------------------------------------------ HUD
	-- как у кораблей (ShipControlUI): две маленькие плашки у нижнего края по бокам от слота рюкзака:
	-- слева скорость · высота и газ, справа корпус · бомбы. На ПК клавиши — панель UI.controls слева внизу.
	local SLOT_GAP, BOTTOM = 32, -6
	local function plate(name, anchorX, xOff, barColor)
		local p = UI.panel(gui, {Name = name, AnchorPoint = Vector2.new(anchorX, 1), Position = UDim2.new(0.5, xOff, 1, BOTTOM),
			Size = UDim2.fromOffset(190, 34), Visible = false})
		p.BackgroundTransparency = 0.35
		UI.scale(p, 0.75)
		UI.padding(p, 6)
		local lbl = UI.label(p, "", {TextSize = 14, Size = UDim2.new(1, 0, 0, 16), RichText = true, TextXAlignment = Enum.TextXAlignment.Center})
		local bg = UI.new("Frame", {Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, p)
		UI.corner(bg, 4)
		local f = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = barColor, BorderSizePixel = 0}, bg)
		UI.corner(f, 4)
		return p, lbl, f
	end
	local panel, flightLbl, thrBar = plate("Panel", 1, -SLOT_GAP, T.Gold)
	local statusPanel, statusLbl, hpBar = plate("StatusPanel", 0, SLOT_GAP, T.Good)
	local warn = UI.label(gui, "", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(400, 30),
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.Bad, TextSize = 24, TextStrokeTransparency = 0.4, Visible = false})

	-- сенсорное управление: круглые кнопки вокруг прыжка (джойстик в самолёте не нужен — курс за камерой)
	local touchOnly = UI.touchOnly
	local stick = nil
	local held = {up = false, down = false, fire = false}
	local touchBtns = {}
	local fireDrag -- задаётся ниже, рядом с курсом (aimYaw / aimPitch)
	local function hold(key, slot, text, color, move)
		local b = UI.roundButton(gui, slot, text, color)
		UI.onHold(b, function() held[key] = true end, function() held[key] = false end, move)
		table.insert(touchBtns, b)
	end
	local bombBtn, sightBtn
	local dropBomb -- задаётся ниже (нужен текущий самолёт)
	local toggleSight -- тоже
	if touchOnly then
		-- зажал FIRE и ведёшь пальцем — курс самолёта идёт за пальцем (как при перетаскивании по экрану)
		hold("fire", "main", "FIRE", T.Bad, function(d) if fireDrag then fireDrag(d) end end)
		hold("up", "a2", "GAS\n+")
		hold("down", "a1", "GAS\n−")
		-- отдельная кнопка сброса бомбы во втором ряду
		bombBtn = UI.roundButton(gui, "b1", "BOMB", Color3.fromRGB(150, 95, 30))
		bombBtn.Activated:Connect(function() if dropBomb then dropBomb() end end)
		-- бомбовый прицел — рядом с BOMB
		sightBtn = UI.roundButton(gui, "b2", "SIGHT", Color3.fromRGB(60, 70, 90))
		sightBtn.Activated:Connect(function() if toggleSight then toggleSight() end end)
	end
	local function showTouch(on)
		for _, b in ipairs(touchBtns) do b.Visible = on end
		if bombBtn then bombBtn.Visible = on and (P.Bombs or 0) > 0 end
		if sightBtn then sightBtn.Visible = on and (P.Bombs or 0) > 0 end
		if stick then stick.request("plane", on) end
	end

	-- прицел (куда направлен курс) и метка носа (куда стреляют пулемёты)
	local aimMark = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, Visible = false}, gui)
	UI.corner(aimMark, 15)
	UI.stroke(aimMark, Color3.new(1, 1, 1), 2)
	local noseMark = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = T.Gold, BorderSizePixel = 0, Visible = false}, gui)
	UI.corner(noseMark, 5)
	-- точка падения бомбы
	local bombMark = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Visible = false}, gui)
	UI.corner(bombMark, 13)
	UI.stroke(bombMark, Color3.fromRGB(255, 80, 60), 3)
	UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromRGB(255, 80, 60), BorderSizePixel = 0}, bombMark)
	-- бомбовый прицел: перекрестие в центре = точка падения (камера смотрит на неё)
	local SIGHT_RED = Color3.fromRGB(255, 80, 60)
	local sightFrame = UI.new("Frame", {Name = "BombSight", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false}, gui)
	for _, s in ipairs({
		{UDim2.new(0.5, -130, 0.5, 0), UDim2.fromOffset(100, 2)}, {UDim2.new(0.5, 130, 0.5, 0), UDim2.fromOffset(100, 2)},
		{UDim2.new(0.5, 0, 0.5, -130), UDim2.fromOffset(2, 100)}, {UDim2.new(0.5, 0, 0.5, 130), UDim2.fromOffset(2, 100)},
	}) do
		UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = s[1], Size = s[2], BackgroundColor3 = SIGHT_RED, BorderSizePixel = 0}, sightFrame)
	end
	local sightRing = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1}, sightFrame)
	UI.corner(sightRing, 22)
	UI.stroke(sightRing, SIGHT_RED, 2)
	UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = SIGHT_RED, BorderSizePixel = 0}, sightFrame)
	local sightLbl = UI.label(sightFrame, "", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 190), Size = UDim2.fromOffset(420, 20),
		TextSize = 15, TextColor3 = SIGHT_RED, TextStrokeTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Center})
	local BASE_FOV, SIGHT_FOV = 70, 40
	local sightOn = false

	------------------------------------------------------------ состояние
	local flying -- {model, root, ao, lv, seat, hum}
	local firstPerson = false
	local charHidden = false
	local function hideChar(on)
		local char = player.Character
		if not char then return end
		local v = on and 1 or 0
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = v end
		end
		charHidden = on
	end
	local throttle, speed, bank = 0, 0, 0
	local aimYaw, aimPitch = 0, 0
	fireDrag = function(d)
		aimYaw -= d.X * 0.006
		aimPitch = math.clamp(aimPitch - d.Y * 0.006, -1.35, 1.35)
	end
	local lastFiring = false

	local function planeSeat()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if seat and seat:GetAttribute("PlaneSeat") then
			return seat, hum, seat:FindFirstAncestorOfClass("Model")
		end
		return nil
	end

	local function rotateToward(a, b, maxAng)
		local d = math.clamp(a:Dot(b), -1, 1)
		local ang = math.acos(d)
		if ang <= maxAng or ang < 1e-4 then return b end
		local axis = a:Cross(b)
		if axis.Magnitude < 1e-6 then axis = Vector3.yAxis end
		return (CFrame.fromAxisAngle(axis.Unit, maxAng) * a).Unit
	end

	local function start(seat, hum, model)
		local root = model:FindFirstChild("Root")
		if not root then return end
		P = Config.Planes[model:GetAttribute("PlaneType") or "Fighter"] or Config.Planes.Fighter
		local rows = {
			{"Mouse", "Fly where you look"},
			{"W / S", "Throttle up / down"},
			{"A / D", "Turn left / right"},
			{"Arrows", "Turn / nose up-down"},
			{"LMB", "Machine guns"},
			{"RMB", "Zoom"},
		}
		if (P.Bombs or 0) > 0 then
			table.insert(rows, {"E", "Drop bomb"})
			table.insert(rows, {"Z", "Bomb sight"})
		end
		table.insert(rows, {"Space", "Leave the plane"})
		UI.controls("plane", rows)
		flying = {model = model, root = root, ao = root:FindFirstChild("FlightAlign"), lv = root:FindFirstChild("FlightDrive"), seat = seat, hum = hum, muzzles = {}, shotN = 0, lastShot = 0,
			bay = model:FindFirstChild("BombBay"), impact = nil}
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "GunMuzzle" then table.insert(flying.muzzles, d) end
		end
		local look = root.CFrame.LookVector
		aimYaw = math.atan2(-look.X, -look.Z)
		aimPitch = 0
		throttle, bank = 0, 0
		speed = root.AssemblyLinearVelocity.Magnitude
		hum:UnequipTools()
		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		if not touchOnly then UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end
		panel.Visible, statusPanel.Visible = true, true
		-- хвостовая турель бомбардировщика стоит между камерой пилота и самолётом — для него полупрозрачная
		flying.faded = {}
		local tur = model:FindFirstChild("TailTurret")
		for _, p in ipairs(tur and tur:GetDescendants() or {}) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				p.LocalTransparencyModifier = 0.75
				table.insert(flying.faded, p)
			end
		end
		showTouch(touchOnly)
		aimMark.Visible, noseMark.Visible = true, true
	end

	local function setSight(on)
		if on == sightOn then return end
		sightOn = on
		sightFrame.Visible = on
		if sightBtn then sightBtn.BackgroundColor3 = on and Color3.fromRGB(70, 140, 220) or sightBtn:GetAttribute("BaseColor") end
		if not on then workspace.CurrentCamera.FieldOfView = BASE_FOV end
	end
	toggleSight = function()
		if not flying or (flying.model:GetAttribute("Bombs") or 0) <= 0 then return end -- бомб нет — прицел ни к чему
		if not sightOn and flying.onGround then
			UI.toast("Bomb sight works in the air", "error")
			return
		end
		setSight(not sightOn)
	end

	local function stop()
		setSight(false)
		for _, p in ipairs(flying and flying.faded or {}) do
			if p.Parent then p.LocalTransparencyModifier = 0 end
		end
		flying = nil
		if charHidden then hideChar(false) end
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Custom
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		panel.Visible, statusPanel.Visible, warn.Visible = false, false, false
		UI.controls("plane", nil)
		showTouch(false)
		aimMark.Visible, noseMark.Visible, bombMark.Visible = false, false, false
		if lastFiring then
			lastFiring = false
			Fire:FireServer(false)
		end
	end

	-- мышь / палец двигают курс
	UserInputService.InputChanged:Connect(function(input, processed)
		if not flying then return end
		-- в бомбовом прицеле — только курс, медленнее (точное доведение на цель)
		local k = sightOn and 0.4 or 1
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			aimYaw -= input.Delta.X * 0.0035 * k
			if not sightOn then aimPitch = math.clamp(aimPitch - input.Delta.Y * 0.0035, -1.35, 1.35) end
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
			aimYaw -= input.Delta.X * 0.006 * k
			if not sightOn then aimPitch = math.clamp(aimPitch - input.Delta.Y * 0.006, -1.35, 1.35) end
		end
	end)

	local function key(k) return UserInputService:IsKeyDown(k) end

	-- сброс бомбы: точка и скорость — как у пилота (сервер проверит и решит, можно ли)
	dropBomb = function()
		if not flying or not flying.root.Parent then return end
		if (flying.model:GetAttribute("Bombs") or 0) <= 0 then
			UI.toast("No bombs left — land and stop to rearm", "error")
			return
		end
		local root = flying.root
		local from = flying.bay and flying.bay.Position or root.Position - root.CFrame.UpVector * 3
		BombRemote:FireServer(from, root.AssemblyLinearVelocity)
	end
	UserInputService.InputBegan:Connect(function(input)
		if not flying or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.E then dropBomb() end
		if input.KeyCode == Enum.KeyCode.Z then toggleSight() end
	end)

	-- куда упадёт бомба, сброшенная сейчас (та же баллистика, что на сервере)
	local sightParams = RaycastParams.new()
	sightParams.FilterType = Enum.RaycastFilterType.Exclude
	sightParams.IgnoreWater = false
	local function predictImpact()
		local root = flying.root
		local p = flying.bay and flying.bay.Position or root.Position
		local v = root.AssemblyLinearVelocity
		local ignore = {flying.model, player.Character}
		for _, n in ipairs({"ClientFx", "Effects"}) do
			local f = workspace:FindFirstChild(n)
			if f then table.insert(ignore, f) end
		end
		sightParams.FilterDescendantsInstances = ignore
		local dt = 0.1
		for _ = 1, 100 do
			local nv = v + Vector3.new(0, -BC.Gravity * dt, 0)
			local np = p + (v + nv) * 0.5 * dt
			local hit = workspace:Raycast(p, np - p, sightParams)
			if hit then return hit.Position end
			if np.Y < 0 then return Vector3.new(np.X, 0, np.Z) end
			p, v = np, nv
		end
		return nil
	end

	RunService.RenderStepped:Connect(function(dt)
		local seat, hum, model = planeSeat()
		if seat and not flying then start(seat, hum, model) elseif not seat and flying then stop() end
		if not flying or not flying.root.Parent then return end
		dt = math.min(dt, 0.1)
		local root, char = flying.root, player.Character

		-- ввод
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		local thr = 0
		if not typing then
			if key(Enum.KeyCode.W) then thr += 1 end
			if key(Enum.KeyCode.S) then thr -= 1 end
			if key(Enum.KeyCode.Left) or key(Enum.KeyCode.A) then aimYaw += 2.0 * dt end
			if key(Enum.KeyCode.Right) or key(Enum.KeyCode.D) then aimYaw -= 2.0 * dt end
			if key(Enum.KeyCode.Up) then aimPitch = math.clamp(aimPitch + 1.5 * dt, -1.35, 1.35) end
			if key(Enum.KeyCode.Down) then aimPitch = math.clamp(aimPitch - 1.5 * dt, -1.35, 1.35) end
		end
		if held.up then thr += 1 end
		if held.down then thr -= 1 end
		-- джойстик: вбок — поворот, вверх/вниз — нос вверх/вниз
		if stick then
			local v = stick.vector()
			if math.abs(v.X) > 0.1 then aimYaw -= v.X * 1.8 * dt end
			if math.abs(v.Y) > 0.1 then aimPitch = math.clamp(aimPitch + v.Y * 1.3 * dt, -1.35, 1.35) end
		end
		throttle = math.clamp(throttle + thr * 0.6 * dt, 0, 1)

		local cf = root.CFrame
		local fwd = cf.LookVector
		local pos = root.Position
		local gear = flying.model:GetAttribute("GearHeight") or 6.2

		-- земля под шасси
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {flying.model, char}
		params.IgnoreWater = false
		local ground = workspace:Raycast(pos, Vector3.new(0, -(gear + 2.5), 0), params)
		local onGround = ground ~= nil and ground.Material ~= Enum.Material.Water
		flying.onGround = onGround
		if onGround and sightOn then setSight(false) end
		-- в бомбовом прицеле самолёт плавно выходит в горизонт
		if sightOn then aimPitch -= aimPitch * math.min(1, dt * 1.5) end
		local groundVel = Vector3.zero
		if onGround and ground.Instance:IsA("BasePart") then
			local gv = ground.Instance:GetVelocityAtPosition(ground.Position)
			groundVel = Vector3.new(gv.X, 0, gv.Z) -- палуба движущегося авианосца
		end

		-- скорость
		local reversing = onGround and throttle <= 0.001 and thr < 0
		if reversing then
			speed = math.max(-P.ReverseSpeed, speed - 8 * dt) -- задний ход
		elseif speed < 0 then
			speed = math.min(0, speed + 12 * dt) -- отпустили S — останавливаемся
		else
			local target = throttle * P.MaxSpeed
			if speed < target then
				speed = math.min(target, speed + P.Acceleration * dt)
			else
				speed = math.max(target, speed - P.Acceleration * 0.5 * dt)
			end
			if not onGround then speed -= fwd.Y * 22 * dt end -- набор высоты стоит скорости, пикирование разгоняет
			if onGround and throttle < 0.05 then speed = math.max(0, speed - P.GroundBrake * dt) end
		end
		speed = math.clamp(speed, -P.ReverseSpeed, P.MaxSpeed * 1.35)

		-- потолок высоты: нос вниз
		local limitMsg
		if pos.Y > P.MaxAltitude then
			aimPitch = math.min(aimPitch, -0.2)
			limitMsg = "Altitude ceiling"
		elseif pos.Y > P.MaxAltitude - 220 then
			-- чем ближе к потолку, тем положе разрешённый набор
			aimPitch = math.min(aimPitch, (P.MaxAltitude - pos.Y) / 220 * 0.9)
		end
		-- граница карты: курс к центру
		if not onGround and (math.abs(pos.X) > P.BoundsX or math.abs(pos.Z) > P.BoundsZ) then
			local toCenter = Vector3.new(-pos.X, 0, -pos.Z).Unit
			local wantYaw = math.atan2(-toCenter.X, -toCenter.Z)
			local d = (wantYaw - aimYaw + math.pi) % (2 * math.pi) - math.pi
			aimYaw += math.clamp(d, -2.5 * dt, 2.5 * dt)
			limitMsg = "Map edge — turn back"
		end
		local aimDir = CFrame.fromOrientation(aimPitch, aimYaw, 0).LookVector
		local newFwd, vel
		local stalled = false
		if onGround and speed < P.TakeoffSpeed then
			-- руление и разбег: хвост поднимается с ростом скорости
			local flatF = Vector3.new(fwd.X, 0, fwd.Z)
			flatF = flatF.Magnitude > 0.01 and flatF.Unit or -Vector3.zAxis
			-- на разворачивающейся палубе самолёт поворачивается вместе с ней
			if ground.Instance:IsA("BasePart") then
				local w = ground.Instance.AssemblyAngularVelocity.Y
				if math.abs(w) > 1e-4 then
					flatF = CFrame.Angles(0, w * dt, 0):VectorToWorldSpace(flatF)
					aimYaw += w * dt
				end
			end
			local flatA = Vector3.new(aimDir.X, 0, aimDir.Z)
			if flatA.Magnitude > 0.01 then flatF = rotateToward(flatF, flatA.Unit, math.rad(45) * dt) end
			local stance = math.rad(10) * (1 - math.clamp(math.abs(speed) / (P.TakeoffSpeed * 0.8), 0, 1))
			newFwd = (flatF * math.cos(stance) + Vector3.yAxis * math.sin(stance)).Unit
			local vy = (ground.Position.Y + gear - pos.Y) * 6
			vel = flatF * speed + Vector3.new(0, vy, 0) + groundVel
		else
			local control = math.clamp((speed - P.StallSpeed * 0.6) / (P.TakeoffSpeed - P.StallSpeed * 0.6), 0.25, 1)
			newFwd = rotateToward(fwd, aimDir, math.rad(P.TurnRate) * dt * control)
			if onGround and newFwd.Y < 0 then
				newFwd = Vector3.new(newFwd.X, 0, newFwd.Z).Unit
			end
			vel = newFwd * speed
			if not onGround and speed < P.StallSpeed then
				stalled = true
				vel += Vector3.new(0, -(P.StallSpeed - speed) * 1.6, 0)
				newFwd = rotateToward(newFwd, Vector3.new(newFwd.X * 0.3, -1, newFwd.Z * 0.3).Unit, math.rad(35) * dt)
			end
			if onGround then
				local vy = (ground.Position.Y + gear - pos.Y) * 6
				vel = Vector3.new(vel.X, math.max(vel.Y, vy), vel.Z) + groundVel
			end
		end

		if pos.Y > P.MaxAltitude and vel.Y > 0 then
			vel = Vector3.new(vel.X, 0, vel.Z) -- жёсткий потолок
		end

		-- автоматический крен в поворотах
		local flatN = Vector3.new(newFwd.X, 0, newFwd.Z)
		local flatA = Vector3.new(aimDir.X, 0, aimDir.Z)
		local targetBank = 0
		if not onGround and flatN.Magnitude > 0.05 and flatA.Magnitude > 0.05 then
			flatN, flatA = flatN.Unit, flatA.Unit
			local yawErr = math.atan2(flatN:Cross(flatA).Y, flatN:Dot(flatA))
			targetBank = math.clamp(yawErr * 2.2, -math.rad(P.MaxBank), math.rad(P.MaxBank))
		end
		local maxRoll = math.rad(P.RollRate) * dt
		bank += math.clamp(targetBank - bank, -maxRoll, maxRoll)

		local right = newFwd:Cross(Vector3.yAxis)
		if right.Magnitude < 0.01 then right = cf.RightVector end
		right = right.Unit
		local up = right:Cross(newFwd).Unit
		local bankedUp = CFrame.fromAxisAngle(newFwd, -bank) * up
		-- турбулентность в грозовом облаке (StormService ставит самолёту атрибут InStorm): рывки по крену,
		-- тангажу и вверх-вниз
		local turb, bump = CFrame.identity, Vector3.zero
		if flying.model:GetAttribute("InStorm") then
			local t = os.clock()
			turb = CFrame.Angles(math.noise(t * 2.3, 1.7) * 0.35, math.noise(t * 1.9, 4.1) * 0.2, math.noise(t * 2.8, 7.3) * 0.55)
			bump = Vector3.new(0, math.noise(t * 3.1, 9.9) * 35, 0)
		end
		if flying.ao then flying.ao.CFrame = CFrame.lookAt(Vector3.zero, newFwd, bankedUp) * turb end
		if flying.lv then flying.lv.VectorVelocity = vel + bump end

		-- камера за самолётом, смотрит по курсу
		local cam = workspace.CurrentCamera
		-- камера выше самолёта: он в нижней части кадра и не заслоняет прицел в центре
		-- бомбы: точка падения каждый кадр и сглаженная (физика и рельеф дают дрожь в несколько студов)
		local bombs, maxBombs = flying.model:GetAttribute("Bombs") or 0, P.Bombs or 0
		-- бомбы кончились — BOMB и SIGHT прячем (и выходим из прицела), после перезарядки — снова показываем
		if bombBtn then
			bombBtn.Text = ("BOMB\n%d"):format(bombs)
			bombBtn.Visible = bombs > 0
		end
		if sightBtn then sightBtn.Visible = bombs > 0 end
		if bombs <= 0 and sightOn then setSight(false) end
		local raw = (maxBombs > 0 and not onGround) and predictImpact() or nil
		if not raw then
			flying.impact = nil
		elseif not flying.impact or (raw - flying.impact).Magnitude > 400 then
			flying.impact = raw
		else
			flying.impact = flying.impact:Lerp(raw, 1 - math.exp(-8 * dt))
		end

		local camDist = P.CamDistance or 34
		if sightOn then
			-- вид из бомбоотсека на точку падения; верх кадра — по курсу
			local flatF = Vector3.new(newFwd.X, 0, newFwd.Z)
			flatF = flatF.Magnitude > 0.01 and flatF.Unit or -Vector3.zAxis
			local eye = (flying.bay and flying.bay.Position or pos) - Vector3.new(0, 3, 0)
			local look = flying.impact or (eye + flatF * 40 - Vector3.new(0, 100, 0))
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(eye, look, flatF), math.min(1, dt * 10))
			cam.FieldOfView = SIGHT_FOV
			local dist = flying.impact and (flying.impact - eye).Magnitude
			sightLbl.Text = (bombs > 0 and ("BOMBS %d/%d"):format(bombs, maxBombs) or "NO BOMBS — land to rearm")
				.. (dist and (" · %d m"):format(math.floor(dist)) or " · too low") .. (touchOnly and "" or " · E — drop · Z — exit")
		else
			local camPos = pos - aimDir * camDist + Vector3.new(0, 12 * camDist / 34, 0)
			cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(camPos, camPos + aimDir), math.min(1, dt * 12))
		end

		-- метки (в бомбовом прицеле их заменяет перекрестие)
		local a, aOn = cam:WorldToViewportPoint(pos + aimDir * 500)
		local n, nOn = cam:WorldToViewportPoint(pos + newFwd * 500)
		aimMark.Visible = aOn and not sightOn
		noseMark.Visible = nOn and not sightOn
		aimMark.Position = UDim2.fromOffset(a.X, a.Y)
		noseMark.Position = UDim2.fromOffset(n.X, n.Y)
		local bp, bOn = Vector3.zero, false
		if flying.impact and bombs > 0 and not sightOn then bp, bOn = cam:WorldToViewportPoint(flying.impact) end
		bombMark.Visible = bOn
		if bOn then bombMark.Position = UDim2.fromOffset(bp.X, bp.Y) end

		-- приборы
		flightLbl.Text = (speed < -0.5 and ("R %d km/h"):format(math.floor(-speed * 4)) or ("%d km/h"):format(math.floor(math.max(0, speed) * 4)))
			.. (" · %d m"):format(math.max(0, math.floor(pos.Y)))
		thrBar.Size = UDim2.fromScale(throttle, 1)
		local hp = (flying.model:GetAttribute("Health") or 0) / (flying.model:GetAttribute("MaxHealth") or 1)
		hpBar.Size = UDim2.fromScale(math.clamp(hp, 0, 1), 1)
		hpBar.BackgroundColor3 = hp > 0.5 and T.Good or (hp > 0.25 and T.Gold or T.Bad)
		local hullTxt = hp > 0.25 and ("Hull %d%%"):format(math.floor(hp * 100 + 0.5)) or ('<font color="#eb554b">Hull %d%%</font>'):format(math.floor(hp * 100 + 0.5))
		statusLbl.Text = maxBombs > 0 and ("%s · %s"):format(hullTxt, bombs > 0 and ("Bombs %d/%d"):format(bombs, maxBombs) or '<font color="#9aa3b2">Bombs 0 — land to rearm</font>') or hullTxt
		if stalled then
			warn.Text, warn.Visible = "STALL — nose down, add throttle", true
		elseif limitMsg then
			warn.Text, warn.TextColor3, warn.Visible = limitMsg, T.Gold, true
		elseif onGround and speed > P.TakeoffSpeed * 0.9 and aimPitch <= 0.02 then
			warn.Text, warn.TextColor3, warn.Visible = touchOnly and "Takeoff speed — swipe up" or "Takeoff speed — pull the mouse up", T.Gold, true
		else
			warn.Visible = false
			warn.TextColor3 = T.Bad
		end

		-- огонь
		local firing = held.fire or (not touchOnly and not typing and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
		if firing ~= lastFiring then
			lastFiring = firing
			Fire:FireServer(firing)
		end
		-- свои пули — сразу и точно из стволов
		local now = os.clock()
		if firing and #flying.muzzles > 0 and now - flying.lastShot >= P.GunCooldown then
			flying.lastShot = now
			local mz = flying.muzzles[(flying.shotN % #flying.muzzles) + 1]
			flying.shotN += 1
			local origin = mz.Position
			local converge = root.Position + root.CFrame.LookVector * 300
			local dir = (converge - origin).Unit * P.GunRange
			local ignore = {flying.model, char}
			for _, n in ipairs({"ClientFx", "Effects"}) do
				local f = workspace:FindFirstChild(n)
				if f then table.insert(ignore, f) end
			end
			shotParams.FilterDescendantsInstances = ignore
			local hit = workspace:Raycast(origin, dir, shotParams)
			local fx = ctx.screens.ShotFx
			if fx then fx.streak(origin, hit and hit.Position or origin + dir, "PlaneGun") end
			-- попал во что-то живое или в технику — сообщаем серверу (он проверит и нанесёт урон)
			if hit and damageable(hit.Instance) then HitRemote:FireServer(hit.Instance, hit.Position) end
		end
	end)

	-- винты всех самолётов с работающим мотором крутятся (визуально, у каждого клиента)
	local angle = 0
	RunService.RenderStepped:Connect(function(dt)
		angle = (angle + dt * 40) % (math.pi * 2)
		local f = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Planes")
		if not f then return end
		local myHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local meSeated = myHum ~= nil and myHum.SeatPart ~= nil
		for _, plane in ipairs(f:GetChildren()) do
			-- кнопка «сесть стрелком» бомбардировщика: не для пилота этого самолёта и не когда место занято (только у меня)
			local tur = plane:FindFirstChild("TailTurret")
			local ped = tur and tur:FindFirstChild("Pedestal")
			local pr = ped and ped:FindFirstChild("TurretPrompt")
			if pr then
				local seat = tur:FindFirstChild("TurretSeat")
				local want = not (flying and flying.model == plane) and not (seat and seat.Occupant) and plane:GetAttribute("IsPlane") == true
				if pr.Enabled ~= want then pr.Enabled = want end
			end
			-- «вернуться в самолёт» (включает сервер): не показываем, пока я сижу (например, в хвостовой турели);
			-- встал — возвращаем, если место пилота свободно (так же решает сервер)
			local fus = plane:FindFirstChild("Fuselage") or plane:FindFirstChild("Root")
			local board = fus and fus:FindFirstChild("BoardPrompt")
			if board then
				if meSeated then
					if board.Enabled then
						board.Enabled = false
						board:SetAttribute("HiddenLocally", true)
					end
				elseif board:GetAttribute("HiddenLocally") then
					board:SetAttribute("HiddenLocally", nil)
					local ps = plane:FindFirstChild("PilotSeat")
					board.Enabled = ps ~= nil and ps.Occupant == nil
				end
			end
			local gearUp = plane:GetAttribute("GearUp") == true
			if plane:GetAttribute("GearState") ~= gearUp then
				plane:SetAttribute("GearState", gearUp)
				for _, d in ipairs(plane:GetChildren()) do
					if d:IsA("BasePart") and (d.Name == "Wheel" or d.Name == "GearStrut" or d.Name == "GearDoor" or d.Name == "TailWheel" or d.Name == "TailStrut") then
						d.LocalTransparencyModifier = gearUp and 1 or 0
					end
				end
			end
			if plane:GetAttribute("EngineOn") then
				-- все винты самолёта (у бомбардировщика два): PropMotor* с исходным положением в атрибуте BaseC0
				local root = plane:FindFirstChild("Root")
				for _, motor in ipairs(root and root:GetChildren() or {}) do
					if motor:IsA("Motor6D") and motor.Name:sub(1, 9) == "PropMotor" then
						local base = motor:GetAttribute("BaseC0")
						if typeof(base) ~= "CFrame" then base = CFrame.new(0, 0, -9.5) end
						motor.C0 = base * CFrame.Angles(0, 0, angle)
					end
				end
			end
		end
	end)

	return {sightOn = function() return sightOn end}
end
