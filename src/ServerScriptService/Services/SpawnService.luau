-- Лобби, автораспределение по командам (при входе и возврате в лобби), выбор точки появления, возрождение
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local CarrierService = require(Services.CarrierService)
local CombatService = require(Services.CombatService)
local Notifier = require(Services.Notifier)
local Guard = require(Services.RemoteGuard)
local AntiCheat = require(Services.AntiCheatService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SpawnService = {}
-- [игрок] = function(char, hum, hrp): следующий персонаж ставит не на точку появления, а эта функция
-- (десант — сразу в грузовой самолёт). Срабатывает один раз.
SpawnService.placeOverride = {}

local function result(ok, msg)
	return {ok = ok, msg = msg}
end

local function spawnsIn(folder)
	local list = {}
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			if c:IsA("SpawnLocation") then table.insert(list, c) end
		end
	end
	return list
end

local function pick(list)
	return list[math.random(1, #list)]
end

-- у каждой команды своё лобби: Map.Lobby / Map.LobbyRed (атрибут LobbyTeam)
function SpawnService.lobbies()
	local list = {}
	for _, c in ipairs(workspace.Map:GetChildren()) do
		if c:GetAttribute("LobbyTeam") then table.insert(list, c) end
	end
	return list
end

function SpawnService.lobbyOf(team)
	for _, l in ipairs(SpawnService.lobbies()) do
		if l:GetAttribute("LobbyTeam") == team then return l end
	end
	return workspace.Map.Lobby
end

function SpawnService.lobbyPoints(team)
	return spawnsIn(SpawnService.lobbyOf(team).Spawns)
end

function SpawnService.basePoints(team)
	local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
	return spawnsIn(base and base:FindFirstChild("Spawns"))
end

-- куда ставить персонажа: Lobby / Base / Carrier (с откатом на базу)
function SpawnService.resolve(player)
	local team = TeamService.getTeamName(player)
	if player:GetAttribute("State") ~= "Deployed" or not team then
		return pick(SpawnService.lobbyPoints(team)), "Lobby"
	end
	if player:GetAttribute("SpawnChoice") == "Carrier" then
		local pts = CarrierService.getSpawnPoints(team)
		if pts and #pts > 0 then
			return pick(pts), "Carrier"
		end
		player:SetAttribute("SpawnChoice", "Base")
		Notifier.send(player, "Carrier unavailable — spawning at base", "error")
	end
	local base = SpawnService.basePoints(team)
	if #base == 0 then
		return pick(SpawnService.lobbyPoints(team)), "Lobby"
	end
	return pick(base), "Base"
end

local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not hrp or player.Character ~= char then return end

	local override = SpawnService.placeOverride[player]
	local kind
	if override and player:GetAttribute("State") == "Deployed" then
		SpawnService.placeOverride[player] = nil
		kind = "Drop"
		AntiCheat.grace(player, 3)
		override(char, hum, hrp)
	else
		local point
		point, kind = SpawnService.resolve(player)
		local up = point.Size.Y / 2 + hum.HipHeight + hrp.Size.Y / 2 + 0.5
		local target = CFrame.new(point.Position + Vector3.new(math.random(-3, 3), up, math.random(-3, 3))) * point.CFrame.Rotation
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 3)
		end)
		if player.Character ~= char then return end
		AntiCheat.grace(player, 3)
		char:PivotTo(target)
	end
	if player.Character ~= char then return end
	player:SetAttribute("SpawnedAt", kind)

	local devSpeed = Config.Dev and Config.Dev.StudioWalkSpeed or 0
	if devSpeed > 0 and game:GetService("RunService"):IsStudio() then
		hum.WalkSpeed = devSpeed
	else
		hum.WalkSpeed = Config.Spawn.WalkSpeed or 16
	end

	if kind ~= "Lobby" then
		local ff = Instance.new("ForceField")
		ff.Parent = char
		Debris:AddItem(ff, Config.Spawn.ProtectionSeconds)
		-- стартовое оружие команды (синие — M4A1, красные — AK-47); require здесь, чтобы не зависеть от порядка загрузки
		local GunService = require(Services.GunService)
		GunService.give(player, Config.TeamGun[TeamService.getTeamName(player) or ""] or "Rifle")
	end

	-- корабли и самолёты видны на любом расстоянии (Persistent): чтобы за штурвалом и в кабине
	-- дальнего корабля игрок не пропадал (стриминг) и в него можно было попасть, персонаж тоже Persistent
	char.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = "Characters" end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.CollisionGroup = "Characters" end
	end)
	CombatService.trackCharacter(player, char, kind)
	hum.Died:Connect(function()
		task.delay(kind == "Lobby" and 1 or Config.Spawn.RespawnTime, function()
			if player.Parent and player.Character == char then
				player:LoadCharacter()
			end
		end)
	end)
end

-- в лобби игрок уже в команде: куда меньше игроков (свою не меняем, если команды равны)
local function autoTeam(player)
	local team = TeamService.balancedTeam(player)
	if team ~= TeamService.getTeamName(player) then
		TeamService.assign(player, team)
		if player:GetAttribute("SpawnChoice") == "Carrier" and not CarrierService.isActive(team) then
			player:SetAttribute("SpawnChoice", "Base")
		end
	end
	return team
end

function SpawnService.setupPlayer(player)
	player:SetAttribute("State", "Lobby")
	player:SetAttribute("SpawnChoice", "Base")
	TeamService.clear(player)
	autoTeam(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	player:LoadCharacter()
end

-- вступить в команду и сразу появиться (плиты лобби, десант). force — без проверки баланса (уже оплачено).
-- place — своя расстановка персонажа (см. placeOverride). Возвращает ok, сообщение.
function SpawnService.joinAndDeploy(player, teamName, force, place)
	if not Config.Teams[teamName] then return false, "Unknown team" end
	if not DataService.isLoaded(player) then return false, "Data is still loading…" end
	if not force and player:GetAttribute("State") ~= "Lobby" then return false, "You are already deployed" end
	if not force and not TeamService.canJoin(player, teamName) then
		return false, "This team has more players — choose the other one"
	end
	TeamService.assign(player, teamName)
	if player:GetAttribute("SpawnChoice") == "Carrier" and not CarrierService.isActive(teamName) then
		player:SetAttribute("SpawnChoice", "Base")
	end
	SpawnService.placeOverride[player] = place
	player:SetAttribute("State", "Deployed")
	task.spawn(function()
		player:LoadCharacter()
	end)
	return true, "Deploy!"
end

function SpawnService.init()
	Players.PlayerRemoving:Connect(function(p) SpawnService.placeOverride[p] = nil end)
	-- команду выбирает сервер (баланс), самому перейти нельзя
	Remotes.SelectTeam.OnServerInvoke = function()
		return result(false, "Teams are assigned automatically")
	end

	Remotes.SelectSpawn.OnServerInvoke = function(player, choice)
		if not Guard.allow(player, "SelectSpawn") then return result(false, "Too fast, please wait") end
		if choice ~= "Base" and choice ~= "Carrier" then return result(false, "Unknown spawn point") end
		local team = TeamService.getTeamName(player)
		if not team then return result(false, "Choose a team first") end
		if choice == "Carrier" then
			local ok, why = CarrierService.status(team)
			if not ok then return result(false, why) end
		end
		player:SetAttribute("SpawnChoice", choice)
		local where = choice == "Carrier" and "carrier" or "base"
		if player:GetAttribute("State") == "Deployed" then
			return result(true, "Next spawn: " .. where)
		end
		return result(true, "Spawn point: " .. where)
	end

	Remotes.Deploy.OnServerInvoke = function(player)
		if not Guard.allow(player, "Deploy") then return result(false, "Too fast, please wait") end
		if player:GetAttribute("State") ~= "Lobby" then return result(false, "You are already deployed") end
		if not DataService.isLoaded(player) then return result(false, "Data is still loading…") end
		local team = TeamService.getTeamName(player)
		if not team then return result(false, "Choose a team first") end
		local note
		if player:GetAttribute("SpawnChoice") == "Carrier" and not CarrierService.isActive(team) then
			player:SetAttribute("SpawnChoice", "Base")
			note = "Carrier unavailable — spawning at base"
		end
		player:SetAttribute("State", "Deployed")
		task.spawn(function()
			player:LoadCharacter()
		end)
		return result(true, note or "Deploy!")
	end

	Remotes.ReturnToLobby.OnServerInvoke = function(player)
		if not Guard.allow(player, "ReturnToLobby") then return result(false, "Too fast, please wait") end
		if player:GetAttribute("State") ~= "Deployed" then return result(false, "You are already in the lobby") end
		if CombatService.inCombat(player) then
			return result(false, ("In combat — wait %d s"):format(Config.Combat.KillCreditWindow))
		end
		player:SetAttribute("State", "Lobby")
		local before = TeamService.getTeamName(player)
		local team = autoTeam(player)
		task.spawn(function()
			player:LoadCharacter()
		end)
		if team ~= before then
			return result(true, "You are in the lobby · moved to " .. Config.Teams[team].DisplayName .. " for balance")
		end
		return result(true, "You are in the lobby")
	end
end

return SpawnService
