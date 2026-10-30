-- Значки Roblox (Config.Badges): выдаются один раз за первое действие (RankService.Action), вход, ранг,
-- а также по вызову других сервисов (BadgesService.award). Значок с ID 0 ещё не создан — пропускается.
-- За сессию по каждому значку пробуем не больше одного раза (лимиты BadgeService).
local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local RankService = require(Services.RankService)

local BadgesService = {}
local B = Config.Badges
local tried = {} -- [игрок] = {[ключ] = true}

-- действие (ключ RankService.Action) → значок за первое такое действие
local BY_ACTION = {
	Kill = "FirstKill", BotKill = "FirstKill", PlaneKill = "FirstPlane", Sink = "FirstSink", CarrierKill = "FirstSink",
	Capture = "FirstCapture", RoundWin = "RoundWin",
}

function BadgesService.award(player, key)
	local id = B[key]
	if key == "OfficerTier" or type(id) ~= "number" or id <= 0 then return end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then return end
	local t = tried[player] or {}
	tried[player] = t
	if t[key] then return end
	t[key] = true
	task.spawn(function()
		local okHas, owned = pcall(function() return BadgeService:UserHasBadgeAsync(player.UserId, id) end)
		if okHas and owned then return end
		local ok, err = pcall(function() return BadgeService:AwardBadge(player.UserId, id) end)
		if not ok then
			t[key] = nil -- сбой сервиса — попробуем при следующем случае
			warn(("[BadgesService] %s: %s"):format(key, tostring(err)))
		end
	end)
end

local function checkRank(player, rank)
	local def = Config.Ranks.List[rank or 0]
	if def and def.Tier >= (B.OfficerTier or 99) then BadgesService.award(player, "Officer") end
end

function BadgesService.init()
	RankService.Action.Event:Connect(function(player, key)
		local b = BY_ACTION[key]
		if b then BadgesService.award(player, b) end
	end)
	DataService.Loaded.Event:Connect(function(player)
		BadgesService.award(player, "Welcome")
		checkRank(player, DataService.get(player, "Rank"))
	end)
	DataService.StatChanged.Event:Connect(function(player, field, value)
		if field == "Rank" then checkRank(player, value) end
	end)
	Players.PlayerRemoving:Connect(function(p) tried[p] = nil end)
end

return BadgesService
