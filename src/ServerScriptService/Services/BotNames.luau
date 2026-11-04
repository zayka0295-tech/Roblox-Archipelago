-- Случайные ники для ботов в стиле обычных игроков Roblox (имя + цифры, два слова, нижний регистр...),
-- без мата и без слова «bot». BotNames.new(used) — ник, которого нет в used ({[ник] = true}).
local BotNames = {}

local FIRST = {"Liam", "Noah", "Ethan", "Mason", "Lucas", "Logan", "Jake", "Ryan", "Tyler", "Dylan", "Kevin", "Alex",
	"Max", "Leo", "Sam", "Owen", "Caleb", "Nathan", "Aiden", "Jayden", "Evan", "Mia", "Emma", "Ava", "Lily", "Chloe",
	"Zoe", "Ella", "Sofia", "Ruby", "Maya", "Nina", "Luna", "Daniel", "Adam", "Oscar", "Felix", "Hugo", "Marco", "Ivan",
	"Artem", "Danny", "Josh", "Ben", "Finn", "Kai", "Milo", "Theo", "Jack", "Eli"}
local ADJ = {"Silent", "Blue", "Red", "Dark", "Swift", "Lucky", "Crazy", "Epic", "Iron", "Frozen", "Golden", "Shadow",
	"Rapid", "Brave", "Sneaky", "Cosmic", "Wild", "Angry", "Happy", "Little", "Mega", "Turbo", "Night", "Storm", "Pixel",
	"Toxic", "Salty", "Fluffy", "Rusty", "Hyper", "Ninja", "Royal", "Sky", "Sea", "Neon"}
local NOUN = {"Fox", "Wolf", "Tiger", "Shark", "Eagle", "Hawk", "Panda", "Falcon", "Ghost", "Sniper", "Pilot", "Captain",
	"Rider", "Hunter", "Knight", "Dragon", "Viper", "Cobra", "Raven", "Bear", "Lion", "Gamer", "Player", "Racer",
	"Sailor", "Gunner", "Ace", "Cat", "Duck", "Potato", "Cookie", "Taco", "Noodle", "Storm", "Blaze", "Bolt"}

local rng = Random.new()
local function pick(t) return t[rng:NextInteger(1, #t)] end
local function digits()
	local r = rng:NextNumber()
	if r < 0.3 then return tostring(rng:NextInteger(2005, 2016)) end -- год рождения
	if r < 0.65 then return tostring(rng:NextInteger(1, 99)) end
	return tostring(rng:NextInteger(100, 9999))
end

local PATTERNS = {
	function() return pick(FIRST) .. digits() end,                             -- Liam2012
	function() return pick(FIRST) .. "_" .. digits() end,                      -- Emma_44
	function() return pick(ADJ) .. pick(NOUN) end,                             -- SilentFox
	function() return pick(ADJ) .. pick(NOUN) .. digits() end,                 -- CrazyShark77
	function() return string.lower(pick(ADJ) .. pick(NOUN)) .. digits() end,   -- pixelwolf09
	function() return pick(NOUN) .. pick(FIRST) end,                           -- PandaMax
	function() return string.lower(pick(FIRST)) .. "_" .. string.lower(pick(NOUN)) end, -- leo_hawk
	function() return pick(FIRST) .. pick(NOUN) .. digits() end,               -- JakeGamer123
	function() return "x" .. pick(ADJ) .. pick(NOUN) .. "x" end,               -- xEpicGhostx
}

function BotNames.new(used)
	local name
	for _ = 1, 20 do
		name = pick(PATTERNS)()
		if #name <= 20 and not (used and used[name]) then return name end
	end
	return name .. rng:NextInteger(10, 99)
end

-- ранг «как у обычного игрока»: в основном младшие звания, изредка повыше (индекс в Config.Ranks.List)
function BotNames.rank(maxRank)
	local r = rng:NextNumber()
	local v = r < 0.45 and rng:NextInteger(1, 3) or r < 0.8 and rng:NextInteger(3, 6) or r < 0.95 and rng:NextInteger(6, 9) or rng:NextInteger(9, 12)
	return math.min(v, maxRank)
end

return BotNames
