-- Точка входа клиента: создаёт интерфейсы и переключает их по состоянию игрока
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local GameState = ReplicatedStorage:WaitForChild("GameState")
local UI = require(script:WaitForChild("UIKit"))

local ctx = {
	player = player,
	Remotes = Remotes,
	Config = Config,
	GameState = GameState,
	UI = UI,
	screens = {},
}

function ctx.state()
	return player:GetAttribute("State") or "Lobby"
end

function ctx.team()
	local t = player.Team
	if t and Config.Teams[t.Name] then return t.Name end
	return nil
end

function ctx.stat(name)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(name)
	return v and v.Value or 0
end

-- состояние авианосца команды: доступен?, текст, код состояния
function ctx.carrierStatus(team)
	if not team then return false, "No team selected", "None" end
	local st = GameState:GetAttribute("Carrier_" .. team) or "None"
	if st == "Active" then
		return true, ("Afloat · hull %d/%d"):format(
			GameState:GetAttribute("Carrier_" .. team .. "_Health") or 0,
			GameState:GetAttribute("Carrier_" .. team .. "_MaxHealth") or 0), st
	elseif st == "Sinking" or st == "Destroyed" then
		return false, "Sinking · a new one once it goes down", "Sinking"
	end
	return false, ("Not purchased · %d from treasury at the shipyard"):format(Config.Economy.CarrierPrice), st
end

-- безопасный вызов RemoteFunction
function ctx.invoke(name, ...)
	local args = table.pack(...)
	local ok, res = pcall(function()
		return Remotes[name]:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok or type(res) ~= "table" then
		return {ok = false, msg = "Server did not respond, try again"}
	end
	return res
end

Remotes.Notify.OnClientEvent:Connect(function(text, kind)
	UI.toast(text, kind)
end)

for _, name in ipairs({"ErrorReporter", "ShotFx", "LeaderboardUI", "HUD", "SpawnSelectionUI", "ShopUI", "HangarUI", "ShipControlUI", "TurretUI", "PlaneClient", "SeatCamera", "IslandsUI", "TeamMarkers", "EngineSounds", "Music", "AirRaid", "BaseAnim", "CaptureFlags", "GunClient", "GunPose", "GunViewmodel", "BaseWaypoints", "QuestUI", "DamageNumbers", "RoundUI", "CaptainUI", "GuidePath", "DailySpinUI", "RankUI", "RankTags", "VipChat", "VehicleZoom", "ParachuteUI", "DropMapUI", "SkydivePose", "UniformUI", "JudgeUI"}) do
	ctx.screens[name] = require(script:WaitForChild(name))(ctx)
end

local function route()
	local state = ctx.state()
	for _, s in pairs(ctx.screens) do
		if s.onState then s.onState(state) end
	end
end
player:GetAttributeChangedSignal("State"):Connect(route)
route()

-- в любой технике (сидим в сиденье: самолёт, корабль, турель) панель оружия скрыта — не мешает приборам
local StarterGui = game:GetService("StarterGui")
local function setBackpack(on)
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, on) end)
end
local function watchSeat(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	setBackpack(hum.SeatPart == nil)
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function() setBackpack(hum.SeatPart == nil) end)
	hum.Died:Connect(function() setBackpack(true) end)
end
player.CharacterAdded:Connect(watchSeat)
if player.Character then task.spawn(watchSeat, player.Character) end
