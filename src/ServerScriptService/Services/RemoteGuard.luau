-- Защита Remote от спама: минимальный интервал между вызовами одного игрока
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Guard = {}
local last = {}

function Guard.allow(player, key)
	local limit = Config.RateLimits[key] or 0.5
	local now = os.clock()
	local t = last[player]
	if not t then
		t = {}
		last[player] = t
	end
	if t[key] and now - t[key] < limit then
		return false
	end
	t[key] = now
	return true
end

-- частые управляющие события (штурвал, гашетка): token bucket — rate событий/с в среднем, burst подряд.
-- Обычный клиент шлёт меньше и не замечает ограничения; лишнее просто отбрасываем.
local buckets = {}
function Guard.bucket(player, key, rate, burst)
	local now = os.clock()
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local b = pb[key]
	if not b then
		b = {tokens = burst, t = now}
		pb[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.t) * rate)
	b.t = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
	buckets[player] = nil
end)

return Guard
