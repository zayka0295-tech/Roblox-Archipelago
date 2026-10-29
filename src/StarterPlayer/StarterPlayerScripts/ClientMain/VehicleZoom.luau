-- Прицеливание (зум) в самолёте и у штурвала кораблей без своей пушки (подлодка; у линкора и авианосца нет).
-- Турели и штурвал катера (с носовой пушкой) зумит TurretUI. ПК — пока зажата ПКМ (или Z — переключатель; в самолёте Z — бомбовый прицел PlaneClient),
-- телефон — круглая кнопка ZOOM. В зуме у штурвала — перекрестие в центре (у самолёта свои метки).
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BASE_FOV = 70
local FOV = {plane = 38, helm = 28}

return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local player = ctx.player
	local touchOnly = UI.touchOnly
	local gui = UI.screen("VehicleZoom", 14)
	local ZOOM_ON = Color3.fromRGB(70, 140, 220)
	local zoomBtn = touchOnly and UI.roundButton(gui, "zoomHigh", "ZOOM") -- над GAS+ / UP or nil
	if zoomBtn then zoomBtn.Visible = false end

	local cross = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, Visible = false}, gui)
	UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = T.Text, BorderSizePixel = 0}, cross)
	UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = T.Text, BorderSizePixel = 0}, cross)

	local toggled = false
	local active = false -- мы сейчас управляем полем зрения
	local fovNow = BASE_FOV

	-- самолёт или штурвал без пушки — вид зума, иначе nil
	local function kind()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.Health > 0 and hum.SeatPart
		if not seat then return nil end
		if seat:GetAttribute("PlaneSeat") then return "plane" end -- как в PlaneClient
		if seat:GetAttribute("Helm") and not seat:GetAttribute("AimTurret") then
			-- у штурвала линкора и авианосца зум бессмысленный: стреляют башни
			local model = seat:FindFirstAncestorOfClass("Model")
			if model and (model:GetAttribute("ShipType") == "Battleship" or model:GetAttribute("IsCarrier")) then return nil end
			return "helm"
		end
		return nil
	end

	local function setToggled(on)
		toggled = on
		if zoomBtn then zoomBtn.BackgroundColor3 = on and ZOOM_ON or zoomBtn:GetAttribute("BaseColor") end
	end
	if zoomBtn then zoomBtn.Activated:Connect(function() setToggled(not toggled) end) end
	UserInputService.InputBegan:Connect(function(input, processed)
		local k = not processed and input.KeyCode == Enum.KeyCode.Z and kind()
		if k and k ~= "plane" then setToggled(not toggled) end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local k = kind()
		local cam = workspace.CurrentCamera
		-- бомбовый прицел сам управляет полем зрения — зум на это время выключен
		local pc = ctx.screens.PlaneClient
		if k == "plane" and pc and pc.sightOn and pc.sightOn() then
			if zoomBtn then zoomBtn.Visible = false end
			setToggled(false)
			fovNow = BASE_FOV
			if not touchOnly then UserInputService.MouseDeltaSensitivity = 1 end
			return
		end
		if zoomBtn then zoomBtn.Visible = k ~= nil end
		if not k then
			cross.Visible = false
			if active then
				active = false
				setToggled(false)
				fovNow = BASE_FOV
				if cam then cam.FieldOfView = BASE_FOV end
				UserInputService.MouseDeltaSensitivity = 1
			end
			return
		end
		active = true
		local rmb = not touchOnly and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			and not UserInputService:GetFocusedTextBox()
		local zoomNow = toggled or rmb
		cross.Visible = zoomNow and k == "helm"
		local want = zoomNow and FOV[k] or BASE_FOV
		if cam and math.abs(fovNow - want) > 0.05 then
			fovNow += (want - fovNow) * math.min(1, dt * 12)
			cam.FieldOfView = fovNow
		end
		-- ПК: в зуме мышь ведёт камеру медленнее, пропорционально полю зрения
		if not touchOnly then UserInputService.MouseDeltaSensitivity = math.clamp(fovNow / BASE_FOV, 0.3, 1) end
	end)
	return {}
end
