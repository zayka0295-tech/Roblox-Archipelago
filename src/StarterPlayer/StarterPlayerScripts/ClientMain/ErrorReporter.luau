-- Ошибки клиентских скриптов — на сервер (ErrorLogService складывает и пишет в DataStore).
-- Каждую одинаковую — не чаще раза в REPEAT сек.: ошибка в RenderStepped иначе слала бы 60 раз в секунду.
local ScriptContext = game:GetService("ScriptContext")

local REPEAT = 60

return function(ctx)
	local remote = ctx.Remotes:WaitForChild("ClientError")
	local lastSent = {}
	ScriptContext.Error:Connect(function(msg, trace, scr)
		msg = tostring(msg)
		local t = os.clock()
		if lastSent[msg] and t - lastSent[msg] < REPEAT then return end
		lastSent[msg] = t
		remote:FireServer(msg:sub(1, 300), tostring(trace or ""):sub(1, 300), scr and scr:GetFullName() or "")
	end)
	return {}
end
