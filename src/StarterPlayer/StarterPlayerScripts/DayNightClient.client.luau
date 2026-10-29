-- Смена дня и ночи на клиенте, синхронно по серверному времени (без сетевого трафика)
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local DAY_LENGTH = 1200 -- 20 минут = сутки
local START_HOUR = 9

local DAY = {Ambient = Color3.fromRGB(110, 115, 125), Outdoor = Color3.fromRGB(125, 130, 140), Brightness = 3, Top = Color3.fromRGB(255, 255, 255), Atmos = Color3.fromRGB(199, 215, 235), Decay = Color3.fromRGB(106, 112, 125)}
local NIGHT = {Ambient = Color3.fromRGB(62, 70, 100), Outdoor = Color3.fromRGB(74, 86, 122), Brightness = 1.1, Top = Color3.fromRGB(120, 140, 200), Atmos = Color3.fromRGB(46, 60, 100), Decay = Color3.fromRGB(28, 34, 60)}
local CollectionService = game:GetService("CollectionService")
-- ночные огни: источники света с тегом NightLight и окна NightWindow включаются в сумерках
local nightOn = nil
local function applyLight(inst, on)
	if inst:IsA("Light") then
		inst.Enabled = on
	elseif inst:IsA("BasePart") then
		if inst:GetAttribute("DayMaterial") == nil then
			inst:SetAttribute("DayMaterial", inst.Material.Name)
			inst:SetAttribute("DayColor", inst.Color)
		end
		if on then
			inst.Material = Enum.Material.Neon
			inst.Color = inst:GetAttribute("NightColor") or Color3.fromRGB(255, 200, 120)
		else
			inst.Material = Enum.Material[inst:GetAttribute("DayMaterial")]
			inst.Color = inst:GetAttribute("DayColor")
		end
	end
end
local function setNight(on)
	if nightOn == on then return end
	nightOn = on
	for _, tag in ipairs({"NightLight", "NightWindow"}) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do applyLight(inst, on) end
	end
end
-- подлодка под водой огней не зажигает.
-- Огни каждой подлодки запоминаем один раз (и пересобираем, если при стриминге пришли новые детали);
-- трогаем их только когда меняется состояние «под водой / ночь».
local subs = setmetatable({}, {__mode = "k"}) -- [модель] = {lights, navs, state, dirty}
local function subEntry(m)
	local e = subs[m]
	if not e then
		e = {dirty = true}
		subs[m] = e
		m.DescendantAdded:Connect(function() e.dirty = true end)
	end
	if e.dirty then
		e.dirty, e.state = false, nil
		e.lights, e.navs, e.parts = {}, {}, {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("Light") and CollectionService:HasTag(d, "NightLight") then
				table.insert(e.lights, d)
			elseif d:IsA("BasePart") and d.Name == "NavLight" then
				table.insert(e.navs, d)
			end
			if d:IsA("BasePart") then table.insert(e.parts, d) end
		end
	end
	return e
end
-- чужая подлодка на глубине не просвечивает сквозь воду (с высокой рубки линкора её было видно).
-- Видна лишь метка сонара (TeamMarkers). Порог глубины — как у меток.
local HIDE_DEPTH = 6
local player = game:GetService("Players").LocalPlayer
local Teams = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"):WaitForChild("GameConfig")).Teams
local function myTeam()
	for key, t in pairs(Teams) do
		if player.Team and (player.Team.Name == key or player.Team.Name == t.DisplayName) then return key end
	end
end
local function updateSubs()
	local map = workspace:FindFirstChild("Map")
	local vessels = map and map:FindFirstChild("Vessels")
	local mine = myTeam()
	for _, m in ipairs(vessels and vessels:GetChildren() or {}) do
		if m:GetAttribute("ShipType") == "Submarine" then
			local depth = m:GetAttribute("Depth") or 0
			local under = depth > 2
			local hidden = depth > HIDE_DEPTH and m:GetAttribute("Team") ~= mine
			local e = subEntry(m)
			local state = (hidden and 4 or 0) + (under and 2 or 0) + (nightOn and 1 or 0)
			if e.state ~= state then
				e.state = state
				for _, l in ipairs(e.lights) do l.Enabled = nightOn == true and not under end
				for _, p in ipairs(e.parts) do
					if p.Parent then p.LocalTransparencyModifier = (hidden or (under and p.Name == "NavLight")) and 1 or 0 end
				end
			end
		end
	end
end
for _, tag in ipairs({"NightLight", "NightWindow"}) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if nightOn ~= nil then applyLight(inst, nightOn) end
	end)
end
local SUNSET = Color3.fromRGB(255, 150, 80)

local sky = Lighting:FindFirstChildOfClass("Sky")
if sky then
	sky.CelestialBodiesShown = true
	sky.StarCount = 3000
end
local atmos = Lighting:FindFirstChildOfClass("Atmosphere")

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then return end
	acc = 0
	local t = (START_HOUR + (workspace:GetServerTimeNow() % DAY_LENGTH) / DAY_LENGTH * 24) % 24
	local dev = workspace:GetAttribute("DevClockTime") -- только для тестов в Studio
	if type(dev) == "number" then t = dev end
	Lighting.ClockTime = t
	local h = math.sin((t - 6) * math.pi / 12)
	local d = math.clamp((h + 0.15) / 0.45, 0, 1)
	d = d * d * (3 - 2 * d)
	local warm = math.clamp(1 - math.abs(h) / 0.3, 0, 1)
	Lighting.Ambient = NIGHT.Ambient:Lerp(DAY.Ambient, d)
	Lighting.OutdoorAmbient = NIGHT.Outdoor:Lerp(DAY.Outdoor, d)
	Lighting.Brightness = NIGHT.Brightness + (DAY.Brightness - NIGHT.Brightness) * d
	Lighting.ExposureCompensation = 0.35 * (1 - d)
	setNight(d < 0.55)
	updateSubs()
	Lighting.ColorShift_Top = NIGHT.Top:Lerp(DAY.Top, d):Lerp(SUNSET, warm * 0.6)
	if atmos then
		atmos.Color = NIGHT.Atmos:Lerp(DAY.Atmos, d):Lerp(SUNSET, warm * 0.35)
		atmos.Decay = NIGHT.Decay:Lerp(DAY.Decay, d)
	end
end)
