-- Уведомления игрокам (тосты на клиенте)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")

local Config = require(ReplicatedStorage.Config.GameConfig)

local Notifier = {}

-- у VIP золото за бой удваивает DataService.addGold, а текст с суммой составляет тот, кто начислил:
-- «+N gold» и «you +N» переписываем на фактическую сумму с пометкой VIP
local function vipText(player, text)
	local m = Config.Vip and Config.Vip.GoldMult or 1
	if type(text) ~= "string" or m == 1 or player:GetAttribute("VIP") ~= true then return text end
	local function dbl(n) return ("+%d"):format(tonumber(n) * m) end
	local out = text:gsub("%+(%d+) gold", function(n) return dbl(n) .. " gold (VIP ×" .. m .. ")" end)
	out = out:gsub("you %+(%d+)", function(n) return "you " .. dbl(n) .. " (VIP ×" .. m .. ")" end)
	return out
end

function Notifier.send(player, text, kind)
	if typeof(player) == "Instance" and player:IsA("Player") and player.Parent then
		Notify:FireClient(player, vipText(player, text), kind or "info")
	end
end

function Notifier.team(teamName, text, kind)
	local team = Teams:FindFirstChild(teamName)
	if not team then return end
	for _, p in ipairs(team:GetPlayers()) do
		Notifier.send(p, text, kind)
	end
end

function Notifier.all(text, kind)
	Notify:FireAllClients(text, kind or "info")
end

return Notifier
