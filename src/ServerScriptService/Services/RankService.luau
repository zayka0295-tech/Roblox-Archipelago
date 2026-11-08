-- Ранги (косметика). Опыт начисляют другие сервисы через RankService.award(игрок, ключ Config.Ranks.XP);
-- здесь же — опыт за время в бою. Когда опыта хватает на следующий ранг, кнопка ранга у игрока
-- загорается (считает клиент по атрибутам XP / Rank), повышение он подтверждает — Remotes.Rank("confirm").
-- Remotes.XPGain(сколько, за что) — всплывающее «+100 XP» у кнопки.
-- RankService.Action (игрок, ключ, опыт без VIP, sub) — каждое засчитанное действие (и минута в бою, PlayMinute):
-- на него подписаны ежедневные задания, значки и статистика раунда.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local Notifier = require(Services.Notifier)
local Guard = require(Services.RemoteGuard)

local RankService = {}
RankService.Action = Instance.new("BindableEvent")
local RC = Config.Ranks
local REASON = {
	Kill = "Enemy eliminated", BotKill = "Enemy eliminated", PlaneKill = "Plane shot down", Sink = "Ship sunk",
	CarrierKill = "Carrier destroyed", Capture = "Island captured", Neutralize = "Island neutralized",
	Delivery = "Cargo delivered", CargoKill = "Cargo ship sunk", TruckKill = "Cargo truck destroyed",
	Quest = "Quest complete", Tutorial = "Captain's task", RoundWin = "Round won", RoundLoss = "Round played",
	PlayMinute = "Time in battle",
}

local botKills = {}   -- [игрок] = ботов с опытом в этом раунде
local victims = {}    -- [игрок] = {[жертва] = {времена убийств}}

local function isPlayer(x) return typeof(x) == "Instance" and x:IsA("Player") and x.Parent ~= nil end

-- key — ключ Config.Ranks.XP (для Sink — с типом корабля sub); mult — множитель (боты, бомбардировщик …)
function RankService.award(player, key, mult, sub)
	if not isPlayer(player) then return end
	local base = RC.XP[key]
	if type(base) == "table" then base = base[sub] end
	local n = math.floor((base or 0) * (mult or 1) + 0.5)
	if n <= 0 then return end
	RankService.Action:Fire(player, key, n, sub)
	if DataService.addXP(player, n) then
		-- DataService уже умножил для VIP — показываем итоговую цифру
		local vip = player:GetAttribute("VIP") == true
		local remote = ReplicatedStorage.Remotes:FindFirstChild("XPGain")
		if remote then remote:FireClient(player, vip and n * (Config.Vip.XPMult or 1) or n, (REASON[key] or key) .. (vip and " · VIP" or "")) end
	end
end

-- убийство (CombatService): лимит ботов за раунд и меньше опыта за повторные убийства одного игрока.
-- Возвращает, какое это убийство по счёту: ботов за раунд / этого игрока за RepeatKillWindow (для золота)
function RankService.onKill(killer, victim, victimIsBot)
	if not isPlayer(killer) then return 0 end
	if victimIsBot then
		botKills[killer] = (botKills[killer] or 0) + 1
		if botKills[killer] <= (RC.BotKillCap or 50) then RankService.award(killer, "BotKill") end
		return botKills[killer]
	end
	local now = os.clock()
	local byVictim = victims[killer] or {}
	victims[killer] = byVictim
	local list = {}
	for _, t in ipairs(byVictim[victim] or {}) do
		if now - t < (RC.RepeatKillWindow or 300) then table.insert(list, t) end
	end
	table.insert(list, now)
	byVictim[victim] = list
	RankService.award(killer, "Kill", #list >= 3 and (RC.RepeatKillMult or 0.25) or 1)
	return #list
end

-- новый раунд (RoundService)
function RankService.newRound()
	table.clear(botKills)
end

function RankService.init()
	ReplicatedStorage.Remotes:WaitForChild("Rank").OnServerInvoke = function(player, action)
		if not Guard.allow(player, "Rank") then return {ok = false, msg = "Too fast, please wait"} end
		if action ~= "confirm" then return {ok = false} end
		local rank, why = DataService.promote(player)
		if not rank then
			return {ok = false, msg = why == "NotYet" and "Not enough XP for the next rank yet" or "Data is still loading"}
		end
		task.spawn(DataService.save, player)
		local def = RC.List[rank]
		-- высокий ранг — всем на сервере
		if def.Tier >= 5 then
			Notifier.all(("%s was promoted to %s!"):format(player.DisplayName, def.Name), "info")
		end
		return {ok = true, rank = rank}
	end

	-- опыт за время в бою (не в лобби), раз в минуту — без всплывающей надписи, чтобы не мешать
	local inBattle = {}
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("State") == "Deployed" then
					inBattle[p] = (inBattle[p] or 0) + 5
					if inBattle[p] >= 60 then
						inBattle[p] -= 60
						-- ошибка у одного игрока не должна навсегда остановить цикл (опыт за время встал бы у всех)
						local ok, err = pcall(DataService.addXP, p, RC.XP.PlayMinute or 0)
						if not ok then warn("[RankService] play minute: " .. tostring(err)) end
						RankService.Action:Fire(p, "PlayMinute", RC.XP.PlayMinute or 0)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		botKills[p] = nil
		victims[p] = nil
		inBattle[p] = nil
		for _, byVictim in pairs(victims) do byVictim[p] = nil end
	end)
end

return RankService
