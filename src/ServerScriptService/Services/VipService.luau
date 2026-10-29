-- VIP (геймпасс Config.Vip.GamepassId). Владение проверяем при входе и после покупки и публикуем
-- атрибутом игрока VIP = true. По нему: DataService.addGold и RankService.award умножают награду, Notifier
-- пишет в уведомлении удвоенную сумму, клиенты рисуют корону и тег [VIP] (RankTags, VipChat, LeaderboardUI).
-- Купить — золотая плита VIP в лобби (LobbyPadService → VipService.prompt).
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Notifier = require(script.Parent.Notifier)

local VipService = {}
local V = Config.Vip

function VipService.isVip(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player:GetAttribute("VIP") == true
end

-- золотые искры вокруг персонажа VIP (видны всем, ненавязчиво)
local function sparkle(char)
	local hrp = char and char:WaitForChild("HumanoidRootPart", 10)
	if not hrp or hrp:FindFirstChild("VipSparkles") then return end
	local e = Instance.new("ParticleEmitter")
	e.Name = "VipSparkles"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(255, 215, 90))
	e.LightEmission = 1
	e.Rate = 3
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})
	e.Transparency = NumberSequence.new(0.2)
	e.Parent = hrp
end

local function grant(player, bought)
	if not player.Parent or player:GetAttribute("VIP") then return end
	player:SetAttribute("VIP", true)
	if player.Character then task.spawn(sparkle, player.Character) end
	player.CharacterAdded:Connect(sparkle)
	if bought then
		Notifier.send(player, ("VIP activated! ×%d XP and ×%d gold from now on"):format(V.XPMult, V.GoldMult), "success")
		Notifier.all(("👑 %s is now VIP!"):format(player.DisplayName), "info")
	end
end

local function check(player)
	if V.GamepassId == 0 then return end
	for _ = 1, 3 do
		local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, V.GamepassId) end)
		if ok then
			if owns then
				grant(player, false)
				Notifier.all(("👑 VIP %s joined the battle!"):format(player.DisplayName), "info")
			end
			return
		end
		task.wait(2)
	end
end

-- плита VIP в лобби
function VipService.prompt(player)
	if VipService.isVip(player) then
		Notifier.send(player, ("You're already VIP — enjoy ×%d XP and gold!"):format(V.XPMult), "success")
		return
	end
	if V.GamepassId == 0 then
		if RunService:IsStudio() then
			Notifier.send(player, "Studio test: VIP granted for this session (Gamepass ID not set)", "info")
			grant(player, true)
		else
			Notifier.send(player, "VIP is coming soon!", "info")
		end
		return
	end
	pcall(function() MarketplaceService:PromptGamePassPurchase(player, V.GamepassId) end)
end

function VipService.init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, purchased)
		if purchased and id == V.GamepassId then grant(player, true) end
	end)
	Players.PlayerAdded:Connect(check)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(check, p) end
end

return VipService
