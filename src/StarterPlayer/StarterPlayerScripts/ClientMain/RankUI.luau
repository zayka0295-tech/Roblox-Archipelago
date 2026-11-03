-- Ранги: круглая кнопка со значком ранга под рулеткой (DailySpinUI) и окно со списком рангов, прогрессом и
-- тем, за что дают опыт. Хватает опыта на следующий ранг — кнопка загорается, в окне кнопка
-- ACCEPT PROMOTION (Remotes.Rank "confirm"), после неё — надпись «PROMOTED». Данные — атрибуты игрока XP и Rank.
-- Remotes.XPGain — всплывающее «+100 XP» рядом с кнопкой.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local RC = Config.Ranks
	local LIST = RC.List
	local RankBadge = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RankBadge"))
	local remote = ctx.Remotes:WaitForChild("Rank")
	local GOLD = Color3.fromRGB(255, 205, 90)

	local function num(n)
		local s = tostring(math.floor(n))
		return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end
	local function rank() return math.clamp(player:GetAttribute("Rank") or 1, 1, #LIST) end
	local function xp() return player:GetAttribute("XP") or 0 end
	local function pending()
		local nx = LIST[rank() + 1]
		return nx ~= nil and xp() >= nx.XP
	end

	---------------------------------------------------------------- кнопка на экране (под рулеткой)
	-- рамка как у DailySpinUI (такая же позиция и масштаб) — кнопка всегда ровно под кнопкой рулетки
	local hudGui = UI.screen("RankButton", 6)
	local frame = UI.new("Frame", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(250, 92), BackgroundTransparency = 1}, hudGui)
	UI.scale(frame)
	-- на телефоне — вплотную под рулеткой (её позиция в DailySpinUI)
	local btnX, btnY = -6, 122
	if UI.touchOnly then btnX, btnY = -16, 96 end
	-- значок ранга — картинка из RankBadge внутри диска (своей картинки у кнопки нет)
	local hb = UI.hudButton(frame, nil, "RANK", Color3.fromRGB(60, 90, 150), {
		Name = "RankButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, btnX, 1, btnY),
	})
	local btn, btnScale, btnStroke, btnGlow = hb.btn, hb.scale, hb.stroke, hb.glow
	btnGlow.BackgroundColor3 = GOLD
	local btnBadge
	local newBadge = UI.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(40, 20), Rotation = 12,
		BackgroundColor3 = Color3.fromRGB(235, 45, 60), Text = "UP!", TextColor3 = Color3.new(1, 1, 1), Font = UI.Bold, TextSize = 13, ZIndex = 6, Visible = false,
	}, btn)
	UI.corner(newBadge, 10)
	UI.new("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, newBadge)
	local btnLbl = hb.label
	-- всплывающее «+N XP» слева от кнопки
	local function floatXP(n, reason)
		local l = UI.label(frame, ("+%d XP"):format(n) .. (reason and ("  ·  " .. reason) or ""), {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, btnX - 78, 1, btnY + 33), Size = UDim2.fromOffset(260, 20),
			TextSize = 15, TextColor3 = GOLD, TextStrokeTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Right,
		})
		local info = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(l, info, {Position = l.Position - UDim2.fromOffset(0, 34), TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		task.delay(1.9, function() l:Destroy() end)
	end

	---------------------------------------------------------------- окно рангов
	local gui = UI.screen("RankUI", 45)
	gui.Enabled = false
	local dim = UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false}, gui)
	local panel = UI.panel(gui, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 600)})
	UI.scale(panel, 0.55)
	-- подложка: нажатие по пустому месту окна не проваливается в затемнение (а оно закрывает окно)
	UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 0}, panel)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(34, 42, 62), Color3.fromRGB(16, 21, 29))}, panel)
	UI.label(panel, "RANKS", {Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -80, 0, 34), TextSize = 30, TextColor3 = GOLD})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(38, 38), TextSize = 20})

	-- текущий ранг и прогресс
	local head = UI.new("Frame", {Position = UDim2.fromOffset(20, 58), Size = UDim2.new(1, -40, 0, 112), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, panel)
	UI.corner(head, 10)
	UI.plate(head)
	local headBadgeHolder = UI.new("Frame", {Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(80, 80), BackgroundTransparency = 1}, head)
	local curName = UI.label(head, "", {Position = UDim2.fromOffset(116, 12), Size = UDim2.new(1, -130, 0, 28), TextSize = 24})
	local curSub = UI.label(head, "", {Position = UDim2.fromOffset(116, 40), Size = UDim2.new(1, -130, 0, 18), TextSize = 14, Font = UI.Medium, TextColor3 = T.Muted})
	local barBg = UI.new("Frame", {Position = UDim2.fromOffset(116, 64), Size = UDim2.new(1, -132, 0, 12), BackgroundColor3 = T.Panel, BorderSizePixel = 0}, head)
	UI.corner(barBg, 6)
	local bar = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD, BorderSizePixel = 0}, barBg)
	UI.corner(bar, 6)
	UI.bar(barBg, bar)
	local barTxt = UI.label(head, "", {Position = UDim2.fromOffset(116, 80), Size = UDim2.new(1, -132, 0, 18), TextSize = 13, Font = UI.Medium, TextColor3 = T.Text})
	-- повышение ждёт подтверждения
	local accept = UI.button(head, "ACCEPT PROMOTION", T.Good, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0, 26), Size = UDim2.fromOffset(200, 36), TextSize = 15, Visible = false, ZIndex = 3})
	local acceptStroke = UI.new("UIStroke", {Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, accept)

	-- список рангов (слева) и за что дают опыт (справа)
	local scroll = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 182), Size = UDim2.new(0, 360, 1, -202), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, ScrollBarImageColor3 = T.Line, CanvasSize = UDim2.fromOffset(0, #LIST * 52), ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	UI.new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
	local rows = {}
	for i, def in ipairs(LIST) do
		local row = UI.new("Frame", {LayoutOrder = i, Size = UDim2.new(1, -12, 0, 48), BackgroundColor3 = T.Panel2, BackgroundTransparency = 0.25, BorderSizePixel = 0}, scroll)
		UI.corner(row, 8)
		UI.plate(row)
		local rs = UI.new("UIStroke", {Color = GOLD, Thickness = 2, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, row)
		RankBadge.build(row, i, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0)}, 34)
		local name = UI.label(row, def.Name, {Position = UDim2.fromOffset(56, 6), Size = UDim2.new(1, -150, 0, 20), TextSize = 15, TextColor3 = RankBadge.textColor(i), TextTruncate = Enum.TextTruncate.AtEnd})
		local req = UI.label(row, i == 1 and "Start" or (num(def.XP) .. " XP"), {Position = UDim2.fromOffset(56, 26), Size = UDim2.new(1, -150, 0, 16), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted})
		local st = UI.label(row, "", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(90, 18), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right})
		rows[i] = {row = row, stroke = rs, name = name, req = req, status = st}
	end

	local how = UI.new("Frame", {Position = UDim2.new(0, 396, 0, 182), Size = UDim2.new(1, -416, 1, -202), BackgroundColor3 = T.Panel2, BackgroundTransparency = 0.25, BorderSizePixel = 0}, panel)
	UI.corner(how, 8)
	UI.plate(how)
	UI.padding(how, 12)
	UI.label(how, "HOW TO EARN XP", {Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = GOLD})
	local X = RC.XP
	local ways = {
		{"Kill an enemy player", X.Kill}, {"Kill a bot", X.BotKill},
		{"Shoot down a plane", X.PlaneKill}, {"Sink a gunboat", X.Sink.Gunboat},
		{"Sink a submarine", X.Sink.Submarine}, {"Sink a battleship", X.Sink.Battleship},
		{"Destroy a carrier", X.CarrierKill}, {"Capture an island", X.Capture},
		{"Neutralize an island", X.Neutralize}, {"Cargo delivered", X.Delivery},
		{"Sink a cargo ship", X.CargoKill}, {"Destroy a cargo truck", X.TruckKill},
		{"Complete a quest", X.Quest}, {"Win a round", X.RoundWin},
		{"Play a round", X.RoundLoss}, {"Each minute in battle", X.PlayMinute},
	}
	for k, w in ipairs(ways) do
		local y = 26 + (k - 1) * 22
		UI.label(how, w[1], {Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -60, 0, 20), TextSize = 13, Font = UI.Medium, TextColor3 = T.Text})
		UI.label(how, "+" .. w[2], {Position = UDim2.new(1, -60, 0, y), Size = UDim2.fromOffset(60, 20), TextSize = 13, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right})
	end

	---------------------------------------------------------------- «PROMOTED»
	local cer = UI.screen("RankPromotion", 60)
	local cerFrame = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(520, 300), BackgroundTransparency = 1, Visible = false}, cer)
	UI.scale(cerFrame, 0.6)
	local cerScale = UI.new("UIScale", {}, cerFrame)
	local cerTitle = UI.label(cerFrame, "PROMOTED!", {Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 50), TextSize = 46, TextColor3 = GOLD, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center})
	local cerHolder = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(150, 150), BackgroundTransparency = 1}, cerFrame)
	local cerName = UI.label(cerFrame, "", {Position = UDim2.fromOffset(0, 232), Size = UDim2.new(1, 0, 0, 40), TextSize = 32, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center})
	local function ceremony(r)
		for _, c in ipairs(cerHolder:GetChildren()) do c:Destroy() end
		RankBadge.build(cerHolder, r, {Size = UDim2.fromScale(1, 1)}, 150)
		cerName.Text = string.upper(LIST[r].Name)
		cerName.TextColor3 = RankBadge.textColor(r)
		cerFrame.Visible = true
		cerScale.Scale = 0.2
		TweenService:Create(cerScale, TweenInfo.new(0.5, Enum.EasingStyle.Back), {Scale = 1}):Play()
		task.delay(3.2, function()
			TweenService:Create(cerScale, TweenInfo.new(0.3), {Scale = 0}):Play()
			task.delay(0.32, function() cerFrame.Visible = false end)
		end)
	end

	---------------------------------------------------------------- обновление
	local shownRank
	local busy = false
	local function refresh()
		local r, x = rank(), xp()
		if shownRank ~= r then
			shownRank = r
			if btnBadge then btnBadge:Destroy() end
			btnBadge = RankBadge.build(hb.body, r, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8)}, 48)
			for _, c in ipairs(headBadgeHolder:GetChildren()) do c:Destroy() end
			RankBadge.build(headBadgeHolder, r, {Size = UDim2.fromScale(1, 1)}, 80)
		end
		local def, nx = LIST[r], LIST[r + 1]
		curName.Text = string.upper(def.Name)
		curName.TextColor3 = RankBadge.textColor(r)
		local ready = pending()
		if nx then
			local span = nx.XP - def.XP
			bar.Size = UDim2.fromScale(math.clamp((x - def.XP) / span, 0, 1), 1)
			curSub.Text = ("Rank %d of %d · next: %s"):format(r, #LIST, nx.Name)
			barTxt.Text = ready and ("%s XP · promotion to %s is ready!"):format(num(x), nx.Name)
				or ("%s / %s XP · %s to go"):format(num(x), num(nx.XP), num(nx.XP - x))
		else
			bar.Size = UDim2.fromScale(1, 1)
			curSub.Text = ("Rank %d of %d · the highest rank"):format(r, #LIST)
			barTxt.Text = num(x) .. " XP"
		end
		accept.Visible = ready
		if ready and not busy then UI.setEnabled(accept, true, T.Good, "ACCEPT PROMOTION") end
		for i, row in ipairs(rows) do
			local reached = i <= r
			row.row.BackgroundTransparency = i == r and 0 or 0.25
			row.stroke.Transparency = (i == r or (ready and i == r + 1)) and 0 or 1
			row.stroke.Color = i == r and GOLD or T.Good
			if i == r then
				row.status.Text, row.status.TextColor3 = "CURRENT", GOLD
			elseif reached then
				row.status.Text, row.status.TextColor3 = "REACHED", T.Good
			elseif ready and i == r + 1 then
				row.status.Text, row.status.TextColor3 = "READY!", T.Good
			elseif x >= LIST[i].XP then
				-- опыта хватает, но сначала подтвердить предыдущие
				row.status.Text, row.status.TextColor3 = "XP READY", T.Good:Lerp(T.Muted, 0.4)
			else
				row.status.Text, row.status.TextColor3 = num(math.max(0, LIST[i].XP - x)) .. " to go", T.Muted
			end
		end
		btnLbl.Text = ready and "PROMOTION!" or string.upper(def.Name)
		btnLbl.TextColor3 = ready and GOLD or RankBadge.textColor(r)
		newBadge.Visible = ready
	end

	local function open()
		gui.Enabled = true
		refresh()
		-- список — на текущий ранг
		scroll.CanvasPosition = Vector2.new(0, math.max(0, (rank() - 3) * 52))
		panel.Size = UDim2.fromOffset(580, 560)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Size = UDim2.fromOffset(620, 600)}):Play()
	end
	local function shut() gui.Enabled = false end
	btn.Activated:Connect(function() if gui.Enabled then shut() else open() end end)
	close.Activated:Connect(shut)
	dim.Activated:Connect(shut)

	accept.Activated:Connect(function()
		if busy or not accept:GetAttribute("Enabled") then return end
		busy = true
		UI.setEnabled(accept, false, T.Good, "…")
		local ok, res = pcall(function() return remote:InvokeServer("confirm") end)
		busy = false
		if not ok or type(res) ~= "table" or not res.ok then
			UI.toast(type(res) == "table" and res.msg or "Promotion failed — try again", "error")
			refresh()
			return
		end
		shut()
		ceremony(res.rank)
		UI.toast(("You are now %s!"):format(LIST[res.rank].Name), "success")
	end)

	player:GetAttributeChangedSignal("XP"):Connect(function() if gui.Enabled then refresh() end end)
	player:GetAttributeChangedSignal("Rank"):Connect(refresh)
	ctx.Remotes:WaitForChild("XPGain").OnClientEvent:Connect(function(n, reason)
		if type(n) == "number" and frame.Visible then floatXP(n, reason) end
	end)

	-- кнопка: есть повышение — горит золотом и пульсирует
	local acc = 0
	local wasReady
	RunService.RenderStepped:Connect(function(dt)
		frame.Visible = player:GetAttribute("Rank") ~= nil -- и в лобби, и в бою
		if not frame.Visible then gui.Enabled = false return end
		local t = os.clock()
		local ready = pending()
		if ready ~= wasReady then
			wasReady = ready
			refresh()
		end
		if ready then
			btnScale.Scale = 1 + 0.05 * math.sin(t * 4)
			btnStroke.Color = GOLD
			btnStroke.Transparency = 0.4 - 0.4 * math.sin(t * 4)
			btnGlow.BackgroundTransparency = 0.55 + 0.25 * math.sin(t * 4)
			acceptStroke.Transparency = 0.5 - 0.5 * math.sin(t * 5)
		else
			btnScale.Scale = 1
			btnStroke.Color = UI.Outline
			btnStroke.Transparency = 0
			btnGlow.BackgroundTransparency = 1
		end
		acc += dt
		if acc > 1 then
			acc = 0
			if not gui.Enabled then refresh() end
		end
	end)

	refresh()
	return {}
end
