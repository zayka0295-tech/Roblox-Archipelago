-- Карьера (Config.Career): долгие достижения за всё время с тремя уровнями (бронза / серебро / золото).
-- Счётчики (поля C*) растут от RankService.Action; уровень забирают в окне у статуи на площади базы.
-- Забранные уровни — биты CareerDone (бит = (номер достижения - 1) * 3 + уровень - 1).
-- Remotes.Career (RemoteFunction): ("get") → {ok, state}; ("claim", id) → {ok, msg, state} — забирает следующий уровень.
-- Атрибуты игрока: CareerLevel — сколько уровней забрано (по нему клиент наряжает статую), CareerReady — сколько можно забрать.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local DataService = require(Services.DataService)
local RankService = require(Services.RankService)
local Notifier = require(Services.Notifier)
local Guard = require(Services.RemoteGuard)

local CareerService = {}
local C = Config.Career

local function bitOf(i, tier) return 2 ^ ((i - 1) * 3 + tier - 1) end
local function has(bits, bit) return bit32.band(bits, bit) ~= 0 end

-- сколько уровней достижения i уже забрано (по порядку: 0..3)
local function claimedOf(data, i)
	local n = 0
	for tier = 1, 3 do
		if has(data.CareerDone, bitOf(i, tier)) then n = tier else break end
	end
	return n
end

local function stateFor(player)
	local p = {}
	for _, a in ipairs(C.List) do p[a.Field] = DataService.get(player, a.Field) or 0 end
	p.CareerDone = DataService.get(player, "CareerDone") or 0
	local st = {list = {}, level = 0, ready = 0, max = #C.List * 3, rewards = C.Rewards, stages = C.Stages}
	for i, a in ipairs(C.List) do
		local claimed = claimedOf(p, i)
		local count = p[a.Field]
		local nextGoal = a.Tiers[claimed + 1]
		local ready = nextGoal ~= nil and count >= nextGoal
		st.level += claimed
		if ready then st.ready += 1 end
		st.list[i] = {id = a.Id, text = a.Text, icon = a.Icon, count = count, tiers = a.Tiers, claimed = claimed, ready = ready}
	end
	return st
end

local function publish(player)
	local st = stateFor(player)
	player:SetAttribute("CareerLevel", st.level)
	player:SetAttribute("CareerReady", st.ready)
	return st
end

local function stageName(level)
	local name = C.Stages[1].Name
	for _, s in ipairs(C.Stages) do
		if level >= s.From then name = s.Name end
	end
	return name
end

local function onAction(player, key)
	if not DataService.isLoaded(player) then return end
	local hit = false
	for _, a in ipairs(C.List) do
		if a.Events[key] then hit = true end
	end
	if not hit then return end
	local before = player:GetAttribute("CareerReady") or 0
	DataService.apply(player, function(data)
		for _, a in ipairs(C.List) do
			local add = a.Events[key]
			if add then data[a.Field] += add end
		end
		return {}
	end)
	local st = publish(player)
	if st.ready > before then
		Notifier.send(player, "Career milestone reached! Claim it at the statue on your base", "success")
	end
end

local function claim(player, id)
	local i, a
	for k, x in ipairs(C.List) do
		if x.Id == id then i, a = k, x end
	end
	if not a then return false, "Unknown achievement" end
	local tierGot
	local res, why = DataService.apply(player, function(data)
		local claimed = claimedOf(data, i)
		local goal = a.Tiers[claimed + 1]
		if not goal then return nil, "Done" end
		if data[a.Field] < goal then return nil, "NotYet" end
		data.CareerDone = bit32.bor(data.CareerDone, bitOf(i, claimed + 1))
		tierGot = claimed + 1
		local r = C.Rewards[tierGot]
		return {Gold = r.Gold, Diamonds = r.Diamonds}
	end, true)
	if not res then
		return false, why == "Done" and "Already maxed out" or (why == "NotYet" and "Not reached yet" or
			(why == "Syncing" and "Your saved data is still loading — try again in a moment" or "Data is still loading…"))
	end
	task.spawn(DataService.save, player)
	local parts = {}
	if (res.Gold or 0) > 0 then table.insert(parts, ("+%d gold"):format(res.Gold)) end
	if (res.Diamonds or 0) > 0 then table.insert(parts, ("+%d 💎"):format(res.Diamonds)) end
	local oldStage = stageName((player:GetAttribute("CareerLevel") or 0))
	local st = publish(player)
	local newStage = stageName(st.level)
	local msg = ("%s — %s tier: %s"):format(a.Text, ({"Bronze", "Silver", "Gold"})[tierGot], table.concat(parts, " "))
	if newStage ~= oldStage then
		Notifier.send(player, ("Your statue is now %s!"):format(newStage), "success")
	end
	return true, msg
end

function CareerService.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = Remotes:FindFirstChild("Career")
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = "Career"
		remote.Parent = Remotes
	end
	remote.OnServerInvoke = function(player, action, id)
		if not Guard.allow(player, action == "claim" and "Rewards" or "RewardsGet") then return {ok = false, msg = "Too fast, please wait"} end
		if not DataService.isLoaded(player) then return {ok = false, msg = "Data is still loading…"} end
		if action == "claim" then
			if type(id) ~= "string" then return {ok = false, msg = "Unknown achievement"} end
			local ok, msg = claim(player, id)
			return {ok = ok, msg = msg, state = stateFor(player)}
		end
		return {ok = true, state = publish(player)}
	end
	RankService.Action.Event:Connect(onAction)
	DataService.Loaded.Event:Connect(publish)
	-- профиль забран с другого сервера позже (DataService.adoptLater пересылает все поля) — статуя и счётчик
	-- на кнопке по сохранённой карьере, а не по временной
	DataService.StatChanged.Event:Connect(function(player, field)
		if field == "CareerDone" and player.Parent then publish(player) end
	end)
end

-- только для тестов в Studio (DevCommands "career"): добавить n ко всем счётчикам
function CareerService.devAdd(player, n)
	if not game:GetService("RunService"):IsStudio() then return false end
	DataService.apply(player, function(data)
		for _, a in ipairs(C.List) do data[a.Field] += n or 0 end
		return {}
	end)
	publish(player)
	return true
end

return CareerService
