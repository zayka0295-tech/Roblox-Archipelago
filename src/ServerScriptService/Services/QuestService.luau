-- Доска заданий (у оружейного стенда базы): одноразовые задания с наградой золотом (Config.Quests).
--  group — вступить в группу Roblox (проверяем по списку групп игрока),
--  play  — наиграть N секунд (суммарно, за любое число заходов),
--  kills — N убийств вражеских игроков (боты не считаются) с момента появления задания.
-- Прогресс и флаги выполнения хранит DataService; награду забирают кнопкой на доске (Remotes.Quests).
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local CombatService = require(Services.CombatService)
local Notifier = require(Services.Notifier)
local Guard = require(Services.RemoteGuard)

local QuestService = {}
local Q = Config.Quests
local TICK = 5            -- сек.: шаг учёта времени в игре
local groupCache = {}     -- [игрок] = {ok, t}
local notified = {}       -- [игрок] = {[id] = true}: «задание готово» уже сообщали

local function questOf(id)
	for _, q in ipairs(Q.List) do
		if q.Id == id then return q end
	end
end

local function groupEnabled()
	return (Q.GroupId or 0) > 0
end

-- состоит ли в группе. Список групп просим заново (IsInGroup кэшируется на всю сессию и не увидит
-- вступление без перезахода); результат держим 10 с, чтобы не дёргать сервис на каждое открытие
local function inGroup(player)
	if not groupEnabled() then return false end
	local c = groupCache[player]
	if c and os.clock() - c.t < 10 then return c.ok end
	local found = false
	local ok, groups = pcall(function() return GroupService:GetGroupsAsync(player.UserId) end)
	if ok and type(groups) == "table" then
		for _, g in ipairs(groups) do
			if g.Id == Q.GroupId then found = true break end
		end
	else
		local ok2, res = pcall(function() return player:IsInGroup(Q.GroupId) end)
		found = ok2 and res == true
	end
	groupCache[player] = {ok = found, t = os.clock()}
	return found
end

-- состояние задания для игрока (для доски и для проверки перед наградой)
local function stateOf(player, q)
	local done = bit32.band(DataService.get(player, "QuestDone") or 0, q.Bit) ~= 0
	local s = {id = q.Id, reward = q.Reward, done = done, locked = false}
	if q.Id == "group" then
		s.locked = not groupEnabled()
		s.groupName = Q.GroupName
		s.goal = 1
		s.progress = (done or (not s.locked and inGroup(player))) and 1 or 0
	elseif q.Id == "play" then
		s.goal = q.Goal
		s.progress = math.min(q.Goal, DataService.get(player, "PlaySec") or 0)
	else
		s.goal = q.Goal
		s.progress = math.min(q.Goal, DataService.get(player, "QuestKills") or 0)
	end
	s.ready = not done and not s.locked and s.progress >= s.goal
	return s
end

local function listFor(player)
	local list = {}
	for _, q in ipairs(Q.List) do table.insert(list, stateOf(player, q)) end
	return list
end

local function claim(player, id)
	local q = type(id) == "string" and questOf(id)
	if not q then return "Unknown quest", false end
	if q.Id == "group" then groupCache[player] = nil end -- мог только что вступить — проверяем заново
	local s = stateOf(player, q)
	if s.done then return "Already completed", false end
	if s.locked then return "This quest is not available yet", false end
	if not s.ready then
		if q.Id == "group" then return ("Join %s first (press JOIN)"):format(Q.GroupName), false end
		return "Not finished yet", false
	end
	local ok, why = DataService.completeQuest(player, q.Bit, q.Reward)
	if not ok then
		if why == "Done" then return "Already completed", false end
		if why == "Syncing" then return "Your saved data is still loading — try again in a moment", false end
		return "Data is still loading", false
	end
	require(Services.RankService).award(player, "Quest")
	task.spawn(DataService.save, player)
	return ("Quest complete! +%d gold"):format(q.Reward), true
end

-- задание стало готово — один раз напомнить про доску
local function checkReady(player, id)
	local q = questOf(id)
	if not q or not DataService.isLoaded(player) then return end
	local n = notified[player] or {}
	notified[player] = n
	if n[id] then return end
	if stateOf(player, q).ready then
		n[id] = true
		Notifier.send(player, ("Quest done! Claim +%d gold at the quest board next to the RPG stand"):format(q.Reward), "success")
	end
end

function QuestService.init()
	-- убийства для задания (CombatService зовёт при каждом засчитанном убийстве игроком)
	CombatService.onKill = function(killer)
		DataService.addProgress(killer, "QuestKills", 1)
		checkReady(killer, "kills")
	end

	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Quests").OnServerInvoke = function(player, action, id)
		-- отдельные лимиты: автообновление окна не должно мешать нажатию CLAIM
		if not Guard.allow(player, action == "claim" and "Quests" or "QuestsGet") then return {ok = false, msg = "Too fast, please wait"} end
		if not DataService.isLoaded(player) then return {ok = false, msg = "Data is still loading…"} end
		if action == "claim" then
			local msg, ok = claim(player, id)
			return {ok = ok, msg = msg, list = listFor(player)}
		end
		return {ok = true, list = listFor(player)}
	end

	-- время в игре
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, p in ipairs(Players:GetPlayers()) do
				if DataService.isLoaded(p) then
					DataService.addProgress(p, "PlaySec", TICK)
					checkReady(p, "play")
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		groupCache[p] = nil
		notified[p] = nil
	end)
end

return QuestService
