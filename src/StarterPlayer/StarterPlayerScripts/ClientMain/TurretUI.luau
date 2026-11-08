-- Панель стрелка турели: наведение мышью (или центром экрана на телефоне), огонь ЛКМ/кнопкой.
-- На телефоне — круглая FIRE слева от прыжка (и у носовой пушки катера), выход — прыжок.
-- Зенитка (пули): попадание определяем здесь, по тому что в прицеле (TurretHit), сервер проверяет.
-- Снарядные орудия (линкор, катер) считает сервер: снаряд летит по баллистике.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local player = ctx.player
	local mouse = player:GetMouse()
	local Input = ctx.Remotes:WaitForChild("TurretInput")
	local HitRemote = ctx.Remotes:WaitForChild("TurretHit")
	local TC = ctx.Config.Combat.Turret
	local shotParams = RaycastParams.new()
	shotParams.FilterType = Enum.RaycastFilterType.Exclude
	shotParams.CollisionGroup = "Weapons"
	local lastLocalShot = 0
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
	local function ignoreList(seat, char)
		local turret = seat:FindFirstAncestorOfClass("Model")
		local list = {turret and turret:FindFirstAncestorOfClass("Model") or turret, char}
		for _, n in ipairs({"ClientFx", "Effects"}) do
			local f = workspace:FindFirstChild(n)
			if f then table.insert(list, f) end
		end
		return list
	end
	local gui = UI.screen("TurretUI", 15)
	local touchOnly = UI.touchOnly

	-- ПК: клавиши — в общей панели UI.controls слева внизу (у штурвала катера её показывает ShipControlUI)
	local TURRET_KEYS = {
		{"Mouse", "Aim"},
		{"LMB", "Fire"},
		{"RMB / Z", "Zoom"},
		{"Space", "Leave the turret"},
	}
	local fireBtn = touchOnly and UI.roundButton(gui, "main", "FIRE", T.Bad) or nil

	-- приближение для стрелка: маленькая кнопка на телефоне; на ПК — пока зажата ПКМ (как у оружия) или Z
	local BASE_FOV, ZOOM_FOV, GUN_ZOOM_FOV = 70, 28, 40
	local zoomed, fovNow = false, BASE_FOV
	local zoomShown = false -- зум сейчас действует (переключатель или зажатая ПКМ)
	local ZOOM_ON = Color3.fromRGB(70, 140, 220)
	local zoomBtn = touchOnly and UI.roundButton(gui, "zoom", "ZOOM") or nil
	-- с приближением свой катер (мачта, рубка) лез бы в кадр — делаем его полупрозрачным
	local fadedParts = {}
	local gunFadeOf = {} -- [деталь пушки] = прозрачность в виде от орудия (к ней возвращаемся после зума)
	-- свет, погашенный на время зума (только у этого игрока): {свет, исходная яркость}.
	-- Гасим яркостью, а не Enabled: Enabled переключает смена дня и ночи (DayNightClient)
	local offLights = {}
	local function fadeOwn(on)
		for _, p in ipairs(fadedParts) do
			if p.Parent then p.LocalTransparencyModifier = gunFadeOf[p] or 0 end
		end
		fadedParts = {}
		for _, e in ipairs(offLights) do
			if e[1].Parent then e[1].Brightness = e[2] end
		end
		offLights = {}
		if not on then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		local own = seat and seat:GetAttribute("AimTurret") and seat:FindFirstAncestorOfClass("Model")
		if not own then return end
		local mast = own:FindFirstChild("Mast", true)
		for _, p in ipairs(own:GetDescendants()) do
			if p:IsA("BasePart") then
				-- мачта с флагом и огнём на ней стоят прямо перед прицелом — прячем целиком вместе со свечением;
				-- прожектор на крыше рубки светит в кадр — гасим
				local onMast = p.Name == "Flag" or p.Name == "Mast"
					or (p.Name == "NavLight" and mast ~= nil and (p.Position - mast.Position).Magnitude < 5)
				if onMast or p.Name == "DeckFlood" then
					for _, l in ipairs(p:GetChildren()) do
						if l:IsA("Light") then
							table.insert(offLights, {l, l.Brightness})
							l.Brightness = 0
						end
					end
				end
				if p.Transparency < 1 then
					p.LocalTransparencyModifier = onMast and 1 or 0.75
					table.insert(fadedParts, p)
				end
			end
		end
	end
	local function setZoom(on)
		zoomed = on
		if zoomBtn then zoomBtn.BackgroundColor3 = on and ZOOM_ON or zoomBtn:GetAttribute("BaseColor") end
	end
	local function rmbZoom()
		return not touchOnly and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			and not UserInputService:GetFocusedTextBox()
	end
	if zoomBtn then zoomBtn.Activated:Connect(function() setZoom(not zoomed) end) end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.Z then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if seat and (seat:GetAttribute("Turret") or seat:GetAttribute("AimTurret")) then setZoom(not zoomed) end
	end)

	-- прицел в центре экрана для сенсорных устройств
	local cross = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Visible = false}, gui)
	UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = T.Text, BorderSizePixel = 0}, cross)
	UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = T.Text, BorderSizePixel = 0}, cross)
	-- куда сейчас реально смотрит ствол (орудие доворачивает не мгновенно) — кольцо на телефоне
	local gunMark = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Visible = false}, gui)
	UI.corner(gunMark, 9)
	UI.stroke(gunMark, T.Gold, 2)

	local fireHeld = false
	-- зажал FIRE и ведёшь пальцем — камера (а с ней прицел турели) поворачивается
	if fireBtn then UI.onHold(fireBtn, function() fireHeld = true end, function() fireHeld = false end, UI.cameraDrag) end

	-- обзор стрелка: камера выше пушки, сама пушка для него полупрозрачная
	local viewParts, viewHum = {}, nil
	local function setView(seat, on, aimOnly)
		for _, p in ipairs(viewParts) do
			if p.Parent then p.LocalTransparencyModifier = 0 end
		end
		viewParts = {}
		if viewHum and viewHum.Parent then viewHum.CameraOffset = Vector3.zero end
		viewHum = nil
		if not on or not seat then return end
		if aimOnly then
			-- у штурвала катера: на телефоне прицел — центр экрана, и рубка с игроком его закрывали.
			-- Поднимаем камеру над рубкой: катер уходит вниз кадра, прицел смотрит на море.
			if not touchOnly then return end
			local char = player.Character
			viewHum = char and char:FindFirstChildOfClass("Humanoid")
			if viewHum then viewHum.CameraOffset = Vector3.new(0, seat:GetAttribute("CamOffsetY") or 9, 0) end
			return
		end
		local turret = seat:FindFirstAncestorOfClass("Model")
		for _, p in ipairs(turret:GetDescendants()) do
			if p:IsA("BasePart") and p:GetAttribute("TurretMoving") and p ~= seat then
				p.LocalTransparencyModifier = 0.6
				table.insert(viewParts, p)
			end
		end
		local char = player.Character
		viewHum = char and char:FindFirstChildOfClass("Humanoid")
		-- у башен линкора камера выше крыши (CamOffsetY на месте стрелка)
		if viewHum then viewHum.CameraOffset = Vector3.new(0, seat:GetAttribute("CamOffsetY") or 4, 0) end
	end

	local function turretSeat()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if seat and (seat:GetAttribute("Turret") or seat:GetAttribute("AimTurret")) then return seat, hum, char end
		return nil
	end

	-- вид от орудия: камера приближена до упора — ещё шаг колесом (щипок на телефоне) переносит её
	-- на пушку (первое лицо над стволом, стрельба по центру экрана); колесо/щипок назад — обратно.
	-- Пока включён, SeatCamera камеру не трогает (ctx.gunView).
	local eye = UI.new("Part", {Name = "GunEye", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one})
	local gunView, eyeGun = false, nil
	local EYE_UP = 1.8 -- студов над верхом корпуса пушки
	local gunFaded = {} -- детали пушки, полупрозрачные в виде от орудия (щит вплотную закрывал кадр)
	local savedMax, savedMin, savedMode
	local atMinSince, pinchFromMin = nil, false
	local function gunPartOf(seat)
		local holder = seat:FindFirstAncestorOfClass("Model")
		local aim = seat:GetAttribute("AimTurret")
		local m = aim and holder and holder:FindFirstChild(aim) or holder
		return m and m:FindFirstChild("GunBody")
	end
	local function setGunView(on, seat)
		if on == gunView then return end
		local cam = workspace.CurrentCamera
		if on then
			eyeGun = seat and gunPartOf(seat)
			if not eyeGun then return end
			gunView, ctx.gunView = true, true
			eye.CFrame = CFrame.new(eyeGun.Position + eyeGun.CFrame.UpVector * (eyeGun.Size.Y / 2 + EYE_UP))
			for _, p in ipairs(eyeGun.Parent:GetDescendants()) do
				if p:IsA("BasePart") and p.Transparency < 1 and p ~= seat then
					table.insert(gunFaded, {p, p.LocalTransparencyModifier})
					gunFadeOf[p] = 0.6
					p.LocalTransparencyModifier = 0.6 -- как у наземных турелей (setView)
				end
			end
			eye.Parent = cam
			savedMax, savedMin, savedMode = player.CameraMaxZoomDistance, player.CameraMinZoomDistance, player.CameraMode
			player.CameraMode = Enum.CameraMode.LockFirstPerson
			player.CameraMinZoomDistance = 0.5
			player.CameraMaxZoomDistance = 0.5
			cam.CameraSubject = eye
		else
			gunView, ctx.gunView, eyeGun = false, false, nil
			for _, e in ipairs(gunFaded) do
				if e[1].Parent then e[1].LocalTransparencyModifier = e[2] end
			end
			gunFaded = {}
			gunFadeOf = {}
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then cam.CameraSubject = hum end
			eye.Parent = nil
			player.CameraMode = savedMode or Enum.CameraMode.Classic
			player.CameraMaxZoomDistance = savedMax or 400
			player.CameraMinZoomDistance = savedMin or 0.5
		end
	end
	-- точка обзора едет с пушкой (до того как камера пересчитается)
	RunService:BindToRenderStep("GunEye", Enum.RenderPriority.Camera.Value - 1, function()
		if gunView and eyeGun and eyeGun.Parent then
			eye.CFrame = CFrame.new(eyeGun.Position + eyeGun.CFrame.UpVector * (eyeGun.Size.Y / 2 + EYE_UP))
		end
	end)
	-- уже у упора (чуть дольше мгновения — чтобы тот же шаг, что довёл до упора, не включал вид)
	local function settledAtMin()
		return atMinSince ~= nil and os.clock() - atMinSince > 0.15
	end
	local function zoomStep(dir, fromMin)
		local seat = turretSeat()
		-- только у носовой пушки катера: у башен линкора и наземных турелей хватает обычного обзора
		if not seat or not seat:GetAttribute("AimTurret") then return end
		if dir > 0 and not gunView and fromMin then
			setGunView(true, seat)
		elseif dir < 0 and gunView then
			setGunView(false)
		end
	end
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel and input.Position.Z ~= 0 then
			zoomStep(input.Position.Z > 0 and 1 or -1, settledAtMin())
		end
	end)
	UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if state == Enum.UserInputState.Begin then
			pinchFromMin = settledAtMin()
		elseif state == Enum.UserInputState.End then
			if scale > 1.1 then zoomStep(1, pinchFromMin) elseif scale < 0.9 then zoomStep(-1, false) end
		end
	end)

	local timer, lastFiring, wasSeated = 0, false, false
	local sentTarget = nil -- последняя отправленная серверу точка прицела

	RunService.RenderStepped:Connect(function(dt)
		local seat, hum, char = turretSeat()
		local aimOnly = seat ~= nil and seat:GetAttribute("AimTurret") ~= nil
		UI.controls("turret", (seat ~= nil and not aimOnly) and TURRET_KEYS or nil)
		if fireBtn then fireBtn.Visible = seat ~= nil end
		if zoomBtn then zoomBtn.Visible = seat ~= nil end
		local cam = workspace.CurrentCamera
		cross.Visible = seat ~= nil and (touchOnly or gunView) -- в виде от орудия — и на ПК (мышь в центре)
		if not seat then
			gunMark.Visible = false
			atMinSince = nil
			if wasSeated then
				wasSeated = false
				setGunView(false)
				setZoom(false)
				if zoomShown then zoomShown = false fadeOwn(false) end
				fovNow = BASE_FOV
				if cam then cam.FieldOfView = BASE_FOV end
				UserInputService.MouseDeltaSensitivity = 1
				mouse.Icon = ""
				fireHeld = false
				sentTarget, lastFiring = nil, false -- в следующей турели первый кадр отправится сразу
				setView(nil, false)
			end
			return
		end
		if not wasSeated then
			wasSeated = true
			hum:UnequipTools()
			mouse.Icon = "rbxasset://textures/GunCursor.png"
			setView(seat, true, aimOnly)
		end

		-- камера у упора приближения? (для входа в вид от орудия)
		if not gunView and cam then
			local close = player.CameraMode == Enum.CameraMode.LockFirstPerson
				or (cam.CFrame.Position - cam.Focus.Position).Magnitude <= player.CameraMinZoomDistance + 1.5
			if close then atMinSince = atMinSince or os.clock() else atMinSince = nil end
		end
		-- плавный зум
		local zoomNow = zoomed or rmbZoom()
		if zoomNow ~= zoomShown then
			zoomShown = zoomNow
			fadeOwn(zoomNow)
		end
		-- в виде от орудия прицел уже у глаза — приближение мягче
		local wantFov = zoomNow and (gunView and GUN_ZOOM_FOV or ZOOM_FOV) or BASE_FOV
		if math.abs(fovNow - wantFov) > 0.05 then
			fovNow += (wantFov - fovNow) * math.min(1, dt * 12)
			cam.FieldOfView = fovNow
		end
		-- ПК: в зуме мышь крутит камеру медленнее (пропорционально полю зрения), иначе прицел скачет
		if not touchOnly then UserInputService.MouseDeltaSensitivity = math.clamp(fovNow / BASE_FOV, 0.3, 1) end
		local target
		if touchOnly then
			-- точка под прицелом в центре экрана (а не просто далеко впереди): ствол стоит не в камере
			shotParams.FilterDescendantsInstances = ignoreList(seat, char)
			local r = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 1500, shotParams)
			target = r and r.Position or cam.CFrame.Position + cam.CFrame.LookVector * 1000
		else
			local own = seat:FindFirstAncestorOfClass("Model")
			if aimOnly then
				mouse.TargetFilter = own or char -- свой катер
			else
				mouse.TargetFilter = own and own.Parent or char -- корабль/база, на которых стоит башня
			end
			target = mouse.Hit.Position
		end
		-- кольцо ствола: точка, куда полетит выстрел прямо сейчас
		if touchOnly then
			local holder = seat:FindFirstAncestorOfClass("Model")
			local gunModel = aimOnly and holder and holder:FindFirstChild(seat:GetAttribute("AimTurret")) or holder
			local gunPart = gunModel and gunModel:FindFirstChild("GunBody")
			local shown = false
			if gunPart then
				shotParams.FilterDescendantsInstances = ignoreList(seat, char)
				local look = gunPart.CFrame.LookVector * 1500
				local r = workspace:Raycast(gunPart.Position, look, shotParams)
				local sp, onScreen = cam:WorldToViewportPoint(r and r.Position or gunPart.Position + look)
				if onScreen then
					gunMark.Position = UDim2.fromOffset(sp.X, sp.Y)
					shown = true
				end
			end
			gunMark.Visible = shown
		end
		local firing = fireHeld or (not touchOnly and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not UserInputService:GetFocusedTextBox())

		-- зенитка (нет WeaponType): свои выстрелы в темпе пулемёта — попали во что-то, сообщаем серверу
		local turret = seat:FindFirstAncestorOfClass("Model")
		local now = os.clock()
		if firing and not aimOnly and turret and turret:GetAttribute("WeaponType") == nil and now - lastLocalShot >= TC.Cooldown then
			lastLocalShot = now
			local gun = turret:FindFirstChild("GunBody")
			local dir = gun and target - gun.Position
			if dir and dir.Magnitude > 1 then
				shotParams.FilterDescendantsInstances = ignoreList(seat, char)
				local res = workspace:Raycast(gun.Position, dir.Unit * TC.Range, shotParams)
				if res and damageable(res.Instance) then HitRemote:FireServer(res.Instance, res.Position) end
			end
		end

		-- смена огня — сразу; точка прицела — не чаще 20 раз в секунду и только если заметно сдвинулась
		-- (сервер держит последнюю точку сам), плюс подтверждение раз в 0,25 с.
		-- Сервер отбрасывает пакеты чаще 0,02 с — смену огня сразу после отправки откладываем на кадр
		timer += dt
		local moved = not sentTarget or (target - sentTarget).Magnitude > 0.3 + (target - cam.CFrame.Position).Magnitude * 0.002
		if (firing ~= lastFiring and timer >= 0.025) or (timer >= 0.05 and moved) or timer >= 0.25 then
			timer = 0
			lastFiring = firing
			sentTarget = target
			Input:FireServer(target, firing)
		end
	end)
	return {}
end
