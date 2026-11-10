-- Покупки за робуксы (Developer Products). Единственный MarketplaceService.ProcessReceipt в игре.
-- Сервисы регистрируют выдачу: MonetizationService.register(productKey, fn(player) → true, если выдано).
-- Каждая покупка (PurchaseId) выдаётся один раз: факт выдачи — в DataStore Purchases_v1 (в Studio — _Studio).
-- Не выдали (игрок вышел, выдача не удалась) — NotProcessedYet: Roblox повторит, когда игрок вернётся.
-- Повтор приходит в момент входа, когда профиль ещё грузится, — поэтому загрузку ждём (PROFILE_WAIT).
-- Product ID = 0 (ещё не создан): в Studio prompt() сразу выдаёт бесплатно (тест), в игре — «скоро».
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local Notifier = require(Services.Notifier)

local MonetizationService = {}
local handlers = {} -- [productId] = fn(player) → выдано?
local byKey = {}    -- [ключ из Config.Products] = fn
-- PurchaseId, которые сейчас выдаются: выдача может ждать (причал, выбор маршрута десанта), а Roblox
-- за это время вызывает ProcessReceipt повторно — второй вызов не должен выдать ещё раз
local granting = {}
local grantedHere = {} -- выдано на этом сервере, но запись в DataStore не удалась

local store
pcall(function()
	store = DataStoreService:GetDataStore("Purchases_v1" .. (RunService:IsStudio() and "_Studio" or ""))
end)

function MonetizationService.register(key, fn)
	byKey[key] = fn
	local id = Config.Products[key]
	if id and id ~= 0 then handlers[id] = fn end
end

-- предложить покупку
function MonetizationService.prompt(player, key)
	local id = Config.Products[key]
	if not id or id == 0 then
		if RunService:IsStudio() and byKey[key] then
			Notifier.send(player, "Studio test: purchase granted for free (Product ID not set)", "info")
			task.spawn(byKey[key], player) -- выдача может ждать (десант ждёт выбора маршрута)
		else
			Notifier.send(player, "Coming soon!", "info")
		end
		return
	end
	pcall(function() MarketplaceService:PromptProductPurchase(player, id) end)
end

-- сек.: сколько ждём загрузку профиля. DataService при входе ждёт чужой замок до 60 с (LOCK_WAIT) и после
-- этого заводит профиль в любом случае — запас покрывает и повторы запросов к DataStore
local PROFILE_WAIT = 90

-- отказ вместо ожидания отложил бы выдачу до следующего входа — а там профиль точно так же ещё не загружен
local function waitProfile(player)
	local deadline = os.clock() + PROFILE_WAIT
	while not DataService.isLoaded(player) do
		if player.Parent == nil or os.clock() >= deadline then return false end
		task.wait(0.5)
	end
	return player.Parent ~= nil
end

-- проверка «уже выдано?» и выдача (вызывается под отметкой granting)
local function grantOnce(info, player, fn)
	if not waitProfile(player) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if store then
		local ok, done = pcall(function() return store:GetAsync(info.PurchaseId) end)
		if not ok then return Enum.ProductPurchaseDecision.NotProcessedYet end
		if done then return Enum.ProductPurchaseDecision.PurchaseGranted end -- уже выдано раньше
	end
	local ok, granted = pcall(fn, player)
	if not ok then
		warn("[MonetizationService] grant failed: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
	-- товар уже выдан: квитанцию закрываем в любом случае (NotProcessedYet выдал бы его второй раз),
	-- а запись пробуем сделать несколько раз
	grantedHere[info.PurchaseId] = true
	if store then
		for attempt = 1, 3 do
			local saved = pcall(function() store:SetAsync(info.PurchaseId, {u = info.PlayerId, p = info.ProductId, t = os.time()}) end)
			if saved then
				-- факт выдачи уже в DataStore — помнить его здесь больше незачем (таблица не растёт)
				grantedHere[info.PurchaseId] = nil
				break
			end
			if attempt == 3 then warn("[MonetizationService] could not record purchase " .. tostring(info.PurchaseId)) end
			task.wait(attempt)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(info)
	if granting[info.PurchaseId] then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if grantedHere[info.PurchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local fn = handlers[info.ProductId]
	if not player or not fn then return Enum.ProductPurchaseDecision.NotProcessedYet end
	-- отметка ставится ДО любых ожиданий (загрузка профиля, GetAsync): иначе два одновременных вызова по одной
	-- покупке оба прошли бы проверку, пока ждут, и выдали бы товар дважды
	granting[info.PurchaseId] = true
	local ok, decision = pcall(grantOnce, info, player, fn)
	granting[info.PurchaseId] = nil
	if not ok then
		warn("[MonetizationService] receipt error: " .. tostring(decision))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService
