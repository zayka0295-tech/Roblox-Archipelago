-- Ежедневная рулетка (Config.DailySpin). Приз выбирает только сервер, клиент лишь докручивает колесо до него.
-- Remotes.DailySpin (RemoteFunction) → {ok, index, kind, amount} или {ok = false, err}.
-- Время последнего спина — поле LastSpin (os.time), атрибут игрока для таймера на кнопке.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local Guard = require(Services.RemoteGuard)

local DailySpinService = {}
local S = Config.DailySpin
local rng = Random.new()
local REVEAL = 5.7 -- сек.: сколько крутится колесо у клиента (DailySpinUI SPIN_TIME) с запасом

local function pick()
	local total = 0
	for _, pz in ipairs(S.Prizes) do total += pz.Weight end
	local r = rng:NextNumber() * total
	for i, pz in ipairs(S.Prizes) do
		r -= pz.Weight
		if r < 0 then return i end
	end
	return 1
end

function DailySpinService.init()
	ReplicatedStorage.Remotes:WaitForChild("DailySpin").OnServerInvoke = function(player)
		-- спам вызовами: отказ без обращения к профилю (клиент покажет «Spin failed — try again»)
		if not Guard.bucket(player, "DailySpin", 1, 3) then return {ok = false, err = "Busy"} end
		if not DataService.isLoaded(player) then return {ok = false, err = "NoData"} end
		local i = pick()
		local pz = S.Prizes[i]
		local ok, err = DataService.claimSpin(player, os.time(), S.Cooldown, pz.Kind, pz.Amount)
		if not ok then return {ok = false, err = err} end
		task.spawn(DataService.save, player)
		task.delay(REVEAL, DataService.sync, player, pz.Kind) -- баланс в HUD — когда колесо остановится
		return {ok = true, index = i, kind = pz.Kind, amount = pz.Amount}
	end
end

return DailySpinService
