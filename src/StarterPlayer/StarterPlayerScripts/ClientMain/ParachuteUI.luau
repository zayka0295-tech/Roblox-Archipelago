-- Десант (CargoDropService): в кресле грузового самолёта — большая кнопка JUMP (или обычный прыжок);
-- после прыжка — подсказка по атрибуту игрока Parachute ("fall" / "open").
-- Персонажем управляет клиент, поэтому на выходе из самолёта скорость самолёта гасим здесь:
-- чуть вперёд и вниз (иначе летел бы вбок на скорости самолёта, и античит вернул бы назад).
-- Из боевого самолёта с парашютом военного базара (бит в атрибуте Items) — катапульта: подбрасывает вверх
-- (EJECT_UP) с облачком дыма, купол раскрывается, только когда пошли вниз (не раньше EJECT_HOLD сек.).
local RunService = game:GetService("RunService")

return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local player = ctx.player
	local gui = UI.screen("ParachuteUI", 16)
	local box = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96), Size = UDim2.fromOffset(420, 110), BackgroundTransparency = 1, Visible = false}, gui)
	UI.scale(box, 0.7)
	local jumpBtn = UI.button(box, "JUMP!", T.Bad, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(230, 64), TextSize = 32})
	UI.stroke(jumpBtn, Color3.new(1, 1, 1), 2)
	local hint = UI.label(box, "Bail out over the spot you want — the parachute opens by itself", {
		Size = UDim2.new(1, 0, 0, 36), TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3,
	})
	local status = UI.label(gui, "", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = UDim2.fromOffset(520, 28),
		TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, TextColor3 = T.Gold, Visible = false,
	})

	local function humanoid()
		local char = player.Character
		return char and char:FindFirstChildOfClass("Humanoid"), char and char:FindFirstChild("HumanoidRootPart")
	end
	jumpBtn.Activated:Connect(function()
		local hum = humanoid()
		-- Jump из скрипта перезаписывает модуль управления — встаём из кресла напрямую
		if hum and hum.SeatPart and hum.SeatPart:GetAttribute("CargoSeat") then hum.Sit = false end
	end)

	-- в свободном падении сами следим за высотой и просим сервер раскрыть купол (сервер видит нас с задержкой)
	local ChuteOpen = ctx.Remotes:WaitForChild("ChuteOpen")
	local OPEN_AT = ctx.Config.ParachuteDrop.OpenHeight
	local FALL_SPEED = ctx.Config.ParachuteDrop.FallSpeed or 170
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.IgnoreWater = false
	local asked = 0

	-- витрины над донатными плитами лобби (Map.Lobby*/Pads/*.DisplayChute / DisplayShip): медленно крутятся и покачиваются (только у себя).
	-- Исходная точка — атрибут Origin (а не GetPivot: до подгрузки модель пустая, и витрина уехала бы в 0,0,0)
	-- список витрин ищем раз в 2 с (стриминг), а не обходим карту каждый кадр
	local shows, showsAt = {}, -math.huge
	local function findShows()
		table.clear(shows)
		local map = workspace:FindFirstChild("Map")
		if not map then return end
		for _, lobby in ipairs(map:GetChildren()) do
			local pads = lobby:GetAttribute("LobbyTeam") and lobby:FindFirstChild("Pads")
			for _, m in ipairs(pads and pads:GetChildren() or {}) do
				local show = m:FindFirstChild("DisplayChute") or m:FindFirstChild("DisplayShip")
				if show then table.insert(shows, show) end
			end
		end
	end
	local function animateShows(t)
		if t - showsAt > 2 then
			showsAt = t
			findShows()
		end
		for _, show in ipairs(shows) do
			local p = show:GetAttribute("Origin")
			if p and show.Parent and show.PrimaryPart then
				show:PivotTo(CFrame.new(p.X, p.Y + math.sin(t * 1.3) * 0.7, p.Z) * CFrame.Angles(0, t * 0.5, math.sin(t * 0.9) * 0.08))
			end
		end
	end

	local chuteBit = 0
	for _, it in ipairs(ctx.Config.Bazaar.Items) do
		if it.Id == "Parachute" then chuteBit = it.Bit end
	end
	-- кресло самолёта (пилот / стрелок), из которого прыгаем с парашютом базара
	local function planeSeat(seat)
		if bit32.band(player:GetAttribute("Items") or 0, chuteBit) == 0 then return false end
		local m = seat:FindFirstAncestorWhichIsA("Model")
		while m and not m:GetAttribute("IsPlane") do m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model") end
		return m ~= nil
	end

	local EJECT_UP, EJECT_HOLD = 95, 0.9 -- скорость вверх (≈ +23 студа), раньше купол не раскрываем
	local ejectT = 0
	local function groundBelow(hrp, len)
		local ignore = {player.Character}
		local drops = workspace:FindFirstChild("CargoDrops")
		local planes = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Planes") -- свой самолёт ещё под ногами
		if drops then table.insert(ignore, drops) end
		if planes then table.insert(ignore, planes) end
		ray.FilterDescendantsInstances = ignore
		return workspace:Raycast(hrp.Position, Vector3.new(0, -len, 0), ray)
	end
	-- облачко дыма от катапульты (только у себя)
	local function puff(pos)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency = true, false, false, false, 1
		p.Size = Vector3.one
		p.Position = pos
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(225, 225, 225))
		e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7)})
		e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)})
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(6, 14)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 0
		e.Parent = p
		p.Parent = workspace
		e:Emit(18)
		game:GetService("Debris"):AddItem(p, 2)
	end

	local inCargo, fromPlane, look = false, false, Vector3.zero
	RunService.RenderStepped:Connect(function()
		local hum, hrp = humanoid()
		local seat = hum and hum.SeatPart
		local cargo = seat ~= nil and seat:GetAttribute("CargoSeat") == true
		local now = cargo or (seat ~= nil and planeSeat(seat))
		if now then
			local l = seat.CFrame.LookVector
			look = Vector3.new(l.X, 0, l.Z)
			fromPlane = not cargo
		elseif inCargo and hrp then
			-- только что выпрыгнул
			local fwd = look.Magnitude > 0 and look.Unit or Vector3.zero
			if fromPlane and groundBelow(hrp, ctx.Config.Bazaar.BailMinHeight + 5) == nil then
				-- катапульта из боевого самолёта
				hrp.AssemblyLinearVelocity = fwd * 20 + Vector3.new(0, EJECT_UP, 0)
				ejectT = os.clock()
				puff(hrp.Position - Vector3.new(0, 2, 0))
			else
				hrp.AssemblyLinearVelocity = fwd * 14 + Vector3.new(0, -6, 0)
			end
			-- в самолёте камера была далеко (CamMinZoom кресла) — после прыжка подтягиваем её к игроку
			-- (с задержкой: сначала SeatCamera должен вернуть минимум, иначе он держит камеру далеко)
			task.delay(0.1, function()
				local maxZoom = player.CameraMaxZoomDistance
				if maxZoom <= 28 then return end
				player.CameraMaxZoomDistance = 28
				task.wait(0.2)
				if player.CameraMaxZoomDistance == 28 then player.CameraMaxZoomDistance = maxZoom end
			end)
		end
		inCargo = now
		box.Visible = cargo
		if player:GetAttribute("State") ~= "Deployed" then animateShows(os.clock()) end
		local chute = player:GetAttribute("Parachute")
		-- сопротивление воздуха: быстрее FALL_SPEED не падаем (иначе с высоты купол раскрывался бы слишком низко)
		if chute == "fall" and hrp then
			local v = hrp.AssemblyLinearVelocity
			if v.Y < -FALL_SPEED then hrp.AssemblyLinearVelocity = Vector3.new(v.X, -FALL_SPEED, v.Z) end
		end
		-- после катапульты купол — только когда полетели вниз
		local ejecting = os.clock() - ejectT < 6 and (os.clock() - ejectT < EJECT_HOLD or (hrp and hrp.AssemblyLinearVelocity.Y > 0))
		if chute == "fall" and hrp and not ejecting and os.clock() - asked > 0.5 then
			local hit = groundBelow(hrp, OPEN_AT)
			if hit then
				asked = os.clock()
				ChuteOpen:FireServer()
			end
		end
		if chute == "fall" then
			status.Text = ejecting and "Ejected!" or "Free fall! The parachute opens automatically"
		elseif chute == "open" then
			status.Text = UI.touchOnly and "Parachute open · steer with the joystick" or "Parachute open · steer with WASD"
		end
		status.Visible = chute ~= nil
	end)
	return {}
end
