-- Ранг над головой других игроков (и своих, и врагов): значок + название в цвете ранга, над стандартным именем.
-- Высокие ранги крупнее и видны дальше. В технике значок скрыт (не загораживает обзор). Ранг — атрибут Rank игрока.
-- VIP (атрибут VIP) — ещё золотая плашка «👑 VIP» перед значком, заметна издалека.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

return function(ctx)
	local Config = ctx.Config
	local LIST = Config.Ranks.List
	local RankBadge = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RankBadge"))
	local tags = {} -- [игрок] = {bb, rank, char, vip}
	local VIP_GOLD = Color3.fromRGB(255, 200, 50)

	local function remove(p)
		local t = tags[p]
		if t and t.bb then t.bb:Destroy() end
		tags[p] = nil
	end

	local function build(p, char, r, vip)
		remove(p)
		local head = char:FindFirstChild("Head")
		if not head then return end
		local def = LIST[r]
		local tier = def.Tier
		local px = 24 + tier * 2 -- выше ранг — крупнее значок
		local bb = Instance.new("BillboardGui")
		bb.Name = "RankTag"
		bb.Size = UDim2.fromOffset(vip and 300 or 220, px + 4)
		bb.StudsOffset = Vector3.new(0, 3.4, 0)
		bb.MaxDistance = 70 + tier * 15 + (vip and 60 or 0)
		bb.LightInfluence = 0
		bb.Adornee = head
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, 1)
		row.Parent = bb
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.SortOrder = Enum.SortOrder.LayoutOrder -- VIP → значок → название
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 6)
		layout.Parent = row
		if vip then
			local pill = Instance.new("TextLabel")
			pill.LayoutOrder = 0
			pill.AutomaticSize = Enum.AutomaticSize.X
			pill.Size = UDim2.fromOffset(0, math.floor(px * 0.75))
			pill.BackgroundColor3 = Color3.new(1, 1, 1)
			pill.Text = " 👑 VIP "
			pill.Font = Enum.Font.GothamBlack
			pill.TextSize = 14
			pill.TextColor3 = Color3.fromRGB(70, 40, 0)
			Instance.new("UICorner", pill).CornerRadius = UDim.new(0.5, 0)
			local g = Instance.new("UIGradient")
			g.Rotation = 90
			g.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(235, 160, 30))
			g.Parent = pill
			local s = Instance.new("UIStroke")
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Color = Color3.fromRGB(255, 250, 210)
			s.Thickness = 1.5
			s.Parent = pill
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
			pad.Parent = pill
			pill.Parent = row
		end
		RankBadge.build(row, r, {LayoutOrder = 1}, px)
		local name = Instance.new("TextLabel")
		name.LayoutOrder = 2
		name.AutomaticSize = Enum.AutomaticSize.X
		name.Size = UDim2.fromOffset(0, px)
		name.BackgroundTransparency = 1
		name.Text = def.Name
		name.Font = tier >= 5 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		name.TextSize = 13 + math.min(tier, 6)
		name.TextColor3 = RankBadge.textColor(r)
		name.TextStrokeTransparency = 0.35
		name.Parent = row
		local shine
		if tier >= 6 then
			-- адмиралы и маршал: по названию бежит белый блик (текст белый, цвет ранга — в градиенте)
			local c = name.TextColor3
			name.TextColor3 = Color3.new(1, 1, 1)
			shine = Instance.new("UIGradient")
			shine.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, c), ColorSequenceKeypoint.new(0.42, c), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.58, c), ColorSequenceKeypoint.new(1, c),
			})
			shine.Parent = name
		end
		bb.Parent = head
		tags[p] = {bb = bb, rank = r, char = char, shine = shine, vip = vip}
	end

	Players.PlayerRemoving:Connect(remove)

	RunService.RenderStepped:Connect(function()
		local x = (os.clock() * 0.6) % 2.6 - 1.3
		for _, t in pairs(tags) do
			if t.shine then t.shine.Offset = Vector2.new(x, 0) end
		end
	end)

	-- раз в полсекунды: новые персонажи, смена ранга, сел/встал в технику
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then return end
		acc = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= ctx.player then
				local char = p.Character
				local r = p:GetAttribute("Rank")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not char or type(r) ~= "number" or not LIST[r] or not hum or hum.Health <= 0 then
					remove(p)
				else
					local t = tags[p]
					local vip = p:GetAttribute("VIP") == true
					if not t or t.rank ~= r or t.char ~= char or t.vip ~= vip or not t.bb.Parent then
						build(p, char, r, vip)
						t = tags[p]
					end
					if t then t.bb.Enabled = hum.SeatPart == nil end
				end
			end
		end
	end)

	return {}
end
