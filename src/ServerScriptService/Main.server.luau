-- Точка входа сервера: порядок инициализации сервисов
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
Players.CharacterAutoLoads = false

-- группы столкновений: самолёты проходят сквозь людей (нет «тарана» и подброса игроков)
for _, g in ipairs({"Characters", "Planes"}) do
	pcall(function() PhysicsService:RegisterCollisionGroup(g) end)
end
PhysicsService:CollisionGroupSetCollidable("Characters", "Planes", false)
pcall(function() PhysicsService:RegisterCollisionGroup("Cargo") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Weapons") end) -- лучи и взрывы оружия: видят всё, включая грузовые суда
PhysicsService:CollisionGroupSetCollidable("Cargo", "Default", false)
PhysicsService:CollisionGroupSetCollidable("Cargo", "Planes", false)
PhysicsService:CollisionGroupSetCollidable("Cargo", "Cargo", false)
PhysicsService:CollisionGroupSetCollidable("Cargo", "Characters", true)

local Services = script.Parent:WaitForChild("Services")
-- сбор ошибок — первым, чтобы ловить и ошибки запуска остальных сервисов
local ErrorLogService = require(Services.ErrorLogService)
ErrorLogService.init()
local DataService = require(Services.DataService)
local CarrierService = require(Services.CarrierService)
local CombatService = require(Services.CombatService)
local SpawnService = require(Services.SpawnService)
local LeaderboardService = require(Services.LeaderboardService)
local TurretService = require(Services.TurretService)
local PlaneService = require(Services.PlaneService)
local BotService = require(Services.BotService)
local ProjectileService = require(Services.ProjectileService)
local ShipService = require(Services.ShipService)
local TreasuryService = require(Services.TreasuryService)
local CaptureService = require(Services.CaptureService)
local LogisticsService = require(Services.LogisticsService)
local HeliService = require(Services.HeliService)
local StormService = require(Services.StormService)
local NavalWeaponsService = require(Services.NavalWeaponsService)
local AirRaidService = require(Services.AirRaidService)
local GunService = require(Services.GunService)
local QuestService = require(Services.QuestService)
local AntiCheatService = require(Services.AntiCheatService)
local RoundService = require(Services.RoundService)
local TutorialService = require(Services.TutorialService)
local DailySpinService = require(Services.DailySpinService)
local FallDamageService = require(Services.FallDamageService)
local MonetizationService = require(Services.MonetizationService)
local CargoDropService = require(Services.CargoDropService)
local DonateShipService = require(Services.DonateShipService)
local UniformService = require(Services.UniformService)
local JudgeService = require(Services.JudgeService)
local LobbyPadService = require(Services.LobbyPadService)
local PreviewService = require(Services.PreviewService)
local RankService = require(Services.RankService)
local VipService = require(Services.VipService)
local BadgesService = require(Services.BadgesService)
local RewardsService = require(Services.RewardsService)
local CareerService = require(Services.CareerService)
local BazaarService = require(Services.BazaarService)
local NavalPhysics = require(Services.NavalPhysics)

-- ошибка в init одного сервиса не должна оставить сервер без остальных (и без появления игроков ниже)
local function start(name, svc)
	local ok, err = pcall(svc.init)
	if not ok then warn(("[Main] %s.init: %s"):format(name, tostring(err))) end
end

start("DataService", DataService)
start("NavalPhysics", NavalPhysics) -- столкновения кораблей: до сервисов техники (группа столкновений «Vessels»)
start("CarrierService", CarrierService)
start("CombatService", CombatService)
start("SpawnService", SpawnService)
start("LeaderboardService", LeaderboardService)
start("TurretService", TurretService)
start("PlaneService", PlaneService)
start("ProjectileService", ProjectileService)
start("ShipService", ShipService)
start("TreasuryService", TreasuryService)
start("CaptureService", CaptureService)
start("LogisticsService", LogisticsService)
start("HeliService", HeliService) -- после LogisticsService: дополняет его CombatService.onCargoHit
start("StormService", StormService)
start("NavalWeaponsService", NavalWeaponsService)
start("AirRaidService", AirRaidService)
start("GunService", GunService)
start("QuestService", QuestService)
start("RoundService", RoundService) -- считает убийства за раунд через CombatService.onKill
start("TutorialService", TutorialService)
start("DailySpinService", DailySpinService)
start("FallDamageService", FallDamageService)
start("MonetizationService", MonetizationService)
start("CargoDropService", CargoDropService) -- регистрирует покупку ParachuteDrop
start("DonateShipService", DonateShipService) -- DonateBattleship / DonateCarrier
start("UniformService", UniformService)
start("JudgeService", JudgeService)
start("LobbyPadService", LobbyPadService)
start("PreviewService", PreviewService) -- мини-модели для HangarUI / ShopUI
start("RankService", RankService)
start("VipService", VipService)
start("BadgesService", BadgesService)
start("RewardsService", RewardsService) -- ежедневные задания, серия входов, сундуки, приглашения
start("CareerService", CareerService) -- карьерные достижения (статуя на базе)
start("BazaarService", BazaarService) -- военный базар на площади: магазин за диаманты
start("AntiCheatService", AntiCheatService)
start("BotService", BotService)

-- PlayerAdded и цикл по уже вошедшим могут сработать для одного игрока дважды — второй раз пропускаем
local handled = setmetatable({}, {__mode = "k"})
local function onPlayer(player)
	if handled[player] then return end
	handled[player] = true
	task.spawn(DataService.load, player)
	SpawnService.setupPlayer(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end

-- Только для тестов в Studio: ServerStorage.DevCommands:Invoke("gold", player, 1000)
if game:GetService("RunService"):IsStudio() then
	local dev = Instance.new("BindableFunction")
	dev.Name = "DevCommands"
	dev.OnInvoke = function(cmd, player, amount)
		if cmd == "gold" then
			return DataService.addGold(player, amount, true)
		elseif cmd == "addKill" then
			for _ = 1, amount or 1 do DataService.increment(player, "Kills") end
			return true
		elseif cmd == "playSec" then
			DataService.addProgress(player, "PlaySec", amount) -- задание «поиграть»
			return true
		elseif cmd == "questKills" then
			for _ = 1, amount or 1 do CombatService.onKill(player) end -- как засчитанное убийство
			return true
		elseif cmd == "save" then
			return DataService.save(player, false)
		elseif cmd == "carrierSpeed" then
			CarrierService.devSetpoint(player, amount) -- player = имя команды
			return true
		elseif cmd == "treasury" then
			TreasuryService.devSet(player, amount) -- player = команда
			return true
		elseif cmd == "tutorial" then
			-- поставить шаг обучения (0 — заново) и сразу сохранить
			player:SetAttribute("TutReady", false)
			local ok = DataService.advanceTutorial(player, DataService.get(player, "Tutorial"), amount or 0, 0)
			return ok and DataService.save(player, false)
		elseif cmd == "errorFlush" then
			ErrorLogService.flush() -- записать собранные ошибки сразу, а не через 5 мин
			return ErrorLogService.read()
		elseif cmd == "plane" then
			-- самолёт на старте своей базы и сразу в кресло (amount = тип, по умолчанию Fighter)
			return PlaneService.requestSpawn(player, player.Team and player.Team.Name, "Base", nil, amount or "Fighter")
		elseif cmd == "drop" then
			task.spawn(CargoDropService.drop, player, amount or "Blue") -- десант без покупки, amount = команда
			return true
		elseif cmd == "xp" then
			return DataService.addXP(player, amount) -- опыт для проверки рангов
		elseif cmd == "rewards" then
			return RewardsService.devShift(player, amount) -- amount: "newday" / "gifts" / "quests"
		elseif cmd == "career" then
			return CareerService.devAdd(player, amount) -- прибавить ко всем счётчикам карьеры
		elseif cmd == "spinReset" then
			return DataService.devSet(player, "LastSpin", 0) -- рулетка снова доступна
		elseif cmd == "roundPlayed" then
			return RoundService.devAddPlayed(player, amount) -- секунды в бою за текущую команду в этом раунде
		elseif cmd == "islandOwner" then
			return CaptureService.devSetOwner(player, amount) -- player = Id острова, amount = команда
		elseif cmd == "heliDepart" then
			return HeliService.devDepart(player) -- player = Id платформы (RigN / RigS)
		elseif cmd == "cargoDepart" then
			return LogisticsService.devDepartNow(player) -- player = Id острова
		elseif cmd == "cargoState" then
			return LogisticsService.devState()
		elseif cmd == "cargoDamage" then
			for _, st in ipairs(LogisticsService.getShips()) do
				if st.model:GetAttribute("IslandId") == player then LogisticsService.damage(st.model, amount, nil) return true end
			end
			return false
		elseif cmd == "destroyCarrier" then
			CarrierService.destroy(player, nil) -- здесь player = имя команды
			return true
		end
		return false
	end
	dev.Parent = game:GetService("ServerStorage")
end
