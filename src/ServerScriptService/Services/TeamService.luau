-- Команды и баланс игроков
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local TeamService = {}

function TeamService.getTeamName(who)
	if typeof(who) ~= "Instance" then return nil end
	if who:IsA("Player") then
		local t = who.Team
		if t and Config.Teams[t.Name] then return t.Name end
		return nil
	end
	local a = who:GetAttribute("Team") -- боты
	if a and Config.Teams[a] then return a end
	return nil
end

function TeamService.count(teamName)
	local t = Teams:FindFirstChild(teamName)
	return t and #t:GetPlayers() or 0
end

function TeamService.canJoin(player, teamName)
	if not Config.Teams[teamName] then return false, "BadTeam" end
	local current = TeamService.getTeamName(player)
	if current == teamName then return true end
	local target = TeamService.count(teamName) + 1
	for _, other in ipairs(Config.TeamOrder) do
		if other ~= teamName then
			local c = TeamService.count(other) - (current == other and 1 or 0)
			if target - c > Config.Balance.MaxTeamDifference then
				return false, "Unbalanced"
			end
		end
	end
	return true
end

-- команда для автораспределения: где меньше игроков (не считая самого игрока), при равенстве — случайная
function TeamService.balancedTeam(player)
	local current = TeamService.getTeamName(player)
	local best, bestN, ties = nil, math.huge, {}
	for _, name in ipairs(Config.TeamOrder) do
		local n = TeamService.count(name) - (current == name and 1 or 0)
		if n < bestN then
			best, bestN, ties = name, n, {name}
		elseif n == bestN then
			table.insert(ties, name)
		end
	end
	-- текущую команду не меняем без нужды
	if current and table.find(ties, current) then return current end
	return ties[math.random(1, #ties)] or best
end

function TeamService.assign(player, teamName)
	player.Team = Teams:FindFirstChild(teamName)
	player.Neutral = false
end

function TeamService.clear(player)
	player.Team = nil
	player.Neutral = true
end

return TeamService
