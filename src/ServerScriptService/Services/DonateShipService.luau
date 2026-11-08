-- Техника за донат (Config.Products.DonateBattleship / DonateCarrier, Config.DonateShips).
--  • Покупка на плитах лобби Battleship / Carrier (LobbyPadService): за свою (автоматическую) команду.
--  • До окна покупки проверяем, что корабль можно спустить (не брать робуксы зазря).
--  • На время окна оплаты и выдачи место бронируется (ShipService/CarrierService.reserveDonate): второй
--    покупатель, покупка из казны и боты его не займут. Отказался от оплаты / вышел — бронь снимается.
--  • Выдача: корабль у своей верфи, покупатель вступает в команду и появляется сразу за штурвалом.
--    Нельзя спустить прямо сейчас (причал занят, авианосец тонет) — ждём до GRANT_WAIT сек. в этой же сессии;
--    и только потом покупка не считается выданной, Roblox повторит при следующем заходе.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local SpawnService = require(Services.SpawnService)
local ShipService = require(Services.ShipService)
local CarrierService = require(Services.CarrierService)
local MonetizationService = require(Services.MonetizationService)
local AntiCheat = require(Services.AntiCheatService)
local Notifier = require(Services.Notifier)

local DonateShipService = {}
-- ключ плиты (атрибут Kind) → ключ товара в Config.Products
DonateShipService.Products = {Battleship = "DonateBattleship", Carrier = "DonateCarrier"}
local pendingTeam = {} -- [игрок] = команда плиты, на которой начал покупку
local held = {}        -- [игрок] = {kind, team}: действующая бронь
local PROMPT_HOLD = 90 -- сек.: бронь на время окна оплаты
local PAID_HOLD = 60   -- сек.: оплатил — держим до выдачи
local GRANT_WAIT = 60  -- сек.: сколько выдача ждёт свободного причала
local GRANT_RETRY = 3

-- nil — можно покупать, иначе причина
function DonateShipService.check(kind, team, player)
	if kind == "Carrier" then return CarrierService.donateFail(team, player) end
	return ShipService.donateFail(kind, team, player)
end

local function reserve(kind, team, player, seconds)
	local ok
	if kind == "Carrier" then
		ok = CarrierService.reserveDonate(team, player, seconds)
	else
		ok = ShipService.reserveDonate(kind, team, player, seconds)
	end
	if ok then held[player] = {kind = kind, team = team} end
	return ok
end

local function release(player)
	local h = held[player]
	held[player] = nil
	if not h then return end
	if h.kind == "Carrier" then
		CarrierService.releaseDonate(h.team, player)
	else
		ShipService.releaseDonate(h.kind, h.team, player)
	end
end

function DonateShipService.prompt(player, kind, team)
	-- место держим за покупателем, пока открыто окно оплаты
	if not reserve(kind, team, player, PROMPT_HOLD) then
		Notifier.send(player, DonateShipService.check(kind, team, player) or "Another player is buying this ship right now", "error")
		return
	end
	pendingTeam[player] = team
	MonetizationService.prompt(player, DonateShipService.Products[kind])
end

local function sitAt(seat, char, hum)
	char:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
	seat:Sit(hum)
end

local function grant(kind, player)
	local team = pendingTeam[player] or TeamService.getTeamName(player)
	if not team then
		team = TeamService.count("Blue") <= TeamService.count("Red") and "Blue" or "Red"
	end
	pendingTeam[player] = nil
	-- причал занят или авианосец ещё тонет — ждём и пробуем снова, держа бронь
	local seat, why
	local deadline, warned = os.clock() + GRANT_WAIT, false
	while player.Parent do
		reserve(kind, team, player, GRANT_RETRY * 4)
		if kind == "Carrier" then
			local model
			model, why = CarrierService.donateSpawn(player, team)
			seat = model and model:FindFirstChild("HelmSeat")
		else
			local model, st = ShipService.donateSpawn(player, kind, team)
			if model then seat = st.seat else why = st end
		end
		if seat or os.clock() >= deadline then break end
		if not warned then
			warned = true
			Notifier.send(player, (why or "Can't launch right now") .. " — your ship will launch as soon as it's possible", "info")
		end
		task.wait(GRANT_RETRY)
	end
	release(player)
	if not seat then
		Notifier.send(player, (why or "Can't launch right now") .. " — your purchase will be delivered on your next visit", "error")
		return false
	end
	local ok = SpawnService.joinAndDeploy(player, team, true, function(char, hum)
		hum:UnequipTools()
		pcall(function() player:RequestStreamAroundAsync(seat.Position, 3) end)
		if player.Character ~= char then return end
		-- корабль пропал, пока грузился персонаж: false — SpawnService поставит на обычную точку
		if not seat.Parent then return false end
		AntiCheat.grace(player)
		sitAt(seat, char, hum)
		Notifier.send(player, "You're the captain! WASD to sail.", "success")
	end)
	return ok
end

function DonateShipService.init()
	for kind, key in pairs(DonateShipService.Products) do
		MonetizationService.register(key, function(player) return grant(kind, player) end)
	end
	-- окно оплаты закрыто: не купил — бронь снимаем, купил — держим до выдачи (ProcessReceipt)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local player = Players:GetPlayerByUserId(userId)
		local h = player and held[player]
		if not h or Config.Products[DonateShipService.Products[h.kind]] ~= productId then return end
		if purchased then
			reserve(h.kind, h.team, player, PAID_HOLD)
		else
			release(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		pendingTeam[p] = nil
		release(p)
	end)
end

return DonateShipService
