-- Ошибки клиентских скриптов — на сервер (ErrorLogService складывает и пишет в DataStore).
-- Каждую одинаковую — не чаще раза в REPEAT сек.: ошибка в RenderStepped иначе слала бы 60 раз в секунду.
local ScriptContext = game:GetService("ScriptContext")

local REPEAT = 60
local MAX_SENT = 30 -- сервер (ErrorLogService.PER_PLAYER) больше за сессию всё равно не примет

return function(ctx)
	local remote = ctx.Remotes:WaitForChild("ClientError")
	local lastSent = {}
	local count = 0
	ScriptContext.Error:Connect(function(msg, trace, scr)
		if count >= MAX_SENT then return end -- и таблица lastSent не растёт от ошибок с меняющимся текстом
		msg = tostring(msg)
		local t = os.clock()
		if lastSent[msg] and t - lastSent[msg] < REPEAT then return end
		lastSent[msg] = t
		count += 1
		remote:FireServer(msg:sub(1, 300), tostring(trace or ""):sub(1, 300), scr and scr:GetFullName() or "")
	end)
	return {}
end
