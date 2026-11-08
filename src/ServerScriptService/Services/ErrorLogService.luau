-- Сбор ошибок с живых серверов: ошибки серверных скриптов (S), наши предупреждения вида "[Сервис] …" (W)
-- и ошибки клиентов (C, присылает ClientMain.ErrorReporter через Remotes.ClientError).
-- Одинаковые складываем (счётчик), раз в FLUSH сек. и при закрытии сервера дописываем в DataStore
-- ErrorLog_v1 (в Studio — ErrorLog_v1_Studio), ключ "d_ГГГГ-ММ-ДД" (UTC): {[текст] = {n, src, trace, ver, first, last}}.
-- В дне не больше MAX_KEYS разных ошибок (редкие вытесняются). Читать — ErrorLogService.read(дата) или из Studio.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local LogService = game:GetService("LogService")

local Services = script.Parent
local Guard = require(Services.RemoteGuard)

local ErrorLogService = {}
local FLUSH = 300
local MAX_KEYS = 150
local MAX_LEN = 300
local PER_PLAYER = 30 -- клиентских ошибок с одного игрока за сессию
-- клиентские тексты присылает клиент (можно заспамить мусором): им — не больше трети мест,
-- и при вытеснении первыми уходят они, а не ошибки сервера
local MAX_CLIENT = 50
local pendingClient = 0

local store
pcall(function()
	store = DataStoreService:GetDataStore("ErrorLog_v1" .. (RunService:IsStudio() and "_Studio" or ""))
end)

local pending = {} -- ещё не записанные: [текст] = запись
local pendingCount = 0
local sent = {} -- [игрок] = сколько ошибок прислал

-- обрезка до MAX_LEN байт без разрыва UTF-8 (битый UTF-8 DataStore не примет — и весь журнал перестанет писаться)
local function clip(s)
	s = tostring(s or "")
	if not utf8.len(s) then
		-- чаще всего битый только хвост (строку уже обрезали по байтам) — срезаем его, а не всю кириллицу в «?»
		for _ = 1, 3 do
			s = s:sub(1, -2)
			if utf8.len(s) then break end
		end
		if not utf8.len(s) then s = s:gsub("[\128-\255]", "?") end
	end
	if #s <= MAX_LEN then return s end
	s = s:sub(1, MAX_LEN)
	for _ = 1, 3 do
		if utf8.len(s) then break end
		s = s:sub(1, -2)
	end
	return s
end

local function add(kind, msg, trace, src)
	local key = kind .. "|" .. clip(msg)
	local e = pending[key]
	if e then
		e.n += 1
		e.last = os.time()
		return
	end
	if pendingCount >= MAX_KEYS then return end -- шторм разных ошибок: лишнее до следующей записи не держим
	if kind == "C" then
		if pendingClient >= MAX_CLIENT then return end
		pendingClient += 1
	end
	pendingCount += 1
	pending[key] = {n = 1, src = clip(src), trace = clip(trace), ver = game.PlaceVersion, first = os.time(), last = os.time()}
end

local function dayKey(t)
	return "d_" .. os.date("!%Y-%m-%d", t or os.time())
end

local function flush()
	if not store or pendingCount == 0 then return end
	local batch = pending
	pending, pendingCount, pendingClient = {}, 0, 0
	local ok, err = pcall(function()
		store:UpdateAsync(dayKey(), function(old)
			old = type(old) == "table" and old or {}
			for key, e in pairs(batch) do
				local o = old[key]
				if type(o) == "table" then
					o.n = (o.n or 0) + e.n
					o.last = math.max(o.last or 0, e.last)
					o.ver = math.max(o.ver or 0, e.ver)
				else
					old[key] = e
				end
			end
			-- слишком много разных — выкидываем самые редкие
			local keys = {}
			for k in pairs(old) do table.insert(keys, k) end
			if #keys > MAX_KEYS then
				table.sort(keys, function(a, b)
					local ca, cb = a:sub(1, 2) == "C|", b:sub(1, 2) == "C|"
					if ca ~= cb then return cb end -- ошибки сервера важнее клиентских
					return (old[a].n or 0) > (old[b].n or 0)
				end)
				for i = MAX_KEYS + 1, #keys do old[keys[i]] = nil end
			end
			return old
		end)
	end)
	if not ok then
		-- не записалось (лимит / нет доступа) — вернём в очередь до следующего раза
		for key, e in pairs(batch) do
			if not pending[key] and pendingCount < MAX_KEYS then
				pending[key] = e
				pendingCount += 1
				if key:sub(1, 2) == "C|" then pendingClient += 1 end
			end
		end
		if tostring(err):find("StudioAccessToApisNotAllowed", 1, true) then store = nil end
	end
end
ErrorLogService.flush = flush

-- записи за день ("ГГГГ-ММ-ДД", по умолчанию сегодня UTC)
function ErrorLogService.read(date)
	if not store then return nil end
	local ok, data = pcall(function() return store:GetAsync(date and ("d_" .. date) or dayKey()) end)
	return ok and data or nil
end

function ErrorLogService.init()
	ScriptContext.Error:Connect(function(msg, trace, scr)
		add("S", msg, trace, scr and scr:GetFullName() or "")
	end)
	-- наши предупреждения (DataService, AntiCheat, PlaneService…) пишутся с префиксом "[Имя]"
	LogService.MessageOut:Connect(function(msg, t)
		if t == Enum.MessageType.MessageWarning and msg:sub(1, 1) == "[" then add("W", msg, "", "") end
	end)

	-- init зовут первым в Main: без ClientError в Remotes бесконечный WaitForChild здесь остановил бы запуск всего сервера
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ClientError", 30)
		if not remote then
			warn("[ErrorLogService] Remotes.ClientError not found — client errors are not collected")
			return
		end
		remote.OnServerEvent:Connect(function(player, msg, trace, src)
			if type(msg) ~= "string" or (trace ~= nil and type(trace) ~= "string") or (src ~= nil and type(src) ~= "string") then return end
			if not Guard.bucket(player, "ClientError", 0.5, 5) then return end
			local n = (sent[player] or 0) + 1
			if n > PER_PLAYER then return end
			sent[player] = n
			-- огромные строки от читера не гоняем через utf8/gsub целиком: clip всё равно оставит MAX_LEN
			local cap = MAX_LEN * 2
			add("C", msg:sub(1, cap), trace and trace:sub(1, cap), src and src:sub(1, cap))
		end)
	end)
	Players.PlayerRemoving:Connect(function(p) sent[p] = nil end)

	task.spawn(function()
		while true do
			task.wait(FLUSH)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return ErrorLogService
