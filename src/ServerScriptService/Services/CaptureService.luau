-- Захват островов. Сервер — единственный источник истины: считает присутствие в зоне,
-- двигает прогресс, меняет владельца и публикует состояние атрибутами (клиенты только читают).
--
-- Прогресс Control: от -1 (Red) через 0 (нейтрально) до +1 (Blue).
-- Захват нейтрального: 0 → ±1 за Capture.Time. Вражеский остров сначала нейтрализуется (до 0), потом захватывается.
-- В зоне обе команды — прогресс стоит («спорная зона»). Никого — плавно возвращается к владельцу.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local Notifier = require(Services.Notifier)
local DataService = require(Services.DataService)

local CaptureService = {}
CaptureService.OwnerChanged = Instance.new("BindableEvent") -- (islandId, newOwner, oldOwner)

local C = Config.Capture
local NEUTRAL_COLOR = Color3.fromRGB(215, 215, 215)
local islands = {} -- [id] = состояние
local order = {}
local GameState = ReplicatedStorage:WaitForChild("GameState")

local function teamColor(team)
	local t = Config.Teams[team]
	return t and t.Color or NEUTRAL_COLOR
end

local function ownerSign(owner)
	return owner == "Blue" and 1 or owner == "Red" and -1 or 0
end

------------------------------------------------------------------ кто в зоне
-- живой, пешком (не в технике) и в зоне острова, не выше MaxHeightAboveGround: и для захвата, и для награды
local function inCaptureZone(isl, hrp, hum)
	if not hrp or not hum or hum.Health <= 0 or hum.SeatPart then return false end
	local p, center = hrp.Position, isl.center
	local dx, dz = p.X - center.X, p.Z - center.Z
	return dx * dx + dz * dz <= isl.radius * isl.radius and p.Y - center.Y <= (C.MaxHeightAboveGround or 25) and p.Y >= center.Y - 10
end

-- кто может захватывать (в бою, с командой): {команда, корень, гуманоид} — один раз за такт на все острова
local function collectActors()
	local list = {}
	local function add(team, hrp, hum)
		if (team == "Blue" or team == "Red") and hrp and hum then table.insert(list, {team, hrp, hum}) end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("State") == "Deployed" then
			local char = p.Character
			add(TeamService.getTeamName(p), char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid"))
		end
	end
	if C.BotsCount then
		local bots = workspace:FindFirstChild("Bots")
		for _, b in ipairs(bots and bots:GetChildren() or {}) do
			add(b:GetAttribute("Team"), b:FindFirstChild("HumanoidRootPart"), b:FindFirstChildOfClass("Humanoid"))
		end
	end
	return list
end

local function countInZone(isl, actors)
	local blue, red = 0, 0
	for _, a in ipairs(actors) do
		if inCaptureZone(isl, a[2], a[3]) then
			if a[1] == "Blue" then blue += 1 else red += 1 end
		end
	end
	return blue, red
end

------------------------------------------------------------------ публикация и визуал
local function publishCounts()
	local n = {Blue = 0, Red = 0}
	for _, isl in pairs(islands) do
		if n[isl.owner] then n[isl.owner] += 1 end
	end
	GameState:SetAttribute("Islands_Blue", n.Blue)
	GameState:SetAttribute("Islands_Red", n.Red)
end

local function updateVisuals(isl)
	local col = teamColor(isl.owner)
	if isl.flag then isl.flag.Color = col end
	local ringCol = isl.contested and Color3.fromRGB(255, 200, 60) or col
	if isl.ring then isl.ring.Color = ringCol end
	if isl.edge then isl.edge.Color = ringCol end

	-- значок над островом (виден издалека)
	local badge = isl.badge
	if badge then
		badge.Circle.BackgroundColor3 = isl.owner == "Neutral" and Color3.fromRGB(150, 155, 165) or col
		local stroke = badge.Circle.Stroke
		if isl.contested then
			stroke.Color = Color3.fromRGB(255, 200, 60)
		elseif isl.def.IsCenter then
			stroke.Color = Color3.fromRGB(255, 220, 120)
		else
			stroke.Color = Color3.fromRGB(20, 24, 32)
		end
		local active = isl.capturing ~= nil or isl.contested
		badge.Bar.Visible = active
		if active then
			local cap = isl.capturing or (isl.control >= 0 and "Blue" or "Red")
			badge.Bar.Fill.Size = UDim2.fromScale(math.clamp(math.abs(isl.control), 0, 1), 1)
			badge.Bar.Fill.BackgroundColor3 = isl.contested and Color3.fromRGB(255, 200, 60) or teamColor(cap)
		end
	end
	-- табличка вблизи: только состояние рейса (владелец и прогресс захвата видны по флагу)
	local gui = isl.gui
	if not gui then return end
	local panel = gui.Panel
	local status = isl.extraStatus or ""
	panel.Visible = status ~= ""
	panel.Stroke.Color = col
	panel.Status.Text = status
	panel.Status.TextColor3 = Color3.fromRGB(235, 238, 245)
end

local function setOwner(isl, owner)
	local old = isl.owner
	if old == owner then return end
	isl.owner = owner
	isl.point:SetAttribute("Owner", owner)
	GameState:SetAttribute("Island_" .. isl.id .. "_Owner", owner)
	isl.outpost:SetAttribute("Owner", owner)
	publishCounts()
	updateVisuals(isl)
	-- игроки команды team, которые сейчас в зоне острова (по тем же правилам, что и захват)
	local function inZone(team)
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if TeamService.getTeamName(p) == team and p:GetAttribute("State") == "Deployed"
				and inCaptureZone(isl, char and char:FindFirstChild("HumanoidRootPart"), char and char:FindFirstChildOfClass("Humanoid")) then
				table.insert(list, p)
			end
		end
		return list
	end
	local RankService = require(script.Parent.RankService)
	if owner == "Neutral" then
		Notifier.all(("%s neutralized (%s lost control)"):format(isl.name, Config.Teams[old].DisplayName), "info")
		if old == "Blue" or old == "Red" then
			for _, p in ipairs(inZone(old == "Blue" and "Red" or "Blue")) do RankService.award(p, "Neutralize") end
		end
	else
		Notifier.team(owner, isl.def.IsRig and ("Oil rig captured: %s! A cargo helicopter will fly to your base."):format(isl.name)
			or ("Island captured: %s! Cargo ships will sail to your base."):format(isl.name), "success")
		-- личная награда участникам захвата (кто сейчас в зоне)
		local rw = Config.Economy.Rewards and Config.Economy.Rewards.CaptureParticipant or 0
		for _, p in ipairs(inZone(owner)) do
			if rw > 0 then
				DataService.addGold(p, rw)
				Notifier.send(p, ("You captured %s · +%d gold"):format(isl.name, rw), "success")
			end
			RankService.award(p, "Capture")
		end
		local enemy = owner == "Blue" and "Red" or "Blue"
		Notifier.team(enemy, ("%s captured %s"):format(Config.Teams[owner].DisplayName, isl.name), "error")
	end
	CaptureService.OwnerChanged:Fire(isl.id, owner, old)
end

------------------------------------------------------------------ API
function CaptureService.getOwner(id)
	local isl = islands[id]
	return isl and isl.owner or "Neutral"
end

function CaptureService.getIslands()
	return islands, order
end

-- дополнительная строка состояния на табличке (например, расписание рейса)
function CaptureService.setExtraStatus(id, text)
	local isl = islands[id]
	if isl and isl.extraStatus ~= text then
		isl.extraStatus = text
		updateVisuals(isl)
	end
end

-- новый раунд: все острова снова нейтральные, прогресс захвата обнулён (без сообщений «нейтрализован»)
function CaptureService.resetAll()
	for _, isl in pairs(islands) do
		local old = isl.owner
		isl.control, isl.contested, isl.capturing = 0, false, nil
		isl.point:SetAttribute("Control", 0)
		isl.point:SetAttribute("Contested", false)
		isl.point:SetAttribute("Capturing", "")
		GameState:SetAttribute("Island_" .. isl.id .. "_Contested", false)
		GameState:SetAttribute("Island_" .. isl.id .. "_Capturing", "")
		if old ~= "Neutral" then
			isl.owner = "Neutral"
			isl.point:SetAttribute("Owner", "Neutral")
			GameState:SetAttribute("Island_" .. isl.id .. "_Owner", "Neutral")
			isl.outpost:SetAttribute("Owner", "Neutral")
			CaptureService.OwnerChanged:Fire(isl.id, "Neutral", old)
		end
		updateVisuals(isl)
	end
	publishCounts()
end

-- только для тестов в Studio
function CaptureService.devSetOwner(id, owner)
	local isl = islands[id]
	if not isl then return false end
	isl.control = ownerSign(owner)
	isl.point:SetAttribute("Control", isl.control)
	setOwner(isl, owner)
	return true
end

function CaptureService.init()
	for _, def in ipairs(Config.Islands) do
		local outpost = workspace.Map.Neutral:FindFirstChild(def.Outpost)
		local cap = outpost and outpost:FindFirstChild("Capture")
		local point = cap and cap:FindFirstChild("CapturePoint")
		if point then
			local isl = {
				id = def.Id, name = def.Name, def = def, outpost = outpost, point = point,
				center = point.Position - Vector3.new(0, 1, 0),
				radius = point:GetAttribute("Radius") or (def.IsCenter and C.CenterRadius) or C.Radius,
				owner = "Neutral", control = 0, contested = false, capturing = nil,
				flag = outpost:FindFirstChild("Flag"),
				ring = cap:FindFirstChild("ZoneRing"), edge = cap:FindFirstChild("ZoneEdge"),
				gui = cap:FindFirstChild("LabelAnchor") and cap.LabelAnchor:FindFirstChild("CaptureGui"),
				badge = cap:FindFirstChild("LabelAnchor") and cap.LabelAnchor:FindFirstChild("IslandBadge"),
			}
			point:SetAttribute("Owner", "Neutral")
			point:SetAttribute("Control", 0)
			point:SetAttribute("Contested", false)
			point:SetAttribute("IslandName", def.Name)
			-- буква точки на значке над островом
			local letter = isl.badge and isl.badge:FindFirstChild("Letter", true)
			if letter and def.Letter then letter.Text = def.Letter end
			outpost:SetAttribute("Owner", "Neutral")
			GameState:SetAttribute("Island_" .. def.Id .. "_Owner", "Neutral")
			GameState:SetAttribute("Island_" .. def.Id .. "_Contested", false)
			GameState:SetAttribute("Island_" .. def.Id .. "_Capturing", "")
			islands[def.Id] = isl
			table.insert(order, def.Id)
			updateVisuals(isl)
		else
			warn("[CaptureService] no capture point at " .. def.Outpost)
		end
	end
	publishCounts()

	local acc = 0
	local warnedAt = {} -- [id острова] = когда последний раз писали ошибку
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then return end
		local step = acc
		acc = 0
		local actors = collectActors()
		-- остров под pcall: сбой у одного (нет детали значка, ошибка в награде) не останавливает захват остальных
		local function stepIsland(isl)
			local blue, red = countInZone(isl, actors)
			local prevC, prevContested, prevCap = isl.control, isl.contested, isl.capturing
			isl.contested = blue > 0 and red > 0
			isl.capturing = nil
			if not isl.contested and (blue > 0 or red > 0) then
				local team = blue > 0 and "Blue" or "Red"
				local n = math.max(blue, red)
				local mult = math.min(1 + (n - 1) * (C.ExtraPlayerBonus or 0.25), C.MaxSpeedMultiplier or 2)
				local dir = ownerSign(team)
				if isl.control * dir < 1 then
					isl.capturing = team
					isl.control = math.clamp(isl.control + dir * step / C.Time * mult, -1, 1)
				end
			elseif not isl.contested then
				-- никого: плавно к состоянию владельца
				local target = ownerSign(isl.owner)
				local d = target - isl.control
				local maxStep = step / (C.DecayTime or 30)
				if math.abs(d) <= maxStep then isl.control = target else isl.control += math.sign(d) * maxStep end
			end
			-- смена владельца
			if isl.control >= 1 and isl.owner ~= "Blue" then
				setOwner(isl, "Blue")
			elseif isl.control <= -1 and isl.owner ~= "Red" then
				setOwner(isl, "Red")
			elseif isl.owner == "Blue" and isl.control <= 0 then
				setOwner(isl, "Neutral")
			elseif isl.owner == "Red" and isl.control >= 0 then
				setOwner(isl, "Neutral")
			end
			if isl.control ~= prevC then isl.point:SetAttribute("Control", math.floor(isl.control * 1000) / 1000) end
			if isl.contested ~= prevContested then
				isl.point:SetAttribute("Contested", isl.contested)
				GameState:SetAttribute("Island_" .. isl.id .. "_Contested", isl.contested)
			end
			if isl.capturing ~= prevCap then
				GameState:SetAttribute("Island_" .. isl.id .. "_Capturing", isl.capturing or "")
				isl.point:SetAttribute("Capturing", isl.capturing or "")
			end
			if isl.control ~= prevC or isl.contested ~= prevContested or isl.capturing ~= prevCap then
				updateVisuals(isl)
			end
		end
		for id, isl in pairs(islands) do
			local ok, err = pcall(stepIsland, isl)
			-- одна и та же поломка повторялась бы 4 раза в секунду — пишем не чаще раза в 30 с на остров
			if not ok and os.clock() - (warnedAt[id] or -math.huge) > 30 then
				warnedAt[id] = os.clock()
				warn("[CaptureService] " .. tostring(id) .. ": " .. tostring(err))
			end
		end
	end)
end

return CaptureService
