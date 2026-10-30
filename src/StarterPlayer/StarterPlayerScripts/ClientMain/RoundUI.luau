-- Раунд: полоска под панелью золота (номер, таймер, счёт команд) и экран итогов (Remotes.RoundResult):
-- победитель, награда, личная статистика за раунд, звания с золотом и лучшие игроки.
-- Всё состояние — атрибуты GameState Round_* (см. RoundService).
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local GameState = ctx.GameState
	local DIAMOND = Color3.fromRGB(120, 220, 255)

	local function teamName(t) return Config.Teams[t] and string.upper(Config.Teams[t].DisplayName) or t end
	local function hex(c) return string.format("#%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255) end
	local function clock(sec)
		sec = math.max(0, math.floor(sec))
		return ("%d:%02d"):format(sec // 60, sec % 60)
	end

	-- полоска крепится под HUD.Stats (и масштабируется вместе с ней)
	local hud = player.PlayerGui:WaitForChild("HUD")
	local stats = hud:WaitForChild("Stats")
	local strip = UI.panel(stats, {Name = "Round", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.new(1, 0, 0, 26)})
	strip.BackgroundTransparency = 0.3
	local stripLbl = UI.label(strip, "", {Size = UDim2.fromScale(1, 1), TextSize = 15, RichText = true, TextXAlignment = Enum.TextXAlignment.Center})

	local function refresh()
		local st = GameState:GetAttribute("Round_State")
		local endsAt = GameState:GetAttribute("Round_EndsAt") or 0
		local left = endsAt - workspace:GetServerTimeNow()
		if st == "Active" then
			local b, r = GameState:GetAttribute("Round_Score_Blue") or 0, GameState:GetAttribute("Round_Score_Red") or 0
			stripLbl.Text = ('ROUND %d · %s   <font color="%s">%s %d</font> : <font color="%s">%d %s</font>'):format(
				GameState:GetAttribute("Round_Number") or 1, clock(left),
				hex(Config.Teams.Blue.Color), teamName("Blue"), b, hex(Config.Teams.Red.Color), r, teamName("Red"))
		elseif st == "Intermission" then
			stripLbl.Text = ("Round over · next round in %s"):format(clock(left))
		else
			stripLbl.Text = ""
		end
		strip.Visible = stripLbl.Text ~= ""
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then acc = 0 refresh() end
	end)
	refresh()

	-- экран итогов раунда: победитель и счёт, награда, личная статистика, звания с золотом, лучшие игроки
	local TITLE_KEYS = {"MVP", "Ace", "Captain", "Conqueror"}
	local TITLE_LOOK = {
		MVP = {"👑", "MVP", "points"}, Ace = {"✈️", "ACE", "planes shot down"},
		Captain = {"⚓", "CAPTAIN", "ships sunk"}, Conqueror = {"🚩", "CONQUEROR", "island captures"},
	}
	local gui = UI.screen("RoundUI", 40)
	local banner = UI.panel(gui, {Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 520), Visible = false})
	UI.scale(banner, 0.55)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(36, 46, 66), Color3.fromRGB(16, 21, 29))}, banner)
	local bannerScale = UI.new("UIScale", {}, banner)
	UI.padding(banner, 16)
	local title = UI.label(banner, "", {Size = UDim2.new(1, 0, 0, 46), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center})
	local scoreLbl = UI.label(banner, "", {Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 24), TextSize = 18, RichText = true, Font = UI.Medium, TextXAlignment = Enum.TextXAlignment.Center})
	local personal = UI.label(banner, "", {Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center})
	local closeBtn = UI.button(banner, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(34, 34), TextSize = 16})
	UI.stroke(closeBtn)

	-- твой раунд
	UI.label(banner, "YOUR ROUND", {Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = T.Muted})
	local MY = {{"kills", "KILLS"}, {"planes", "PLANES"}, {"sinks", "SHIPS"}, {"caps", "CAPTURES"}, {"score", "POINTS"}, {"place", "PLACE"}}
	local myCells = {}
	for i, m in ipairs(MY) do
		local c = UI.new("Frame", {Position = UDim2.new((i - 1) / 6, 2, 0, 124), Size = UDim2.new(1 / 6, -4, 0, 58), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, banner)
		UI.corner(c, 8)
		myCells[m[1]] = UI.label(c, "0", {Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 28), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center})
		UI.label(c, m[2], {Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
	end

	-- звания
	UI.label(banner, "ROUND HONOURS", {Position = UDim2.fromOffset(0, 192), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = T.Muted})
	local titleCards = {}
	for i = 1, 4 do
		local c = UI.new("Frame", {Position = UDim2.new((i - 1) / 4, 3, 0, 212), Size = UDim2.new(1 / 4, -6, 0, 92), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, banner)
		UI.corner(c, 8)
		titleCards[i] = {
			stroke = UI.new("UIStroke", {Color = T.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, c),
			head = UI.label(c, "", {Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center}),
			who = UI.label(c, "", {Position = UDim2.fromOffset(4, 28), Size = UDim2.new(1, -8, 0, 20), TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Center}),
			what = UI.label(c, "", {Position = UDim2.fromOffset(4, 50), Size = UDim2.new(1, -8, 0, 16), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center}),
			gold = UI.label(c, "", {Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center}),
		}
	end

	-- лучшие игроки
	UI.label(banner, "TOP PLAYERS", {Position = UDim2.fromOffset(0, 314), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = T.Muted})
	local COLS = {{"#", 0.06}, {"PLAYER", 0.38}, {"KILLS", 0.11}, {"PLANES", 0.11}, {"SHIPS", 0.11}, {"CAPS", 0.11}, {"POINTS", 0.12}}
	local boardBox = UI.new("Frame", {Position = UDim2.fromOffset(0, 334), Size = UDim2.new(1, 0, 0, 140), BackgroundColor3 = T.Panel2, BackgroundTransparency = 0.3, BorderSizePixel = 0}, banner)
	UI.corner(boardBox, 8)
	local function rowLabels(y, size, color)
		local labels, x = {}, 0
		for _, col in ipairs(COLS) do
			table.insert(labels, UI.label(boardBox, "", {Position = UDim2.new(x, col[1] == "PLAYER" and 6 or 0, 0, y), Size = UDim2.new(col[2], 0, 0, 20), TextSize = size,
				TextColor3 = color or T.Text, TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = col[1] == "PLAYER" and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center}))
			x += col[2]
		end
		return labels
	end
	for i, lbl in ipairs(rowLabels(4, 11, T.Muted)) do lbl.Text = COLS[i][1] end
	local boardRows = {}
	for i = 1, 5 do boardRows[i] = rowLabels(4 + i * 22, 14) end
	local footer = UI.label(banner, "", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
	local shown = 0
	closeBtn.Activated:Connect(function() banner.Visible = false end)

	ctx.Remotes:WaitForChild("RoundResult").OnClientEvent:Connect(function(res)
		if type(res) ~= "table" then return end
		local w = res.winner
		if w and Config.Teams[w] then
			title.Text = teamName(w) .. " WINS!"
			title.TextColor3 = Config.Teams[w].Color
		else
			title.Text = "DRAW"
			title.TextColor3 = T.Text
		end
		scoreLbl.Text = ('<font color="%s">%s %d</font>  :  <font color="%s">%d %s</font>'):format(
			hex(Config.Teams.Blue.Color), teamName("Blue"), res.blue or 0, hex(Config.Teams.Red.Color), res.red or 0, teamName("Red"))
		if (res.diamonds or 0) > 0 then
			personal.Text = ("Victory reward: +%d 💎"):format(res.diamonds)
			personal.TextColor3 = DIAMOND
		elseif not w then
			personal.Text = "No winner this time — no diamonds"
			personal.TextColor3 = T.Muted
		elseif res.team == w then
			personal.Text = ("Play at least %d min of a round for your team to earn 💎 (you played %d min)"):format(
				math.floor((res.needSec or 0) / 60), math.floor((res.playedSec or 0) / 60))
			personal.TextColor3 = T.Muted
		else
			personal.Text = "Your team lost this round. Next one is yours!"
			personal.TextColor3 = T.Muted
		end

		local me = type(res.me) == "table" and res.me or {}
		for key, lbl in pairs(myCells) do
			local v = me[key]
			lbl.Text = key == "place" and (v and ("#%d"):format(v) or "—") or tostring(v or 0)
		end

		local titles = type(res.titles) == "table" and res.titles or {}
		for i, card in ipairs(titleCards) do
			local key = TITLE_KEYS[i]
			local look = TITLE_LOOK[key]
			local tt
			for _, x in ipairs(titles) do
				if x.key == key then tt = x end
			end
			card.head.Text = look[1] .. " " .. look[2]
			local mine = tt ~= nil and tt.userId == player.UserId
			if tt then
				card.who.Text = tt.name
				card.who.TextColor3 = Config.Teams[tt.team] and Config.Teams[tt.team].Color or T.Text
				card.what.Text = ("%d %s"):format(tt.value, look[3])
				card.gold.Text = (tt.gold or 0) > 0 and ("+%d gold"):format(tt.gold) or ""
			else
				card.who.Text, card.who.TextColor3, card.what.Text, card.gold.Text = "—", T.Muted, "nobody this round", ""
			end
			card.stroke.Color = mine and T.Gold or T.Line
			card.stroke.Thickness = mine and 3 or 1
		end

		local board = type(res.board) == "table" and res.board or {}
		for i, labels in ipairs(boardRows) do
			local b = board[i]
			local vals = b and {i, b.name, b.kills, b.planes, b.sinks, b.caps, b.score} or {"", "", "", "", "", "", ""}
			for j, lbl in ipairs(labels) do
				lbl.Text = tostring(vals[j])
				local color = T.Text
				if b and j == 2 and Config.Teams[b.team] then color = Config.Teams[b.team].Color
				elseif b and b.userId == player.UserId then color = T.Gold end
				lbl.TextColor3 = color
			end
		end
		local bonus = me.bonus or 0
		footer.Text = (bonus > 0 and ("Your honours: +%d gold · "):format(bonus) or "") .. "Next round starts soon"

		banner.Visible = true
		bannerScale.Scale = 0.8
		TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		shown += 1
		local my = shown
		task.delay(math.max(8, (Config.Round.Intermission or 20) - 1), function()
			if shown == my then banner.Visible = false end
		end)
	end)

	return {}
end
