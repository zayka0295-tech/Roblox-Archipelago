-- Командная казна. Из неё покупается командная техника (авианосец, линкоры, в будущем — другая).
-- Пополняется доставками с островов, пассивным доходом базы и бонусами за крупные победы.
-- Живёт в пределах сервера; состояние видно клиентам через GameState (Treasury_Blue / Treasury_Red).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local Notifier = require(Services.Notifier)

local TreasuryService = {}
local GameState = ReplicatedStorage:WaitForChild("GameState")
local T = Config.Treasury or {}
local balance = {}

local function publish(team)
	GameState:SetAttribute("Treasury_" .. team, math.floor(balance[team] or 0))
end

function TreasuryService.get(team)
	return balance[team] or 0
end

function TreasuryService.add(team, amount, reason)
	if not balance[team] or amount <= 0 then return end
	balance[team] += amount
	publish(team)
	if reason then
		Notifier.team(team, ("Treasury +%d · %s"):format(amount, reason), "info")
	end
end

-- списать, если хватает; возвращает true/false (атомарно — без await между проверкой и списанием)
function TreasuryService.spend(team, amount)
	if not balance[team] or balance[team] < amount then return false end
	balance[team] -= amount
	publish(team)
	return true
end

-- вернуть деньги, если покупка не удалась
function TreasuryService.refund(team, amount)
	if balance[team] then
		balance[team] += amount
		publish(team)
	end
end

-- только для тестов в Studio
function TreasuryService.devSet(team, amount)
	if balance[team] then
		balance[team] = amount
		publish(team)
	end
end

-- стартовая казна (Studio: Config.Dev.StudioTreasury, 0 — выключено)
local function startAmount()
	local studio = game:GetService("RunService"):IsStudio() and Config.Dev and Config.Dev.StudioTreasury
	if studio and studio > 0 then return studio end
	return T.Start or 0
end

-- новый раунд (RoundService): казна каждой команды — снова стартовая
function TreasuryService.reset()
	for _, team in ipairs(Config.TeamOrder) do
		balance[team] = startAmount()
		publish(team)
	end
end

function TreasuryService.init()
	TreasuryService.reset()
	local every = T.PassiveInterval or 30
	local amount = T.PassiveAmount or 0
	if amount > 0 then
		task.spawn(function()
			while true do
				task.wait(every)
				for _, team in ipairs(Config.TeamOrder) do
					balance[team] += amount
					publish(team)
				end
			end
		end)
	end
end

return TreasuryService
