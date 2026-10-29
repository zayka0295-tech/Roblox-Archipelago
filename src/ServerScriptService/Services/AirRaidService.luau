-- Воздушная тревога: GameState.AirRaid_<команда> = true, пока живой вражеский самолёт
-- находится над островом базы этой команды (габариты базы + Config.AirRaid.Margin, по горизонтали).
-- Сирену и маяк включает клиент (ClientMain.AirRaid).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local AirRaidService = {}
local A = Config.AirRaid or {Margin = 250, Interval = 0.5}

function AirRaidService.init()
	local GameState = ReplicatedStorage:WaitForChild("GameState")
	-- зоны баз: рамка по габаритам самого острова (считаем один раз, базы неподвижны).
	-- Верфь (причалы, буи) и зоны уходят далеко в море — с ними сирена выла бы от самолётов над водой.
	local SKIP = {Shipyard = true, Zones = true}
	local zones = {}
	for _, team in ipairs(Config.TeamOrder) do
		local base = workspace.Map.Teams:FindFirstChild(team .. "Base")
		if base then
			local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
			for _, child in ipairs(base:GetChildren()) do
				if not SKIP[child.Name] then
					for _, p in ipairs(child:GetDescendants()) do
						if p:IsA("BasePart") then
							mn = mn:Min(p.Position - p.Size / 2)
							mx = mx:Max(p.Position + p.Size / 2)
						end
					end
				end
			end
			local cf, size
			if mn.X < mx.X then
				cf, size = CFrame.new((mn + mx) / 2), mx - mn
			else
				cf, size = base:GetBoundingBox()
			end
			zones[team] = {cf = cf, half = Vector3.new(size.X / 2 + A.Margin, 0, size.Z / 2 + A.Margin)}
			GameState:SetAttribute("AirRaid_" .. team, false)
		end
	end

	local function enemyOver(team, zone)
		local planes = workspace.Map:FindFirstChild("Planes")
		if not planes then return false end
		for _, m in ipairs(planes:GetChildren()) do
			local pt = m:GetAttribute("Team")
			local root = m:FindFirstChild("Root")
			-- IsPlane = false — самолёт сбит (обломки догорают несколько секунд)
			if root and pt and pt ~= team and m:GetAttribute("IsPlane") == true then
				local lp = zone.cf:PointToObjectSpace(root.Position)
				if math.abs(lp.X) <= zone.half.X and math.abs(lp.Z) <= zone.half.Z then return true end
			end
		end
		return false
	end

	task.spawn(function()
		while true do
			for team, zone in pairs(zones) do
				local on = enemyOver(team, zone)
				local key = "AirRaid_" .. team
				if GameState:GetAttribute(key) ~= on then GameState:SetAttribute(key, on) end
			end
			task.wait(A.Interval)
		end
	end)
end

return AirRaidService
