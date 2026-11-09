-- Стрельба из ручного оружия: обычная камера Roblox (без сдвига к плечу).
-- С оружием в руках всегда первое лицо — и на ПК, и на телефоне (честно: стреляешь только туда, куда смотришь;
-- сервер отклоняет выстрелы в сторону от взгляда, GunService). Убрал оружие — камера возвращается
-- в третье лицо на прежнее расстояние. Телефон: FIRE — по центру экрана, тап — в точку касания.
-- От первого лица — прицел в центре экрана, Alt — освободить курсор.
-- ПКМ — прицеливание (зум, меньше разброс), ЛКМ — огонь (автомат — очередью), R — перезарядка.
-- Отдача (только от первого лица) плавно поднимает настоящий прицел (первые пули очереди — слабо), после очереди ствол частично
-- возвращается сам; если игрок сам тянет мышь вниз, возврат уменьшается.
-- Клиент только целится: попадание, урон и патроны считает сервер (GunService).
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundFx = require(script.Parent:WaitForChild("SoundFx"))

local BASE_FOV = 70
local RECOIL_SNAP = 22     -- как быстро толчок доходит до прицела (1/с): почти весь за ~0,1 с
local RECOVER_DELAY = 0.14 -- через сколько после выстрела ствол начинает возвращаться
local RECOVER_RATE = 7     -- скорость возврата (1/с)
local RECOVER_SHARE = 0.7  -- какую часть подъёма ствол возвращает сам
local MOUSE_DEG = 0.27     -- градусов наклона камеры на пиксель мыши (как у стандартной камеры)
local BLOOM_DECAY = 6   -- градусов разброса в секунду

return function(ctx)
	local player = ctx.player
	local Config = ctx.Config
	local Fire = ctx.Remotes:WaitForChild("Fire")
	local ReloadRemote = ctx.Remotes:WaitForChild("GunReload")
	local HitMarker = ctx.Remotes:WaitForChild("HitMarker")
	local UI = ctx.UI
	local touchOnly = UI.touchOnly
	local rng = Random.new()
	-- общее с GunPose: толчок оружия в руках и прицеливание
	local gunState = {kick = 0, aiming = false}
	ctx.gunState = gunState

	------------------------------------------------------------------ интерфейс
	local gui = Instance.new("ScreenGui")
	gui.Name = "GunHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 12
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local cross = Instance.new("Frame")
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromOffset(1, 1)
	cross.BackgroundTransparency = 1
	cross.Parent = gui
	-- картинка прицела (Icons.Crosshair): размер растёт вместе с разбросом
	local crossImg = UI.new("ImageLabel", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1,
		Image = UI.Icons.Crosshair, ScaleType = Enum.ScaleType.Fit, ImageTransparency = 0.1}, cross)
	-- перезарядка: крутящийся значок под прицелом
	local reloadImg = UI.new("ImageLabel", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1,
		Image = UI.Icons.Reload, ScaleType = Enum.ScaleType.Fit, Visible = false}, cross)
	-- хитмаркер: белый крест, в голову — красный
	local hit = Instance.new("Frame")
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromOffset(24, 24)
	hit.BackgroundTransparency = 1
	hit.Visible = false
	hit.Parent = gui
	local hitImg = UI.new("ImageLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = UI.Icons.Hit, ScaleType = Enum.ScaleType.Fit}, hit)
	local hitScale = UI.new("UIScale", {}, hit)

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -24, 1, -24)
	panel.Size = UDim2.fromOffset(220, 74)
	if touchOnly then
		-- на телефоне справа внизу кнопки — патроны по центру снизу
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.new(0.5, 0, 1, -10)
		panel.Size = UDim2.fromOffset(170, 58)
	end
	panel.BackgroundColor3 = Color3.fromRGB(26, 74, 160)
	panel.BackgroundTransparency = 0.1
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(13, 27, 61)
	ps.Thickness = 3
	ps.Parent = panel
	panel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = panel
	local function label(text, pos, size, ts, color, align)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = pos
		l.Size = size
		l.Font = Enum.Font.GothamBold
		l.TextSize = ts
		l.TextColor3 = color
		l.TextXAlignment = align or Enum.TextXAlignment.Right
		l.Text = text
		l.Parent = panel
		return l
	end
	local nameLbl = label("", UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 18), 14, Color3.fromRGB(170, 180, 195))
	local ammoLbl = label("", UDim2.fromOffset(14, 26), UDim2.new(1, -28, 0, 30), 28, Color3.new(1, 1, 1))
	local hintLbl = label("", UDim2.fromOffset(14, 54), UDim2.new(1, -28, 0, 14), 11, Color3.fromRGB(150, 158, 170))

	-- телефон: круглые кнопки вокруг прыжка — перезарядка (слева), FIRE (выше-слева; зажав,
	-- можно вести пальцем и крутить камеру), AIM (над прыжком)
	local touchButtons = {}
	if touchOnly then
		touchButtons.fire = UI.roundButton(gui, "gunFire", "FIRE", Color3.fromRGB(205, 60, 50))
		touchButtons.reload = UI.roundButton(gui, "gunReload", "R")
		touchButtons.aim = UI.roundButton(gui, "gunAim", "AIM")
		for _, b in pairs(touchButtons) do b.Visible = true end -- видны вместе с интерфейсом оружия (gui)
	end
	local dragX, dragY = 0, 0 -- палец на FIRE ведёт прицел
	local TOUCH_DEG = 0.22 -- градусов поворота на пиксель сдвига пальца

	------------------------------------------------------------------ состояние
	local tool, gun, hum, hrp
	local firing, aiming, freeCursor = false, false, false
	local pendingShot = false -- клик короче кадра не должен теряться
	local reloadAskedAt, reloadStart, wasReloading = 0, 0, false
	local nextShot, bloom = 0, 0
	local pendP, pendY = 0, 0           -- толчок, который ещё не дошёл до прицела, градусы
	local climb, lastShot, burst, shake = 0, 0, 0, 0 -- насколько очередь увела вверх; номер пули в очереди
	local fovNow, offsetNow = BASE_FOV, Vector3.zero
	local firstPerson = false
	local tapRay = nil       -- телефон: выстрел через точку касания
	local aimPos = nil       -- куда целимся от третьего лица (точка под курсором / последний выстрел)
	local wasFirstPerson = nil
	local savedCam = nil -- телефон: камера до того, как взяли оружие (режим и расстояние)
	local faded = {} -- детали аксессуаров на спине, которые мы сделали полупрозрачными

	-- флаги, рюкзаки и прочее на спине закрывают прицел из-за плеча (v = nil — вернуть как было)
	local function setBackFade(char, v)
		if not v then
			for p in pairs(faded) do if p.Parent then p.LocalTransparencyModifier = 0 end end
			table.clear(faded)
			return
		end
		for _, acc in ipairs(char:GetChildren()) do
			local h = acc:IsA("Accessory") and acc:FindFirstChild("Handle")
			local att = h and h:FindFirstChildWhichIsA("Attachment")
			if att and att.Name:find("Back") and not h:FindFirstChildWhichIsA("WrapLayer") then
				h.LocalTransparencyModifier = v
				faded[h] = true
			end
		end
	end


	local function currentTool()
		local char = player.Character
		local h = char and char:FindFirstChildOfClass("Humanoid")
		if not h or h.Health <= 0 or h.SeatPart then return nil end
		local t = char:FindFirstChildOfClass("Tool")
		if t and t:GetAttribute("Gun") and Config.Guns[t:GetAttribute("Gun")] then return t, h end
		return nil
	end

	local function requestReload()
		if not tool or not gun or tool:GetAttribute("Reloading") then return end
		if (tool:GetAttribute("Ammo") or 0) >= gun.Mag then return end
		if gun.Reserve and (tool:GetAttribute("Reserve") or 0) <= 0 then return end
		if os.clock() - reloadAskedAt < 0.8 then return end -- пока сервер не ответил — не спамим
		reloadAskedAt = os.clock()
		ReloadRemote:FireServer()
		SoundFx.play("Reload")
	end

	local function activate(t, h)
		tool, gun, hum = t, Config.Guns[t:GetAttribute("Gun")], h
		hrp = h.Parent and h.Parent:FindFirstChild("HumanoidRootPart")
		gui.Enabled = true
		nameLbl.Text = gun.DisplayName
		bloom, pendP, pendY, climb, burst, shake = 0, 0, 0, 0, 0, 0
		aimPos, tapRay, wasFirstPerson = nil, nil, nil
		gunState.tool = t
		-- взял оружие — сразу первое лицо
		if not savedCam then
			local cam = workspace.CurrentCamera
			local dist = cam and (cam.CFrame.Position - cam.Focus.Position).Magnitude or 12
			savedCam = {mode = player.CameraMode, dist = dist > 1 and dist or 12}
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
	end
	-- убрал оружие — обратно третье лицо на прежнее расстояние
	local origMinZoom, zoomToken = nil, 0 -- настоящий мин. зум, пока он временно подменён
	local function restoreCamera()
		if not savedCam then return end
		local s = savedCam
		savedCam = nil
		player.CameraMode = s.mode == Enum.CameraMode.LockFirstPerson and Enum.CameraMode.Classic or s.mode
		-- после LockFirstPerson камера остаётся в голове: отодвигаем её через минимальный зум на пару кадров.
		-- Исходное значение запоминаем один раз: при быстрой смене оружия (снял–взял–снял за 0,1 с)
		-- иначе «запомнился» бы временный зум и остался навсегда
		origMinZoom = origMinZoom or player.CameraMinZoomDistance
		ctx.origMinZoom = origMinZoom -- SeatCamera (сел в технику с оружием в руках) запомнит настоящее значение, а не временное
		local temp = math.min(s.dist, player.CameraMaxZoomDistance)
		player.CameraMinZoomDistance = temp
		zoomToken += 1
		local my = zoomToken
		task.delay(0.1, function()
			if my ~= zoomToken or not origMinZoom then return end
			-- за это время мин. зум мог взять на себя SeatCamera (место с CamMinZoom) — тогда его не трогаем
			if math.abs(player.CameraMinZoomDistance - temp) < 0.01 then player.CameraMinZoomDistance = origMinZoom end
			origMinZoom, ctx.origMinZoom = nil, nil
		end)
	end
	local function deactivate()
		if hum and hum.Parent then
			hum.AutoRotate = true
			hum.CameraOffset = Vector3.zero
		end
		setBackFade(nil, nil)
		firstPerson = false
		gunState.firstPerson = false
		gunState.aimPitch = nil
		gunState.tool = nil
		tool, gun, hum, hrp = nil, nil, nil, nil
		firing, aiming = false, false
		-- клик/касание за миг до того, как убрал оружие (сел, умер), не должен выстрелить при следующем взятии
		pendingShot, tapRay, dragX, dragY = false, nil, 0, 0
		gui.Enabled = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		restoreCamera()
	end

	------------------------------------------------------------------ выстрел
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.CollisionGroup = "Weapons"

	local function muzzleFlash(mcf, small)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 200, 90)
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * (gun.Rocket and 1.6 or 0.7) * (small and 0.35 or 1)
		p.CFrame = mcf * CFrame.new(0, 0, -0.3)
		local l = Instance.new("PointLight")
		l.Color = p.Color
		l.Range = 10
		l.Brightness = 3
		l.Parent = p
		p.Parent = workspace:FindFirstChild("ClientFx") or workspace
		task.delay(0.045, function() p:Destroy() end)
	end

	-- луч прицела: через точку касания, через курсор (третье лицо на ПК) или через центр экрана
	local function aimRay(cam)
		if tapRay then
			local r = tapRay
			tapRay = nil
			return r.Origin, r.Direction.Unit
		end
		if not touchOnly and not firstPerson then
			local m = UserInputService:GetMouseLocation()
			local r = cam:ViewportPointToRay(m.X, m.Y)
			return r.Origin, r.Direction.Unit
		end
		return cam.CFrame.Position, cam.CFrame.LookVector
	end

	local function shoot()
		local cam = workspace.CurrentCamera
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if not cam or not head then return end
		-- разброс: база + разогрев очереди; в движении и в прыжке больше
		local spread = (aiming and gun.Aim or gun.Hip) + bloom
		if hum.MoveDirection.Magnitude > 0.1 then spread *= aiming and 1.3 or 1.5 end
		if hum.FloorMaterial == Enum.Material.Air then spread *= 2 end
		local r = math.rad(spread) * math.sqrt(rng:NextNumber())
		local a = rng:NextNumber() * math.pi * 2
		local origin, baseDir = aimRay(cam)
		local dir = (CFrame.lookAt(Vector3.zero, baseDir) * CFrame.Angles(math.sin(a) * r, math.cos(a) * r, 0)).LookVector
		local fx = workspace:FindFirstChild("ClientFx")
		local sfx = workspace:FindFirstChild("Effects")
		local ex = {char}
		if fx then table.insert(ex, fx) end
		if sfx then table.insert(ex, sfx) end
		rayParams.FilterDescendantsInstances = ex
		local reach = gun.Range + (origin - head.Position).Magnitude
		local res = workspace:Raycast(origin, dir * reach, rayParams)
		local target = res and res.Position or origin + dir * reach
		-- цель не может быть между камерой и стрелком (камера сзади)
		if (target - head.Position):Dot(dir) < 1 then target = head.Position + dir * gun.Range end
		aimPos = target
		-- деталь, в которую попали на нашем экране: сервер проверит и засчитает (иначе пинг съедает попадания)
		Fire:FireServer(target, res and res.Instance or nil)
		local muzzle = tool:FindFirstChild("Muzzle") or tool:FindFirstChild("Handle")
		-- от первого лица настоящее оружие скрыто — вспышка и трассер идут из дула копии перед камерой
		local fpCF = gunState.firstPerson and gunState.vmMuzzleCF
		local mcf = fpCF or (muzzle and muzzle.CFrame)
		if mcf then
			muzzleFlash(mcf, fpCF ~= nil)
			if not gun.Rocket then
				local shotFx = ctx.screens.ShotFx
				if shotFx then shotFx.streak(mcf.Position, target, gun.Sound) end
			end
		end
		-- отдача: толчок копится и плавно доходит до прицела (GunRecoil); первые пули очереди почти не уводят
		local now = os.clock()
		if now - lastShot > 60 / gun.RPM * 2.5 then burst = 0 end
		burst += 1
		lastShot = now
		local k = (aiming and 0.6 or 1) * ((burst <= 2 and not gun.Rocket) and 0.4 or 1)
		pendP += gun.Recoil * k * rng:NextNumber(0.9, 1.1)
		-- вбок: свой «рисунок» у каждого ствола (RecoilDrift — куда тянет очередь) плюс немного случайности
		local drift = math.sin(burst * 0.35) * (gun.RecoilDrift or 0)
		pendY += (drift + rng:NextNumber(-1, 1)) * gun.RecoilYaw * k
		shake = math.min(shake + (gun.Shake or 0.4), 3)
		gunState.kick = math.min(gunState.kick + (gun.Rocket and 2 or 1), 2)
		bloom = math.min(bloom + gun.Bloom, gun.Hip * 1.6)
	end

	------------------------------------------------------------------ ввод
	UserInputService.InputBegan:Connect(function(input, processed)
		if not tool then return end
		if input.KeyCode == Enum.KeyCode.LeftAlt then freeCursor = true return end
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = true pendingShot = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then aiming = true
		elseif input.KeyCode == Enum.KeyCode.R then requestReload() end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt then freeCursor = false end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then aiming = false end
	end)
	if touchOnly then
		UI.onHold(touchButtons.fire, function()
			firing, pendingShot = true, true
		end, function()
			firing = false
		end, function(d)
			dragX += d.X
			dragY += d.Y
		end)
		touchButtons.aim.Activated:Connect(function() aiming = not aiming end)
		touchButtons.reload.Activated:Connect(requestReload)
		-- коснулся мира (не кнопок) — выстрел туда
		UserInputService.TouchTapInWorld:Connect(function(pos, processed)
			local cam = workspace.CurrentCamera
			if processed or not tool or not cam then return end
			tapRay = cam:ScreenPointToRay(pos.X, pos.Y)
			pendingShot = true
		end)
	end
	local hitN = 0
	HitMarker.OnClientEvent:Connect(function(head)
		hitImg.Image = head and UI.Icons.HitKill or UI.Icons.Hit
		hit.Visible = true
		hitScale.Scale = 1.5
		TweenService:Create(hitScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Scale = 1}):Play()
		SoundFx.play("HitMarker")
		hitN += 1
		local my = hitN
		task.delay(head and 0.25 or 0.16, function()
			if hitN == my then hit.Visible = false end
		end)
	end)

	------------------------------------------------------------------ кадр
	RunService.RenderStepped:Connect(function(dt)
		local t, h = currentTool()
		if t ~= tool then
			if tool then deactivate() end
			if t then activate(t, h) end
		end
		local cam = workspace.CurrentCamera
		if not tool then
			-- плавно вернуть поле зрения после снятия оружия
			if cam and math.abs(fovNow - BASE_FOV) > 0.05 then
				fovNow += (BASE_FOV - fovNow) * math.min(1, dt * 12)
				cam.FieldOfView = fovNow
			end
			return
		end
		-- прицеливание: зум и плечо
		local wantFov = aiming and gun.AimFOV or BASE_FOV
		fovNow += (wantFov - fovNow) * math.min(1, dt * 12)
		if cam then cam.FieldOfView = fovNow end
		-- камера без сдвига к плечу: свободное третье лицо или первое (прицеливание от первого лица рисует GunViewmodel)
		firstPerson = cam ~= nil and (cam.CFrame.Position - cam.Focus.Position).Magnitude < 1
		gunState.firstPerson = firstPerson
		offsetNow = offsetNow:Lerp(Vector3.zero, math.min(1, dt * 12))
		hum.CameraOffset = offsetNow
		local mouseMode = not touchOnly and not firstPerson
		-- ПК: от первого лица курсор в центре (Alt освобождает), от третьего — свободен и сам стал прицелом.
		-- В третьем лице MouseBehavior трогаем только при переключении (правая кнопка крутит камеру сама).
		if not touchOnly then
			if firstPerson then
				UserInputService.MouseBehavior = freeCursor and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
			elseif wasFirstPerson ~= false then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			UserInputService.MouseIconEnabled = freeCursor
		end
		wasFirstPerson = firstPerson
		-- прицел идёт за курсором; точка под ним — для поворота персонажа и наклона оружия
		local char = hum.Parent
		if mouseMode and cam then
			local m = UserInputService:GetMouseLocation()
			cross.Position = UDim2.fromOffset(m.X, m.Y)
			hit.Position = cross.Position
			local r = cam:ViewportPointToRay(m.X, m.Y)
			local fx = workspace:FindFirstChild("ClientFx")
			rayParams.FilterDescendantsInstances = fx and {char, fx} or {char}
			local res = workspace:Raycast(r.Origin, r.Direction * 1000, rayParams)
			aimPos = res and res.Position or r.Origin + r.Direction * 1000
		else
			cross.Position = UDim2.fromScale(0.5, 0.5)
			hit.Position = cross.Position
		end
		-- куда смотрит персонаж: от первого лица — по камере; от третьего — к цели, пока стреляет или целится,
		-- а в остальное время ходит как обычно (лицом по ходу)
		local look
		local busy = firing or aiming or os.clock() - lastShot < 0.8
		if firstPerson and cam then
			look = cam.CFrame.LookVector
		elseif busy and aimPos and hrp and (mouseMode or not aiming) then
			look = aimPos - hrp.Position
		elseif busy and cam then
			look = cam.CFrame.LookVector
		end
		local flat = look and Vector3.new(look.X, 0, look.Z)
		if hrp and flat and flat.Magnitude > 0.01 then
			hum.AutoRotate = false
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
		else
			hum.AutoRotate = true
		end
		-- наклон оружия в руках (GunPose): от третьего лица — к точке прицела
		local head = char:FindFirstChild("Head")
		if not firstPerson and busy and aimPos and head and (aimPos - head.Position).Magnitude > 1 then
			gunState.aimPitch = math.asin(math.clamp((aimPos - head.Position).Unit.Y, -1, 1))
		elseif not firstPerson then
			gunState.aimPitch = 0
		else
			gunState.aimPitch = nil
		end
		-- разогрев остывает
		bloom = math.max(0, bloom - dt * BLOOM_DECAY)
		gunState.aiming = aiming
		local ammo = tool:GetAttribute("Ammo") or 0
		local reloading = tool:GetAttribute("Reloading")
		-- фаза перезарядки 0..1 — для анимации (GunViewmodel)
		local nowT = os.clock()
		if reloading and not wasReloading then reloadStart = nowT end
		wasReloading = reloading == true
		gunState.reload = reloading and math.clamp((nowT - reloadStart) / gun.Reload, 0, 1) or nil
		-- магазин пуст — перезаряжаемся сами (после выстрела РПГ не надо жать R)
		if ammo <= 0 and not reloading and nowT - lastShot > 0.35 then requestReload() end
		-- прицел расходится по разбросу
		local spread = (aiming and gun.Aim or gun.Hip) + bloom
		if hum.MoveDirection.Magnitude > 0.1 then spread *= aiming and 1.3 or 1.5 end
		if hum.FloorMaterial == Enum.Material.Air then spread *= 2 end
		local vh = cam and cam.ViewportSize.Y or 720
		local gap = 4 + math.tan(math.rad(spread)) / math.tan(math.rad(fovNow / 2)) * vh / 2
		-- мелкий: 16 px в покое, растёт с разбросом, но не больше 44
		local d = math.clamp(8 + gap * 1.2, 16, 44)
		crossImg.Size = UDim2.fromOffset(d, d)
		reloadImg.Visible = reloading == true
		if reloading then
			reloadImg.Position = UDim2.fromOffset(0, d / 2 + 14)
			reloadImg.Rotation = (nowT * 360) % 360
		end
		-- патроны
		if gun.Reserve then
			ammoLbl.Text = ("%d / %d"):format(ammo, tool:GetAttribute("Reserve") or 0)
		else
			ammoLbl.Text = ("%d / %d"):format(ammo, gun.Mag)
		end
		ammoLbl.TextColor3 = ammo == 0 and Color3.fromRGB(255, 90, 80) or Color3.new(1, 1, 1)
		hintLbl.Text = reloading and "RELOADING..." or (touchOnly and "" or (firstPerson and "RMB aim · R reload · Alt cursor" or "Click — fire · RMB aim · R reload"))
	end)

	-- отдача и огонь — после стандартной камеры. Камера Roblox берёт направление из текущего cam.CFrame,
	-- поэтому поворот здесь сохраняется: применяем только приращение за кадр, иначе отдача накапливается.
	RunService:BindToRenderStep("GunRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		if not tool or not gun or not cam then return end
		-- от третьего лица камеру отдачей не дёргаем (цель — курсор или касание), остаётся разброс
		if not firstPerson then pendP, pendY, climb, shake = 0, 0, 0, 0 end
		local f = math.min(1, dt * RECOIL_SNAP)
		local dP, dY = pendP * f, pendY * f
		pendP -= dP
		pendY -= dY
		climb += dP
		-- игрок сам тянет мышь вниз — эту часть подъёма возвращать уже не нужно
		if not touchOnly and climb > 0 then
			local md = UserInputService:GetMouseDelta()
			if md.Y > 0 then
				climb = math.max(0, climb - md.Y * MOUSE_DEG * UserSettings().GameSettings.MouseSensitivity)
			end
		end
		-- после очереди ствол частично возвращается
		if os.clock() - lastShot > RECOVER_DELAY and climb > 0.005 then
			local r = climb * math.min(1, dt * RECOVER_RATE)
			climb -= r
			dP -= r * RECOVER_SHARE
		end
		-- палец движется по кнопке огня — ведём прицел, как в мобильных шутерах
		if dragX ~= 0 or dragY ~= 0 then
			local s = TOUCH_DEG * (aiming and 0.6 or 1)
			local cf = cam.CFrame
			local look = cf.LookVector
			local pitch = math.clamp(math.asin(look.Y) - math.rad(dragY * s), math.rad(-80), math.rad(80))
			local yaw = math.atan2(-look.X, -look.Z) - math.rad(dragX * s)
			cam.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(pitch, yaw, 0)
			dragX, dragY = 0, 0
		end
		shake -= shake * math.min(1, dt * 16)
		local roll = math.sin(os.clock() * 70) * shake * 0.35
		if math.abs(dP) > 1e-4 or math.abs(dY) > 1e-4 or shake > 0.01 then
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(dP), math.rad(dY), math.rad(roll))
		end
		-- огонь: луч идёт ровно туда, куда смотрит прицел в этом кадре
		local now = os.clock()
		local ammo = tool:GetAttribute("Ammo") or 0
		-- стрелять — только от первого лица (пока камера не доехала до головы — ждём)
		if (firing or pendingShot) and firstPerson and not tool:GetAttribute("Reloading") and now >= nextShot and not freeCursor then
			pendingShot = false
			if ammo > 0 then
				nextShot = now + 60 / gun.RPM
				shoot()
				if gun.Rocket then firing = false end -- РПГ — по одному выстрелу на нажатие
			else
				requestReload()
				nextShot = now + 0.4
			end
		end
		if not firing and pendingShot and tool:GetAttribute("Reloading") then pendingShot = false end
	end)

	return {}
end
