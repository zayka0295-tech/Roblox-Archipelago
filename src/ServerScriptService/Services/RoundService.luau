-- Раунды. Идут строго по таймеру (Config.Round.Duration), досрочной победы нет: иначе на пустом или
-- личном сервере раунды можно было бы «прокручивать» ради диамантов.
--  • Очки: каждые ScoreTick сек. команда получает PointsPerIsland за каждый свой остров.
--  • Конец: больше очков — победа; равно — решают убийства игроков за раунд; и тут равно — ничья.
--  • Награда: WinDiamonds каждому игроку победившей команды, который сейчас в ней
--    и отыграл за неё в этом раунде не меньше MinPlaySec (в бою, не в лобби).
--  • После конца — перерыв Intermission (баннер), затем острова сбрасываются и идёт новый раунд.
--  • Итоги: личная статистика за раунд (RankService.Action — убийства, самолёты, корабли, захваты, очки = опыт
--    за действия) и звания (Config.Round.Awards: MVP, Ace, Captain, Conqueror) с золотом — на экран итогов.
-- Состояние для клиентов — атрибуты GameState (Round_*), итог — Remotes.RoundResult.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local TeamService = require(Services.TeamService)
local CaptureService = require(Services.CaptureService)
local CombatService = require(Services.CombatService)
local Notifier = require(Services.Notifier)
local RankService = require(Services.RankService)
local BadgesService = require(Services.BadgesService)

local RoundService = {}
local R = Config.Round
local TEAMS = {"Blue", "Red"}

local GameState = ReplicatedStorage:WaitForChild("GameState")
local score = {Blue = 0, Red = 0}
local kills = {Blue = 0, Red = 0}
local played = {} -- [игрок] = {Blue = сек, Red = сек} в бою за каждую команду в этом раунде
local stats = {}  -- [игрок] = {kills, planes, sinks, caps, score} за этот раунд
-- какие действия идут в какую графу итогов (очки — за все, кроме служебных)
local STAT_OF = {Kill = "kills", BotKill = "kills", PlaneKill = "planes", Sink = "sinks", CarrierKill = "sinks", CargoKill = "sinks",
	Capture = "caps", Neutralize = "caps"}
local NO_SCORE = {PlayMinute = true, RoundWin = true, RoundLoss = true, Quest = true, Tutorial = true}
local TITLES = {{"MVP", "score"}, {"Ace", "planes"}, {"Captain", "sinks"}, {"Conqueror", "caps"}}
local roundNo = 0
local active = false
local endsAt = 0

local function now() return workspace:GetServerTimeNow() end

local function publish()
	GameState:SetAttribute("Round_Score_Blue", score.Blue)
	GameState:SetAttribute("Round_Score_Red", score.Red)
end

local function startRound()
	roundNo += 1
	for _, t in ipairs(TEAMS) do score[t], kills[t] = 0, 0 end
	played = {}
	stats = {}
	RankService.newRound()
	CaptureService.resetAll()
	active = true
	endsAt = now() + R.Duration
	GameState:SetAttribute("Round_Number", roundNo)
	GameState:SetAttribute("Round_State", "Active")
	GameState:SetAttribute("Round_EndsAt", endsAt)
	publish()
	if roundNo > 1 then
		Notifier.all(("Round %d started! Hold islands to score points"):format(roundNo), "info")
	end
end

local function winnerOf()
	if score.Blue ~= score.Red then return score.Blue > score.Red and "Blue" or "Red" end
	if kills.Blue ~= kills.Red then return kills.Blue > kills.Red and "Blue" or "Red" end
	return nil
end

local function endRound()
	active = false
	local winner = winnerOf()
	endsAt = now() + R.Intermission
	GameState:SetAttribute("Round_State", "Intermission")
	GameState:SetAttribute("Round_EndsAt", endsAt)
	GameState:SetAttribute("Round_LastWinner", winner or "Draw")
	local remote = ReplicatedStorage.Remotes:FindFirstChild("RoundResult")

	-- звания: у кого больше всех в графе (хотя бы 1), с золотом
	local titles, bonus = {}, {}
	for _, t in ipairs(TITLES) do
		local top, best = nil, 0
		for p, st in pairs(stats) do
			if p.Parent and st[t[2]] > best then top, best = p, st[t[2]] end
		end
		if top then
			local gold = R.Awards and R.Awards[t[1]] or 0
			if gold > 0 then DataService.addGold(top, gold) end
			bonus[top] = (bonus[top] or 0) + gold
			table.insert(titles, {key = t[1], name = top.DisplayName, team = TeamService.getTeamName(top), value = best, gold = gold, userId = top.UserId})
			if t[1] == "MVP" then BadgesService.award(top, "MVP") end
		end
	end
	-- таблица лучших по очкам
	local order = {}
	for p, st in pairs(stats) do
		if p.Parent then table.insert(order, {p = p, st = st}) end
	end
	table.sort(order, function(a, b) return a.st.score > b.st.score end)
	local board, place = {}, {}
	for i, e in ipairs(order) do
		place[e.p] = i
		if i <= (R.BoardSize or 5) then
			local st = e.st
			table.insert(board, {name = e.p.DisplayName, team = TeamService.getTeamName(e.p), userId = e.p.UserId,
				kills = st.kills, planes = st.planes, sinks = st.sinks, caps = st.caps, score = st.score})
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		local sec = winner and played[p] and played[p][winner] or 0
		local got = 0
		if winner and TeamService.getTeamName(p) == winner and sec >= R.MinPlaySec then
			if DataService.addDiamonds(p, R.WinDiamonds) then
				got = R.WinDiamonds
				task.spawn(DataService.save, p)
			end
			RankService.award(p, "RoundWin")
		else
			-- опыт за раунд — и проигравшим (и при ничьей), если столько же были в бою
			local rec = played[p]
			if rec and (rec.Blue or 0) + (rec.Red or 0) >= R.MinPlaySec then RankService.award(p, "RoundLoss") end
		end
		if remote then
			remote:FireClient(p, {
				winner = winner, blue = score.Blue, red = score.Red, killsBlue = kills.Blue, killsRed = kills.Red,
				diamonds = got, team = TeamService.getTeamName(p), playedSec = math.floor(sec), needSec = R.MinPlaySec,
				board = board, titles = titles, players = #order,
				me = stats[p] and {kills = stats[p].kills, planes = stats[p].planes, sinks = stats[p].sinks, caps = stats[p].caps,
					score = stats[p].score, place = place[p], bonus = bonus[p] or 0} or nil,
			})
		end
	end
end

-- только для тестов в Studio (Main → DevCommands "roundPlayed")
function RoundService.devAddPlayed(player, sec)
	local t = TeamService.getTeamName(player)
	if not RunService:IsStudio() or not (t == "Blue" or t == "Red") then return false end
	local rec = played[player] or {Blue = 0, Red = 0}
	played[player] = rec
	rec[t] += sec or 0
	return true
end

function RoundService.getState()
	return {active = active, number = roundNo, endsAt = endsAt, score = table.clone(score)}
end

function RoundService.init()
	-- убийства игроков за раунд (для ничьи по очкам); прежний обработчик (задания) сохраняем
	local prevOnKill = CombatService.onKill
	CombatService.onKill = function(killer, ...)
		if prevOnKill then prevOnKill(killer, ...) end
		local t = active and killer and TeamService.getTeamName(killer)
		if t and kills[t] then kills[t] += 1 end
	end

	-- личная статистика раунда
	RankService.Action.Event:Connect(function(p, key, xp)
		if not active then return end
		local st = stats[p]
		if not st then
			st = {kills = 0, planes = 0, sinks = 0, caps = 0, score = 0}
			stats[p] = st
		end
		local f = STAT_OF[key]
		if f then st[f] += 1 end
		if not NO_SCORE[key] then st.score += xp or 0 end
	end)

	Players.PlayerRemoving:Connect(function(p)
		played[p] = nil
		stats[p] = nil
	end)

	startRound()
	task.spawn(function()
		local acc = 0
		while true do
			local dt = task.wait(1)
			-- Studio: атрибут GameState.Round_DevEnd = true завершает раунд сразу (для проверки)
			local devEnd = RunService:IsStudio() and GameState:GetAttribute("Round_DevEnd") == true
			if devEnd then GameState:SetAttribute("Round_DevEnd", nil) end
			if active then
				-- время в бою за команду
				for _, p in ipairs(Players:GetPlayers()) do
					local t = p:GetAttribute("State") == "Deployed" and TeamService.getTeamName(p)
					if t == "Blue" or t == "Red" then
						local rec = played[p] or {Blue = 0, Red = 0}
						played[p] = rec
						rec[t] += dt
					end
				end
				-- очки за острова
				acc += dt
				if acc >= R.ScoreTick then
					acc -= R.ScoreTick
					for _, t in ipairs(TEAMS) do
						score[t] += (GameState:GetAttribute("Islands_" .. t) or 0) * R.PointsPerIsland
					end
					publish()
				end
				if now() >= endsAt or devEnd then
					endRound()
				end
			elseif now() >= endsAt or devEnd then
				acc = 0
				startRound()
			end
		end
	end)
end

return RoundService
