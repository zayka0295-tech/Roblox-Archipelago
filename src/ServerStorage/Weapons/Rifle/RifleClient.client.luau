-- Клиент винтовки: только ввод и запрос выстрела. Попадание и урон считает сервер.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tool = script.Parent
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Fire = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fire")
local Config = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local COOLDOWN = Config.Combat.Rifle.Cooldown

local holding = false
local lastShot = 0

local function shoot()
	local now = os.clock()
	if now - lastShot < COOLDOWN then return end
	lastShot = now
	mouse.TargetFilter = player.Character
	Fire:FireServer(mouse.Hit.Position)
end

tool.Equipped:Connect(function()
	mouse.Icon = "rbxasset://textures/GunCursor.png"
end)
tool.Unequipped:Connect(function()
	holding = false
	mouse.Icon = ""
end)
tool.Activated:Connect(function()
	if holding then return end
	holding = true
	while holding and tool.Parent == player.Character do
		shoot()
		task.wait(COOLDOWN)
	end
	holding = false
end)
tool.Deactivated:Connect(function()
	holding = false
end)
