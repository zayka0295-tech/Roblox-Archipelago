-- Суд: список тиммейтов и голос за изгнание (открывается плитой JUDGE в лобби, Remotes.OpenJudge).
-- Считает и решает всё сервер (JudgeService); окно показывает список и обновляет его, пока открыто.
return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local gui = UI.screen("JudgeUI", 24)
	local panel = UI.panel(gui, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 420), Visible = false,
	})
	UI.scale(panel, 0.8)
	UI.padding(panel, 16)
	UI.label(panel, "⚖ JUDGE · VOTE KICK", {TextSize = 22, TextColor3 = Color3.fromRGB(200, 160, 255)})
	local info = UI.label(panel, "", {
		Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -40, 0, 50), TextSize = 13, Font = UI.Medium,
		TextColor3 = T.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -4), Size = UDim2.fromOffset(36, 36), TextSize = 16})
	UI.stroke(close)
	local list = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 1, -84), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
	}, panel)
	UI.new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, list)

	local busy = false
	local refresh -- ниже
	local function render(res)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
		end
		if not res.ok then
			info.Text = res.msg or ""
			return
		end
		info.Text = ("A teammate is removed from this server when %d of your teammates vote. Votes expire after %d min. Only vote for real cheaters or griefers.")
			:format(res.needed, math.floor(Config.Judge.VoteTTL / 60))
			.. (res.canVote and "" or ("\n" .. (res.reason or "")))
		if #res.rows == 0 then
			UI.label(list, "No teammates on the server", {Size = UDim2.new(1, 0, 0, 30), TextSize = 15, Font = UI.Medium, TextColor3 = T.Muted})
		end
		for i, r in ipairs(res.rows) do
			local row = UI.new("Frame", {LayoutOrder = i, Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = T.Panel2, BorderSizePixel = 0}, list)
			UI.corner(row, 8)
			UI.plate(row)
			local tc = r.team and Config.Teams[r.team]
			UI.label(row, r.name, {Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 22), TextSize = 16, TextColor3 = tc and tc.Color or T.Text})
			UI.label(row, ("@%s · %s"):format(r.user, tc and tc.DisplayName or "lobby"), {
				Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -170, 0, 16), TextSize = 12, Font = UI.Medium, TextColor3 = T.Muted,
			})
			UI.label(row, ("%d/%d"):format(r.votes, res.needed), {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -124, 0.5, 0), Size = UDim2.fromOffset(44, 20),
				TextSize = 15, TextColor3 = r.votes > 0 and T.Bad or T.Muted, TextXAlignment = Enum.TextXAlignment.Right,
			})
			local b = UI.button(row, "", T.Bad, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(104, 36), TextSize = 13})
			UI.setEnabled(b, res.canVote and not r.protected, r.mine and T.Panel or T.Bad, r.protected and "OWNER" or (r.mine and "UNVOTE" or "VOTE KICK"))
			b.Activated:Connect(function()
				if busy then return end
				busy = true
				local v = ctx.invoke("Judge", "vote", r.id)
				busy = false
				UI.toast(v.msg or "", v.ok and "success" or "error")
				refresh()
			end)
		end
	end
	function refresh()
		if panel.Visible then render(ctx.invoke("Judge", "list")) end
	end

	local api = {}
	function api.open()
		panel.Visible = true
		refresh()
	end
	function api.close()
		panel.Visible = false
	end
	function api.onState(state)
		if state ~= "Lobby" then panel.Visible = false end
	end
	close.Activated:Connect(api.close)
	ctx.Remotes:WaitForChild("OpenJudge").OnClientEvent:Connect(function()
		if ctx.state() == "Lobby" then api.open() end
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			if not busy then refresh() end
		end
	end)
	return api
end
