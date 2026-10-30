-- Обучение у Капитана (модель Captain в Decor каждой базы, у казармы рядом с площадью).
-- Шаг хранит DataService.Tutorial:
--  0 — ещё не говорил. Разговор → задание «самолёт» (шаг 1).
--  1 — улететь на FlyDistance от места, где сел в самолёт, и вернуться к Капитану → FlyReward, шаг 2.
--  2 — то же на корабле (у штурвала) → SailReward, шаг 3: Капитан прощается, желает удачи и исчезает.
-- За каждый шаг — ещё опыт для ранга (RankService).
--  3 — пройдено: для этого игрока Капитана больше нет (прячет клиент).
-- Прогресс полёта/заплыва считает сервер и публикует атрибутами игрока TutProgress / TutReady (в пределах
-- сессии; вышел из игры — пролететь придётся заново). Реплики — Remotes.Captain (сервер → клиент).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local Notifier = require(Services.Notifier)
local RankService = require(Services.RankService)

local TutorialService = {}
local T = Config.Tutorial
local CHECK = 0.5 -- сек.: шаг проверки полёта/заплыва
-- техникой физически управляет клиент: скачок дальше этого за проверку (самолёт — 150 студ/с)
-- считаем телепортом и в прогресс не засчитываем
local MAX_STEP = 250 * CHECK

local progress = {}  -- [игрок] = {step, start = Vector3, done = bool}
local lastTalk = {}  -- [игрок] = os.clock()

local function stepOf(player)
	return DataService.get(player, "Tutorial") or 0
end

local function stateFor(player)
	local step = stepOf(player)
	local pr = progress[player]
	if not pr or pr.step ~= step then
		pr = {step = step, start = nil, done = false}
		progress[player] = pr
		player:SetAttribute("TutProgress", 0)
		player:SetAttribute("TutReady", false)
	end
	return pr, step
end

-- сидит за штурвалом нужной техники? (шаг 1 — самолёт, шаг 2 — корабль)
local function inVehicle(player, step)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.Health > 0 and hum.SeatPart
	if not seat then return nil end
	if step == 1 then
		local planes = workspace.Map:FindFirstChild("Planes")
		if seat.Name == "PilotSeat" and planes and seat:IsDescendantOf(planes) then return seat end
	elseif step == 2 then
		if seat:GetAttribute("Helm") then return seat end
	end
	return nil
end

local function goalOf(step)
	return step == 1 and T.FlyDistance or T.SailDistance
end

local function say(player, payload)
	local remote = ReplicatedStorage.Remotes:FindFirstChild("Captain")
	if remote then remote:FireClient(player, payload) end
end

local function talk(player)
	if not DataService.isLoaded(player) then return end
	if player:GetAttribute("State") ~= "Deployed" then return end
	local t = os.clock()
	if lastTalk[player] and t - lastTalk[player] < 0.6 then return end
	lastTalk[player] = t

	local pr, step = stateFor(player)
	local km = function(n) return ("%g km"):format(n / 1000) end
	if step == 0 then
		local ok = DataService.advanceTutorial(player, 0, 1, 0)
		if not ok then return end
		say(player, {step = 1, lines = {
			"Welcome aboard, soldier! I'm the Captain of this base.",
			"Before you go to war, I need to see what you're made of.",
			("First, the sky. Take a plane at the Air Terminal, fly %s out and come back to me."):format(km(T.FlyDistance)),
		}})
	elseif step == 1 or step == 2 then
		if not pr.done then
			local what = step == 1 and "Take a plane at the Air Terminal" or "Take a boat at the Shipyard"
			local verb = step == 1 and "fly" or "sail"
			say(player, {step = step, lines = {
				("%s, %s %s out and come back to me. You've done %d of %d m."):format(what, verb, km(goalOf(step)),
					math.min(goalOf(step), math.floor(player:GetAttribute("TutProgress") or 0)), goalOf(step)),
			}})
			return
		end
		if step == 1 then
			if not DataService.advanceTutorial(player, 1, 2, T.FlyReward) then return end
			RankService.award(player, "Tutorial")
			task.spawn(DataService.save, player)
			say(player, {step = 2, reward = T.FlyReward, lines = {
				"Excellent flying! You're a born pilot.",
				("Here's %d gold for the fuel."):format(T.FlyReward),
				("Now let's test you at sea. Take a boat at the Shipyard, sail %s out and come back to me."):format(km(T.SailDistance)),
			}})
		else
			if not DataService.advanceTutorial(player, 2, 3, T.SailReward) then return end
			RankService.award(player, "Tutorial")
			task.spawn(DataService.save, player)
			say(player, {step = 3, reward = T.SailReward, final = true, lines = {
				"Outstanding work. Sky or sea, you're an excellent soldier.",
				("Take %d gold, you've earned it."):format(T.SailReward),
				"I've taught you all I can. It's time for me to go.",
				"Good luck out there, soldier. Make us proud!",
			}})
		end
	end
end

function TutorialService.init()
	-- кнопка «поговорить» на каждом Капитане
	for _, base in ipairs(workspace.Map.Teams:GetChildren()) do
		local decor = base:FindFirstChild("Decor")
		local cap = decor and decor:FindFirstChild("Captain")
		local root = cap and cap:FindFirstChild("HumanoidRootPart")
		if root then
			local prompt = root:FindFirstChild("TalkPrompt") or Instance.new("ProximityPrompt")
			prompt.Name = "TalkPrompt"
			prompt.ActionText = "Talk"
			prompt.ObjectText = "Captain"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = root
			prompt.Triggered:Connect(talk)
		end
	end

	-- полёт / заплыв: считаем расстояние по горизонтали от места, где сел за штурвал
	task.spawn(function()
		while true do
			task.wait(CHECK)
			for _, p in ipairs(Players:GetPlayers()) do
				if DataService.isLoaded(p) then
					local pr, step = stateFor(p)
					if (step == 1 or step == 2) and not pr.done then
						local seat = inVehicle(p, step)
						if not seat then pr.last = nil end
						if seat then
							local pos = seat.Position
							pr.start = pr.start or pos
							if pr.last then
								local jump = Vector3.new(pos.X - pr.last.X, 0, pos.Z - pr.last.Z)
								if jump.Magnitude > MAX_STEP then pr.start += jump end -- сдвигаем старт вслед за скачком
							end
							pr.last = pos
							local d = Vector3.new(pos.X - pr.start.X, 0, pos.Z - pr.start.Z).Magnitude
							if d > (p:GetAttribute("TutProgress") or 0) then p:SetAttribute("TutProgress", math.floor(d)) end
							if d >= goalOf(step) then
								pr.done = true
								p:SetAttribute("TutReady", true)
								Notifier.send(p, "Task done! Return to the Captain at the barracks", "success")
							end
						end
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		progress[p] = nil
		lastTalk[p] = nil
	end)
end

return TutorialService
