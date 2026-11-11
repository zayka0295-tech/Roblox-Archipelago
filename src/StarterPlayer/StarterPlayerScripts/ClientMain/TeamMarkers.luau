-- Метки над техникой: значок типа + расстояние. Союзники — всегда, противник — только вблизи.
-- Экранный интерфейс: каждый кадр метка ставится в точку экрана над техникой.
-- Только клиент, только чтение (данные — атрибуты моделей, которые публикует сервер).
local RunService = game:GetService("RunService")

local ICON = {Plane = "▲", Ship = "◆", Carrier = "■", Cargo = "●"}
local LIFT = {Plane = 7, Ship = 26, Carrier = 70, Cargo = 18}

return function(ctx)
	local Config = ctx.Config
	local UI = ctx.UI
	local player = ctx.player
	local M = Config.Markers or {}
	local gui = UI.screen("TeamMarkers", 2) -- под остальным интерфейсом
	gui.IgnoreGuiInset = true
	local markers = {} -- [модель] = {frame, icon, dist, part, kind}
	local tracked = {} -- текущий список для отрисовки

	local function myTeam()
		for key, t in pairs(Config.Teams) do
			if player.Team and (player.Team.Name == key or player.Team.Name == t.DisplayName) then return key end
		end
	end

	local function make(kind)
		local f = Instance.new("Frame")
		f.Name = "Marker"
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.Size = UDim2.fromOffset(76, 44)
		f.BackgroundTransparency = 1
		f.Visible = false
		if UI.touchOnly then Instance.new("UIScale", f).Scale = 0.75 end -- на телефоне метки техники мельче
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(1, 0, 0, 26)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.GothamBlack
		icon.TextSize = 28
		icon.Text = ICON[kind] or "●"
		icon.TextStrokeTransparency = 0.2
		icon.Parent = f
		local dist = Instance.new("TextLabel")
		dist.Name = "Dist"
		dist.Position = UDim2.fromOffset(0, 26)
		dist.Size = UDim2.new(1, 0, 0, 16)
		dist.BackgroundTransparency = 1
		dist.Font = Enum.Font.GothamBold
		dist.TextSize = 14
		dist.TextStrokeTransparency = 0.3
		dist.Parent = f
		f.Parent = gui
		return {frame = f, icon = icon, dist = dist, kind = kind}
	end

	local function collect()
		local list = {}
		local map = workspace:FindFirstChild("Map")
		if not map then return list end
		local function scan(folderName, kind, partName, aliveAttr)
			local f = map:FindFirstChild(folderName)
			for _, mdl in ipairs(f and f:GetChildren() or {}) do
				local part = mdl:FindFirstChild(partName)
				if part and mdl:GetAttribute(aliveAttr) then
					table.insert(list, {model = mdl, kind = kind, part = part})
				end
			end
		end
		scan("Planes", "Plane", "Root", "IsPlane")
		scan("Vessels", "Ship", "Hull", "IsVessel")
		scan("Carriers", "Carrier", "Hull", "IsCarrier")
		scan("Cargo", "Cargo", "Hull", "IsCargo")
		return list
	end

	local function fmt(d)
		if d >= 1000 then return ("%.1f km"):format(d / 1000) end
		return ("%d m"):format(math.floor(d / 10 + 0.5) * 10)
	end

	-- раз в 0.2 с: кого показывать
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then return end
		acc = 0
		local mine = myTeam()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		local cam = workspace.CurrentCamera
		local eye = cam and cam.CFrame.Position or Vector3.zero
		local seen = {}
		local list = {}
		if mine and player:GetAttribute("State") == "Deployed" then
			for _, v in ipairs(collect()) do
				local team = v.model:GetAttribute("Team")
				if team == "Blue" or team == "Red" then
					local d = (v.part.Position - eye).Magnitude
					local ally = team == mine
					local own = seat and seat:IsDescendantOf(v.model)
					local submerged = (v.model:GetAttribute("Depth") or 0) > 6
					-- противник: вблизи (если не на глубине), на сонаре нашей команды или выдал себя выстрелом
					local spotted = v.model:GetAttribute("Sonar_" .. mine) == true
						or (v.model:GetAttribute("RevealedUntil") or 0) > workspace:GetServerTimeNow()
					local show = not own and d >= (M.HideCloserThan or 70) and d <= (M.MaxDistance or 12000)
						and (ally or spotted or (d <= (M.EnemyRevealDistance or 300) and not submerged))
					if show then
						seen[v.model] = true
						local mk = markers[v.model]
						if not mk then
							mk = make(v.kind)
							markers[v.model] = mk
						end
						mk.part = v.part
						mk.icon.TextColor3 = Config.Teams[team].Color
						mk.dist.TextColor3 = ally and Color3.fromRGB(225, 235, 245) or Color3.fromRGB(255, 190, 180)
						mk.dist.Text = fmt(d)
						table.insert(list, mk)
					end
				end
			end
		end
		for mdl, mk in pairs(markers) do
			if not seen[mdl] then
				mk.frame:Destroy()
				markers[mdl] = nil
			end
		end
		tracked = list
		-- таблички авианосца (BRIDGE, TAKEOFF) видны сквозь стены — показываем только на своём
		local carriers = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Carriers")
		for _, c in ipairs(carriers and carriers:GetChildren() or {}) do
			local own = mine ~= nil and c:GetAttribute("Team") == mine
			for _, partName in ipairs({"HelmAccess", "AirTerminal"}) do
				local part = c:FindFirstChild(partName)
				local bb = part and part:FindFirstChildOfClass("BillboardGui")
				if bb and bb.Enabled ~= own then bb.Enabled = own end
			end
		end
	end)

	-- каждый кадр: позиция на экране
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		for _, mk in ipairs(tracked) do
			local part = mk.part
			if part and part.Parent then
				local v, onScreen = cam:WorldToViewportPoint(part.Position + Vector3.new(0, LIFT[mk.kind] or 10, 0))
				mk.frame.Visible = onScreen
				if onScreen then mk.frame.Position = UDim2.fromOffset(v.X, v.Y) end
			else
				mk.frame.Visible = false
			end
		end
	end)
	return {}
end
