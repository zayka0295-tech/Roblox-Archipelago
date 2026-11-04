-- Доска заданий «Путь новичка» (FIRST STEPS): окно открывается подсказкой у доски QuestBoard рядом со стендом РПГ.
-- Шаги — первые действия в игре (Config.Quests), каждый с разовой наградой золотом. Прогресс и награды считает
-- сервер (QuestService); окно только показывает и просит забрать награду.
-- Задание «группа»: кнопка JOIN открывает встроенное окно Roblox «вступить в группу» (ссылки в браузер
-- игра открывать не может); вступил — награда забирается сразу (членство проверяет сервер).
-- «!» над доской (BillboardGui в модели QuestBoard) виден, только пока у игрока есть невыполненные задания.
local ProximityPromptService = game:GetService("ProximityPromptService")
local GroupService = game:GetService("GroupService")

-- название и подсказка «где / как» для каждого шага
local TITLE = {
	group = function(s) return ("Join %s on Roblox"):format(s.groupName or "our group") end,
	deploy = function() return "Deploy to the battlefield" end,
	plane = function() return "Take off in a plane" end,
	helm = function() return "Take the helm of a ship" end,
	firstkill = function() return "Defeat your first enemy" end,
	capture = function() return "Help capture an island" end,
	reward = function() return "Claim a reward in REWARDS" end,
	play = function(s) return ("Play for %d minutes"):format(math.floor(s.goal / 60)) end,
}
local HINT = {
	deploy = "Step on a deploy pad in the lobby",
	plane = "Hop into a plane at your base airfield",
	helm = "Board a ship at the shipyard and sit at the helm",
	firstkill = "Any enemy soldier counts",
	capture = "Stand in an island's capture zone with your team",
	reward = "Press the 🎁 REWARDS button on the right",
}

local function progressText(s)
	if s.done then return "Completed" end
	if s.id == "group" then
		if s.locked then return "Coming soon" end
		return s.progress >= 1 and "You are in the group!" or "Press JOIN to join the group"
	elseif s.id == "play" then
		return ("%d / %d min"):format(math.floor(s.progress / 60), math.floor(s.goal / 60))
	end
	return s.progress >= s.goal and "Done — claim your reward!" or (HINT[s.id] or "")
end

local ROW_H, ROW_GAP = 72, 8

return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local gui = UI.screen("QuestUI", 22)
	gui.Enabled = false
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 520),
	})
	UI.scale(panel, 0.7) -- на телефоне не мельче 0.7 (так окно 520 ещё влезает в 390 по высоте вместе с кнопкой X)
	UI.padding(panel, 16)
	UI.label(panel, "FIRST STEPS", {TextSize = 22, TextColor3 = T.Gold})
	UI.label(panel, "Learn the ropes · one-time gold rewards", {
		Position = UDim2.fromOffset(0, 26), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted,
	})
	local doneLbl = UI.label(panel, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -48, 0, 4), Size = UDim2.fromOffset(150, 20),
		TextSize = 15, TextColor3 = T.Good, TextXAlignment = Enum.TextXAlignment.Right})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -4), Size = UDim2.fromOffset(36, 36), TextSize = 16})
	UI.stroke(close)
	local list = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollBarImageColor3 = T.Line, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel)
	UI.new("UIListLayout", {Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder}, list)

	local rows = {}
	local current = {}
	local busy = false
	local refresh -- объявлена ниже
	local claimRow -- объявлена ниже

	-- «!» над досками баз (стриминг: доски подгружаются позже — применяем и в цикле ниже)
	local allDone = false
	local function applyMark()
		for _, e in ipairs(UI.baseDecor("QuestBoard")) do
			local board = e[2]
			local bb = board:FindFirstChild("Board") and board.Board:FindFirstChild("BillboardGui")
			if bb then bb.Enabled = not allDone end
		end
	end

	local function makeRow(i)
		local row = UI.new("Frame", {Size = UDim2.new(1, -10, 0, ROW_H), BackgroundColor3 = T.Panel2, BorderSizePixel = 0, LayoutOrder = i}, list)
		UI.corner(row, 8)
		UI.plate(row)
		local r = {row = row}
		r.num = UI.label(row, tostring(i), {Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 22, 1, 0), TextSize = 18, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
		r.title = UI.label(row, "", {Position = UDim2.fromOffset(40, 8), Size = UDim2.new(1, -180, 0, 20), TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd})
		r.progress = UI.label(row, "", {Position = UDim2.fromOffset(40, 30), Size = UDim2.new(1, -180, 0, 16), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted, TextTruncate = Enum.TextTruncate.AtEnd})
		local barBg = UI.new("Frame", {Position = UDim2.fromOffset(40, 52), Size = UDim2.new(1, -180, 0, 8), BackgroundColor3 = T.Panel, BorderSizePixel = 0}, row)
		UI.corner(barBg, 4)
		r.fill = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0}, barBg)
		UI.corner(r.fill, 4)
		UI.bar(barBg, r.fill)
		r.reward = UI.label(row, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(120, 18),
			TextSize = 14, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Right})
		r.button = UI.button(row, "", T.Accent, {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -8), Size = UDim2.fromOffset(120, 32), TextSize = 13})
		r.button.Activated:Connect(function() claimRow(r) end)
		rows[i] = r
		return r
	end

	local function render(newList)
		current = newList or current
		allDone = #current > 0
		local doneN = 0
		for _, s in ipairs(current) do
			if s.done or s.locked then doneN += 1 else allDone = false end
		end
		applyMark()
		doneLbl.Text = #current > 0 and ("%d / %d done"):format(doneN, #current) or ""
		for i, s in ipairs(current) do
			local r = rows[i] or makeRow(i)
			r.id = s.id
			r.title.Text = (TITLE[s.id] or function() return s.id end)(s)
			r.progress.Text = progressText(s)
			r.reward.Text = ("+%d gold"):format(s.reward)
			r.fill.Size = UDim2.fromScale(math.clamp(s.goal > 0 and s.progress / s.goal or 0, 0, 1), 1)
			r.fill.BackgroundColor3 = (s.done or s.ready) and T.Good or T.Accent
			r.num.TextColor3 = s.done and T.Good or T.Muted
			r.row.BackgroundTransparency = s.done and 0.5 or 0
			local canPress = s.ready or (s.id == "group" and not s.locked and not s.done)
			local text = s.done and "DONE" or (s.ready and "CLAIM") or (s.locked and "SOON") or (s.id == "group" and "JOIN") or "IN PROGRESS"
			UI.setEnabled(r.button, canPress, s.ready and T.Good or T.Accent, text)
		end
		for i = #current + 1, #rows do rows[i].row.Visible = false end
	end

	local function claim(id)
		busy = true
		local res = ctx.invoke("Quests", "claim", id)
		busy = false
		UI.toast(res.msg or "", res.ok and "success" or "error")
		if res.list then render(res.list) end
		return res.ok
	end
	claimRow = function(r)
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
				if not claim(r.id) then
					UI.toast("You joined! If the reward didn't arrive, press CLAIM again in a few seconds", "info")
				end
			elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
				UI.toast("Join request sent — claim the reward once it's accepted", "info")
			end
			return
		end
		claim(r.id)
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
