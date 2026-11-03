-- Панель капитана: появляется, когда игрок сидит у штурвала.
-- Ввод: клавиатура, геймпад, на телефоне — джойстик техники слева (вперёд/назад — ход, вбок — руль).
-- Везде — две маленькие плашки у нижнего края (ход / оружие). На ПК клавиши — панель UI.controls слева внизу;
-- на телефоне — круглые кнопки вокруг прыжка
-- (оружие, погружение); выход из рубки — сам прыжок, стоп — джойстик в центр.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local Ship = ctx.Remotes:WaitForChild("ShipControl")
	local Weapon = ctx.Remotes:WaitForChild("ShipWeapon")
	local PERISCOPE = (Config.Ships.Submarine and Config.Ships.Submarine.PeriscopeDepth) or 8
	local touchOnly = UI.touchOnly
	local stick = touchOnly and UI.joystick() or nil

	local gui = UI.screen("ShipControlUI", 15)
	-- две маленькие плашки у нижнего края по бокам от слота оружия (и на ПК, и на телефоне):
	-- слева ход, справа оружие корабля. Верх экрана и море остаются свободными
	local compact = true
	local PANEL_W, PANEL_H = compact and 190 or 500, compact and 34 or 128
	local SLOT_GAP, BOTTOM = 32, -6 -- полширины слота рюкзака Roblox + зазор; отступ от низа
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = compact and Vector2.new(1, 1) or Vector2.new(0.5, 1),
		Position = compact and UDim2.new(0.5, -SLOT_GAP, 1, BOTTOM) or UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H), Visible = false,
	})
	if compact then panel.BackgroundTransparency = 0.35 end
	UI.scale(panel, compact and 0.75 or nil)
	UI.padding(panel, compact and 6 or 14)
	local titleLbl = UI.label(panel, "BRIDGE", {TextSize = 15, TextColor3 = T.Accent, Visible = not compact})
	local speedLbl = UI.label(panel, "Speed: 0", compact
		and {Position = UDim2.fromOffset(0, 0), TextSize = 14, Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center}
		or {Position = UDim2.fromOffset(0, 24), TextSize = 22, Size = UDim2.new(1, 0, 0, 26)})
	local barBg = UI.new("Frame", {Position = UDim2.fromOffset(0, compact and 18 or 56), Size = UDim2.new(1, 0, 0, compact and 4 or 8), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, panel)
	UI.corner(barBg, 4)
	local fill = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Good, BorderSizePixel = 0}, barBg)
	UI.corner(fill, 4)
	local BASE_HINT = "W/S — throttle · A/D — steer · X — stop · RMB — zoom · Space — leave"
	local hintLbl = UI.label(panel, BASE_HINT, {
		Position = UDim2.fromOffset(0, 70), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Visible = not compact,
	})

	-- оружие корабля: торпеды подлодки / глубинные бомбы катера (строка состояния над панелью)
	local weaponPanel = UI.panel(gui, {Name = "WeaponPanel",
		AnchorPoint = compact and Vector2.new(0, 1) or Vector2.new(0.5, 1),
		Position = compact and UDim2.new(0.5, SLOT_GAP, 1, BOTTOM) or UDim2.new(0.5, 0, 1, -(PANEL_H + 26)),
		Size = UDim2.fromOffset(PANEL_W, compact and 34 or 48), Visible = false})
	if compact then weaponPanel.BackgroundTransparency = 0.35 end
	UI.scale(weaponPanel, compact and 0.75 or nil)
	UI.padding(weaponPanel, compact and 3 or 6)
	local wInfo = UI.label(weaponPanel, "", {Size = UDim2.new(1, 0, 1, 0), TextSize = compact and 12 or 14, RichText = true, TextWrapped = true,
		TextXAlignment = compact and Enum.TextXAlignment.Center or nil})

	-- сенсорные кнопки: торпеда — большая слева от прыжка, всплытие/погружение — рядом;
	-- у катера большая кнопка — огонь носовой пушки (TurretUI), бомба — рядом
	local diveHeld = {down = false, up = false}
	local torpBtn, chargeBtn, surfaceBtn, diveBtn
	local weaponKind
	local stopFlag = false
	local function fireWeapon()
		local b = weaponKind == "torpedo" and torpBtn or chargeBtn
		if weaponKind and (not b or b:GetAttribute("Enabled") ~= false) then Weapon:FireServer(weaponKind) end
	end
	if touchOnly then
		torpBtn = UI.roundButton(gui, "main", "TORPEDO", T.Bad)
		chargeBtn = UI.roundButton(gui, "a1", "BOMB", T.Bad)
		UI.roundIcon(chargeBtn, "Charge") -- глубинная бомба, а не авиабомба
		surfaceBtn = UI.roundButton(gui, "a2", "▲\nUP")
		diveBtn = UI.roundButton(gui, "a1", "▼\nDIVE")
		UI.onHold(surfaceBtn, function() diveHeld.up = true end, function() diveHeld.up = false end)
		UI.onHold(diveBtn, function() diveHeld.down = true end, function() diveHeld.down = false end)
		torpBtn.Activated:Connect(fireWeapon)
		chargeBtn.Activated:Connect(fireWeapon)
	end
	local function showTouch(seated, kind, canDive)
		if not touchOnly then return end
		torpBtn.Visible = seated and kind == "torpedo"
		chargeBtn.Visible = seated and kind == "depthcharge"
		surfaceBtn.Visible, diveBtn.Visible = seated and canDive, seated and canDive
		stick.request("ship", seated)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not weaponKind then return end
		if weaponKind == "torpedo" and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.T) then
			fireWeapon()
		elseif weaponKind == "depthcharge" and input.KeyCode == Enum.KeyCode.G then
			fireWeapon()
		end
	end)

	local function helm()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if seat and seat:GetAttribute("Helm") then return seat, hum end
		return nil
	end

	local function key(...)
		for _, k in ipairs({...}) do
			if UserInputService:IsKeyDown(k) then return true end
		end
		return false
	end

	local function readInput()
		local throttle, steer = 0, 0
		if not UserInputService:GetFocusedTextBox() then
			if key(Enum.KeyCode.W, Enum.KeyCode.Up) then throttle += 1 end
			if key(Enum.KeyCode.S, Enum.KeyCode.Down) then throttle -= 1 end
			if key(Enum.KeyCode.D, Enum.KeyCode.Right) then steer += 1 end
			if key(Enum.KeyCode.A, Enum.KeyCode.Left) then steer -= 1 end
			if key(Enum.KeyCode.X) then stopFlag = true end
		end
		-- телефон: джойстик техники (вперёд — ход, вбок — руль)
		if stick then
			local v = stick.vector()
			if math.abs(v.Y) > 0.15 then throttle += v.Y end
			if math.abs(v.X) > 0.15 then steer += v.X end
		end
		-- геймпад: левый стик
		if UserInputService.GamepadEnabled then
			for _, input in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
				if input.KeyCode == Enum.KeyCode.Thumbstick1 then
					local v = input.Position
					if math.abs(v.Y) > 0.2 then throttle += v.Y end
					if math.abs(v.X) > 0.2 then steer += v.X end
				end
			end
		end
		return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1)
	end

	local sentT, sentS, sentV, timer = 0, 0, 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local seat = helm()
		panel.Visible = seat ~= nil
		if not seat then
			UI.controls("ship", nil)
			showTouch(false)
			weaponPanel.Visible = false
			weaponKind = nil
			sentT, sentS = 0, 0
			diveHeld.down, diveHeld.up = false, false
			return
		end

		local throttle, steer = readInput()
		local model = seat:FindFirstAncestorOfClass("Model")
		local canDive = model and model:GetAttribute("CanDive") == true
		local stype = model and model:GetAttribute("ShipType")
		weaponKind = stype == "Submarine" and "torpedo" or (stype == "Gunboat" and "depthcharge" or nil)
		weaponPanel.Visible = weaponKind ~= nil
		if touchOnly then
			showTouch(true, weaponKind, canDive)
		else
			local extra = canDive and " · Q/F — dive/surface" or ""
			if weaponKind == "torpedo" then extra ..= " · LMB/T — torpedo" elseif weaponKind == "depthcharge" then extra ..= " · G — depth charge · Wheel in — gun view" end
			local noZoom = stype == "Battleship" or (model and model:GetAttribute("IsCarrier"))
			local base = noZoom and BASE_HINT:gsub(" · RMB — zoom", "") or BASE_HINT -- у штурвала линкора и авианосца зума нет
			hintLbl.Text = base .. extra
			local rows = {
				{"W / S", "Ahead / astern"},
				{"A / D", "Steer left / right"},
				{"X", "Full stop"},
			}
			if canDive then table.insert(rows, {"Q / F", "Dive / surface"}) end
			if weaponKind == "torpedo" then
				table.insert(rows, {"LMB / T", "Fire torpedo"})
			elseif weaponKind == "depthcharge" then
				table.insert(rows, {"G", "Drop depth charge"})
				table.insert(rows, {"Wheel in", "Bow gun view"})
			end
			if not noZoom then table.insert(rows, {"RMB", "Zoom"}) end
			table.insert(rows, {"Space", "Leave the helm"})
			UI.controls("ship", rows)
		end
		if weaponKind == "torpedo" then
			local torps = model:GetAttribute("Torpedoes") or 2
			local reloadAt = model:GetAttribute("TorpedoReloadAt") or 0
			local depth = model:GetAttribute("Depth") or 0
			local air = model:GetAttribute("Air") or 100
			local scope = depth <= PERISCOPE
			local tTxt = torps > 0 and ("Torpedoes %d/2"):format(torps) or ("Reloading %d s"):format(math.max(0, math.ceil(reloadAt - workspace:GetServerTimeNow())))
			local airTxt = air < 25 and ('<font color="#eb554b">Air %d%%</font>'):format(air) or ("Air %d%%"):format(air)
			if compact then
				local tShort = torps > 0 and ("Torp %d/2"):format(torps) or ("Reload %ds"):format(math.max(0, math.ceil(reloadAt - workspace:GetServerTimeNow())))
				wInfo.Text = ("%s · %s\n%s"):format(airTxt, tShort, scope and '<font color="#50c86e">Ready to fire</font>' or "Too deep")
			else
				wInfo.Text = ("%s · %s\n%s"):format(airTxt, tTxt, scope and '<font color="#50c86e">Periscope depth — ready to fire</font>' or "Too deep to fire")
			end
			if torpBtn then UI.setEnabled(torpBtn, torps > 0 and scope, T.Bad) end
		elseif weaponKind == "depthcharge" then
			local n = model:GetAttribute("DepthCharges") or 3
			wInfo.Text = compact and ("Depth charges %d/3"):format(n) or ("Depth charges %d/3\ndropped astern — anti-submarine"):format(n)
			if chargeBtn then UI.setEnabled(chargeBtn, n > 0, T.Bad) end
		end
		local vertical = 0
		if canDive then
			local typingNow = UserInputService:GetFocusedTextBox() ~= nil
			if diveHeld.down or (not typingNow and UserInputService:IsKeyDown(Enum.KeyCode.Q)) then vertical -= 1 end
			if diveHeld.up or (not typingNow and UserInputService:IsKeyDown(Enum.KeyCode.F)) then vertical += 1 end
		end
		titleLbl.Text = "BRIDGE · " .. (model and model:GetAttribute("DisplayName") or "Carrier")
		timer += dt
		local changed = math.abs(throttle - sentT) > 0.1 or math.abs(steer - sentS) > 0.1 or vertical ~= sentV
		if stopFlag or (timer >= 0.05 and (changed or timer >= 0.4)) then
			timer = 0
			sentT, sentS, sentV = throttle, steer, vertical
			Ship:FireServer(throttle, steer, stopFlag, vertical)
			stopFlag = false
		end

		local speed = model and model:GetAttribute("Speed") or 0
		local set = model and model:GetAttribute("Setpoint") or 0
		local max = model and model:GetAttribute("MaxSpeed") or Config.Carrier.MaxSpeed
		local dir = set > 0 and "ahead" or (set < 0 and "astern" or "stop")
		local depthTxt = canDive and (" · depth %d"):format(model:GetAttribute("Depth") or 0) or ""
		if compact then
			local dTxt = canDive and (" · %dm"):format(model:GetAttribute("Depth") or 0) or ""
			speedLbl.Text = ("%d/%d · %s%s"):format(math.abs(speed), max, dir == "stop" and "stop" or (dir .. " " .. math.abs(set)), dTxt)
		else
			speedLbl.Text = ("Speed: %d / %d · set: %s %d%s"):format(math.abs(speed), max, dir, math.abs(set), depthTxt)
		end
		local rev = model and model:GetAttribute("MaxReverseSpeed") or Config.Carrier.MaxReverseSpeed
		fill.Size = UDim2.fromScale(math.clamp(math.abs(set) / (set < 0 and rev or max), 0, 1), 1)
		fill.BackgroundColor3 = set < 0 and T.Bad or T.Good
	end)

	return {}
end
