-- Предупреждения владельцу брошенной техники: за Config.AbandonWarn сек (60 / 30 / 10 / 3) до самоуничтожения
-- пустого самолёта или корабля. Вернулся на борт после предупреждения — «техника в безопасности».
-- Состояние — поля техники st.abandonT (когда опустела, nil — на борту кто-то есть) и st.warned (сколько отметок уже прошло).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)
local Notifier = require(script.Parent.Notifier)

local AbandonTimer = {}
local WARN = Config.AbandonWarn

-- name — как назвать технику в тексте («plane», «gunboat»), despawn — через сколько сек самоуничтожение
function AbandonTimer.check(st, name, despawn, now)
	if not st.abandonT then
		if (st.warned or 0) > 0 then
			Notifier.send(st.owner, ("Back aboard — your %s is safe"):format(name), "success")
		end
		st.warned = nil
		return
	end
	local left = despawn - (now - st.abandonT)
	local passed = 0
	for i, mark in ipairs(WARN) do
		if left <= mark then passed = i end
	end
	if passed > (st.warned or 0) then
		Notifier.send(st.owner, ("Your %s is empty — it self-destructs in %d s! Get back aboard"):format(name, math.max(1, math.ceil(left))),
			WARN[passed] <= 10 and "error" or "info")
	end
	-- таймер сбросился (на борт сел стрелок) — отметки отсчитываются заново
	st.warned = passed
end

return AbandonTimer
