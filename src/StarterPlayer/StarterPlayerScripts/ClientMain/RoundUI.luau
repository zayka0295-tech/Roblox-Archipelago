-- Раунд: полоска под панелью золота (номер, таймер, счёт команд) и баннер итога (Remotes.RoundResult).
-- Всё состояние — атрибуты GameState Round_* (см. RoundService).
local RunService = game:GetService("RunService")

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

	-- баннер итога раунда
	local gui = UI.screen("RoundUI", 40)
	local banner = UI.panel(gui, {Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(520, 170), Visible = false})
	UI.scale(banner, 0.6)
	UI.padding(banner, 16)
	local title = UI.label(banner, "", {Size = UDim2.new(1, 0, 0, 48), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center})
	local scoreLbl = UI.label(banner, "", {Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 24), TextSize = 18, RichText = true, Font = UI.Medium, TextXAlignment = Enum.TextXAlignment.Center})
	local personal = UI.label(banner, "", {Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 48), TextSize = 20, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center})
	local shown = 0

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
		banner.Visible = true
		shown += 1
		local my = shown
		task.delay(9, function()
			if shown == my then banner.Visible = false end
		end)
	end)

	return {}
end
