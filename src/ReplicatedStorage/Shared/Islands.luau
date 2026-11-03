-- Острова из Config.Islands: поиск по Id и аэродром на острове (Config.IslandAirfield).
-- Общее для сервера (SpawnService, PlaneService) и клиента — раньше каждый искал сам.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Islands = {}

-- запись острова по Id или nil
function Islands.def(id)
	for _, d in ipairs(Config.Islands) do
		if d.Id == id then return d end
	end
	return nil
end

-- остров с аэродромом (запись Config.Islands) или nil
function Islands.airfield()
	return Islands.def(Config.IslandAirfield and Config.IslandAirfield.Island)
end

-- модель взлётной полосы острова-аэродрома (Map.Neutral.<Outpost>.Airstrip) или nil
function Islands.airstrip()
	local def = Islands.airfield()
	local map = workspace:FindFirstChild("Map")
	local neutral = map and map:FindFirstChild("Neutral")
	local outpost = def and neutral and neutral:FindFirstChild(def.Outpost)
	return outpost and outpost:FindFirstChild("Airstrip")
end

return Islands
