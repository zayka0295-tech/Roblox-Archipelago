-- Суд: голосование за изгнание игрока с сервера (плита JUDGE в лобби → JudgeUI, Remotes.Judge).
--  • Каждый игрок — один голос против конкретного игрока (можно забрать), голос сгорает через VoteTTL.
--  • Голосуют только тиммейты цели: иначе одна команда выгоняла бы сильных соперников.
--    Нужно max(MinVotes, Share от тиммейтов цели): в маленькой команде — 3, в большой — половина,
--    чтобы трое друзей не выгоняли кого хотят. Голосуют только игроки, проведшие на сервере MinPlaySec.
--    Сменил команду (автобаланс) — его голос против бывших тиммейтов больше не считается.
--  • Набралось — игрок исключён и не сможет зайти на этот сервер; случай пишется в DataStore JudgeLog_v1
--    (счётчик изгнаний по UserId — по нему видно постоянных нарушителей). Владельца игры исключить нельзя.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local Notifier = require(Services.Notifier)
local Guard = require(Services.RemoteGuard)

local JudgeService = {}
local J = Config.Judge
local votes = {}    -- [UserId цели] = {[UserId голосующего] = время}
local joinedAt = {} -- [игрок] = os.clock() входа
local banned = {}   -- [UserId] = true — исключён с этого сервера
local owners = {}   -- [UserId] = true — владелец группы, которой принадлежит игра

local store
pcall(function()
	store = DataStoreService:GetDataStore("JudgeLog_v1" .. (RunService:IsStudio() and "_Studio" or ""))
end)

local function fail(msg) return {ok = false, msg = msg} end

-- игроки команды team, кроме except
local function teammates(team, except)
	local list = {}
	if not team then return list end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= except and TeamService.getTeamName(p) == team then table.insert(list, p) end
	end
	return list
end

-- сколько голосов нужно против игрока команды team (доля — от его тиммейтов)
local function needed(team)
	local others = math.max(0, #teammates(team) - 1)
	return math.max(J.MinVotes, math.ceil(J.Share * others))
end

-- действующие голоса против игрока (сгоревшие, от ушедших и из другой команды убираем)
local function count(id)
	local v = votes[id]
	if not v then return 0 end
	if not next(v) then votes[id] = nil return 0 end
	local target = Players:GetPlayerByUserId(id)
	local team = target and TeamService.getTeamName(target)
	local now, n = os.clock(), 0
	for voter, t in pairs(v) do
		local vp = Players:GetPlayerByUserId(voter)
		if now - t > J.VoteTTL or not vp or not team or TeamService.getTeamName(vp) ~= team then v[voter] = nil else n += 1 end
	end
	return n
end

local function protected(target)
	if game.CreatorType == Enum.CreatorType.User then return target.UserId == game.CreatorId end
	return owners[target.UserId] == true
end

local function canVote(player)
	local team = TeamService.getTeamName(player)
	if not team then return false, "Join a team first" end
	if #teammates(team, player) < J.MinVotes then
		return false, ("Voting needs at least %d players on your team"):format(J.MinVotes + 1)
	end
	local left = J.MinPlaySec - (os.clock() - (joinedAt[player] or os.clock()))
	if left > 0 then return false, ("You can vote after %d s on this server"):format(math.ceil(left)) end
	return true
end

local function exile(target)
	banned[target.UserId] = true
	votes[target.UserId] = nil
	Notifier.all(("%s was voted off the server by the Judge"):format(target.DisplayName), "info")
	task.spawn(function()
		if store then
			pcall(function()
				store:UpdateAsync(tostring(target.UserId), function(old)
					old = type(old) == "table" and old or {n = 0}
					old.n = (old.n or 0) + 1
					old.last = os.time()
					old.name = target.Name
					return old
				end)
			end)
		end
	end)
	target:Kick("Players voted to remove you from this server. You can join another server.")
end

local function list(player)
	local ok, why = canVote(player)
	local team = TeamService.getTeamName(player)
	local rows = {}
	for _, p in ipairs(teammates(team, player)) do
		local v = votes[p.UserId]
		table.insert(rows, {
			id = p.UserId, name = p.DisplayName, user = p.Name, team = team,
			votes = count(p.UserId), mine = v ~= nil and v[player.UserId] ~= nil, protected = protected(p),
		})
	end
	table.sort(rows, function(a, b)
		if a.votes ~= b.votes then return a.votes > b.votes end
		return a.name:lower() < b.name:lower()
	end)
	return {ok = true, rows = rows, needed = needed(team), canVote = ok, reason = why}
end

local function vote(player, id)
	local target = type(id) == "number" and Players:GetPlayerByUserId(id)
	if not target or target == player then return fail("Player not found") end
	local team = TeamService.getTeamName(player)
	if not team or TeamService.getTeamName(target) ~= team then return fail("You can only vote on your own teammates") end
	local ok, why = canVote(player)
	if not ok then return fail(why) end
	if protected(target) then return fail("The game owner can't be voted off") end
	votes[id] = votes[id] or {}
	if votes[id][player.UserId] then
		votes[id][player.UserId] = nil
		return {ok = true, msg = "Vote withdrawn"}
	end
	votes[id][player.UserId] = os.clock()
	local n, need = count(id), needed(team)
	if n >= need then
		exile(target)
		return {ok = true, msg = target.DisplayName .. " was removed from the server"}
	end
	-- цель узнаёт, что за неё голосуют (без имён) — есть шанс исправиться
	Notifier.send(target, ("Players are voting to remove you from the server: %d/%d"):format(n, need), "error")
	return {ok = true, msg = ("Vote counted: %d/%d"):format(n, need)}
end

function JudgeService.init()
	local function joined(p)
		if banned[p.UserId] then
			p:Kick("You were voted off this server. Please join another server.")
			return
		end
		joinedAt[p] = os.clock()
		-- игра на группе: владелец и старшие ранги группы (250+, разработчики и модераторы) тоже неприкосновенны
		if game.CreatorType == Enum.CreatorType.Group then
			task.spawn(function()
				local ok, rank = pcall(function() return p:GetRankInGroup(game.CreatorId) end)
				if ok and rank >= 250 then owners[p.UserId] = true end
			end)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do joined(p) end
	Players.PlayerAdded:Connect(joined)
	Players.PlayerRemoving:Connect(function(p)
		joinedAt[p] = nil
		-- голоса против ушедшего не стираем: иначе перезашёл — и чист. Они сами сгорят через VoteTTL.
		owners[p.UserId] = nil
	end)
	ReplicatedStorage.Remotes.Judge.OnServerInvoke = function(player, action, id)
		if not Guard.bucket(player, "Judge", 2, 6) then return fail("Too fast, please wait") end
		if action == "list" then return list(player) end
		if action == "vote" then return vote(player, id) end
		return fail("Unknown action")
	end
end

return JudgeService
