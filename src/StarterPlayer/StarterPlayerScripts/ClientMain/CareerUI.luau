-- Карьера: окно HALL OF HONOR у статуи на площади базы (подсказка CareerPrompt) и облик самой статуи.
-- Статуя у каждого игрока своя: по атрибуту CareerLevel (сколько уровней карьеры забрано, CareerService)
-- клиент локально наряжает статую СВОЕЙ базы (у статуи чужой базы — базовый каменный вид): меняет материал скульптуры (камень → бронза → серебро → золото …) и включает украшения
-- из папок Stage2..Stage6 модели CareerStatue (флаги, прожекторы, жаровни, неон, нимб и столб света).
-- На своей статуе вместо солдата — каменная копия персонажа игрока (как он одет сейчас: форма или свой скин)
-- в позе отдания чести, а на флагах Stage2 — знак его текущего ранга (RankBadge).
-- Ступени — Config.Career.Stages. Данные и награды — сервер (Remotes.Career).
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RankBadge = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RankBadge"))

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
-- что даёт каждая ступень (подпись при нажатии на ступень)
local STAGE_PERK = {"plain stone", "bronze + team flags", "silver + spotlights", "gold + fire braziers", "champion neon + sparkles", "halo, light pillar & stars"}

return function(ctx)
	local UI, T, Config = ctx.UI, ctx.UI.T, ctx.Config
	local player = ctx.player
	local C = Config.Career
	-- картинка вместо эмодзи из Config.Career (Icon)
	local I = UI.Icons
	local ICON_PIC = {["✈️"] = I.PlaneDown, ["⚓"] = I.ShipSunk, ["🚩"] = I.Capture, ["🏆"] = I.Win, ["📦"] = I.Cargo, ["🎯"] = I.Kill}
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

	-- каменная копия персонажа: клон без скриптов, одежды и текстур, все детали закреплены
	local STRIP = {"LuaSourceContainer", "Tool", "ForceField", "Sound", "Shirt", "Pants", "ShirtGraphic", "BodyColors", "Decal", "Texture",
		"SurfaceAppearance", "BillboardGui", "SurfaceGui", "ProximityPrompt", "Light", "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke",
		"Sparkles", "Highlight", "Animator", "FaceControls"}
	local function isStripped(d)
		for _, cls in ipairs(STRIP) do
			if d:IsA(cls) then return true end
		end
		return false
	end
	-- соединение двух деталей в нейтральной позе (без анимации): part0, part1 и CFrame part1 в осях part0
	local function jointRel(j)
		if j:IsA("Motor6D") or j:IsA("Weld") or j:IsA("ManualWeld") or j:IsA("Snap") then
			if j.Part0 and j.Part1 then return j.Part0, j.Part1, j.C0 * j.C1:Inverse() end
		elseif j:IsA("AnimationConstraint") or j:IsA("RigidConstraint") then
			local a0, a1 = j.Attachment0, j.Attachment1
			if a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
				return a0.Parent, a1.Parent, a0.CFrame * a1.CFrame:Inverse()
			end
		elseif j:IsA("WeldConstraint") then
			if j.Part0 and j.Part1 then return j.Part0, j.Part1, j.Part0.CFrame:ToObjectSpace(j.Part1.CFrame) end
		end
		return nil
	end
	-- повернуть детали вокруг точки
	local function turn(parts, pivot, rot)
		for _, p in ipairs(parts) do p.CFrame = CFrame.new(pivot) * rot * (p.CFrame - pivot) end
	end
	local function attPos(part, name)
		local a = part and part:FindFirstChild(name)
		return a and a:IsA("Attachment") and a.WorldPosition
	end
	local function buildFigure(char)
		if not char:FindFirstChild("HumanoidRootPart") or not char:FindFirstChild("UpperTorso") or not char:FindFirstChild("Head") then
			return nil -- только R15
		end
		local wasArchivable = char.Archivable
		char.Archivable = true
		local ok, m = pcall(function() return char:Clone() end)
		char.Archivable = wasArchivable
		if not ok or not m then return nil end
		m.Name = "AvatarFigure"
		-- нейтральная поза: обходим соединения от корня (клон застаёт персонажа в кадре анимации)
		local edges = {}
		for _, j in ipairs(m:GetDescendants()) do
			local p0, p1, rel = jointRel(j)
			if p0 and p1 and p0:IsDescendantOf(m) and p1:IsDescendantOf(m) then
				edges[p0] = edges[p0] or {}
				edges[p1] = edges[p1] or {}
				table.insert(edges[p0], {p1, rel})
				table.insert(edges[p1], {p0, rel:Inverse()})
			end
		end
		local root = m.HumanoidRootPart
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) -- в кресле корень бывает наклонён
		local seen, queue = {[root] = true}, {root}
		while #queue > 0 do
			local p = table.remove(queue, 1)
			for _, e in ipairs(edges[p] or {}) do
				if not seen[e[1]] then
					seen[e[1]] = true
					e[1].CFrame = p.CFrame * e[2]
					table.insert(queue, e[1])
				end
			end
		end
		for _, d in ipairs(m:GetDescendants()) do
			if isStripped(d) or d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("WeldConstraint") then d:Destroy() end
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
				d.Massless = true
				if d ~= root then d:SetAttribute("StatueRole", "Sculpture") end
				if d:IsA("MeshPart") then pcall(function() d.TextureID = "" end) end
			elseif d:IsA("SpecialMesh") then
				d.TextureId = ""
			end
		end
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			pcall(function() hum.EvaluateStateMachine = false end)
		end
		-- отдание чести: правое плечо в сторону и чуть вперёд, предплечье — к виску, ладонь к козырьку
		local ut, ua, la, hand, head = m:FindFirstChild("UpperTorso"), m:FindFirstChild("RightUpperArm"), m:FindFirstChild("RightLowerArm"),
			m:FindFirstChild("RightHand"), m:FindFirstChild("Head")
		local sh = attPos(ut, "RightShoulderRigAttachment")
		local el = attPos(ua, "RightElbowRigAttachment")
		if sh and el and la and hand and head then
			local tr = ut.CFrame - ut.Position
			turn({ua, la, hand}, sh, CFrame.fromRotationBetweenVectors((el - sh).Unit, tr:VectorToWorldSpace(Vector3.new(0.85, 0.12, -0.5).Unit)))
			el = attPos(ua, "RightElbowRigAttachment")
			local wr = attPos(la, "RightWristRigAttachment")
			local hs = head.Size
			local brow = (head.CFrame * CFrame.new(hs.X * 0.3, hs.Y * 0.2, -hs.Z * 0.45)).Position
			if el and wr then
				turn({la, hand}, el, CFrame.fromRotationBetweenVectors((wr - el).Unit, (brow - el).Unit))
				wr = attPos(la, "RightWristRigAttachment")
				turn({hand}, wr, CFrame.fromRotationBetweenVectors((hand.Position - wr).Unit,
					((brow - el).Unit + tr:VectorToWorldSpace(Vector3.new(-0.6, 0.3, 0))).Unit))
			end
		end
		m.PrimaryPart = root
		return m
	end
	-- признак внешности: фигуру пересобираем, только если персонаж переоделся
	local function looksOf(char)
		local parts = {}
		for _, d in ipairs(char:GetChildren()) do
			if d:IsA("Accessory") then
				table.insert(parts, "a:" .. d.Name)
			elseif d:IsA("Shirt") then
				table.insert(parts, "s:" .. d.ShirtTemplate)
			elseif d:IsA("Pants") then
				table.insert(parts, "p:" .. d.PantsTemplate)
			elseif d:IsA("MeshPart") then
				table.insert(parts, d.Name .. ":" .. d.MeshId)
			end
		end
		table.sort(parts)
		return table.concat(parts, "|")
	end
	local figureLooks -- внешность, с которой собрана текущая фигура
	local function liveChar()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and hum and hum.Health > 0 and char:FindFirstChild("UpperTorso") and char:FindFirstChild("HumanoidRootPart") then return char end
		return nil
	end
	-- своя статуя: фигура игрока вместо солдата; чужая — солдат
	local function placeFigure(st, mine)
		local soldier = st:FindFirstChild("Soldier")
		local fig = st:FindFirstChild("AvatarFigure")
		local char = liveChar()
		-- солдат мог ещё не подгрузиться (стриминг): тогда размер не знаем — ждём следующей проверки
		local soldierPart = soldier and soldier:FindFirstChildWhichIsA("BasePart", true)
		if mine and soldierPart and char then
			local looks = looksOf(char)
			if not fig or figureLooks ~= looks then
				local ok, m = pcall(buildFigure, char)
				local cf, sz = soldier:GetBoundingBox()
				local msz = ok and m and select(2, m:GetBoundingBox())
				if msz and msz.Y > 0.5 and sz.Y > 1 then
					m:ScaleTo(sz.Y * 0.92 / msz.Y)
					local mcf, msz2 = m:GetBoundingBox()
					local up = m:GetPivot().Position.Y - (mcf.Position.Y - msz2.Y / 2)
					local at = Vector3.new(cf.Position.X, cf.Position.Y - sz.Y / 2 + up, cf.Position.Z)
					local look = soldier:GetPivot().LookVector * Vector3.new(1, 0, 1)
					m:PivotTo(CFrame.lookAt(at, at + look))
					if fig then fig:Destroy() end
					m.Parent = st
					fig = m
					figureLooks = looks
				elseif ok and m then
					m:Destroy()
				end
			end
		elseif not mine and fig then
			fig:Destroy()
			fig = nil
		end
		if soldier then
			for _, p in ipairs(soldier:GetDescendants()) do
				if p:IsA("BasePart") then p.LocalTransparencyModifier = fig and 1 or 0 end
			end
		end
	end

	-- флаги Stage2 своей статуи: знак текущего ранга и его название (с обеих сторон полотнища)
	local function rankFlags(st, mine, idx)
		local stage2 = st:FindFirstChild("Stage2")
		local rank = math.clamp(player:GetAttribute("Rank") or 1, 1, #Config.Ranks.List)
		for _, flag in ipairs(stage2 and stage2:GetDescendants() or {}) do
			if flag:IsA("BasePart") and flag.Name == "Flag" then
				for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
					local name = "RankFlag" .. face.Name
					local sg = flag:FindFirstChild(name)
					if sg and (not mine or sg:GetAttribute("Rank") ~= rank) then
						sg:Destroy()
						sg = nil
					end
					if mine and not sg then
						sg = Instance.new("SurfaceGui")
						sg.Name = name
						sg.Face = face
						sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
						sg.PixelsPerStud = 40
						sg.LightInfluence = 0.6
						sg:SetAttribute("Rank", rank)
						local dark = flag.Color:Lerp(Color3.new(0, 0, 0), 0.6)
						local bg = Instance.new("Frame")
						bg.Size = UDim2.fromScale(1, 1)
						bg.BackgroundColor3 = Color3.new(1, 1, 1)
						bg.BorderSizePixel = 0
						bg.Parent = sg
						local grad = Instance.new("UIGradient")
						grad.Rotation = 90
						grad.Color = ColorSequence.new(flag.Color, dark)
						grad.Parent = bg
						local edge = Instance.new("UIStroke")
						edge.Color = RankBadge.textColor(rank)
						edge.Thickness = 8
						edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
						edge.Parent = bg
						RankBadge.build(bg, rank, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
							Size = UDim2.fromScale(0.6, 0.6), SizeConstraint = Enum.SizeConstraint.RelativeYY}, 120)
						local lbl = Instance.new("TextLabel")
						lbl.AnchorPoint = Vector2.new(0.5, 1)
						lbl.Position = UDim2.fromScale(0.5, 0.96)
						lbl.Size = UDim2.fromScale(0.92, 0.2)
						lbl.BackgroundTransparency = 1
						lbl.Font = Enum.Font.GothamBlack
						lbl.TextScaled = true
						lbl.Text = string.upper(Config.Ranks.List[rank].Name)
						lbl.TextColor3 = RankBadge.textColor(rank)
						lbl.TextStrokeTransparency = 0.3
						lbl.Parent = bg
						sg.Parent = flag
					end
					if sg then sg.Enabled = idx >= 2 end
				end
			end
		end
	end

	local applied = {} -- [статуя] = {level, count, rank, mine}
	local function applyStatue(st, level, mine)
		placeFigure(st, mine)
		local idx = stageOf(level)
		rankFlags(st, mine, idx)
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
		applied[st] = {level = level, count = #st:GetDescendants(), rank = player:GetAttribute("Rank"), mine = mine}
	end
	local function applyAll(force)
		local myLevel = player:GetAttribute("CareerLevel") or 0
		local char = liveChar()
		local looks = char and looksOf(char)
		for _, e in ipairs(statues()) do
			local st, mine = e[1], e[2]
			local level = mine and myLevel or 0
			local a = applied[st]
			-- стриминг: деталей стало больше — применяем заново; переоделся или сменился ранг — новая фигура / флаги
			local stale = force or not a or a.level ~= level or a.mine ~= mine or a.count ~= #st:GetDescendants()
			if mine and a and (a.rank ~= player:GetAttribute("Rank") or (looks and looks ~= figureLooks)
				or (char and not st:FindFirstChild("AvatarFigure"))) then
				stale = true
			end
			if stale then applyStatue(st, level, mine) end
		end
	end

	---------------------------------------------------------------- окно
	local gui = UI.screen("CareerUI", 45)
	gui.Enabled = false
	local dim = UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "", AutoButtonColor = false}, gui)
	local panel = UI.panel(gui, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 560)})
	UI.scale(panel, 0.55)
	-- подложка: нажатие по пустому месту окна не проваливается в затемнение (а оно закрывает окно)
	UI.new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 0}, panel)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(46, 40, 30), Color3.fromRGB(16, 21, 29))}, panel)
	local panelScale = UI.new("UIScale", {}, panel)
	local title = UI.label(panel, "HALL OF HONOR", {Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 38), TextSize = 32, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Center})
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 150, 40))}, title)
	UI.label(panel, "Every tier makes your statue grander · tap a stage or medal to preview it", {Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 18),
		TextSize = 13, Font = UI.Medium, TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Center})
	local close = UI.button(panel, "X", T.Panel2, {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(38, 38), TextSize = 20})
	UI.stroke(close)

	-- ступени статуи (нажатие — что даёт ступень и сколько до неё осталось)
	local chips = {}
	local CHIP_W = (608 - 5 * 6) / 6
	for i, s in ipairs(C.Stages) do
		local c = UI.new("TextButton", {Position = UDim2.fromOffset(16 + (i - 1) * (CHIP_W + 6), 78), Size = UDim2.fromOffset(CHIP_W, 44), BackgroundColor3 = T.Panel2, BorderSizePixel = 0,
			Text = "", AutoButtonColor = false}, panel)
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
		UI.plate(row)
		local r = {row = row}
		r.icon = UI.new("ImageLabel", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(44, 44),
			BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit}, row)
		r.text = UI.label(row, "", {Position = UDim2.fromOffset(54, 6), Size = UDim2.new(1, -330, 0, 20), TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd})
		local barBg = UI.new("Frame", {Position = UDim2.fromOffset(54, 32), Size = UDim2.new(1, -330, 0, 8), BackgroundColor3 = T.Panel, BorderSizePixel = 0}, row)
		UI.corner(barBg, 4)
		r.fill = UI.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.Accent, BorderSizePixel = 0}, barBg)
		UI.corner(r.fill, 4)
		UI.bar(barBg, r.fill)
		r.prog = UI.label(row, "", {Position = UDim2.fromOffset(54, 41), Size = UDim2.new(1, -330, 0, 14), TextSize = 11, Font = UI.Medium, TextColor3 = T.Muted})
		r.medals = {}
		for t = 1, 3 do
			-- медаль уровня: под ней — сколько нужно; нажатие — показать награду и прогресс этого уровня
			local md = UI.new("TextButton", {Position = UDim2.new(1, -266 + (t - 1) * 28, 0, 9), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = MEDAL[t], BorderSizePixel = 0,
				Text = "", AutoButtonColor = false}, row)
			UI.corner(md, 11)
			local mdStroke = UI.new("UIStroke", {Color = Color3.new(1, 1, 1), Transparency = 0.6, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, md)
			local goalLbl = UI.label(row, "", {Position = UDim2.new(1, -270 + (t - 1) * 28, 0, 33), Size = UDim2.fromOffset(30, 14), TextSize = 10, Font = UI.Medium,
				TextColor3 = MEDAL[t], TextXAlignment = Enum.TextXAlignment.Center})
			r.medals[t] = {frame = md, stroke = mdStroke, goal = goalLbl}
		end
		r.reward = UI.label(row, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 6), Size = UDim2.fromOffset(42, 46), TextSize = 11, TextWrapped = true, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Right})
		r.button = UI.button(row, "", T.Good, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(122, 36), TextSize = 13})
		rows[i] = r
	end

	local state
	local busy = false
	local selStage -- выбранная ступень (nil — показываем текущую)
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
			if i == selStage and not cur then c.stroke.Color, c.stroke.Thickness = T.Text, 2 end
		end
		local nextStage = C.Stages[idx + 1]
		local sel = selStage and C.Stages[selStage]
		if sel and selStage ~= idx then
			local left = sel.From - st.level
			levelLbl.Text = ("%s · %s · "):format(sel.Name, STAGE_PERK[selStage])
				.. (left > 0 and ("%d more tier%s to go"):format(left, left == 1 and "" or "s") or "unlocked")
		else
			levelLbl.Text = ("Statue: %s · %d / %d tiers"):format(C.Stages[idx].Name, st.level, st.max)
				.. (nextStage and (" · next: %s at %d"):format(nextStage.Name, nextStage.From) or " · MAXED OUT!")
		end
		for i, r in ipairs(rows) do
			local a = st.list[i]
			r.icon.Image = ICON_PIC[a.icon] or UI.Icons.Career
			r.text.Text = a.text
			local maxed = a.claimed >= 3
			-- показываемый уровень: выбранная медаль или следующий незабранный
			local tier = r.sel or math.min(a.claimed + 1, 3)
			local goal = a.tiers[tier]
			local done = tier <= a.claimed
			r.fill.Size = UDim2.fromScale((done or maxed) and 1 or math.clamp(a.count / goal, 0, 1), 1)
			r.fill.BackgroundColor3 = (done or a.count >= goal) and T.Good or MEDAL[tier]
			if r.sel then
				r.prog.Text = done and ("%s claimed · %d / %d"):format(TIER_NAME[tier], math.min(a.count, goal), goal)
					or ("%d / %d for %s · %d to go"):format(a.count, goal, TIER_NAME[tier], math.max(0, goal - a.count))
			else
				r.prog.Text = maxed and ("%d · all tiers done"):format(a.count) or ("%d / %d for %s"):format(a.count, goal, TIER_NAME[tier])
			end
			for t, md in ipairs(r.medals) do
				md.frame.BackgroundTransparency = t <= a.claimed and 0 or 0.8
				md.stroke.Transparency = t == r.sel and 0 or 0.6
				md.stroke.Thickness = t == r.sel and 2 or 1
				md.goal.Text = tostring(a.tiers[t])
			end
			local showReward = not (maxed and not r.sel)
			local rw = st.rewards[tier]
			r.reward.Text = showReward and rewardText(rw) or ""
			r.reward.TextColor3 = (rw.Diamonds or 0) > 0 and DIAMOND or T.Gold
			r.reward.TextTransparency = done and 0.5 or 0
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
		-- медаль: показать этот уровень, повторное нажатие — вернуть следующий незабранный
		for t, md in ipairs(r.medals) do
			md.frame.Activated:Connect(function()
				r.sel = r.sel ~= t and t or nil
				render()
			end)
		end
	end
	for i, c in ipairs(chips) do
		c.frame.Activated:Connect(function()
			selStage = selStage ~= i and i or nil
			render()
		end)
	end

	local function open()
		selStage = nil
		for _, r in ipairs(rows) do r.sel = nil end
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
	player:GetAttributeChangedSignal("Rank"):Connect(function() applyAll(false) end)
	player:GetPropertyChangedSignal("Team"):Connect(function() applyAll(true) end)
	task.spawn(function()
		while true do
			local ok, err = pcall(applyAll, false)
			if not ok then warn("[CareerUI] statue: " .. tostring(err)) end
			task.wait(3)
		end
	end)

	return {
		onState = function(st)
			if st ~= "Deployed" then closeUI() end
		end,
	}
end
