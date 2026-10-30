-- Карьера: окно HALL OF HONOR у статуи на площади базы (подсказка CareerPrompt) и облик самой статуи.
-- Статуя у каждого игрока своя: по атрибуту CareerLevel (сколько уровней карьеры забрано, CareerService)
-- клиент локально наряжает статую СВОЕЙ базы (у статуи чужой базы — базовый каменный вид): меняет материал скульптуры (камень → бронза → серебро → золото …) и включает украшения
-- из папок Stage2..Stage6 модели CareerStatue (флаги, прожекторы, жаровни, неон, нимб и столб света).
-- Ступени — Config.Career.Stages. Данные и награды — сервер (Remotes.Career).
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

-- облик скульптуры на каждой ступени
local LOOK = {
	{Enum.Material.Slate, Color3.fromRGB(125, 125, 130), 0},
	{Enum.Material.Metal, Color3.fromRGB(170, 108, 58), 0.1},
	{Enum.Material.Metal, Color3.fromRGB(205, 210, 220), 0.25},
	{Enum.Material.Metal, Color3.fromRGB(255, 195, 70), 0.3},
	{Enum.Material.Foil, Color3.fromRGB(255, 205, 85), 0.35},
	{Enum.Material.Foil, Color3.fromRGB(255, 220, 120), 0.45},
}
local MEDAL = {Color3.fromRGB(205, 127, 50), Color3.fromRGB(200, 205, 215), Color3.fromRGB(255, 200, 60)}
local TIER_NAME = {"BRONZE", "SILVER", "GOLD"}

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local C = Config.Career
	ctx.Remotes:WaitForChild("Career")
	local DIAMOND = Color3.fromRGB(120, 220, 255)

	local function stageOf(level)
		local idx = 1
		for i, s in ipairs(C.Stages) do
			if level >= s.From then idx = i end
		end
		return idx
	end

	---------------------------------------------------------------- статуи на базах
	-- {статуя, своя ли база}
	local function statues()
		local list = {}
		local map = workspace:FindFirstChild("Map")
		local teams = map and map:FindFirstChild("Teams")
		local mine = ctx.team()
		for _, base in ipairs(teams and teams:GetChildren() or {}) do
			local decor = base:FindFirstChild("Decor")
			local st = decor and decor:FindFirstChild("CareerStatue")
			if st then table.insert(list, {st, mine ~= nil and base.Name == mine .. "Base"}) end
		end
		return list
	end
	local applied = {} -- [статуя] = {level, count}
	local function applyStatue(st, level)
		local idx = stageOf(level)
		local look = LOOK[idx]
		for _, d in ipairs(st:GetDescendants()) do
			local role = d:GetAttribute("StatueRole")
			if role == "Sculpture" and d:IsA("BasePart") then
				d.Material, d.Color, d.Reflectance = look[1], look[2], look[3]
			end
			local folder = d.Parent
			local n = folder and folder:IsA("Folder") and tonumber(folder.Name:match("^Stage(%d)$"))
			if not n and folder then
				local f2 = folder.Parent
				n = f2 and f2:IsA("Folder") and tonumber(f2.Name:match("^Stage(%d)$"))
			end
			if n then
				local on = idx >= n
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = on and 0 or 1
				elseif d:IsA("Light") or d:IsA("Fire") or d:IsA("ParticleEmitter") or d:IsA("Beam") then
					d.Enabled = on
				end
			end
		end
		local plaque = st:FindFirstChild("Plaque")
		local stageLbl = plaque and plaque:FindFirstChild("SurfaceGui") and plaque.SurfaceGui:FindFirstChild("Stage")
		if stageLbl then stageLbl.Text = ("%s · %d/%d"):format(C.Stages[idx].Name, level, #C.List * 3) end
		applied[st] = {level = level, count = #st:GetDescendants()}
	end
	local function applyAll(force)
		local myLevel = player:GetAttribute("CareerLevel") or 0
		for _, e in ipairs(statues()) do
			local st, level = e[1], e[2] and myLevel or 0
			local a = applied[st]
			-- стриминг: деталей стало больше — применяем заново
			if force or not a or a.level ~= level or a.count ~= #st:GetDescendants() then applyStatue(st, level) end
		end
	end

	---------------------------------------------------------------- окно
	local gui = UI.screen("CareerUI", 45)
	gui.Enabled = false
	local dim = UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false}, gui)
	local panel = UI.panel(gui, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 560)})
	UI.scale(panel, 0.55)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(46, 40, 30), Color3.fromRGB(16, 21, 29))}, panel)
	local panelScale = UI.new("UIScale", {}, panel)
	local title = UI.label(panel, "HALL OF HONOR", {Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 38), TextSize = 32, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center})
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 150, 40))}, title)
	UI.label(panel, "Lifetime achievements · every tier makes your statue grander", {Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 18),
		TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(38, 38), TextSize = 20})
	UI.stroke(close)

	-- ступени статуи
	local chips = {}
	local CHIP_W = (608 - 5 * 6) / 6
	for i, s in ipairs(C.Stages) do
		local c = UI.new("Frame", {Position = UDim2.fromOffset(16 + (i - 1) * (CHIP_W + 6), 78), Size = UDim2.fromOffset(CHIP_W, 44), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, panel)
		UI.corner(c, 8)
		local stroke = UI.new("UIStroke", {Color = T.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, c)
		local name = UI.label(c, s.Name, {Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = LOOK[i][2], TextXAlignment = Enum.TextXAlignment.Center})
		local from = UI.label(c, ("%d+"):format(s.From), {Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
		chips[i] = {frame = c, stroke = stroke, name = name, from = from}
	end
	local levelLbl = UI.label(panel, "", {Position = UDim2.fromOffset(16, 128), Size = UDim2.new(1, -32, 0, 18), TextSize = 14, TextColor3 = T.Text, TextXAlignment = Enum.TextXAlignment.Center})

	-- достижения
	local rows = {}
	for i = 1, #C.List do
		local row = UI.new("Frame", {Position = UDim2.fromOffset(16, 154 + (i - 1) * 64), Size = UDim2.new(1, -32, 0, 58), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, panel)
		UI.corner(row, 8)
		local r = {row = row}
		r.icon = UI.new("TextLabel", {Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(44, 58), BackgroundTransparency = 1, Text = "", TextSize = 28, Font = UI.Bold}, row)
		r.text = UI.label(row, "", {Position = UDim2.fromOffset(54, 6), Size = UDim2.new(1, -330, 0, 20), TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd})
		local barBg = UI.new("Frame", {Position = UDim2.fromOffset(54, 32), Size = UDim2.new(1, -330, 0, 8), BackgroundColor3 = T.Panel, BorderSizePixel = 0}, row)
		UI.corner(barBg, 4)
		r.fill = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0}, barBg)
		UI.corner(r.fill, 4)
		r.prog = UI.label(row, "", {Position = UDim2.fromOffset(54, 41), Size = UDim2.new(1, -330, 0, 14), TextSize = 11, Font = UI.Medium, TextColor3 = T.Muted})
		r.medals = {}
		for t = 1, 3 do
			local md = UI.new("Frame", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, -266 + (t - 1) * 28, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = MEDAL[t], BorderSizePixel = 0}, row)
			UI.corner(md, 11)
			UI.new("UIStroke", {Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 1}, md)
			r.medals[t] = md
		end
		r.reward = UI.label(row, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 6), Size = UDim2.fromOffset(42, 46), TextSize = 11, TextWrapped = true, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Right})
		r.button = UI.button(row, "", T.Good, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(122, 36), TextSize = 13})
		rows[i] = r
	end

	local state
	local busy = false
	local function rewardText(r)
		local parts = {}
		if (r.Gold or 0) > 0 then table.insert(parts, ("%d gold"):format(r.Gold)) end
		if (r.Diamonds or 0) > 0 then table.insert(parts, ("%d 💎"):format(r.Diamonds)) end
		return table.concat(parts, "\n")
	end
	local function render()
		local st = state
		if not st then return end
		local idx = stageOf(st.level)
		for i, c in ipairs(chips) do
			local cur = i == idx
			c.stroke.Color = cur and T.Gold or T.Line
			c.stroke.Thickness = cur and 3 or 1
			c.frame.BackgroundTransparency = i > idx and 0.5 or 0
		end
		local nextStage = C.Stages[idx + 1]
		levelLbl.Text = ("Statue: %s · %d / %d tiers"):format(C.Stages[idx].Name, st.level, st.max)
			.. (nextStage and (" · next: %s at %d"):format(nextStage.Name, nextStage.From) or " · MAXED OUT!")
		for i, r in ipairs(rows) do
			local a = st.list[i]
			r.icon.Text = a.icon
			r.text.Text = a.text
			local goal = a.tiers[math.min(a.claimed + 1, 3)]
			local maxed = a.claimed >= 3
			r.fill.Size = UDim2.fromScale(maxed and 1 or math.clamp(a.count / goal, 0, 1), 1)
			r.fill.BackgroundColor3 = (maxed or a.ready) and T.Good or MEDAL[math.min(a.claimed + 1, 3)]
			r.prog.Text = maxed and ("%d · all tiers done"):format(a.count) or ("%d / %d for %s"):format(a.count, goal, TIER_NAME[a.claimed + 1])
			for t, md in ipairs(r.medals) do md.BackgroundTransparency = t <= a.claimed and 0 or 0.8 end
			r.reward.Text = maxed and "" or rewardText(st.rewards[a.claimed + 1])
			r.reward.TextColor3 = (not maxed and (st.rewards[a.claimed + 1].Diamonds or 0) > 0) and DIAMOND or T.Gold
			UI.setEnabled(r.button, a.ready, T.Good, maxed and "COMPLETE" or (a.ready and ("CLAIM " .. TIER_NAME[a.claimed + 1]) or "IN PROGRESS"))
			r.id = a.id
		end
	end
	local function fetch()
		if busy then return end
		local res = ctx.invoke("Career", "get")
		if res.ok and res.state then state = res.state render() end
	end
	for _, r in ipairs(rows) do
		r.button.Activated:Connect(function()
			if busy or not r.id or not r.button:GetAttribute("Enabled") then return end
			busy = true
			local res = ctx.invoke("Career", "claim", r.id)
			busy = false
			UI.toast(res.msg or "", res.ok and "reward" or "error")
			if res.state then state = res.state render() end
		end)
	end

	local function open()
		gui.Enabled = true
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		fetch()
	end
	local function closeUI() gui.Enabled = false end
	close.Activated:Connect(closeUI)
	dim.Activated:Connect(closeUI)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "CareerPrompt" then open() end
	end)

	player:GetAttributeChangedSignal("CareerLevel"):Connect(function() applyAll(false) end)
	player:GetPropertyChangedSignal("Team"):Connect(function() applyAll(true) end)
	task.spawn(function()
		while true do
			applyAll(false)
			task.wait(3)
		end
	end)

	return {
		onState = function(st)
			if st ~= "Deployed" then closeUI() end
		end,
	}
end
