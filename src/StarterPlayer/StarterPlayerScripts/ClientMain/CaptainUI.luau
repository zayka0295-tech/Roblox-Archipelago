-- Капитан (обучение новичка, см. TutorialService): окно диалога, строка текущего задания
-- под левой колонкой HUD, значок над головой («!» — есть что сказать), анимация стояния.
-- Шаг 3 (пройдено): Капитана для этого игрока нет — прячем модель, значок и кнопку «Talk» локально.
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local IDLE_ANIM = "rbxassetid://507766388" -- стандартное «стояние» R15 от Roblox

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local TC = Config.Tutorial

	local function step() return player:GetAttribute("Tutorial") or 0 end
	-- шаг 3 пришёл прямо сейчас (а не был с входа): Капитан ждёт, пока игрок дочитает прощание
	local lastStep = player:GetAttribute("Tutorial")
	local finaleAt = nil
	player:GetAttributeChangedSignal("Tutorial"):Connect(function()
		local s = step()
		if s >= 3 and lastStep ~= nil and lastStep < 3 then finaleAt = os.clock() end
		lastStep = s
	end)

	------------------------------------------------------------ Капитаны на карте
	local captains = {} -- {model, mark, prompt}
	local refresh -- объявлена ниже
	local function refreshSoon() task.defer(function() if refresh then refresh() end end) end
	local function hookCaptain(cap)
		local head = cap:WaitForChild("Head", 10)
		local hum = cap:FindFirstChildOfClass("Humanoid")
		if not head or not hum then return end
		-- анимация стояния (только у этого клиента)
		pcall(function()
			local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
			local a = Instance.new("Animation")
			a.AnimationId = IDLE_ANIM
			local track = animator:LoadAnimation(a)
			track.Looped = true
			track:Play()
		end)
		local bb = Instance.new("BillboardGui")
		bb.Name = "CaptainMark"
		bb.Size = UDim2.fromOffset(120, 54)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 140
		bb.Adornee = head
		local mark = UI.label(bb, "!", {Size = UDim2.new(1, 0, 0, 30), TextSize = 30, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3})
		UI.label(bb, "CAPTAIN", {Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4})
		bb.Parent = player.PlayerGui
		table.insert(captains, {model = cap, mark = mark, bb = bb, root = cap:FindFirstChild("HumanoidRootPart"), hidden = false})
		refreshSoon()
	end
	-- StreamingEnabled: базы подгружаются позже и могут выгружаться — раз в секунду ищем
	-- ещё не подхваченных Капитанов (см. цикл обновления ниже)
	local hooked = setmetatable({}, {__mode = "k"})
	local function scanCaptains()
		local map = workspace:FindFirstChild("Map")
		local teams = map and map:FindFirstChild("Teams")
		for _, base in ipairs(teams and teams:GetChildren() or {}) do
			local decor = base:FindFirstChild("Decor")
			local cap = decor and decor:FindFirstChild("Captain")
			if cap and not hooked[cap] then
				hooked[cap] = true
				task.spawn(hookCaptain, cap)
			end
		end
	end

	local function setHidden(c, hide, fade)
		if c.hidden == hide then return end
		c.hidden = hide
		c.bb.Enabled = not hide
		local prompt = c.root and c.root:FindFirstChild("TalkPrompt")
		if prompt then prompt.Enabled = not hide end
		for _, p in ipairs(c.model:GetDescendants()) do
			if p:IsA("BasePart") or p:IsA("Decal") then
				if fade and hide then
					TweenService:Create(p, TweenInfo.new(1.6), {LocalTransparencyModifier = 1}):Play()
				else
					p.LocalTransparencyModifier = hide and 1 or 0
				end
			end
		end
		if fade and hide and c.root then
			-- уходит: искры на секунду
			local sp = Instance.new("Sparkles")
			sp.SparkleColor = T.Gold
			sp.Parent = c.root
			task.delay(1.8, function() sp:Destroy() end)
		end
	end

	------------------------------------------------------------ строка задания (под левой колонкой HUD)
	local side = player.PlayerGui:WaitForChild("HUD"):WaitForChild("Side")
	local goal = UI.panel(side, {Name = "CaptainTask", Position = UDim2.fromOffset(0, 200), Size = UDim2.new(1, 0, 0, 56), Visible = false})
	goal.BackgroundTransparency = 0.2
	UI.stroke(goal, T.Gold, 1)
	UI.padding(goal, 8)
	UI.label(goal, "CAPTAIN'S TASK", {Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = T.Gold})
	local goalLbl = UI.label(goal, "", {Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 24), TextSize = 14, Font = UI.Medium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})

	function refresh()
		local s = step()
		local ready = player:GetAttribute("TutReady") == true
		local deployed = ctx.state() == "Deployed"
		local text
		if s == 0 then
			text = "Talk to the Captain at the quest board"
		elseif s == 1 or s == 2 then
			if ready then
				text = "Done! Return to the Captain"
			else
				local need = s == 1 and TC.FlyDistance or TC.SailDistance
				local have = math.min(need, player:GetAttribute("TutProgress") or 0)
				text = ("%s %g km: %d / %d m"):format(s == 1 and "Fly a plane" or "Sail a boat", need / 1000, have, need)
			end
		end
		goal.Visible = deployed and text ~= nil
		if text then goalLbl.Text = text end
		-- выгруженные (стриминг) Капитаны убираем из списка
		for i = #captains, 1, -1 do
			if not captains[i].model.Parent then captains[i].bb:Destroy() table.remove(captains, i) end
		end
		for _, c in ipairs(captains) do
			local waiting = finaleAt and os.clock() - finaleAt < 20
			if not c.fading and not waiting then setHidden(c, s >= 3, false) end
			c.mark.Text = (s == 0 or ready) and "!" or "…"
		end
	end
	for _, a in ipairs({"Tutorial", "TutReady", "TutProgress", "State"}) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	task.spawn(function()
		while true do
			scanCaptains()
			refresh()
			task.wait(1)
		end
	end)

	------------------------------------------------------------ диалог
	local gui = UI.screen("CaptainUI", 35)
	-- повыше нижнего края: там слоты рюкзака Roblox
	local box = UI.panel(gui, {Name = "Dialog", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -76), Size = UDim2.fromOffset(560, 150), Visible = false})
	UI.scale(box, 0.62)
	UI.stroke(box, T.Gold, 2)
	UI.padding(box, 14)
	UI.label(box, "CAPTAIN", {Size = UDim2.new(1, 0, 0, 20), TextSize = 17, TextColor3 = T.Gold})
	local line = UI.label(box, "", {Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 66), TextSize = 18, Font = UI.Medium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top})
	local nextBtn = UI.button(box, "NEXT", T.Good, {AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(130, 36), TextSize = 16})
	local pageLbl = UI.label(box, "", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(120, 20), TextSize = 13, TextColor3 = T.Muted})

	local pages, page, onDone = {}, 1, nil
	local function show()
		line.Text = pages[page] or ""
		pageLbl.Text = #pages > 1 and ("%d / %d"):format(page, #pages) or ""
		nextBtn.Text = page < #pages and "NEXT" or "OK"
	end
	local function advance()
		if not box.Visible then return end
		if page < #pages then
			page += 1
			show()
		else
			box.Visible = false
			if onDone then local f = onDone onDone = nil f() end
		end
	end
	nextBtn.Activated:Connect(advance)
	-- на ПК — и клавишей Enter
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then advance() end
	end)

	ctx.Remotes:WaitForChild("Captain").OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" or type(msg.lines) ~= "table" then return end
		pages, page = msg.lines, 1
		onDone = nil
		if msg.final then
			-- финал: пока читает, Капитан стоит; закрыл окно — уходит
			for _, c in ipairs(captains) do c.fading = true end
			onDone = function()
				finaleAt = nil
				for _, c in ipairs(captains) do setHidden(c, true, true) c.fading = false end
				UI.toast("Training complete — good luck, soldier!", "success")
			end
		end
		box.Visible = true
		show()
	end)

	return {}
end
