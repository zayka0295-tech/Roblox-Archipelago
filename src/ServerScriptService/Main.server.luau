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

DataService.init()
CarrierService.init()
CombatService.init()
SpawnService.init()
LeaderboardService.init()
TurretService.init()
PlaneService.init()
ProjectileService.init()
ShipService.init()
TreasuryService.init()
CaptureService.init()
LogisticsService.init()
NavalWeaponsService.init()
AirRaidService.init()
GunService.init()
QuestService.init()
RoundService.init() -- после QuestService: дополняет его CombatService.onKill
TutorialService.init()
DailySpinService.init()
FallDamageService.init()
MonetizationService.init()
CargoDropService.init() -- регистрирует покупку ParachuteDrop
DonateShipService.init() -- DonateBattleship / DonateCarrier
UniformService.init()
JudgeService.init()
LobbyPadService.init()
PreviewService.init() -- мини-модели для HangarUI / ShopUI
RankService.init()
VipService.init()
AntiCheatService.init()
BotService.init()

local function onPlayer(player)
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
		elseif cmd == "drop" then
			task.spawn(CargoDropService.drop, player, amount or "Blue") -- десант без покупки, amount = команда
			return true
		elseif cmd == "xp" then
			return DataService.addXP(player, amount) -- опыт для проверки рангов
		elseif cmd == "spinReset" then
			return DataService.devSet(player, "LastSpin", 0) -- рулетка снова доступна
		elseif cmd == "roundPlayed" then
			return RoundService.devAddPlayed(player, amount) -- секунды в бою за текущую команду в этом раунде
		elseif cmd == "islandOwner" then
			return CaptureService.devSetOwner(player, amount) -- player = Id острова, amount = команда
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
