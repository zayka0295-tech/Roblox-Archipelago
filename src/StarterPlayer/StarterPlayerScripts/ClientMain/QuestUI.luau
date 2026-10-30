-- Доска заданий: окно с заданиями (открывается подсказкой у доски QuestBoard рядом со стендом РПГ).
-- Прогресс и награды считает сервер (QuestService); окно только показывает и просит забрать награду.
-- Задание «группа»: кнопка JOIN открывает встроенное окно Roblox «вступить в группу» (ссылки в браузер
-- игра открывать не может); вступил — награда забирается сразу (членство проверяет сервер).
-- «!» над доской (BillboardGui в модели QuestBoard) виден, только пока у игрока есть невыполненные задания.
local ProximityPromptService = game:GetService("ProximityPromptService")
local GroupService = game:GetService("GroupService")

local TITLE = {
	group = function(s) return ("Join %s on Roblox"):format(s.groupName or "our group") end,
	play = function(s) return ("Play for %d minutes"):format(math.floor(s.goal / 60)) end,
	kills = function(s) return ("Defeat %d enemy players"):format(s.goal) end, -- боты не считаются
}

local function progressText(s)
	if s.done then return "Completed" end
	if s.id == "group" then
		if s.locked then return "Coming soon" end
		return s.progress >= 1 and "You are in the group!" or "Press JOIN to join the group"
	elseif s.id == "play" then
		return ("%d / %d min"):format(math.floor(s.progress / 60), math.floor(s.goal / 60))
	end
	return ("%d / %d players"):format(s.progress, s.goal)
end

return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local gui = UI.screen("QuestUI", 22)
	gui.Enabled = false
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 340),
	})
	UI.scale(panel, 0.8) -- на телефоне кнопки не сжимаются до крошечных
	UI.padding(panel, 16)
	UI.label(panel, "QUESTS", {TextSize = 22, TextColor3 = T.Gold})
	UI.label(panel, "One-time rewards · gold goes straight to your balance", {
		Position = UDim2.fromOffset(0, 26), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted,
	})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -4), Size = UDim2.fromOffset(36, 36), TextSize = 16})
	UI.stroke(close)

	local rows = {}
	local current = {}
	local busy = false
	local refresh -- объявлена ниже

	-- «!» над досками баз (стриминг: доски подгружаются позже — применяем и в цикле ниже)
	local allDone = false
	local function applyMark()
		local map = workspace:FindFirstChild("Map")
		local teams = map and map:FindFirstChild("Teams")
		for _, base in ipairs(teams and teams:GetChildren() or {}) do
			local decor = base:FindFirstChild("Decor")
			local board = decor and decor:FindFirstChild("QuestBoard")
			local bb = board and board:FindFirstChild("Board") and board.Board:FindFirstChild("BillboardGui")
			if bb then bb.Enabled = not allDone end
		end
	end

	local function render(list)
		current = list or current
		allDone = #current > 0
		for _, s in ipairs(current) do
			if not s.done and not s.locked then allDone = false end
		end
		applyMark()
		for i, s in ipairs(current) do
			local r = rows[i]
			if r then
				r.id = s.id
				r.title.Text = (TITLE[s.id] or function() return s.id end)(s)
				r.progress.Text = progressText(s)
				r.reward.Text = ("+%d gold"):format(s.reward)
				r.fill.Size = UDim2.fromScale(math.clamp(s.goal > 0 and s.progress / s.goal or 0, 0, 1), 1)
				r.fill.BackgroundColor3 = (s.done or s.ready) and T.Good or T.Accent
				local canPress = s.ready or (s.id == "group" and not s.locked and not s.done)
				local text = s.done and "DONE" or (s.ready and "CLAIM") or (s.locked and "SOON") or (s.id == "group" and "JOIN") or "IN PROGRESS"
				UI.setEnabled(r.button, canPress, s.ready and T.Good or T.Accent, text)
			end
		end
	end

	for i = 1, 3 do
		local row = UI.new("Frame", {Position = UDim2.fromOffset(0, 54 + (i - 1) * 88), Size = UDim2.new(1, 0, 0, 80), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, panel)
		UI.corner(row, 8)
		local r = {}
		r.title = UI.label(row, "", {Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -150, 0, 20), TextSize = 16})
		r.progress = UI.label(row, "", {Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -150, 0, 16), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted})
		local barBg = UI.new("Frame", {Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -150, 0, 8), BackgroundColor3 = T.Panel, BorderSizePixel = 0}, row)
		UI.corner(barBg, 4)
		r.fill = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0}, barBg)
		UI.corner(r.fill, 4)
		r.reward = UI.label(row, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(120, 18),
			TextSize = 15, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Right})
		r.button = UI.button(row, "", T.Accent, {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), Size = UDim2.fromOffset(120, 36), TextSize = 14})
		local function claim()
			busy = true
			local res = ctx.invoke("Quests", "claim", r.id)
			busy = false
			UI.toast(res.msg or "", res.ok and "success" or "error")
			if res.list then render(res.list) end
			return res.ok
		end
		r.button.Activated:Connect(function()
			if busy or not r.id or r.button:GetAttribute("Enabled") == false then return end
			local s
			for _, q in ipairs(current) do
				if q.id == r.id then s = q end
			end
			-- группа: ещё не в ней — окно вступления Roblox, потом сразу награда
			if s and s.id == "group" and not s.ready then
				busy = true
				local ok, status = pcall(function()
					return GroupService:PromptJoinAsync(ctx.Config.Quests.GroupId)
				end)
				busy = false
				if not ok then
					UI.toast("Couldn't open the group window — try again", "error")
				elseif status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember then
					task.wait(1) -- дать Roblox записать вступление
					if not claim() then
						UI.toast("You joined! If the reward didn't arrive, press CLAIM again in a few seconds", "info")
					end
				elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
					UI.toast("Join request sent — claim the reward once it's accepted", "info")
				end
				return
			end
			claim()
		end)
		rows[i] = r
	end

	local openId = 0
	local function open()
		gui.Enabled = true
		openId += 1
		local my = openId
		task.spawn(function()
			-- пока окно открыто — обновляем прогресс (время идёт)
			while gui.Enabled and openId == my do
				refresh()
				task.wait(3)
			end
		end)
	end
	local function closeUI()
		gui.Enabled = false
	end
	refresh = function()
		if busy then return end
		local res = ctx.invoke("Quests", "get")
		if res.list then render(res.list) end -- не вышло — просто повторим в следующий раз
	end
	close.Activated:Connect(closeUI)

	-- состояние заданий при входе, затем раз в минуту (время в игре идёт само) и доски из стриминга
	task.spawn(function()
		while not ctx.player:GetAttribute("DataLoaded") do task.wait(1) end
		local n = 0
		while true do
			if n % 20 == 0 and not gui.Enabled then refresh() end
			applyMark()
			n += 1
			task.wait(3)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "QuestPrompt" then open() end
	end)

	return {
		onState = function(state)
			if state ~= "Deployed" then closeUI() end
		end,
	}
end
