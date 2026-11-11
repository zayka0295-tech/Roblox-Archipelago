-- Военный базар на площади базы (Decor.PlazaDecor.MilitaryBazaar): E у прилавка — окно магазина (Remotes.OpenBazaar,
-- BazaarUI), покупка — Remotes.Bazaar ("buy", id). Предметы (Config.Bazaar.Items) — за диаманты, навсегда:
-- бит в поле сохранения Items (DataService.buyItem), клиент видит купленное по атрибуту игрока Items.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local Guard = require(Services.RemoteGuard)

local BazaarService = {}

local function remote(className, name)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local function itemById(id)
	for _, it in ipairs(Config.Bazaar.Items) do
		if it.Id == id then return it end
	end
	return nil
end

local WHY = {
	Owned = "You already own this",
	NotEnough = "Not enough diamonds",
	Syncing = "Your data is still syncing — try again in a moment",
	NoData = "Data is still loading…",
}

function BazaarService.init()
	local open = remote("RemoteEvent", "OpenBazaar")
	local rf = remote("RemoteFunction", "Bazaar")
	rf.OnServerInvoke = function(player, action, id)
		if not Guard.allow(player, "Bazaar") then return {ok = false, msg = "Too fast, please wait"} end
		if action ~= "buy" or type(id) ~= "string" then return {ok = false, msg = "Unknown action"} end
		local it = itemById(id)
		if not it then return {ok = false, msg = "Unknown item"} end
		local ok, why = DataService.buyItem(player, it.Bit, it.Price)
		if not ok then return {ok = false, msg = WHY[why] or "Purchase failed"} end
		task.spawn(DataService.save, player) -- покупка за диаманты — сразу в сохранение, как и награды
		-- оружие — сразу в руки, если игрок в бою (дальше — при каждом появлении, SpawnService)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if it.Gun and player:GetAttribute("State") == "Deployed" and hum and hum.Health > 0 then
			require(Services.GunService).give(player, it.Gun)
		end
		return {ok = true, msg = ("%s bought! It's yours forever"):format(it.Name)}
	end
	-- E у прилавка на каждой базе
	for _, team in ipairs(Config.TeamOrder) do
		local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
		local plaza = base and base:FindFirstChild("Decor") and base.Decor:FindFirstChild("PlazaDecor")
		local bazaar = plaza and plaza:FindFirstChild("MilitaryBazaar")
		local counter = bazaar and bazaar:FindFirstChild("Counter")
		if counter then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BazaarPrompt"
			prompt.ActionText = "Open shop"
			prompt.ObjectText = "Military Bazaar"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 14
			prompt.RequiresLineOfSight = false
			prompt.Parent = counter
			prompt.Triggered:Connect(function(player)
				open:FireClient(player)
			end)
		else
			warn("[BazaarService] no MilitaryBazaar counter at " .. team .. "Base")
		end
	end
end

return BazaarService
