-- Окно REWARDS: ежедневные задания, серия входов (7 дней), сундуки за время в игре и приглашение друзей.
-- Кнопка — в столбце справа под кнопкой ранга (та же рамка, что у DailySpinUI / RankUI), красный счётчик —
-- атрибут игрока RewardsReady. Данные и награды — только сервер (RewardsService, Remotes.Rewards).
-- Награда серии за сегодня не забрана — окно само открывается на вкладке STREAK (раз за заход, в лобби).
-- После первой забранной награды — просьба Roblox включить уведомления игры (раз за заход).
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")

local TIER_TAG = {{"EASY", Color3.fromRGB(80, 200, 110)}, {"MEDIUM", Color3.fromRGB(255, 190, 60)}, {"HARD", Color3.fromRGB(240, 95, 80)}}

return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local player = ctx.player
	ctx.Remotes:WaitForChild("Rewards")
	local DIAMOND = Color3.fromRGB(120, 220, 255)
	local GOLD = T.Gold

	local function circle(f) UI.corner(f, 0) f:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0) return f end
	local function clock(sec)
		sec = math.max(0, math.floor(sec))
		return sec >= 3600 and ("%d:%02d:%02d"):format(sec // 3600, sec // 60 % 60, sec % 60) or ("%d:%02d"):format(sec // 60, sec % 60)
	end
	local function rewardText(gold, diamonds)
		local parts = {}
		if (gold or 0) > 0 then table.insert(parts, ("%d gold"):format(gold)) end
		if (diamonds or 0) > 0 then table.insert(parts, ("%d 💎"):format(diamonds)) end
		return table.concat(parts, " + ")
	end

	---------------------------------------------------------------- кнопка на экране (под кнопкой ранга)
	local hudGui = UI.screen("RewardsButton", 6)
	local frame = UI.new("Frame", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(250, 92), BackgroundTransparency = 1}, hudGui)
	UI.scale(frame)
	-- на телефоне — ближе к краю и вплотную под кнопкой ранга (как сдвинуты кнопки в DailySpinUI / RankUI)
	local btnX, btnY = -6, 232
	if UI.touchOnly then btnX, btnY = 8, 186 end
	local hb = UI.hudButton(frame, UI.Icons.Rewards, "REWARDS", Color3.fromRGB(60, 190, 110), {
		Name = "RewardsButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, btnX, 1, btnY),
	})
	local btn, btnScale = hb.btn, hb.scale
	local count = circle(UI.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(24, 24), ZIndex = 3, Visible = false,
		BackgroundColor3 = Color3.fromRGB(235, 45, 60), Text = "", TextColor3 = Color3.new(1, 1, 1), Font = UI.Bold, TextSize = 14,
	}, btn))
	UI.new("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, count)
	hb.label.TextColor3 = Color3.fromRGB(150, 255, 180)

	---------------------------------------------------------------- окно
	local gui = UI.screen("RewardsUI", 45)
	gui.Enabled = false
	local dim = UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false}, gui)
	local panel = UI.panel(gui, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 500)})
	UI.scale(panel, 0.55)
	-- подложка: нажатие по пустому месту окна не проваливается в затемнение (а оно закрывает окно)
	UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 0}, panel)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(36, 46, 66), Color3.fromRGB(16, 21, 29))}, panel)
	local panelScale = UI.new("UIScale", {}, panel)
	UI.ribbon(panel, "REWARDS", {Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(330, 70)})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(38, 38), TextSize = 20})
	UI.stroke(close)

	-- вкладки
	local TABS = {"DAILY", "STREAK", "GIFTS"}
	local tabBtns, pages, dots = {}, {}, {}
	local currentTab = "DAILY"
	for i, name in ipairs(TABS) do
		local b = UI.button(panel, name, T.Panel2, {Position = UDim2.fromOffset(16 + (i - 1) * 199, 58), Size = UDim2.fromOffset(190, 38), TextSize = 16})
		tabBtns[name] = b
		dots[name] = circle(UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Color3.fromRGB(235, 45, 60), Visible = false, ZIndex = 3}, b))
		pages[name] = UI.new("Frame", {Position = UDim2.fromOffset(16, 106), Size = UDim2.new(1, -32, 1, -172), BackgroundTransparency = 1, Visible = false}, panel)
	end

	-- низ: приглашение друзей
	local inviteBtn = UI.button(panel, "INVITE FRIENDS", Color3.fromRGB(60, 120, 230), {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -14), Size = UDim2.fromOffset(200, 42), TextSize = 16})
	local inviteLbl = UI.label(panel, "", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 228, 1, -14), Size = UDim2.new(1, -244, 0, 42),
		TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, TextWrapped = true})

	---------------------------------------------------------------- DAILY
	local daily = pages.DAILY
	local resetLbl = UI.label(daily, "", {Size = UDim2.new(1, 0, 0, 18), TextSize = 14, Font = UI.Medium, TextColor3 = T.Muted})
	local qRows = {}
	for i = 1, 3 do
		local row = UI.new("Frame", {Position = UDim2.fromOffset(0, 26 + (i - 1) * 74), Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, daily)
		UI.corner(row, 8)
		UI.plate(row)
		local tag = UI.label(row, TIER_TAG[i][1], {Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(70, 16), TextSize = 12, TextColor3 = TIER_TAG[i][2]})
		local r = {row = row, tag = tag}
		r.text = UI.label(row, "", {Position = UDim2.fromOffset(84, 6), Size = UDim2.new(1, -230, 0, 20), TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd})
		local barBg = UI.new("Frame", {Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -170, 0, 10), BackgroundColor3 = T.Panel, BorderSizePixel = 0}, row)
		UI.corner(barBg, 5)
		r.fill = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0}, barBg)
		UI.corner(r.fill, 5)
		UI.bar(barBg, r.fill)
		r.prog = UI.label(row, "", {Position = UDim2.fromOffset(12, 47), Size = UDim2.new(1, -170, 0, 14), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted})
		r.reward = UI.label(row, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(130, 18), TextSize = 14, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right})
		r.button = UI.button(row, "", T.Accent, {AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -8), Size = UDim2.fromOffset(130, 30), TextSize = 13})
		qRows[i] = r
	end
	local bonusRow = UI.new("Frame", {Position = UDim2.fromOffset(0, 26 + 3 * 74), Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Color3.fromRGB(40, 52, 78), BorderSizePixel = 0}, daily)
	UI.corner(bonusRow, 8)
	UI.plate(bonusRow)
	UI.new("UIStroke", {Color = DIAMOND, Transparency = 0.5, Thickness = 1.5}, bonusRow)
	local bonusLbl = UI.label(bonusRow, "", {Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -170, 1, 0), TextSize = 15, TextColor3 = DIAMOND})
	local bonusBtn = UI.button(bonusRow, "", DIAMOND, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(130, 30), TextSize = 13})

	---------------------------------------------------------------- STREAK
	local streak = pages.STREAK
	local streakTitle = UI.label(streak, "", {Size = UDim2.new(1, 0, 0, 30), TextSize = 26, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center})
	-- огоньки по бокам заголовка, следуют за шириной текста
	local flames = {}
	for i, side in ipairs({-1, 1}) do
		flames[i] = UI.new("ImageLabel", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1,
			Image = UI.Icons.Flame, ScaleType = Enum.ScaleType.Fit}, streakTitle)
		local function place()
			-- TextBounds — в пикселях экрана (с UIScale), поэтому через долю ширины
			local frac = streakTitle.AbsoluteSize.X > 0 and streakTitle.TextBounds.X / streakTitle.AbsoluteSize.X or 0
			flames[i].Position = UDim2.new(0.5 + side * frac / 2, side * 22, 0.5, 0)
		end
		streakTitle:GetPropertyChangedSignal("TextBounds"):Connect(place)
		streakTitle:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		place()
	end
	local streakSub = UI.label(streak, "", {Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 18), TextSize = 14, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
	local cards = {}
	local CARD_W, GAP = 76, 6
	for i = 1, 7 do
		local big = i == 7
		local c = UI.new("Frame", {Position = UDim2.fromOffset(10 + (i - 1) * (CARD_W + GAP), 62), Size = UDim2.fromOffset(CARD_W, 132), BackgroundColor3 = big and Color3.fromRGB(70, 56, 30) or T.Panel2, BorderSizePixel = 0}, streak)
		UI.corner(c, 10)
		UI.plate(c)
		local stroke = UI.new("UIStroke", {Color = big and GOLD or T.Line, Thickness = big and 2 or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, c)
		UI.label(c, "DAY " .. i, {Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = big and GOLD or T.Text, TextXAlignment = Enum.TextXAlignment.Center})
		local icon = UI.new("ImageLabel", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26), Size = UDim2.fromOffset(big and 52 or 46, big and 52 or 46),
			BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit}, c)
		local amount = UI.label(c, "", {Position = UDim2.fromOffset(2, 76), Size = UDim2.new(1, -4, 0, 30), TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center})
		local state = UI.label(c, "", {Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center})
		local cs = UI.new("UIScale", {}, c)
		cards[i] = {frame = c, stroke = stroke, icon = icon, amount = amount, state = state, scale = cs, big = big}
	end
	local streakBtn = UI.button(streak, "CLAIM", T.Good, {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 212), Size = UDim2.fromOffset(240, 48), TextSize = 20})
	local streakNote = UI.label(streak, "", {Position = UDim2.fromOffset(0, 268), Size = UDim2.new(1, 0, 0, 36), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center})

	---------------------------------------------------------------- GIFTS
	local gifts = pages.GIFTS
	local giftLbl = UI.label(gifts, "", {Size = UDim2.new(1, 0, 0, 18), TextSize = 14, Font = UI.Medium, TextColor3 = T.Muted})
	local chests = {}
	local CH_W = (588 - 3 * 10) / 4
	for i = 1, 4 do
		local c = UI.new("Frame", {Position = UDim2.fromOffset((i - 1) * (CH_W + 10), 30), Size = UDim2.fromOffset(CH_W, 246), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, gifts)
		UI.corner(c, 10)
		UI.plate(c)
		local stroke = UI.new("UIStroke", {Color = T.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, c)
		-- чем дольше играть, тем крупнее подарок
		local icon = UI.new("ImageLabel", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(48 + i * 6, 48 + i * 6),
			BackgroundTransparency = 1, Image = UI.Icons.Rewards, ScaleType = Enum.ScaleType.Fit}, c)
		local mins = UI.label(c, "", {Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center})
		local reward = UI.label(c, "", {Position = UDim2.fromOffset(6, 106), Size = UDim2.new(1, -12, 0, 36), TextSize = 13, TextWrapped = true, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center})
		local barBg = UI.new("Frame", {Position = UDim2.new(0, 12, 0, 152), Size = UDim2.new(1, -24, 0, 10), BackgroundColor3 = T.Panel, BorderSizePixel = 0}, c)
		UI.corner(barBg, 5)
		local fill = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0}, barBg)
		UI.corner(fill, 5)
		UI.bar(barBg, fill)
		local timeLbl = UI.label(c, "", {Position = UDim2.fromOffset(0, 166), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
		local b = UI.button(c, "", T.Good, {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -24, 0, 36), TextSize = 14})
		local iconScale = UI.new("UIScale", {}, icon)
		chests[i] = {frame = c, stroke = stroke, icon = icon, iconScale = iconScale, mins = mins, reward = reward, fill = fill, time = timeLbl, button = b}
	end

	---------------------------------------------------------------- данные и отрисовка
	local state, stateAt = nil, 0
	local busy = false

	local function setTab(name)
		currentTab = name
		for n, b in pairs(tabBtns) do
			local on = n == name
			b:SetAttribute("BaseColor", on and Color3.fromRGB(60, 120, 230) or T.Panel2)
			b.BackgroundColor3 = b:GetAttribute("BaseColor")
			pages[n].Visible = on
		end
	end
	for n, b in pairs(tabBtns) do b.Activated:Connect(function() setTab(n) end) end

	local function render()
		local st = state
		if not st then return end
		local elapsed = os.clock() - stateAt
		-- вкладка DAILY
		resetLbl.Text = ("New quests in %s"):format(clock((st.resetIn or 0) - elapsed))
		local anyDaily = false
		for i, r in ipairs(qRows) do
			local q = st.quests[i]
			r.row.Visible = q ~= nil
			if q then
				r.text.Text = q.text
				r.fill.Size = UDim2.fromScale(math.clamp(q.progress / math.max(1, q.goal), 0, 1), 1)
				r.fill.BackgroundColor3 = (q.done or q.ready) and T.Good or T.Accent
				r.prog.Text = q.done and "Completed" or ("%d / %d"):format(q.progress, q.goal)
				r.reward.Text = ("+%d gold"):format(q.reward)
				UI.setEnabled(r.button, q.ready, T.Good, q.done and "DONE" or (q.ready and "CLAIM" or "IN PROGRESS"))
				anyDaily = anyDaily or q.ready
			end
		end
		bonusLbl.Text = ("Complete all 3 quests: +%d 💎"):format(st.bonus.diamonds)
		UI.setEnabled(bonusBtn, st.bonus.ready, DIAMOND, st.bonus.done and "DONE" or (st.bonus.ready and "CLAIM" or "LOCKED"))
		dots.DAILY.Visible = anyDaily or st.bonus.ready

		-- вкладка STREAK
		local s = st.streak
		local shownCount = s.claimed and s.count or s.count + 1
		streakTitle.Text = ("Day %d streak"):format(math.max(1, shownCount))
		streakSub.Text = "Come back every day for bigger rewards — day 7 is the jackpot!"
		for i, c in ipairs(cards) do
			local r = s.rewards[i] or {}
			c.icon.Image = (r.Diamonds or 0) > 0 and ((r.Gold or 0) > 0 and UI.Icons.Chest or UI.Icons.Diamond) or UI.Icons.Bag
			c.amount.Text = rewardText(r.Gold, r.Diamonds)
			c.amount.TextColor3 = (r.Diamonds or 0) > 0 and (r.Gold or 0) == 0 and DIAMOND or GOLD
			local past = i < s.index or (s.claimed and i == s.index)
			local today = i == s.index and not s.claimed
			c.frame.BackgroundTransparency = past and 0.5 or 0
			c.icon.ImageTransparency = past and 0.5 or 0
			c.state.Text = past and "CLAIMED" or (today and "TODAY" or "")
			c.state.TextColor3 = past and T.Good or GOLD
			c.stroke.Color = today and GOLD or (c.big and GOLD or T.Line)
			c.stroke.Thickness = today and 3 or (c.big and 2 or 1)
		end
		UI.setEnabled(streakBtn, not s.claimed, T.Good, s.claimed and "COME BACK TOMORROW" or ("CLAIM DAY " .. s.index))
		if s.claimed then
			streakNote.Text = ("Next reward in %s. Miss a day and the streak starts over."):format(clock((st.resetIn or 0) - elapsed))
			streakNote.TextColor3 = T.Muted
		elseif s.lost then
			streakNote.Text = "Your streak was reset — start a new one today!"
			streakNote.TextColor3 = T.Bad
		else
			streakNote.Text = "Miss a day and the streak starts over."
			streakNote.TextColor3 = T.Muted
		end
		dots.STREAK.Visible = not s.claimed

		-- вкладка GIFTS
		local sec = (st.gifts.sec or 0) + elapsed
		giftLbl.Text = ("Played today: %d min · gifts reset every day"):format(math.floor(sec / 60))
		local anyGift = false
		for i, c in ipairs(chests) do
			local g = st.gifts.list[i]
			c.frame.Visible = g ~= nil
			if g then
				local need = g.min * 60
				local ready = g.ready or (not g.done and sec >= need)
				c.mins.Text = ("%d MIN"):format(g.min)
				c.reward.Text = rewardText(g.gold, g.diamonds)
				c.fill.Size = UDim2.fromScale(math.clamp(sec / need, 0, 1), 1)
				c.fill.BackgroundColor3 = (g.done or ready) and T.Good or T.Accent
				c.time.Text = g.done and "Opened" or (ready and "Ready to open!" or ("Opens in " .. clock(need - sec)))
				c.icon.ImageTransparency = g.done and 0.6 or 0
				c.stroke.Color = ready and T.Good or T.Line
				c.stroke.Thickness = ready and 2 or 1
				UI.setEnabled(c.button, ready, T.Good, g.done and "OPENED" or (ready and "OPEN" or "LOCKED"))
				anyGift = anyGift or ready
			end
		end
		dots.GIFTS.Visible = anyGift

		inviteLbl.Text = ("Invite a friend who's new to the game: they get +%d gold, and you get +%d gold when they join your server. Friends invited: %d"):format(
			st.invite.newGold, st.invite.friendGold, st.invite.count)
	end

	local function fetch()
		if busy then return end
		local res = ctx.invoke("Rewards", "get")
		if res.ok and res.state then
			state, stateAt = res.state, os.clock()
			render()
		end
		return res.ok and res.state
	end

	-- просьба включить уведомления игры (Roblox сам решает, можно ли её показать)
	local askedNotify = false
	local function askNotifications()
		if askedNotify then return end
		askedNotify = true
		task.spawn(function()
			local ok, can = pcall(function() return ExperienceNotificationService:CanPromptOptInAsync() end)
			if ok and can then
				task.wait(1.5)
				pcall(function() ExperienceNotificationService:PromptOptIn() end)
			end
		end)
	end

	local function pop(guiObj, scaleObj)
		scaleObj.Scale = 1.25
		TweenService:Create(scaleObj, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end

	local function claim(kind, index, popTarget)
		if busy then return end
		busy = true
		local res = ctx.invoke("Rewards", "claim", kind, index)
		busy = false
		UI.toast(res.msg or "", res.ok and "reward" or "error")
		if res.state then
			state, stateAt = res.state, os.clock()
			render()
		end
		if res.ok then
			if popTarget then pop(popTarget[1], popTarget[2]) end
			askNotifications()
		end
	end
	for i, r in ipairs(qRows) do
		r.button.Activated:Connect(function()
			if r.button:GetAttribute("Enabled") then claim("quest", i) end
		end)
	end
	bonusBtn.Activated:Connect(function()
		if bonusBtn:GetAttribute("Enabled") then claim("bonus") end
	end)
	streakBtn.Activated:Connect(function()
		if not streakBtn:GetAttribute("Enabled") or not state then return end
		local c = cards[state.streak.index]
		claim("streak", nil, c and {c.frame, c.scale})
	end)
	for i, c in ipairs(chests) do
		c.button.Activated:Connect(function()
			if c.button:GetAttribute("Enabled") then claim("gift", i, {c.icon, c.iconScale}) end
		end)
	end

	inviteBtn.Activated:Connect(function()
		local ok, can = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
		if ok and can then
			pcall(function() SocialService:PromptGameInvite(player) end)
		else
			UI.toast("Invites aren't available on this account right now", "error")
		end
	end)

	local openId = 0
	local function open(tab)
		gui.Enabled = true
		setTab(tab or currentTab)
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		render()
		openId += 1
		local my = openId
		task.spawn(function()
			while gui.Enabled and openId == my do
				fetch()
				task.wait(4)
			end
		end)
	end
	local function closeUI() gui.Enabled = false end
	close.Activated:Connect(closeUI)
	dim.Activated:Connect(closeUI)
	btn.Activated:Connect(function()
		if gui.Enabled then closeUI() else open() end
	end)

	-- счётчик на кнопке и лёгкое покачивание, пока есть что забрать
	local function updateCount()
		local n = player:GetAttribute("RewardsReady") or 0
		count.Visible = n > 0
		count.Text = tostring(n)
	end
	player:GetAttributeChangedSignal("RewardsReady"):Connect(function()
		updateCount()
		if gui.Enabled then fetch() end
	end)
	updateCount()
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		local n = player:GetAttribute("RewardsReady") or 0
		btnScale.Scale = n > 0 and 1 + 0.06 * math.max(0, math.sin(t * 4)) or 1
		hb.glow.BackgroundTransparency = n > 0 and 0.45 - 0.3 * math.sin(t * 4) or 1
		if gui.Enabled and state and math.floor(t * 4) ~= math.floor((t - dt) * 4) then render() end
	end)

	-- серия не забрана — открыть окно на вкладке STREAK (раз за заход, когда игрок в лобби)
	task.spawn(function()
		while not player:GetAttribute("DataLoaded") do task.wait(0.5) end
		task.wait(4) -- после экрана загрузки
		for _ = 1, 60 do
			if ctx.state() == "Lobby" then break end
			task.wait(5)
		end
		local st = fetch()
		if st and not st.streak.claimed and not gui.Enabled then open("STREAK") end
	end)

	return {}
end
