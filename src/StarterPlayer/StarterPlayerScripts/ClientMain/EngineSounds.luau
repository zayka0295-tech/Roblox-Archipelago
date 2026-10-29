-- Гул двигателей техники: петля на корневой детали, громкость и тон растут со скоростью.
-- Скорость считаем по смещению модели (корабли двигает сервер, скорость деталей тут ненадёжна).
local RunService = game:GetService("RunService")
local SoundFx = require(script.Parent:WaitForChild("SoundFx"))

-- звук и скорость, на которой тон и громкость максимальны (см. Config.Ships / Carrier / Planes)
local KIND = {
	Plane      = {sound = "EnginePlane", speed = 150},
	Carrier    = {sound = "EngineCarrier", speed = 40},
	Battleship = {sound = "EngineBattleship", speed = 30},
	Gunboat    = {sound = "EngineGunboat", speed = 55},
	Submarine  = {sound = "EngineSubmarine", speed = 26},
	Cargo      = {sound = "EngineCargo", speed = 30},
	-- грузовой самолёт десанта (workspace.CargoDrops): гул + второй слой — свист турбин
	CargoPlane = {sound = "EngineCargoPlane", layer = "EngineCargoPlaneWhine", speed = 90},
}
local STEP = 0.1

return function(ctx)
	local tracked = {} -- [модель] = {sound, e, kind, root, last, vol, pitch}

	local function kindOf(model, folderName)
		if folderName == "Planes" then return "Plane" end
		if folderName == "Carriers" then return "Carrier" end
		if folderName == "CargoDrops" then return "CargoPlane" end
		return model:GetAttribute("ShipType")
	end

	local function add(model, folderName)
		if tracked[model] or not model:IsA("Model") then return end
		local kind = KIND[kindOf(model, folderName)]
		local root = model.PrimaryPart or model:FindFirstChild("Root") or model:FindFirstChild("Pivot")
		if not kind or not root then return end
		local s, e = SoundFx.loop(kind.sound, root)
		if not s then return end
		local t = {sound = s, e = e, kind = kind, root = root, last = root.Position, vol = 0, pitch = e.pitch[1]}
		if kind.layer then t.layer, t.le = SoundFx.loop(kind.layer, root) end
		tracked[model] = t
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				local tr = tracked[model]
				tracked[model] = nil
				if tr then
					tr.sound:Destroy()
					if tr.layer then tr.layer:Destroy() end
				end
			end
		end)
	end

	task.spawn(function()
		local map = workspace:WaitForChild("Map")
		for _, name in ipairs({"Planes", "Carriers", "Vessels", "Cargo", "CargoDrops"}) do
			task.spawn(function()
				local f = (name == "CargoDrops" and workspace or map):WaitForChild(name, 60)
				if not f then return end
				for _, m in ipairs(f:GetChildren()) do add(m, name) end
				f.ChildAdded:Connect(function(m)
					task.wait(0.5) -- дать модели догрузиться и получить атрибуты
					if m.Parent == f then add(m, name) end
				end)
			end)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < STEP then return end
		local step = acc
		acc = 0
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for model, t in pairs(tracked) do
			local pos = t.root.Position
			local d = pos - t.last
			t.last = pos
			local speed = Vector3.new(d.X, 0, d.Z).Magnitude / step
			if t.kind.sound == "EnginePlane" then speed = d.Magnitude / step end
			local e = t.e
			-- далеко — не играем вообще (экономия)
			if (pos - camPos).Magnitude > e.range then
				if t.sound.Playing then t.sound:Stop() end
				if t.layer and t.layer.Playing then t.layer:Stop() end
				t.vol = 0
				continue
			end
			local on = not model:GetAttribute("Sinking") and model:GetAttribute("State") ~= "Destroyed"
			if t.kind.sound == "EnginePlane" then on = on and model:GetAttribute("EngineOn") == true end
			local k = math.clamp(speed / t.kind.speed, 0, 1)
			local targetVol = on and e.volume * (e.idle + (1 - e.idle) * k) or 0
			if t.kind.sound == "EngineSubmarine" and pos.Y < -4 then targetVol *= 0.4 end -- под водой тише
			local targetPitch = e.pitch[1] + (e.pitch[2] - e.pitch[1]) * k
			t.vol += (targetVol - t.vol) * 0.25
			t.pitch += (targetPitch - t.pitch) * 0.25
			t.sound.Volume = t.vol
			t.sound.PlaybackSpeed = t.pitch
			if t.vol > 0.005 and not t.sound.Playing then
				t.sound.TimePosition = math.random() * 10 -- чтобы одинаковые суда не гудели в унисон
				t.sound:Play()
			elseif t.vol <= 0.005 and t.sound.Playing then
				t.sound:Stop()
			end
			-- второй слой идёт в такт с основным: та же доля громкости и тона
			if t.layer then
				local le, f = t.le, e.volume > 0 and t.vol / e.volume or 0
				t.layer.Volume = le.volume * f
				t.layer.PlaybackSpeed = le.pitch[1] + (le.pitch[2] - le.pitch[1]) * k
				if t.layer.Volume > 0.003 and not t.layer.Playing then
					t.layer.TimePosition = math.random() * 10
					t.layer:Play()
				elseif t.layer.Volume <= 0.003 and t.layer.Playing then
					t.layer:Stop()
				end
			end
		end
	end)

	return {}
end
