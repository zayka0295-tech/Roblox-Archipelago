-- Награды за возвращение (окно REWARDS у игрока): ежедневные задания (Config.Daily), серия входов (Config.Streak),
-- сундуки за время в игре сегодня (Config.Gifts) и приглашение друзей (Config.Invite).
-- Прогресс хранит DataService (DQ*, Streak*, Gift*, Flags, Invites); всё считает и начисляет только сервер.
-- День — номер суток UTC (os.time() // 86400): в полночь новые задания, сундуки заново, серия ждёт награду.
-- Remotes.Rewards (RemoteFunction): ("get") → {ok, state}; ("claim", вид, номер) → {ok, msg, state};
-- вид — "quest" (1..3), "bonus", "streak", "gift" (1..#Config.Gifts.List).
-- Атрибут игрока RewardsReady — сколько наград можно забрать сейчас (счётчик на кнопке REWARDS).
-- Напоминания — тосты (Notifier): задание выполнено, сундук открылся, начался новый день.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local RankService = require(Services.RankService)
local BadgesService = require(Services.BadgesService)
local Notifier = require(Services.Notifier)
local Guard = require(Services.RemoteGuard)

local RewardsService = {}
RewardsService.Claimed = Instance.new("BindableEvent") -- (игрок, вид) — забрана любая награда (шаг «Пути новичка»)
local D, S, G, I = Config.Daily, Config.Streak, Config.Gifts, Config.Invite
local TICK = 5            -- сек.: шаг учёта времени для сундуков
local FLAG_REFERRED = 1   -- Flags: награда новичку за приглашение уже выдана
local BONUS_BIT = 8       -- DQDone: бонус за все три задания забран
local lastDay = {}        -- [игрок] = день, который он видел (для тоста «новый день»)

local function today() return os.time() // 86400 end
local function resetIn() return 86400 - os.time() % 86400 end

-- набор заданий дня: по одному из каждого уровня, свой у каждого игрока
local function questsFor(player, day)
	local rng = Random.new(day * 7919 + player.UserId % 1000003)
	local list = {}
	for i, tier in ipairs(D.Tiers) do list[i] = tier[rng:NextInteger(1, #tier)] end
	return list
end

-- начался новый день: задания и сундуки — заново (data — профиль или его копия)
local function roll(data, day)
	if data.DQDay ~= day then data.DQDay, data.DQ1, data.DQ2, data.DQ3, data.DQDone = day, 0, 0, 0, 0 end
	if data.GiftDay ~= day then data.GiftDay, data.GiftSec, data.GiftDone = day, 0, 0 end
end

-- серия: забрана ли награда сегодня, какой по счёту день будет (или был) сегодня, сорвалась ли серия
local function streakOf(data, day)
	local claimed = data.StreakLast == day
	local nextCount = claimed and data.Streak or (data.StreakLast == day - 1 and data.Streak + 1 or 1)
	local lost = not claimed and data.Streak > 0 and data.StreakLast < day - 1
	return claimed, nextCount, lost
end

local function dayIndex(count) return (count - 1) % #S.Rewards + 1 end
local function has(bits, bit) return bit32.band(bits, bit) ~= 0 end

-- состояние для окна (по копии профиля, сам профиль не меняем)
local function stateFor(player)
	local d = DataService.rewardData(player)
	if not d then return nil end
	local day = today()
	roll(d, day)
	local st = {resetIn = resetIn(), ready = 0}

	st.quests = {}
	local allDone = true
	for i, q in ipairs(questsFor(player, day)) do
		local progress = math.min(q.Goal, d["DQ" .. i] or 0)
		local done = has(d.DQDone, 2 ^ (i - 1))
		local ready = not done and progress >= q.Goal
		if not done then allDone = false end
		if ready then st.ready += 1 end
		st.quests[i] = {text = q.Text:format(q.Goal), goal = q.Goal, progress = progress, reward = q.Reward, done = done, ready = ready}
	end
	local bonusDone = has(d.DQDone, BONUS_BIT)
	st.bonus = {diamonds = D.BonusDiamonds, done = bonusDone, ready = allDone and not bonusDone}
	if st.bonus.ready then st.ready += 1 end

	local claimed, nextCount, lost = streakOf(d, day)
	st.streak = {claimed = claimed, count = claimed and d.Streak or nextCount - 1, index = dayIndex(nextCount), lost = lost, rewards = S.Rewards}
	if not claimed then st.ready += 1 end

	st.gifts = {sec = d.GiftSec, list = {}}
	for i, g in ipairs(G.List) do
		local done = has(d.GiftDone, 2 ^ (i - 1))
		local ready = not done and d.GiftSec >= g.Min * 60
		if ready then st.ready += 1 end
		st.gifts.list[i] = {min = g.Min, gold = g.Gold, diamonds = g.Diamonds, done = done, ready = ready}
	end

	st.invite = {friendGold = I.FriendGold, newGold = I.NewPlayerGold, count = d.Invites}
	return st
end

local function publish(player, st)
	st = st or stateFor(player)
	if st then player:SetAttribute("RewardsReady", st.ready) end
	return st
end

-- прогресс ежедневных заданий за действие (RankService.Action)
local function onAction(player, key)
	if not DataService.isLoaded(player) then return end
	local day = today()
	local quests = questsFor(player, day)
	local matches = false
	for _, q in ipairs(quests) do
		if q.Events[key] then matches = true end
	end
	if not matches then return end
	local finished = {}
	local res = DataService.apply(player, function(data)
		roll(data, day)
		local changed = false
		for i, q in ipairs(quests) do
			local add, f = q.Events[key], "DQ" .. i
			if add and data[f] < q.Goal and not has(data.DQDone, 2 ^ (i - 1)) then
				data[f] = math.min(q.Goal, data[f] + add)
				changed = true
				if data[f] >= q.Goal then table.insert(finished, q) end
			end
		end
		return changed and {} or nil
	end)
	if not res then return end
	for _, q in ipairs(finished) do
		Notifier.send(player, ("Daily quest done: %s — claim +%d gold in REWARDS"):format(q.Text:format(q.Goal), q.Reward), "success")
	end
	publish(player)
end

local MSG = {Done = "Already claimed", NotYet = "Not finished yet", Unknown = "Unknown reward",
	Syncing = "Your saved data is still loading — try again in a moment", NoData = "Data is still loading…"}

local function rewardText(r)
	local parts = {}
	if (r.Gold or 0) > 0 then table.insert(parts, ("+%d gold"):format(r.Gold)) end
	if (r.Diamonds or 0) > 0 then table.insert(parts, ("+%d 💎"):format(r.Diamonds)) end
	return table.concat(parts, " ")
end

local function claim(player, kind, index)
	local day = today()
	local res, why
	if kind == "quest" then
		local quests = questsFor(player, day)
		local q = quests[index]
		if not q then return false, MSG.Unknown end
		res, why = DataService.apply(player, function(data)
			roll(data, day)
			local bit = 2 ^ (index - 1)
			if has(data.DQDone, bit) then return nil, "Done" end
			if data["DQ" .. index] < q.Goal then return nil, "NotYet" end
			data.DQDone = bit32.bor(data.DQDone, bit)
			return {Gold = q.Reward}
		end, true)
		if res then RankService.award(player, "Quest") end
	elseif kind == "bonus" then
		res, why = DataService.apply(player, function(data)
			roll(data, day)
			if has(data.DQDone, BONUS_BIT) then return nil, "Done" end
			if bit32.band(data.DQDone, 7) ~= 7 then return nil, "NotYet" end
			data.DQDone = bit32.bor(data.DQDone, BONUS_BIT)
			return {Diamonds = D.BonusDiamonds}
		end, true)
		if res then BadgesService.award(player, "DailyAll") end
	elseif kind == "streak" then
		local count
		res, why = DataService.apply(player, function(data)
			local claimed, nextCount = streakOf(data, day)
			if claimed then return nil, "Done" end
			data.StreakLast, data.Streak = day, nextCount
			count = nextCount
			local r = S.Rewards[dayIndex(nextCount)]
			return {Gold = r.Gold, Diamonds = r.Diamonds}
		end, true)
		if res and count >= 7 then BadgesService.award(player, "Streak7") end
		if res then
			task.spawn(DataService.save, player)
			RewardsService.Claimed:Fire(player, kind)
			return true, ("Day %d streak reward: %s"):format(count, rewardText(res))
		end
	elseif kind == "gift" then
		local g = G.List[index]
		if not g then return false, MSG.Unknown end
		res, why = DataService.apply(player, function(data)
			roll(data, day)
			local bit = 2 ^ (index - 1)
			if has(data.GiftDone, bit) then return nil, "Done" end
			if data.GiftSec < g.Min * 60 then return nil, "NotYet" end
			data.GiftDone = bit32.bor(data.GiftDone, bit)
			return {Gold = g.Gold, Diamonds = g.Diamonds}
		end, true)
	else
		return false, MSG.Unknown
	end
	if not res then return false, MSG[why] or MSG.NoData end
	task.spawn(DataService.save, player)
	RewardsService.Claimed:Fire(player, kind)
	return true, "Reward claimed: " .. rewardText(res)
end

-- кто привёл игрока: приглашение (Join Data от SocialService:PromptGameInvite — ReferredByPlayerId)
-- или вход через «Join» в профиле друга (FollowUserId; тогда проверяем, что они правда друзья)
local function referrer(player)
	local ok, jd = pcall(function() return player:GetJoinData() end)
	local ref = ok and type(jd) == "table" and tonumber(jd.ReferredByPlayerId) or 0
	if ref and ref > 0 and ref ~= player.UserId then return ref end
	local follow = player.FollowUserId
	if follow and follow > 0 and follow ~= player.UserId and Players:GetPlayerByUserId(follow) then
		local okF, friends = pcall(function() return player:IsFriendsWith(follow) end)
		if okF and friends then return follow end
	end
	return nil
end

-- новичок пришёл по приглашению друга: награда ему и пригласившему (если тот на этом сервере)
local function checkReferral(player)
	local ref = referrer(player)
	if not ref then return end
	local inviter = Players:GetPlayerByUserId(ref)
	local got, why = DataService.apply(player, function(data)
		if has(data.Flags, FLAG_REFERRED) then return nil, "Done" end
		if data.PlaySec >= I.NewPlayerMaxSec then return nil, "NotNew" end
		data.Flags = bit32.bor(data.Flags, FLAG_REFERRED)
		return {Gold = I.NewPlayerGold}
	end, true)
	if not got then
		-- пригласивший должен понимать, почему золота нет
		if inviter and why == "NotNew" then
			Notifier.send(inviter, ("%s has already played here — invite rewards are only for new players"):format(player.DisplayName), "info")
		elseif inviter and why == "Done" then
			Notifier.send(inviter, ("%s already got an invite reward before"):format(player.DisplayName), "info")
		end
		return
	end
	task.spawn(DataService.save, player)
	Notifier.send(player, ("Welcome! A friend invited you: +%d gold"):format(I.NewPlayerGold), "success")
	-- пригласившему — только если отметка новичка (Flags) правда сохранится: во временной сессии (DataStore
	-- недоступен) она пропадёт, и тот же аккаунт приносил бы награду при каждом заходе
	if inviter and DataService.isLoaded(inviter) and player:GetAttribute("DataPersistent") == true then
		local paid = DataService.apply(inviter, function(data)
			if data.Invites >= I.MaxRewarded then return nil end
			data.Invites += 1
			return {Gold = I.FriendGold}
		end, true)
		if paid then
			task.spawn(DataService.save, inviter)
			Notifier.send(inviter, ("%s joined from your invite: +%d gold"):format(player.DisplayName, I.FriendGold), "success")
			BadgesService.award(inviter, "InviteFriend")
		end
	end
end

-- шаг учёта времени для сундуков (каждые TICK сек.); новый день — напоминание
local function tickPlayer(p, day)
	if not p.Parent or not DataService.isLoaded(p) then return end
	local opened = {}
	DataService.apply(p, function(data)
		roll(data, day)
		local before = data.GiftSec
		data.GiftSec += TICK
		for _, g in ipairs(G.List) do
			if before < g.Min * 60 and data.GiftSec >= g.Min * 60 then table.insert(opened, g) end
		end
		return {}
	end)
	for _, g in ipairs(opened) do
		Notifier.send(p, ("🎁 Gift unlocked for %d minutes of play — open REWARDS"):format(g.Min), "success")
	end
	if lastDay[p] and lastDay[p] ~= day then
		Notifier.send(p, "New day! Fresh daily quests and your streak reward are waiting in REWARDS", "info")
	end
	lastDay[p] = day
	publish(p)
end

function RewardsService.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = Remotes:FindFirstChild("Rewards")
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = "Rewards"
		remote.Parent = Remotes
	end
	remote.OnServerInvoke = function(player, action, kind, index)
		if not Guard.allow(player, action == "claim" and "Rewards" or "RewardsGet") then return {ok = false, msg = "Too fast, please wait"} end
		if not DataService.isLoaded(player) then return {ok = false, msg = MSG.NoData} end
		if action == "claim" then
			if type(kind) ~= "string" or (index ~= nil and (type(index) ~= "number" or index ~= math.floor(index))) then
				return {ok = false, msg = MSG.Unknown}
			end
			local ok, msg = claim(player, kind, index)
			return {ok = ok, msg = msg, state = publish(player)}
		end
		return {ok = true, state = publish(player)}
	end

	RankService.Action.Event:Connect(onAction)

	DataService.Loaded.Event:Connect(function(player)
		lastDay[player] = today()
		-- профиль ещё забирается с другого сервера: забор награды пока запрещён (Syncing) — приглашение
		-- проверим ещё раз, когда сохранение включится (повторно награда не выдаётся — флаг в Flags).
		-- Подписка до checkReferral: он ждёт ответа IsFriendsWith, а сохранение может включиться в это время
		if player:GetAttribute("DataPersistent") ~= true then
			local conn
			conn = player:GetAttributeChangedSignal("DataPersistent"):Connect(function()
				if player:GetAttribute("DataPersistent") ~= true then return end
				conn:Disconnect()
				checkReferral(player)
				publish(player)
			end)
		end
		checkReferral(player)
		publish(player)
	end)

	-- время в игре для сундуков; новый день — напоминание
	task.spawn(function()
		while true do
			task.wait(TICK)
			local day = today()
			for _, p in ipairs(Players:GetPlayers()) do
				-- ошибка у одного игрока не должна навсегда остановить цикл (сундуки встали бы у всех)
				local ok, err = pcall(tickPlayer, p, day)
				if not ok then warn("[RewardsService] tick: " .. tostring(err)) end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p) lastDay[p] = nil end)
end

-- только для тестов в Studio (DevCommands): сдвинуть награды на «вчера» / открыть сундуки
function RewardsService.devShift(player, what)
	if not game:GetService("RunService"):IsStudio() then return false end
	local day = today()
	DataService.apply(player, function(data)
		if what == "newday" then
			data.DQDay, data.GiftDay = day - 1, day - 1
			if data.StreakLast == day then data.StreakLast = day - 1 end
		elseif what == "gifts" then
			roll(data, day)
			data.GiftSec = 3600
		elseif what == "quests" then
			roll(data, day)
			for i, q in ipairs(questsFor(player, day)) do data["DQ" .. i] = q.Goal end
		end
		return {}
	end)
	publish(player)
	return true
end

return RewardsService
