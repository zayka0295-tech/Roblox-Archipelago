-- Точка входа клиента: создаёт интерфейсы и переключает их по состоянию игрока
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Islands = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Islands"))
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
	local wait = (GameState:GetAttribute("Carrier_" .. team .. "_CooldownEnd") or 0) - os.time()
	if wait > 0 then return false, ("Shipyard rebuilding · %d s"):format(wait), "Cooldown" end
	return false, ("Not purchased · %d from treasury at the shipyard"):format(Config.Economy.CarrierPrice), st
end

-- аэродром на острове (Config.IslandAirfield): доступен команде?, текст, запись острова
function ctx.islandStatus(team)
	local def = Islands.airfield()
	if not def then return false, "No airfield", nil end
	local owner = GameState:GetAttribute("Island_" .. def.Id .. "_Owner") or "Neutral"
	if team and owner == team then return true, ("Point %s · %s"):format(def.Letter, def.Name), def end
	if owner == "Neutral" then return false, ("Capture point %s · %s"):format(def.Letter, def.Name), def end
	return false, ("Point %s held by the enemy"):format(def.Letter), def
end

-- безопасный вызов RemoteFunction: ошибка или нет ответа дольше INVOKE_TIMEOUT — {ok = false}
-- (иначе зависший обработчик сервера навсегда оставлял кнопку «занятой»; поздний ответ просто не ждём)
local INVOKE_TIMEOUT = 30
function ctx.invoke(name, ...)
	local args = table.pack(...)
	local thread = coroutine.running()
	local finished = false
	local function finish(ok, res)
		if finished then return end
		finished = true
		-- defer: ошибка может прийти сразу, ещё до того, как этот поток уснул в coroutine.yield
		task.defer(thread, ok, res)
	end
	task.spawn(function()
		finish(pcall(function()
			return Remotes[name]:InvokeServer(table.unpack(args, 1, args.n))
		end))
	end)
	task.delay(INVOKE_TIMEOUT, finish, false, "timeout")
	local ok, res = coroutine.yield()
	if not ok or type(res) ~= "table" then
		return {ok = false, msg = "Server did not respond, try again"}
	end
	return res
end

local notify = Remotes:WaitForChild("Notify", 10)
if notify then
	notify.OnClientEvent:Connect(function(text, kind)
		UI.toast(text, kind)
	end)
else
	warn("[ClientMain] Remotes.Notify not found — server notifications are off")
end

for _, name in ipairs({"ErrorReporter", "SpawnFade", "ShotFx", "LeaderboardUI", "HUD", "SpawnSelectionUI", "ShopUI", "HangarUI", "BazaarUI", "ShipControlUI", "TurretUI", "PlaneClient", "SeatCamera", "IslandsUI", "TeamMarkers", "EngineSounds", "Music", "AirRaid", "BaseAnim", "CaptureFlags", "ShipSmoke", "GunClient", "GunPose", "GunViewmodel", "BaseWaypoints", "QuestUI", "DamageNumbers", "RoundUI", "CaptainUI", "GuidePath", "DailySpinUI", "RankUI", "RewardsUI", "CareerUI", "StormFx", "RankTags", "VipChat", "VehicleZoom", "ParachuteUI", "DropMapUI", "SkydivePose", "JudgeUI", "SwimLimit"}) do
	-- ошибка в одном модуле не должна оставлять игрока без всех следующих интерфейсов:
	-- ловим её и перебрасываем в отдельном потоке (её увидит Output и ErrorReporter)
	local ok, res = pcall(function()
		return require(script:WaitForChild(name))(ctx)
	end)
	if ok then
		ctx.screens[name] = res
	else
		task.spawn(error, ("[ClientMain] %s failed to start: %s"):format(name, tostring(res)), 0)
	end
end

local function route()
	local state = ctx.state()
	for name, s in pairs(ctx.screens) do
		if type(s) == "table" and s.onState then
			local ok, err = pcall(s.onState, state)
			if not ok then task.spawn(error, ("[ClientMain] %s.onState: %s"):format(name, tostring(err)), 0) end
		end
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
