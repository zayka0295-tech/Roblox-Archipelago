-- Ежедневная рулетка: круглая кнопка под панелью островов (крутящееся мини-колесо, бейдж FREE)
-- и окно с колесом. Приз выбирает сервер (DailySpinService), колесо только докручивается до него.
-- Доступность — атрибут игрока LastSpin (os.time) + Config.DailySpin.Cooldown.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SEG = 60 -- градусов на сектор (6 призов)
local SPIN_TIME = 5.5

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local S = Config.DailySpin
	local remote = ctx.Remotes:WaitForChild("DailySpin")

	-- цвет и подпись приза: чем ценнее, тем ярче
	local function look(pz)
		if pz.Kind == "Diamonds" then
			return pz.Amount >= 100 and Color3.fromRGB(185, 105, 255) or Color3.fromRGB(70, 175, 255), "💎"
		end
		local c = pz.Amount >= 10000 and Color3.fromRGB(255, 95, 45)
			or pz.Amount >= 1000 and Color3.fromRGB(255, 190, 40)
			or pz.Amount >= 100 and Color3.fromRGB(205, 150, 60)
			or Color3.fromRGB(140, 110, 75)
		return c, "GOLD"
	end
	local function short(n)
		return n >= 1000 and ((n % 1000 == 0) and ("%dK"):format(n // 1000) or ("%.1fK"):format(n / 1000)) or tostring(n)
	end
	local function clock(sec)
		sec = math.max(0, math.floor(sec))
		return ("%d:%02d:%02d"):format(sec // 3600, sec // 60 % 60, sec % 60)
	end
	local function circle(f) UI.corner(f, 0) f:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0) return f end

	-- сколько ждать до спина (0 — можно), nil — данные ещё не загружены
	local function waitLeft()
		local last = player:GetAttribute("LastSpin")
		if type(last) ~= "number" then return nil end
		return math.max(0, last + S.Cooldown - workspace:GetServerTimeNow())
	end

	---------------------------------------------------------------- кнопка на экране
	-- рамка того же размера и масштаба, что панель островов (IslandsUI): кнопка всегда ровно под ней
	local hudGui = UI.screen("DailySpinButton", 6)
	local frame = UI.new("Frame", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(250, 92), BackgroundTransparency = 1}, hudGui)
	UI.scale(frame)

	-- на телефоне кнопка ближе к правому краю и к панели островов (так же сдвинута кнопка ранга в RankUI)
	local SPIN_ON, SPIN_OFF = Color3.fromRGB(255, 160, 40), Color3.fromRGB(80, 92, 112)
	local hb = UI.hudButton(frame, UI.Icons.Spin, "DAILY SPIN", SPIN_ON, {
		Name = "SpinButton", AnchorPoint = Vector2.new(1, 0),
		Position = UI.touchOnly and UDim2.new(1, 8, 1, 6) or UDim2.new(1, -6, 1, 12),
	})
	local btn, btnScale = hb.btn, hb.scale
	-- бейдж FREE
	local badge = UI.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(46, 20), Rotation = 12,
		BackgroundColor3 = Color3.fromRGB(235, 45, 60), Text = "FREE", TextColor3 = Color3.new(1, 1, 1), Font = UI.Bold, TextSize = 13, ZIndex = 3,
	}, btn)
	UI.corner(badge, 10)
	UI.new("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, badge)
	local badgeScale = UI.new("UIScale", {}, badge)
	-- подпись под кнопкой: DAILY SPIN или таймер
	local btnLbl = hb.label

	---------------------------------------------------------------- окно с колесом
	local gui = UI.screen("DailySpinUI", 45)
	gui.Enabled = false
	local dim = UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false}, gui)
	local panel = UI.panel(gui, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(440, 560)})
	UI.scale(panel, 0.55)
	-- подложка: нажатие по пустому месту окна не проваливается в затемнение (а оно закрывает окно)
	UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 0}, panel)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 48, 70), Color3.fromRGB(16, 21, 29))}, panel)
	UI.ribbon(panel, "DAILY SPIN", {Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(340, 72)})
	local sub = UI.label(panel, "One free spin every 24 hours", {Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(38, 38), TextSize = 20})

	-- колесо
	local WHEEL = 330
	local wheelHolder = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(WHEEL, WHEEL), BackgroundTransparency = 1}, panel)
	local rim = circle(UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 200, 70)}, wheelHolder))
	UI.new("UIGradient", {Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(255, 235, 150), Color3.fromRGB(200, 120, 30))}, rim)
	-- лампочки по ободу (мигают)
	local bulbs = {}
	for i = 1, 18 do
		local a = math.rad(i * 20)
		bulbs[i] = circle(UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.sin(a) * (WHEEL / 2 - 8), 0.5, -math.cos(a) * (WHEEL / 2 - 8)),
			Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2,
		}, rim))
	end
	local disc = circle(UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(WHEEL - 32, WHEEL - 32), BackgroundColor3 = Color3.fromRGB(22, 28, 44), ZIndex = 2}, wheelHolder))
	local R = (WHEEL - 32) / 2
	local medals = {}
	for i, pz in ipairs(S.Prizes) do
		local col, unit = look(pz)
		-- разделитель между секторами (от центра к ободу)
		local da = (i - 1) * SEG + SEG / 2
		local r = math.rad(da)
		UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.sin(r) * R / 2, 0.5, -math.cos(r) * R / 2),
			Size = UDim2.fromOffset(3, R), Rotation = da, BackgroundColor3 = Color3.fromRGB(255, 210, 90), BorderSizePixel = 0, ZIndex = 3,
		}, disc)
		-- сектор: цветной медальон с призом
		local a = math.rad((i - 1) * SEG)
		local m = circle(UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.sin(a) * R * 0.6, 0.5, -math.cos(a) * R * 0.6),
			Size = UDim2.fromOffset(82, 82), Rotation = (i - 1) * SEG, BackgroundColor3 = col, ZIndex = 4,
		}, disc))
		UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.35), col:Lerp(Color3.new(0, 0, 0), 0.25))}, m)
		local ms = UI.new("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.5}, m)
		UI.label(m, short(pz.Amount), {Position = UDim2.fromScale(0, 0.16), Size = UDim2.fromScale(1, 0.42), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, ZIndex = 5})
		UI.label(m, unit, {Position = UDim2.fromScale(0, 0.56), Size = UDim2.fromScale(1, 0.26), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5, ZIndex = 5})
		medals[i] = {frame = m, stroke = ms}
	end
	local hub = circle(UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Color3.fromRGB(255, 210, 90), ZIndex = 6}, wheelHolder))
	UI.new("UIGradient", {Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(255, 245, 190), Color3.fromRGB(210, 130, 30))}, hub)
	UI.label(hub, "★", {Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(150, 70, 10), ZIndex = 7})
	-- указатель сверху
	local pointer = UI.label(wheelHolder, "▼", {
		AnchorPoint = Vector2.new(0.5, 0.15), Position = UDim2.new(0.5, 0, 0, -16), Size = UDim2.fromOffset(46, 46), TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(255, 70, 70), TextStrokeTransparency = 0, ZIndex = 8,
	})

	-- кнопка SPIN и результат
	local spinBtn = UI.button(panel, "SPIN!", T.Good, {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 438), Size = UDim2.fromOffset(240, 54), TextSize = 26})
	local result = UI.label(panel, "", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 432), Size = UDim2.new(1, -20, 0, 64), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, Visible = false, ZIndex = 9})
	local resultScale = UI.new("UIScale", {}, result)
	-- шансы — честно и на виду
	local odds = {}
	for _, pz in ipairs(S.Prizes) do table.insert(odds, ("%s %s %d%%"):format(short(pz.Amount), pz.Kind == "Gold" and "gold" or "💎", pz.Weight)) end
	UI.label(panel, "Chances: " .. table.concat(odds, " · "), {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 32),
		TextSize = 12, Font = UI.Medium, TextWrapped = true, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center,
	})

	---------------------------------------------------------------- логика
	local spinning = false
	local winner = nil

	local function refreshSpinBtn()
		if spinning then return end
		local left = waitLeft()
		if left == nil then
			UI.setEnabled(spinBtn, false, T.Good, "Loading…")
		elseif left > 0 then
			UI.setEnabled(spinBtn, false, T.Good, "Next spin in " .. clock(left))
		else
			UI.setEnabled(spinBtn, true, T.Good, "SPIN!")
		end
	end

	local function open()
		gui.Enabled = true
		if not spinning then
			result.Visible = false
			spinBtn.Visible = true
		end
		refreshSpinBtn()
		panel.Size = UDim2.fromOffset(400, 510)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Size = UDim2.fromOffset(440, 560)}):Play()
	end
	local function shut()
		if spinning then return end -- пока крутится — не закрываем, приз должен быть виден
		gui.Enabled = false
	end
	btn.Activated:Connect(function() if gui.Enabled then shut() else open() end end)
	close.Activated:Connect(shut)
	dim.Activated:Connect(shut)

	local ERR = {
		Cooldown = "You already spun today — come back later!",
		Syncing = "Your data is still loading — try again in a moment",
		NoData = "Your data is still loading — try again in a moment",
	}

	local function showResult(i)
		local pz = S.Prizes[i]
		local col = look(pz)
		local jackpot = pz.Weight <= 3
		result.Text = (jackpot and "JACKPOT! " or "YOU WON ") .. ("+%s %s"):format(short(pz.Amount), pz.Kind == "Gold" and "GOLD" or "💎")
		result.TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.2)
		result.Visible = true
		spinBtn.Visible = false
		resultScale.Scale = 0.3
		TweenService:Create(resultScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), {Scale = 1}):Play()
		winner = i
		UI.toast(("Daily spin: +%s %s"):format(short(pz.Amount), pz.Kind == "Gold" and "gold" or "💎"), "success")
		task.delay(6, function()
			if winner == i and not spinning then
				winner = nil
				result.Visible = false
				spinBtn.Visible = true
				refreshSpinBtn()
			end
		end)
	end

	spinBtn.Activated:Connect(function()
		if spinning or not spinBtn:GetAttribute("Enabled") then return end
		spinning = true
		winner = nil
		UI.setEnabled(spinBtn, false, T.Good, "…")
		local ok, res = pcall(function() return remote:InvokeServer() end)
		if not ok or type(res) ~= "table" or not res.ok or not S.Prizes[res.index] then
			spinning = false
			UI.toast(ERR[type(res) == "table" and res.err] or "Spin failed — try again", "error")
			refreshSpinBtn()
			return
		end
		-- докрутить так, чтобы сектор приза оказался под указателем (наверху), с небольшим разбросом внутри сектора
		local cur = disc.Rotation
		local want = -(res.index - 1) * SEG + (math.random() - 0.5) * SEG * 0.25
		local target = cur + 360 * 6 + ((want - cur) % 360)
		local tw = TweenService:Create(disc, TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Rotation = target})
		tw:Play()
		tw.Completed:Wait()
		disc.Rotation = target % 360
		spinning = false
		showResult(res.index)
	end)

	---------------------------------------------------------------- анимации каждый кадр
	local lastTick = 0
	local acc = 0
	local spinReady -- что сейчас нарисовано на кнопке (перекрашиваем только при смене)
	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local left = waitLeft()
		local ready = left == 0
		frame.Visible = left ~= nil -- и в лобби, и в бою
		if not frame.Visible and not spinning then gui.Enabled = false end
		-- кнопка: готово — яркая, пульсирует, колесо крутится, иногда покачивается; иначе серая с таймером
		if ready then
			if not spinReady then
				spinReady = true
				hb.setColor(SPIN_ON)
				hb.icon.ImageColor3 = Color3.new(1, 1, 1)
			end
			btnScale.Scale = 1 + 0.06 * math.sin(t * 4)
			hb.glow.BackgroundTransparency = 0.45 - 0.3 * math.sin(t * 4)
			local ph = t % 3.5
			btn.Rotation = ph < 0.6 and 10 * math.sin(ph / 0.6 * math.pi * 3) * (1 - ph / 0.6) or 0
			badge.Visible = true
			badgeScale.Scale = 1 + 0.12 * math.abs(math.sin(t * 3))
			btnLbl.Text = "DAILY SPIN"
			btnLbl.TextColor3 = T.Gold
		else
			if spinReady ~= false then
				spinReady = false
				hb.setColor(SPIN_OFF)
				hb.icon.ImageColor3 = Color3.fromRGB(150, 150, 160) -- приглушённая, пока ждём
			end
			btnScale.Scale = 1
			hb.glow.BackgroundTransparency = 1
			btn.Rotation = 0
			badge.Visible = false
			btnLbl.Text = left and clock(left) or ""
			btnLbl.TextColor3 = T.Muted
		end
		if not gui.Enabled then return end
		-- лампочки бегут (быстрее во время спина)
		local speed = spinning and 14 or 4
		for i, b in ipairs(bulbs) do
			b.BackgroundColor3 = (math.floor(t * speed) + i) % 2 == 0 and Color3.new(1, 1, 1) or Color3.fromRGB(255, 120, 60)
		end
		-- указатель «щёлкает» на каждом разделителе
		local sector = math.floor((disc.Rotation + SEG / 2) / SEG)
		if sector ~= lastTick then
			lastTick = sector
			if spinning then pointer.Rotation = -18 end
		end
		pointer.Rotation *= math.max(0, 1 - dt * 12)
		-- выигравший медальон мигает
		for i, m in ipairs(medals) do
			if winner == i then
				m.stroke.Thickness = 5
				m.stroke.Transparency = 0.5 - 0.5 * math.sin(t * 10)
			else
				m.stroke.Thickness = 2
				m.stroke.Transparency = 0.5
			end
		end
		acc += dt
		if acc >= 0.5 then acc = 0 refreshSpinBtn() end
	end)

	return {}
end
