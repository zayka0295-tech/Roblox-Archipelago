-- Таблица лидеров по убийствам: глобальный OrderedDataStore + живые данные сервера
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local Guard = require(Services.RemoteGuard)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LeaderboardService = {}

local global = {}   -- [userId] = kills (из DataStore)
local offline = {}  -- [userId] = kills ушедших с этого сервера игроков
-- [userId] = последнее известное число убийств игрока на сервере. При выходе DataService может выгрузить профиль
-- раньше, чем сработает наш PlayerRemoving (порядок обработчиков не гарантирован), — тогда берём отсюда
local seen = {}
local names = {}
local current = {}
local lastKey = ""

local function nameOf(userId)
	if names[userId] then return names[userId] end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return names[userId]
	end
	return nil
end

local function refreshGlobal()
	local store = DataService.KillsStore
	if not store then return end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.Data.LeaderboardSize)
	end)
	if not ok then
		warn("[Leaderboard] " .. tostring(pages))
		return
	end
	local fresh = {}
	local unknown = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		local id = tonumber(entry.key)
		if id then
			fresh[id] = entry.value
			if not nameOf(id) then table.insert(unknown, id) end
		end
	end
	-- имена тех, кого нет на сервере, — одним запросом (а не по одному на каждого)
	if #unknown > 0 then
		local okInfo, infos = pcall(function()
			return game:GetService("UserService"):GetUserInfosByUserIdsAsync(unknown)
		end)
		if okInfo and type(infos) == "table" then
			for _, info in ipairs(infos) do names[info.Id] = info.DisplayName end
		else
			warn("[Leaderboard] names: " .. tostring(infos))
		end
	end
	global = fresh
end

local function build()
	local merged = {}
	for id, k in pairs(global) do merged[id] = k end
	for id, k in pairs(offline) do merged[id] = math.max(merged[id] or 0, k) end
	for _, p in ipairs(Players:GetPlayers()) do
		local k = DataService.get(p, "Kills")
		if k then merged[p.UserId] = k end -- живое значение актуальнее
	end
	local list = {}
	for id, k in pairs(merged) do
		if k > 0 then
			table.insert(list, {userId = id, name = nameOf(id) or ("Player " .. id), kills = k})
		end
	end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then return a.kills > b.kills end
		return a.name < b.name
	end)
	for i = #list, Config.Data.LeaderboardSize + 1, -1 do
		list[i] = nil
	end
	for i, e in ipairs(list) do e.rank = i end
	return list
end

-- доски в лобби обеих команд (Map.* с атрибутом LobbyTeam)
local function updateBoard(list)
	local map = workspace:FindFirstChild("Map")
	for _, lobby in ipairs(map and map:GetChildren() or {}) do
		local board = lobby:GetAttribute("LobbyTeam") and lobby:FindFirstChild("LeaderboardBoard")
		local gui = board and board:FindFirstChild("BoardGui")
		if gui then
			for i = 1, Config.Data.LobbyBoardRows do
				local row = gui:FindFirstChild("Row" .. i)
				if row then
					local e = list[i]
					local nameLbl, killsLbl = row:FindFirstChild("Name"), row:FindFirstChild("Kills")
					if nameLbl then nameLbl.Text = e and e.name or "—" end
					if killsLbl then killsLbl.Text = e and tostring(e.kills) or "" end
				end
			end
		end
	end
end

-- ушедшие игроки и имена, которые в таблицу уже не попадут (ниже последнего места), — не храним:
-- иначе за дни работы сервера таблицы растут на каждого, кто заходил
-- (таблица неполная — в ней все с убийствами > 0, так что вне её только записи с нулём: их тоже убираем)
local function prune()
	local keep = {}
	for _, e in ipairs(current) do keep[e.userId] = true end
	for _, p in ipairs(Players:GetPlayers()) do keep[p.UserId] = true end
	for id in pairs(offline) do
		if not keep[id] then offline[id] = nil end
	end
	for id in pairs(names) do
		if not keep[id] and not global[id] then names[id] = nil end
	end
end

local function broadcast(force)
	current = build()
	prune()
	local parts = {}
	for _, e in ipairs(current) do
		table.insert(parts, e.userId .. ":" .. e.kills .. ":" .. e.name)
	end
	local key = table.concat(parts, "|")
	if force or key ~= lastKey then
		lastKey = key
		updateBoard(current)
		Remotes.LeaderboardUpdated:FireAllClients(current)
	end
end

function LeaderboardService.get()
	return current
end

-- изменение убийств: рассылка не на каждое (в бою их много в секунду), а одна за BROADCAST_GAP сек.
local BROADCAST_GAP = 1
local queued = false
local function queueBroadcast()
	if queued then return end
	queued = true
	task.delay(BROADCAST_GAP, function()
		queued = false
		broadcast(false)
	end)
end

function LeaderboardService.init()
	Remotes.GetLeaderboard.OnServerInvoke = function(player)
		if not Guard.allow(player, "GetLeaderboard") then return nil end -- клиент оставит прежние данные
		return current
	end

	DataService.Loaded.Event:Connect(function(p)
		seen[p.UserId] = DataService.get(p, "Kills")
	end)
	DataService.StatChanged.Event:Connect(function(p, field, value)
		if field == "Kills" then
			seen[p.UserId] = value
			queueBroadcast()
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local k = DataService.get(p, "Kills") or seen[p.UserId]
		seen[p.UserId] = nil
		if k then offline[p.UserId] = k end
		names[p.UserId] = names[p.UserId] or p.DisplayName
		task.defer(broadcast, false)
	end)
	Players.PlayerAdded:Connect(function(p)
		names[p.UserId] = p.DisplayName
	end)

	task.spawn(function()
		while true do
			refreshGlobal()
			broadcast(true)
			task.wait(Config.Data.LeaderboardRefreshSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Data.LeaderboardBroadcastSeconds)
			broadcast(false)
		end
	end)
end

return LeaderboardService
