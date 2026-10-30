-- Сохранение прогресса: Gold, Kills, Deaths, задания доски (PlaySec, QuestKills, QuestDone — биты
-- выполненных заданий), Diamonds (премиальная валюта), Tutorial (шаг обучения у Капитана),
-- XP и Rank (подтверждённый ранг, 1..#Config.Ranks.List), награды RewardsService: ежедневные задания (DQDay — день набора,
-- DQ1..DQ3 — прогресс, DQDone — биты забранных + бонус), серия входов (Streak, StreakLast — день последней награды),
-- сундуки за время (GiftDay, GiftSec, GiftDone — биты), Flags (биты разовых событий) и Invites (приглашённые друзья).
-- Diamonds, Tutorial, XP и Rank не в leaderstats — клиенты читают их из атрибутов игрока (Rank — и чужие, для значка над головой).
-- Все изменения только через этот модуль.
--
-- Защита от потери данных при переходе между серверами: профиль в DataStore помечается замком сессии
-- _lock = {job, session, t}. У каждой загрузки — свой токен session (GUID).
--  • Писать и снимать замок может только сессия-владелец: точное совпадение токена. Нет замка = владение
--    потеряно (профиль уже освобождён или забран), такая запись не выполняется.
--  • Чужой действующий замок (моложе LOCK_TTL) никогда не отбирается: ждём до LOCK_WAIT, затем сессия идёт
--    без сохранения и в фоне пробует забрать профиль. Так же при ошибке DataStore во время загрузки.
--    Пока идёт попытка (adopting) — покупки запрещены: заработанное потом переносится в сохранение,
--    и потратить временный баланс нельзя. Если профиль так и не получен (или сервиса DataStore
--    нет вовсе) — сессия целиком временная: ничего из неё не сохраняется и не переносится, покупки на временном
--    балансе разрешены (они ни на что постоянное не влияют).
--  • Сохранения одного игрока выполняются строго по очереди; финальное (release) — последнее, после него
--    профиль закрыт и никакая запись уже не начнётся.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)
local Notifier = require(script.Parent.Notifier)

local DataService = {}
DataService.StatChanged = Instance.new("BindableEvent")
DataService.Loaded = Instance.new("BindableEvent")

local profiles = {}
local store, killsStore
do
	local ok, err = pcall(function()
		-- в Studio — отдельные тестовые хранилища: тестовое золото и прогресс не попадут в живую игру
		local suffix = game:GetService("RunService"):IsStudio() and "_Studio" or ""
		store = DataStoreService:GetDataStore(Config.Data.PlayerStore .. suffix)
		killsStore = DataStoreService:GetOrderedDataStore(Config.Data.LeaderboardStore .. suffix)
	end)
	if not ok then
		store, killsStore = nil, nil
		warn("[DataService] DataStore unavailable: " .. tostring(err))
	end
end
DataService.KillsStore = killsStore

local FIELDS = {"Gold", "Kills", "Deaths", "PlaySec", "QuestKills", "QuestDone", "Diamonds", "Tutorial", "LastSpin", "XP", "Rank",
	"DQDay", "DQ1", "DQ2", "DQ3", "DQDone", "Streak", "StreakLast", "GiftDay", "GiftSec", "GiftDone", "Flags", "Invites"}
-- при слиянии с профилем, забранным позже (adoptLater): битовые поля объединяем, дни и счётчики наград — берём больший
local BIT_FIELDS = {QuestDone = true, DQDone = true, GiftDone = true, Flags = true}
local MAX_FIELDS = {Tutorial = true, LastSpin = true, Rank = true, DQDay = true, DQ1 = true, DQ2 = true, DQ3 = true,
	Streak = true, StreakLast = true, GiftDay = true, GiftSec = true, Invites = true}
local ATTR_FIELDS = {Diamonds = true, Tutorial = true, LastSpin = true, XP = true, Rank = true} -- публикуются атрибутами игрока
local LOCK_TTL = 180   -- сек.: замок старше этого считается брошенным (сервер упал)
local LOCK_WAIT = 60   -- сек.: столько ждём освобождения чужого замка при входе
local LOCK_POLL = 5    -- сек.: как часто проверяем при входе
local ADOPT_POLL = 10  -- сек.: как часто пробуем забрать профиль в фоне
local REFRESH = 90     -- сек.: продление замка, даже если данные не менялись

local function defaults()
	return {Gold = Config.Economy.StartGold, Kills = 0, Deaths = 0, PlaySec = 0, QuestKills = 0, QuestDone = 0, Diamonds = 0, Tutorial = 0, LastSpin = 0, XP = 0, Rank = 1,
		DQDay = 0, DQ1 = 0, DQ2 = 0, DQ3 = 0, DQDone = 0, Streak = 0, StreakLast = 0, GiftDay = 0, GiftSec = 0, GiftDone = 0, Flags = 0, Invites = 0}
end

local function key(player)
	return "u_" .. player.UserId
end

-- Studio без доступа к API (Game Settings → Security): объект хранилища создаётся, но каждый запрос падает с 403
-- StudioAccessToApisNotAllowed. Это не временный сбой: ждать бессмысленно, сессии сразу временные.
local function studioNoApi(err)
	if not game:GetService("RunService"):IsStudio() then return false end
	local s = tostring(err)
	-- код ошибки только в начале сообщения («403: …»), а не где угодно: иначе сработает на номер строки или имя
	return s:find("StudioAccessToApisNotAllowed", 1, true) ~= nil or s:match("^%s*403%s*:") ~= nil
		or s:lower():find("api access is not enabled", 1, true) ~= nil
end

local function retry(fn, tries)
	local ok, res
	for i = 1, tries or 3 do
		ok, res = pcall(fn)
		if ok then return true, res end
		if i < (tries or 3) then task.wait(1.5 * i) end
	end
	return false, res
end

local function syncStat(player, field)
	local p = profiles[player]
	if not p then return end
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild(field)
	if v then v.Value = p.data[field] end
	if ATTR_FIELDS[field] then player:SetAttribute(field, p.data[field]) end
	DataService.StatChanged:Fire(player, field, p.data[field])
end

-- замок принадлежит этой сессии? (точное совпадение токена и сервера)
local function ownsLock(lock, session)
	return type(lock) == "table" and lock.session == session and lock.job == game.JobId
end
-- замок мешает этой сессии? (свободен, наш, истёк или старого формата с этого же сервера — не мешает)
local function blockedBy(lock, session)
	if type(lock) ~= "table" then return false end
	if ownsLock(lock, session) then return false end
	if os.time() - (lock.t or 0) >= LOCK_TTL then return false end
	if lock.session == nil and lock.job == game.JobId then return false end -- замок старой версии модуля с этого сервера
	return true
end

-- читает данные и ставит замок этой сессии; "locked", если профиль держит другая живая сессия
local function claim(player, session)
	local result
	store:UpdateAsync(key(player), function(old)
		old = type(old) == "table" and old or {}
		if blockedBy(old._lock, session) then
			result = "locked"
			return nil -- ничего не меняем
		end
		old._lock = {job = game.JobId, session = session, t = os.time()}
		result = old
		return old
	end)
	return result
end

-- снять только СВОЙ замок (данные не трогаем) — для сессий, которые успели забрать профиль уже после выхода игрока
local function releaseOwn(player, session)
	pcall(function()
		store:UpdateAsync(key(player), function(old)
			if type(old) ~= "table" or not ownsLock(old._lock, session) then return nil end
			old._lock = nil
			return old
		end)
	end)
end

local function readFields(raw)
	local data = defaults()
	if type(raw) == "table" then
		for _, f in ipairs(FIELDS) do
			if type(raw[f]) == "number" and raw[f] == raw[f] then
				data[f] = math.max(0, math.floor(raw[f]))
			end
		end
	end
	data.Rank = math.clamp(data.Rank, 1, #Config.Ranks.List)
	return data
end

local function applyDevGold(data)
	local devGold = Config.Dev and Config.Dev.StudioGold or 0
	if devGold > 0 and game:GetService("RunService"):IsStudio() then
		data.Gold = math.max(data.Gold, devGold)
	end
end

-- профиль ещё нужен этой сессии? (игрок на сервере, профиль тот же, не закрывается)
local function stillOwner(player, p)
	return player.Parent ~= nil and profiles[player] == p and not p.closing
end

-- фон: профиль занят — пробуем забрать, пока чужой замок не истечёт; затем включаем сохранение
local function adoptLater(player, p)
	task.spawn(function()
		local deadline = os.clock() + LOCK_TTL + 15
		while stillOwner(player, p) and os.clock() < deadline do
			task.wait(ADOPT_POLL)
			if not stillOwner(player, p) then return end
			if not store then break end -- хранилище отключено (Studio без API) — ждать нечего
			local ok, res = retry(function() return claim(player, p.session) end, 2)
			if not ok and studioNoApi(res) then
				-- Studio без доступа к API: хранилище выключаем для всех, сессия временная (другие фоновые попытки
				-- увидят это на своём следующем шаге)
				warn("[DataService] Studio has no API access (Game Settings → Security → Enable Studio Access to API Services) — test session without saving")
				store, killsStore = nil, nil
				break
			end
			if ok and res ~= "locked" then
				-- claim уступает управление: игрок мог выйти, пока шла запись — тогда сразу отдаём замок
				if not stillOwner(player, p) then
					releaseOwn(player, p.session)
					return
				end
				-- сохранённое + заработанное без сохранения (покупки в это время были запрещены)
				local stored = readFields(res)
				for _, f in ipairs(FIELDS) do
					if BIT_FIELDS[f] then
						stored[f] = bit32.bor(stored[f], p.data[f]) -- флаги объединяем, а не складываем
					elseif MAX_FIELDS[f] then
						stored[f] = math.max(stored[f], p.data[f]) -- шаг обучения и ранг — дальний из двух; спин — поздний
					else
						stored[f] += math.max(0, p.data[f] - p.base[f])
					end
				end
				stored.Gold = math.min(Config.Economy.MaxGold, stored.Gold)
				stored.Diamonds = math.min(Config.Diamonds.Max, stored.Diamonds)
				applyDevGold(stored)
				p.data, p.canSave, p.adopting, p.dirty, p.lockRefresh = stored, true, false, true, os.clock()
				for _, f in ipairs(FIELDS) do syncStat(player, f) end
				player:SetAttribute("DataPersistent", true)
				Notifier.send(player, "Your saved progress is loaded — saving is back on", "success")
				return
			end
		end
		-- так и не получили: сессия остаётся временной (ничего не сохранится и не перенесётся) — покупки снова можно
		if stillOwner(player, p) and p.adopting then
			p.adopting = false
			warn(("[DataService] %s: saved profile could not be loaded — session stays temporary"):format(player.Name))
			Notifier.send(player, "Saving is unavailable right now — progress from this session won't be saved", "error")
		end
	end)
end

function DataService.load(player)
	if profiles[player] then return end
	local session = HttpService:GenerateGUID(false)
	local raw, canSave, locked, failed = nil, false, false, false
	if store then
		local t0 = os.clock()
		while true do
			local ok, res = retry(function() return claim(player, session) end, 2)
			if ok and res ~= "locked" then
				raw, canSave, locked = res, true, false
				break
			elseif ok then
				-- прошлый сервер ещё сохраняет игрока — ждём, но замок не отбираем
				locked = true
				if os.clock() - t0 >= LOCK_WAIT or not player.Parent then break end
				task.wait(LOCK_POLL)
			elseif studioNoApi(res) then
				-- Studio без доступа к API: дальше DataStore не трогаем, сессии временные, покупки доступны сразу
				warn("[DataService] Studio has no API access (Game Settings → Security → Enable Studio Access to API Services) — test session without saving")
				store, killsStore = nil, nil
				break
			else
				warn(("[DataService] failed to load %s: %s. Retrying in the background; saving stays off until the profile is loaded."):format(player.Name, tostring(res)))
				failed = true
				break
			end
		end
	end
	if not player.Parent then
		-- вышел, пока загружались: если замок успели поставить — снимаем
		if canSave then releaseOwn(player, session) end
		return
	end

	local data = readFields(raw)
	applyDevGold(data)
	local p = {
		data = data, canSave = canSave, dirty = false, lockRefresh = os.clock(), session = session,
		base = table.clone(data), adopting = (locked or failed) and not canSave,
		saving = false, closing = false, closed = false,
	}
	profiles[player] = p

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, f in ipairs({"Kills", "Deaths", "Gold"}) do
		local v = Instance.new("IntValue")
		v.Name = f
		v.Value = data[f]
		v.Parent = ls
	end
	ls.Parent = player

	for f in pairs(ATTR_FIELDS) do player:SetAttribute(f, data[f]) end
	player:SetAttribute("DataPersistent", canSave)
	player:SetAttribute("DataLoaded", true)
	DataService.Loaded:Fire(player)
	if p.adopting then
		if locked then
			warn(("[DataService] %s: profile still locked by another server after %d s — session runs without saving"):format(player.Name, LOCK_WAIT))
			Notifier.send(player, "Your data is still being saved on another server. Purchases are paused for a moment — your progress will load shortly.", "error")
		else
			Notifier.send(player, "Couldn't load your saved data yet — retrying. Purchases are paused for a moment.", "error")
		end
		adoptLater(player, p)
	end
end

function DataService.isLoaded(player)
	return profiles[player] ~= nil
end

function DataService.get(player, field)
	local p = profiles[player]
	return p and p.data[field]
end

local function validAmount(n)
	return type(n) == "number" and n > 0 and n == math.floor(n) and n < 1e12
end

-- золото за бой: у VIP (атрибут VIP, VipService) — ×Config.Vip.GoldMult; raw = true — без множителя
-- (возврат денег, тестовые команды)
function DataService.addGold(player, amount, raw)
	if not validAmount(amount) then return false end
	local p = profiles[player]
	if not p then return false end
	if not raw and player:GetAttribute("VIP") == true then amount *= (Config.Vip and Config.Vip.GoldMult or 1) end
	p.data.Gold = math.min(Config.Economy.MaxGold, p.data.Gold + amount)
	p.dirty = true
	syncStat(player, "Gold")
	return true
end

function DataService.addDiamonds(player, amount)
	if not validAmount(amount) then return false end
	local p = profiles[player]
	if not p then return false end
	p.data.Diamonds = math.min(Config.Diamonds.Max, p.data.Diamonds + amount)
	p.dirty = true
	syncStat(player, "Diamonds")
	return true
end

-- шаг обучения: только с текущего from на to, с наградой золотом — одним шагом без yield
-- (дважды не получить). Пока профиль грузится с другого сервера (adopting) — нельзя.
function DataService.advanceTutorial(player, from, to, reward)
	local p = profiles[player]
	if not p then return false, "NoData" end
	if p.adopting then return false, "Syncing" end
	if p.data.Tutorial ~= from then return false, "Step" end
	p.data.Tutorial = to
	if reward and reward > 0 then p.data.Gold = math.min(Config.Economy.MaxGold, p.data.Gold + reward) end
	p.dirty = true
	syncStat(player, "Tutorial")
	syncStat(player, "Gold")
	return true
end

-- ежедневный спин: проверка кулдауна, отметка времени и приз — одним шагом без yield (дважды не крутить).
-- Пока профиль грузится с другого сервера (adopting) — нельзя: там спин мог быть уже сделан.
-- Баланс игроку не показываем сразу (иначе приз виден до остановки колеса) — потом DataService.sync.
function DataService.claimSpin(player, now, cooldown, kind, amount)
	local p = profiles[player]
	if not p then return false, "NoData" end
	if p.adopting then return false, "Syncing" end
	if now - p.data.LastSpin < cooldown then return false, "Cooldown" end
	if not validAmount(amount) or (kind ~= "Gold" and kind ~= "Diamonds") then return false, "Prize" end
	p.data.LastSpin = now
	local max = kind == "Gold" and Config.Economy.MaxGold or Config.Diamonds.Max
	p.data[kind] = math.min(max, p.data[kind] + amount)
	p.dirty = true
	syncStat(player, "LastSpin")
	return true
end

-- опыт для рангов (начисляет RankService)
function DataService.addXP(player, amount)
	if not validAmount(amount) then return false end
	local p = profiles[player]
	if not p then return false end
	if player:GetAttribute("VIP") == true then amount *= (Config.Vip and Config.Vip.XPMult or 1) end -- VIP: ×2 опыт
	p.data.XP += amount
	p.dirty = true
	syncStat(player, "XP")
	return true
end

-- подтвердить повышение: ровно на один ранг, если опыта хватает (без yield). Возвращает новый ранг.
function DataService.promote(player)
	local p = profiles[player]
	if not p then return nil, "NoData" end
	local nextDef = Config.Ranks.List[p.data.Rank + 1]
	if not nextDef or p.data.XP < nextDef.XP then return nil, "NotYet" end
	p.data.Rank += 1
	p.dirty = true
	syncStat(player, "Rank")
	return p.data.Rank
end

-- показать игроку текущее значение поля (leaderstats / атрибут)
function DataService.sync(player, field)
	syncStat(player, field)
end

-- только для тестов в Studio (DevCommands): поставить числовое поле напрямую
function DataService.devSet(player, field, value)
	if not game:GetService("RunService"):IsStudio() then return false end
	local p = profiles[player]
	if not p or p.data[field] == nil or type(value) ~= "number" then return false end
	p.data[field] = value
	p.dirty = true
	syncStat(player, field)
	return true
end

-- без yield: проверка и списание атомарны.
-- Пока профиль ждёт освобождения на другом сервере, тратить нельзя: временный баланс не попадёт в сохранение.
function DataService.spendGold(player, amount)
	if not validAmount(amount) then return false, "Invalid" end
	local p = profiles[player]
	if not p then return false, "NoData" end
	if p.adopting then return false, "Syncing" end
	if p.data.Gold < amount then return false, "NotEnough" end
	p.data.Gold -= amount
	p.dirty = true
	syncStat(player, "Gold")
	return true
end

function DataService.increment(player, field)
	if field ~= "Kills" and field ~= "Deaths" then return end
	local p = profiles[player]
	if not p then return end
	p.data[field] += 1
	p.dirty = true
	syncStat(player, field)
end

-- прогресс заданий: время в игре (сек.) и убийства для задания
function DataService.addProgress(player, field, n)
	if field ~= "PlaySec" and field ~= "QuestKills" then return end
	if type(n) ~= "number" or n <= 0 or n ~= math.floor(n) then return end
	local p = profiles[player]
	if not p then return end
	p.data[field] += n
	p.dirty = true
	syncStat(player, field)
end

-- задание выполнено: ставим флаг и начисляем награду одним шагом (без yield — дважды не получить).
-- Пока профиль не загружен с другого сервера (adopting), нельзя: там задание могло быть уже выполнено.
function DataService.completeQuest(player, bit, reward)
	local p = profiles[player]
	if not p then return false, "NoData" end
	if p.adopting then return false, "Syncing" end
	if bit32.band(p.data.QuestDone, bit) ~= 0 then return false, "Done" end
	p.data.QuestDone = bit32.bor(p.data.QuestDone, bit)
	p.data.Gold = math.min(Config.Economy.MaxGold, p.data.Gold + reward)
	p.dirty = true
	syncStat(player, "QuestDone")
	syncStat(player, "Gold")
	return true
end

-- награды RewardsService: fn(data) без yield правит поля наград прямо в data и возвращает {Gold =, Diamonds =} —
-- что начислить (можно пустую таблицу), или nil, причина — отказ (тогда data не трогать).
-- Проверка и начисление одним шагом: дважды не получить. claim = true — это забор награды: пока профиль
-- грузится с другого сервера (adopting), нельзя (там награда могла быть уже получена). Золото — без множителя VIP.
local REWARD_FIELDS = {"DQDay", "DQ1", "DQ2", "DQ3", "DQDone", "Streak", "StreakLast", "GiftDay", "GiftSec", "GiftDone", "Flags", "Invites"}
function DataService.apply(player, fn, claim)
	local p = profiles[player]
	if not p then return nil, "NoData" end
	if claim and p.adopting then return nil, "Syncing" end
	local res, why = fn(p.data)
	if type(res) ~= "table" then return nil, why end
	if validAmount(res.Gold) then p.data.Gold = math.min(Config.Economy.MaxGold, p.data.Gold + res.Gold) end
	if validAmount(res.Diamonds) then p.data.Diamonds = math.min(Config.Diamonds.Max, p.data.Diamonds + res.Diamonds) end
	p.dirty = true
	if res.Gold then syncStat(player, "Gold") end
	if res.Diamonds then syncStat(player, "Diamonds") end
	return res
end

-- только чтение полей наград (копия)
function DataService.rewardData(player)
	local p = profiles[player]
	if not p then return nil end
	local t = {}
	for _, f in ipairs(REWARD_FIELDS) do t[f] = p.data[f] end
	t.PlaySec = p.data.PlaySec
	return t
end

-- одна запись в DataStore (вызывается только из save, строго по очереди)
local function write(player, p, release)
	local snap = table.clone(p.data)
	p.dirty = false -- изменения во время записи снова поднимут флаг
	local lostLock = false
	local ok, err = retry(function()
		lostLock = false
		store:UpdateAsync(key(player), function(old)
			-- пишем только под своим замком; нет замка или он чужой — профилем мы больше не владеем
			if type(old) ~= "table" or not ownsLock(old._lock, p.session) then
				lostLock = true
				return nil
			end
			local data = table.clone(snap)
			if not release then data._lock = {job = game.JobId, session = p.session, t = os.time()} end
			return data
		end)
	end, 3)
	if lostLock then
		p.canSave = false
		if player.Parent then player:SetAttribute("DataPersistent", false) end
		warn(("[DataService] %s: profile lock is no longer ours, saving stopped"):format(player.Name))
		return false
	end
	if not ok then
		p.dirty = true
		warn(("[DataService] failed to save %s: %s"):format(player.Name, tostring(err)))
		return false
	end
	p.lockRefresh = os.clock()
	if killsStore and snap.Kills ~= p.savedKills then -- рейтинг пишем, только если число убийств изменилось
		local okK = retry(function()
			killsStore:SetAsync(tostring(player.UserId), snap.Kills)
		end, 2)
		if okK then p.savedKills = snap.Kills end
	end
	return true
end

-- release = true: финальное сохранение (выход игрока / закрытие сервера) — последняя запись, снимает свой замок.
-- Сохранения одного профиля идут строго по очереди; после release профиль закрыт.
function DataService.save(player, release)
	local p = profiles[player]
	if not p or p.closed then return false end
	if release then p.closing = true elseif p.closing then return false end
	-- ждём текущую запись этого профиля (без yield между проверкой и захватом — гонки нет)
	while p.saving do task.wait(0.05) end
	if p.closed or (p.closing and not release) then return false end
	if not p.canSave or not store then
		if release then p.closed = true end
		return false
	end
	if not release and not p.dirty and os.clock() - (p.lockRefresh or 0) < REFRESH then return true end
	p.saving = true
	local ok, res = pcall(write, player, p, release)
	p.saving = false
	if release then p.closed = true end
	if not ok then
		p.dirty = true
		warn(("[DataService] save error %s: %s"):format(player.Name, tostring(res)))
		return false
	end
	return res
end

function DataService.init()
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player, true)
		profiles[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for player, p in pairs(profiles) do
				if not p.closing then task.spawn(DataService.save, player) end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				-- ошибка в save не должна оставить счётчик висеть (иначе сервер ждёт все 25 с)
				local ok, err = pcall(DataService.save, player, true)
				if not ok then warn("[DataService] save on close: " .. tostring(err)) end
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
