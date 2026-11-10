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
local GuiService = game:GetService("GuiService")

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
	local held = {up = false, down = false, fire = false}
	local touchBtns = {}
	local fireDrag -- задаётся ниже, рядом с курсом (aimYaw / aimPitch)
	local function hold(key, slot, text, color, move)
		local b = UI.roundButton(gui, slot, text, color)
		UI.onHold(b, function() held[key] = true end, function() held[key] = false end, move)
		table.insert(touchBtns, b)
		return b
	end
	local bombBtn, sightBtn, upBtn, downBtn
	local dropBomb -- задаётся ниже (нужен текущий самолёт)
	local toggleSight -- тоже
	if touchOnly then
		-- зажал FIRE и ведёшь пальцем — курс самолёта идёт за пальцем (как при перетаскивании по экрану)
		hold("fire", "main", "FIRE", T.Bad, function(d) if fireDrag then fireDrag(d) end end)
		upBtn = hold("up", "a2", "GAS\n+")
		downBtn = hold("down", "a1", "GAS\n−")
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
	local throttle, speed, bank = 0, 0, 0
	local aimYaw, aimPitch = 0, 0
	local camDir -- сглаженное направление камеры (позиция камеры к самолёту привязана жёстко)
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
		local root = model and model:FindFirstChild("Root")
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
		if P.Heli then
			rows = {
				{"Mouse", "Aim — the helicopter turns to it"},
				{"W / S", "Tilt nose down / up (speed up / brake)"},
				{"A / D", "Bank left / right"},
				{"E / Q", "Collective up / down (or Shift / Ctrl)"},
				{"Arrows", "Turn / nose up-down"},
				{"LMB", "Machine gun"},
				{"Space", "Leave the helicopter"},
			}
		end
		if upBtn then upBtn.Text = P.Heli and "UP" or "GAS\n+" end
		if downBtn then downBtn.Text = P.Heli and "DOWN" or "GAS\n−" end
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
		camDir = nil
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
		if not flying or UserInputService:GetFocusedTextBox() or P.Heli then return end -- у вертолёта E / Q — вверх / вниз
		if input.KeyCode == Enum.KeyCode.E then dropBomb() end
		if input.KeyCode == Enum.KeyCode.Z then toggleSight() end
	end)

	-- куда упадёт бомба, сброшенная сейчас (та же баллистика, что на сервере)
	local sightParams = RaycastParams.new()
	sightParams.FilterType = Enum.RaycastFilterType.Exclude
	sightParams.IgnoreWater = false
	-- что не должны видеть лучи самолёта: сам самолёт, пилот и клиентские эффекты
	local function ignoreList(char)
		local ignore = {flying.model, char}
		for _, n in ipairs({"ClientFx", "Effects"}) do
			local f = workspace:FindFirstChild(n)
			if f then table.insert(ignore, f) end
		end
		return ignore
	end
	local function predictImpact()
		local root = flying.root
		local p = flying.bay and flying.bay.Position or root.Position
		local v = root.AssemblyLinearVelocity
		sightParams.FilterDescendantsInstances = ignoreList(player.Character)
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

	-- луч земли под шасси (один объект на всё время, а не новый каждый кадр)
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.IgnoreWater = false

	-- огонь пулемётов (самолёт и вертолёт): смена нажатия — серверу, свои пули — сразу и точно из стволов.
	-- aimAt — точка прицела (вертолёт стреляет туда, куда смотрит камера, но не дальше GUN_CONE от носа:
	-- сервер принимает попадания в конусе 35° от носа); без неё — сходимость на 300 студов перед носом
	local GUN_CONE = math.rad(28)
	local function gunDir(root, origin, aimAt)
		local look = root.CFrame.LookVector
		local want = aimAt and (aimAt - origin) or (root.Position + look * 300 - origin)
		if want.Magnitude < 1 then return look end
		want = want.Unit
		local ang = math.acos(math.clamp(want:Dot(look), -1, 1))
		if ang > GUN_CONE then want = rotateToward(look, want, GUN_CONE) end
		return want
	end
	local function gunStep(root, char, typing, menuOpen, aimAt)
		-- клик по пунктам меню Esc — не очередь из пулемётов
		local firing = held.fire or (not touchOnly and not typing and not menuOpen and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
		if firing ~= lastFiring then
			lastFiring = firing
			Fire:FireServer(firing)
		end
		local now = os.clock()
		if firing and #flying.muzzles > 0 and now - flying.lastShot >= P.GunCooldown then
			flying.lastShot = now
			local mz = flying.muzzles[(flying.shotN % #flying.muzzles) + 1]
			flying.shotN += 1
			local origin = mz.Position
			local dir = gunDir(root, origin, aimAt) * P.GunRange
			shotParams.FilterDescendantsInstances = ignoreList(char)
			local hit = workspace:Raycast(origin, dir, shotParams)
			local fx = ctx.screens.ShotFx
			if fx then fx.streak(origin, hit and hit.Position or origin + dir, "PlaneGun") end
			-- попал во что-то живое или в технику — сообщаем серверу (он проверит и нанесёт урон)
			if hit and damageable(hit.Instance) then HitRemote:FireServer(hit.Instance, hit.Position) end
		end
	end

	-- Вертолёт (P.Heli) — физика полёта. Сил две, обе — через физику Roblox, без телепорта:
	--  • LiftForce (VectorForce у Root, в мировых осях): подъёмная сила несущего винта вдоль оси «вверх» корпуса
	--    плюс сопротивление воздуха; вес даёт сама гравитация. Наклон корпуса наклоняет и тягу — горизонтальная
	--    её часть разгоняет вертолёт, поэтому скорость набирается постепенно и сохраняется (инерция).
	--  • FlightAlign (AlignOrientation): автомат перекоса и хвостовой винт — доворачивают корпус к нужному
	--    наклону и курсу с конечной скоростью (Responsiveness), так ощущается масса. Отпустил — корпус плавно
	--    возвращается в горизонт.
	-- Подъёмная сила ∝ (обороты винта)² × коллектив: сел — винт раскручивается за SpoolTime сек.;
	-- E/Shift — коллектив вверх, Q/Ctrl — вниз, без них коллектив сам держит высоту (зависание).
	-- W/S — наклон носа вперёд/назад (разгон / торможение), A/D — крен влево/вправо (смещение и поворот
	-- траектории). Мышь — прицел: хвостовой винт разворачивает нос к точке прицела, без W/S нос наводится на неё
	-- и по высоте (пулемёт закреплён и бьёт прямо по носу), а «стабилизатор» не даёт этому наклону сносить
	-- вертолёт. Всё считается от массы сборки и гравитации — подходит для любой модели вертолёта.
	-- На телефоне: курс — пальцем, стик Roblox — W/S/A/D, кнопки UP/DOWN — коллектив
	local heliYawVel, heliYawT = 0, 0 -- скорость и целевой курс хвостового винта (ведёт корпус за собой)
	local heliPitch, heliRoll = 0, 0
	local heliRPM = 0
	local heliCam -- сглаженная позиция камеры
	local camParams = RaycastParams.new()
	camParams.FilterType = Enum.RaycastFilterType.Exclude
	local controls
	local function moveVector()
		if not controls then
			local ok, pm = pcall(function() return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 1)) end)
			controls = ok and pm and pm:GetControls() or false
		end
		local ok, v = pcall(function() return controls and controls:GetMoveVector() end)
		return ok and v or Vector3.zero
	end
	local function heliStep(dt, root, char, typing, menuOpen)
		local mx, mz, climb = 0, 0, 0
		if not typing then
			if key(Enum.KeyCode.W) then mz += 1 end
			if key(Enum.KeyCode.S) then mz -= 1 end
			if key(Enum.KeyCode.D) then mx += 1 end
			if key(Enum.KeyCode.A) then mx -= 1 end
			if key(Enum.KeyCode.E) or key(Enum.KeyCode.LeftShift) then climb += 1 end
			if key(Enum.KeyCode.Q) or key(Enum.KeyCode.LeftControl) then climb -= 1 end
			if key(Enum.KeyCode.Left) then aimYaw += 2.0 * dt end
			if key(Enum.KeyCode.Right) then aimYaw -= 2.0 * dt end
			if key(Enum.KeyCode.Up) then aimPitch = math.clamp(aimPitch + 1.5 * dt, -1.35, 1.35) end
			if key(Enum.KeyCode.Down) then aimPitch = math.clamp(aimPitch - 1.5 * dt, -1.35, 1.35) end
		end
		if touchOnly then
			local mv = moveVector()
			mx += mv.X
			mz -= mv.Z
		end
		if held.up then climb += 1 end
		if held.down then climb -= 1 end
		mx, mz, climb = math.clamp(mx, -1, 1), math.clamp(mz, -1, 1), math.clamp(climb, -1, 1)

		local model = flying.model
		local pos = root.Position
		local vel = root.AssemblyLinearVelocity
		local gear = model:GetAttribute("GearHeight") or 6
		groundParams.FilterDescendantsInstances = ignoreList(char)
		local ground = workspace:Raycast(pos, Vector3.new(0, -(gear + 1.5), 0), groundParams)
		local onGround = ground ~= nil and ground.Material ~= Enum.Material.Water
		flying.onGround = onGround
		local look = root.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		if not flying.heliInit then
			-- сел: на земле винт раскручивается с нуля, в воздухе (пересел в зависший) — уже на оборотах
			flying.heliInit = true
			heliRPM = onGround and 0 or 1
			heliYawVel, heliYawT, heliCam = 0, yaw, nil
			local px = root.CFrame:ToOrientation()
			heliPitch, heliRoll = px, 0
			flying.lift = root:FindFirstChild("LiftForce")
			if flying.lv then flying.lv.Enabled = false end -- у вертолёта не задаём скорость напрямую
			if flying.ao then flying.ao.Responsiveness = P.AttitudeResponse or 10 end
		end
		local lift = flying.lift
		local aimDir = CFrame.fromOrientation(aimPitch, aimYaw, 0).LookVector
		-- стоит на земле, пока не начали взлёт
		local parked = onGround and climb <= 0 and vel.Magnitude < 8

		-- обороты несущего винта (раскрутка ~SpoolTime сек.); винт и хвостовой винт крутятся с ними (PlaneClient ниже)
		heliRPM = math.min(1, heliRPM + dt / (P.SpoolTime or 3))
		model:SetAttribute("RotorRPM", heliRPM)

		-- камера: смотрит строго по прицелу (мышь), позиция плавно догоняет точку за вертолётом и выше него
		local cam = workspace.CurrentCamera
		local camDist = P.CamDistance or 40
		local eye = pos + Vector3.new(0, 4, 0)
		local wantCam = pos - aimDir * camDist + Vector3.new(0, 14, 0)
		camParams.FilterDescendantsInstances = ignoreList(char)
		local block = workspace:Raycast(eye, wantCam - eye, camParams)
		if block then wantCam = block.Position + block.Normal * 1.5 end
		if not heliCam or (heliCam - wantCam).Magnitude > 150 then heliCam = wantCam end
		heliCam = heliCam:Lerp(wantCam, 1 - math.exp(-7 * dt))
		cam.CFrame = CFrame.lookAt(heliCam, heliCam + aimDir)
		-- точка прицела: куда смотрит центр экрана (луч камеры), иначе — далеко по прицелу
		shotParams.FilterDescendantsInstances = ignoreList(char)
		local aimHit = workspace:Raycast(heliCam, aimDir * 1000, shotParams)
		local aimAt = aimHit and aimHit.Position or heliCam + aimDir * 600
		local toAim = aimAt - pos
		if toAim.Magnitude < 25 then toAim = aimDir * 25 end
		local flatTo = Vector3.new(toAim.X, 0, toAim.Z).Magnitude

		-- хвостовой винт: курс к точке прицела, у поворота есть разгон
		local turnMax = math.rad(P.TurnRate)
		local yawErr = (math.atan2(-toAim.X, -toAim.Z) - heliYawT + math.pi) % (2 * math.pi) - math.pi
		local wantYawVel = parked and 0 or math.clamp(yawErr * 4, -turnMax, turnMax) * heliRPM
		heliYawVel += (wantYawVel - heliYawVel) * math.min(1, dt * 7)
		heliYawT += heliYawVel * dt
		-- целевой курс не убегает от корпуса дальше ~30° (упёрся во что-то — не накапливаем)
		local lead = (heliYawT - yaw + math.pi) % (2 * math.pi) - math.pi
		heliYawT = yaw + math.clamp(lead, -0.5, 0.5)
		local heading = CFrame.Angles(0, heliYawT, 0)
		local fwd, right = heading.LookVector, heading.RightVector

		-- автомат перекоса: нужный наклон корпуса. W/S — нос вниз/вверх, A/D — крен; без W/S нос — на прицел.
		-- В повороте на скорости — согласованный крен
		local maxTilt = math.rad(P.MaxTilt)
		local hVel = Vector3.new(vel.X, 0, vel.Z)
		local fwdSpeed, sideSpeed = hVel:Dot(fwd), hVel:Dot(right)
		local wantPitch, wantRoll = 0, 0
		local limitMsg
		if not parked then
			if mz ~= 0 then
				wantPitch = -mz * maxTilt
			else
				wantPitch = math.clamp(math.atan2(toAim.Y, flatTo), math.rad(P.AimPitchMin), math.rad(P.AimPitchMax))
			end
			wantRoll = -mx * maxTilt + math.clamp(heliYawVel / turnMax * math.clamp(fwdSpeed / P.MaxSpeed, 0, 1), -1, 1) * math.rad(20)
		end
		-- граница карты: наклон к центру
		if math.abs(pos.X) > P.BoundsX or math.abs(pos.Z) > P.BoundsZ then
			local toC = Vector3.new(-pos.X, 0, -pos.Z).Unit
			wantPitch, wantRoll = -toC:Dot(fwd) * maxTilt, -toC:Dot(right) * maxTilt
			mz, mx = 1, 1 -- стабилизатор не гасит этот наклон
			limitMsg = "Map edge — turn back"
		end
		heliPitch += (wantPitch - heliPitch) * math.min(1, dt * 5)
		heliRoll += (wantRoll - heliRoll) * math.min(1, dt * 5)
		if flying.ao then flying.ao.CFrame = heading * CFrame.Angles(heliPitch, 0, 0) * CFrame.Angles(0, 0, heliRoll) end

		-- подъёмная сила: коллектив держит заданную вертикальную скорость (без E/Q — 0, зависание)
		local M = root.AssemblyMass
		local g = workspace.Gravity
		local wantVy = climb * P.Climb
		if pos.Y > P.MaxAltitude and wantVy > 0 then
			wantVy = 0
			limitMsg = "Altitude ceiling"
		end
		-- мягкая посадка: у земли снижение само замедляется
		if wantVy < 0 then
			local below = workspace:Raycast(pos, Vector3.new(0, -(gear + 30), 0), groundParams)
			if below then wantVy = math.max(wantVy, -(5 + math.max(0, pos.Y - gear - below.Position.Y) * 1.2)) end
		end
		if pos.Y - gear < 2 then wantVy = math.max(wantVy, 6) end -- над самой водой — вверх
		local up = root.CFrame.UpVector
		local needVert = M * (g + (wantVy - vel.Y) * 3) -- вертикальная часть тяги
		local thrust = needVert / math.max(up.Y, 0.35)
		local maxThrust = M * g * (P.LiftReserve or 1.9) * heliRPM * heliRPM
		thrust = math.clamp(thrust, 0, maxThrust)
		if parked then thrust = math.min(thrust, M * g * 0.9 * heliRPM * heliRPM) end -- стоит на полозьях
		local force = up * thrust
		-- стабилизатор: наклон носа на прицел (без W/S) и крен поворота (без A/D) не сносят вертолёт
		local hThrust = Vector3.new(force.X, 0, force.Z)
		if mz == 0 then force -= fwd * hThrust:Dot(fwd) end
		if mx == 0 then force -= right * hThrust:Dot(right) end
		-- сопротивление воздуха по осям вертолёта: даёт предельную скорость MaxSpeed (вперёд при полном
		-- наклоне) и SideSpeed (вбок / назад); без W/S/A/D — ещё и торможение к зависанию (инерция остаётся)
		local tanT = math.tan(maxTilt)
		local cF = g * tanT / (fwdSpeed >= 0 and P.MaxSpeed or P.SideSpeed)
		local cS = g * tanT / P.SideSpeed
		local brake = P.HoverBrake or 0.8
		if mz == 0 then cF += brake end
		if mx == 0 then cS += brake end
		force -= M * (fwd * fwdSpeed * cF + right * sideSpeed * cS)
		-- турбулентность в грозовом облаке
		if model:GetAttribute("InStorm") then
			local t = os.clock()
			force += M * Vector3.new(math.noise(t * 2.1, 3.3) * 80, math.noise(t * 3.1, 9.9) * 120, math.noise(t * 2.4, 5.1) * 80)
		end
		if lift then lift.Force = force end

		-- пулемёт закреплён: бьёт прямо по носу, стволы сведены на дальность точки прицела.
		-- Метки: круг — прицел (центр экрана), точка — куда полетят пули сейчас
		local noseAt = root.Position + root.CFrame.LookVector * math.clamp(toAim.Magnitude, 60, P.GunRange)
		local mzl = flying.muzzles[1]
		local gunFrom = mzl and mzl.Position or pos
		local gunAt = gunFrom + gunDir(root, gunFrom, noseAt) * math.min((noseAt - gunFrom).Magnitude, P.GunRange)
		local vs = cam.ViewportSize
		local n, nOn = cam:WorldToViewportPoint(gunAt)
		aimMark.Visible, noseMark.Visible, bombMark.Visible = true, nOn, false
		aimMark.Position = UDim2.fromOffset(vs.X / 2, vs.Y / 2)
		noseMark.Position = UDim2.fromOffset(n.X, n.Y)

		-- приборы: скорость, высота; полоса — обороты винта, пока раскручивается, потом скорость
		speed = hVel.Magnitude
		local alt = ground and (pos.Y - gear - ground.Position.Y) or (pos.Y - gear)
		flightLbl.Text = ("%d km/h · %d m"):format(math.floor(vel.Magnitude * 4), math.max(0, math.floor(pos.Y)))
		thrBar.Size = UDim2.fromScale(heliRPM < 1 and heliRPM or math.clamp(speed / P.MaxSpeed, 0, 1), 1)
		local hp = (model:GetAttribute("Health") or 0) / (model:GetAttribute("MaxHealth") or 1)
		hpBar.Size = UDim2.fromScale(math.clamp(hp, 0, 1), 1)
		hpBar.BackgroundColor3 = hp > 0.5 and T.Good or (hp > 0.25 and T.Gold or T.Bad)
		statusLbl.Text = hp > 0.25 and ("Hull %d%%"):format(math.floor(hp * 100 + 0.5)) or ('<font color="#eb554b">Hull %d%%</font>'):format(math.floor(hp * 100 + 0.5))
		if limitMsg then
			warn.Text, warn.TextColor3, warn.Visible = limitMsg, T.Gold, true
		elseif heliRPM < 1 and onGround then
			warn.Text, warn.TextColor3, warn.Visible = ("Rotor spinning up · %d%%"):format(math.floor(heliRPM * 100)), T.Gold, true
		elseif onGround and alt < 1 and climb <= 0 then
			warn.Text, warn.TextColor3, warn.Visible = touchOnly and "Hold UP to take off" or "Hold E to take off", T.Gold, true
		else
			warn.Visible = false
		end
		gunStep(root, char, typing, menuOpen, noseAt)
	end

	RunService.RenderStepped:Connect(function(dt)
		local seat, hum, model = planeSeat()
		if seat and not flying then start(seat, hum, model) elseif not seat and flying then stop() end
		-- корень самолёта пропал, а сиденье ещё есть — отпускаем камеру и мышь (иначе зависли бы в Scriptable)
		if flying and not flying.root.Parent then stop() end
		if not flying then return end
		-- курсор держим в центре весь полёт: сел с оружием в руках — GunClient в том же кадре снимает оружие
		-- и возвращает MouseBehavior = Default (уже после start), и мышь упиралась бы в край экрана.
		-- Пока открыто меню Roblox (Esc), мышь не трогаем — им пользуются курсором
		local menuOpen = GuiService.MenuIsOpen
		if not touchOnly and not menuOpen and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		dt = math.min(dt, 0.1)
		local root, char = flying.root, player.Character

		-- ввод
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		if P.Heli then
			heliStep(dt, root, char, typing, menuOpen)
			return
		end
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
		throttle = math.clamp(throttle + thr * 0.6 * dt, 0, 1)

		local cf = root.CFrame
		local fwd = cf.LookVector
		local pos = root.Position
		local gear = flying.model:GetAttribute("GearHeight") or 6.2

		-- земля под шасси
		groundParams.FilterDescendantsInstances = {flying.model, char}
		local ground = workspace:Raycast(pos, Vector3.new(0, -(gear + 2.5), 0), groundParams)
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
			-- на стоянке — на трёх колёсах (ParkPitch); высота Root следует за углом, чтобы и основные,
			-- и хвостовое колесо касались земли
			local k = 1 - math.clamp(math.abs(speed) / (P.TakeoffSpeed * 0.8), 0, 1)
			local stance = math.rad(P.ParkPitch or 10) * k
			newFwd = (flatF * math.cos(stance) + Vector3.yAxis * math.sin(stance)).Unit
			local vy = (ground.Position.Y + gear + ((P.ParkGear or gear) - gear) * k - pos.Y) * 6
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
		-- до 100 лучей за кадр — только когда точка падения кому-то нужна (есть бомбы: кольцо или прицел)
		local raw = (bombs > 0 and not onGround) and predictImpact() or nil
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
			-- Раньше камера догоняла точку через Lerp позиции: на скорости она отставала на десятки студов, и отставание
			-- менялось с длиной кадра — самолёт дёргался в кадре. Теперь позиция считается от самолёта в этом же кадре,
			-- а сглаживается только направление взгляда (не зависит от FPS).
			camDir = camDir and camDir:Lerp(aimDir, 1 - math.exp(-10 * dt)) or aimDir
			if camDir.Magnitude < 0.01 then camDir = aimDir end
			camDir = camDir.Unit
			local camPos = pos - camDir * camDist + Vector3.new(0, 12 * camDist / 34, 0)
			cam.CFrame = CFrame.lookAt(camPos, camPos + camDir)
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
		gunStep(root, char, typing, menuOpen)
	end)

	-- винты всех самолётов с работающим мотором крутятся (визуально, у каждого клиента) — каждый кадр;
	-- кнопки и шасси — 5 раз в секунду (перебор деталей каждый кадр ни к чему).
	-- Моторы PropMotor* (воздушные винты) крутятся вокруг Z; у вертолёта RotorMotor / TailRotorMotor —
	-- вокруг оси из атрибута SpinAxis со скоростью ×SpinRate
	local angle, slowAcc = 0, 0
	local motorCache = setmetatable({}, {__mode = "k"}) -- [самолёт] = {{мотор, исходный C0, ось, скорость}}
	local function motorsOf(plane)
		local list = motorCache[plane]
		if list then return list end
		local root = plane:FindFirstChild("Root")
		if not root then return {} end
		list = {}
		for _, motor in ipairs(root:GetChildren()) do
			if motor:IsA("Motor6D") and (motor.Name:sub(1, 9) == "PropMotor" or motor:GetAttribute("SpinAxis")) then
				local base = motor:GetAttribute("BaseC0")
				table.insert(list, {motor, typeof(base) == "CFrame" and base or CFrame.new(0, 0, -9.5), motor:GetAttribute("SpinAxis") or "Z", motor:GetAttribute("SpinRate") or 1})
			end
		end
		motorCache[plane] = list
		return list
	end
	RunService.RenderStepped:Connect(function(dt)
		angle = (angle + dt * 40) % (math.pi * 2)
		slowAcc += dt
		local slow = slowAcc >= 0.2
		if slow then slowAcc = 0 end
		local f = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Planes")
		if not f then return end
		local myHum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local meSeated = myHum ~= nil and myHum.SeatPart ~= nil
		for _, plane in ipairs(f:GetChildren()) do
			if plane:GetAttribute("EngineOn") then
				local rpm = plane:GetAttribute("RotorRPM") or 1
				for _, m in ipairs(motorsOf(plane)) do
					local a = angle
					if m[3] ~= "Z" then
						-- винты вертолёта: свой угол, скорость — по оборотам (раскрутка у пилота)
						m[5] = ((m[5] or 0) + dt * 40 * m[4] * rpm) % (math.pi * 2)
						a = m[5]
					end
					m[1].C0 = m[2] * (m[3] == "Y" and CFrame.Angles(0, a, 0) or m[3] == "X" and CFrame.Angles(a, 0, 0) or CFrame.Angles(0, 0, a))
				end
			end
			if not slow then continue end
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
			-- «сесть пассажиром» (вертолёт): не показываем, пока я сам где-то сижу (иначе E пилота — это кнопка)
			local door = plane:FindFirstChild("Door")
			local pp = door and door:FindFirstChild("PassengerPrompt")
			if pp then
				local ps = plane:FindFirstChild("PassengerSeat")
				local want = not meSeated and ps ~= nil and ps.Occupant == nil and plane:GetAttribute("IsPlane") == true
				if pp.Enabled ~= want then pp.Enabled = want end
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
		end
	end)

	return {sightOn = function() return sightOn end}
end
