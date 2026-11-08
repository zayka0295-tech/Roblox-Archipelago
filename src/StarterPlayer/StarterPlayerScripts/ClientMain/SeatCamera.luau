-- Места внутри корпуса (подлодка, штурвал катера, мостик линкора): камера держится снаружи (CamMinZoom).
-- Мостик линкора: ещё и CamLift — иначе вблизи камера уходила сквозь корпус под воду.
-- Башни линкора: первое лицо (FirstPerson), высоту камеры задаёт TurretUI.
-- Подлодка: штурвал внутри корпуса, а корма дальше CamMinZoom — вдоль лодки камера оказывалась в корме.
-- Поднимаем точку обзора над корпусом (CameraOffset), камера смотрит поверх.
local RunService = game:GetService("RunService")

local SUB_LIFT = 14

return function(ctx)
	local player = ctx.player
	local saved -- исходная мин. дистанция камеры
	local savedMode -- исходный режим камеры до первого лица
	local liftHum -- гуманоид, которому подняли камеру (подлодка)

	RunService.RenderStepped:Connect(function()
		if ctx.gunView then return end -- вид от орудия: камерой распоряжается TurretUI
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if seat and seat:GetAttribute("FirstPerson") then
			if not savedMode then savedMode = player.CameraMode end
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		elseif savedMode then
			-- сел с оружием в руках: в этом кадре SeatCamera успевает раньше GunClient и запоминает его
			-- LockFirstPerson — встав, игрок остался бы в первом лице без оружия. Обычный режим камеры
			-- первым лицом не бывает (так же считает GunClient.restoreCamera)
			player.CameraMode = savedMode == Enum.CameraMode.LockFirstPerson and Enum.CameraMode.Classic or savedMode
			savedMode = nil
		end
		local model = seat and seat.Name == "HelmSeat" and seat:FindFirstAncestorOfClass("Model")
		-- подъём точки обзора: подлодка или атрибут CamLift на месте (грузовой самолёт)
		local lift = (model and model:GetAttribute("ShipType") == "Submarine" and SUB_LIFT) or (seat and seat:GetAttribute("CamLift"))
		if lift then
			liftHum = hum
			hum.CameraOffset = Vector3.new(0, lift, 0)
		elseif liftHum then
			if liftHum.Parent then liftHum.CameraOffset = Vector3.zero end
			liftHum = nil
		end
		local want = seat and seat:GetAttribute("CamMinZoom")
		if want then
			-- GunClient мог только что временно поднять мин. зум (убрал оружие, садясь) — берём настоящий
			if not saved then saved = ctx.origMinZoom or player.CameraMinZoomDistance end
			if player.CameraMinZoomDistance ~= want then
				player.CameraMinZoomDistance = math.min(want, player.CameraMaxZoomDistance)
			end
		elseif saved then
			player.CameraMinZoomDistance = saved
			saved = nil
		end
	end)
	return {}
end
