-- Значок ранга (только клиент): круглая нашивка с рисунком из Config.Ranks.List[i].Insignia.
-- Всё в долях размера — одинаково в кнопке, списке и BillboardGui над головой. Чем выше Tier, тем богаче:
-- 1 бронза · 2 сталь · 3 серебро · 4 золото · 5 тёмно-синий с золотом и кольцом · 6 адмиральский, блестящий обод ·
-- 7 пурпур с сиянием · 8 маршал: переливающийся фон, двойное кольцо, пульсирующее сияние.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local RankBadge = {}
local rgb = Color3.fromRGB

-- bg — градиент фона (верх, низ), rim — обод, ink — рисунок, text — цвет названия ранга
local TIERS = {
	{bg = {rgb(170, 112, 66), rgb(92, 58, 34)}, rim = rgb(205, 145, 85), ink = rgb(255, 228, 190), text = rgb(214, 160, 110)},
	{bg = {rgb(128, 142, 158), rgb(58, 68, 82)}, rim = rgb(180, 192, 206), ink = rgb(240, 245, 250), text = rgb(178, 192, 210)},
	{bg = {rgb(232, 236, 244), rgb(128, 138, 154)}, rim = rgb(255, 255, 255), ink = rgb(36, 46, 66), text = rgb(222, 230, 242), accent = rgb(255, 196, 60)},
	{bg = {rgb(255, 222, 110), rgb(184, 122, 28)}, rim = rgb(255, 242, 180), ink = rgb(92, 52, 8), text = rgb(255, 210, 90)},
	{bg = {rgb(40, 58, 112), rgb(14, 22, 52)}, rim = rgb(255, 205, 80), ink = rgb(255, 212, 96), text = rgb(255, 214, 110), ring = true},
	{bg = {rgb(26, 40, 92), rgb(8, 12, 36)}, rim = rgb(255, 215, 100), ink = rgb(255, 224, 120), text = rgb(255, 226, 130), ring = true, shine = true},
	{bg = {rgb(110, 46, 176), rgb(34, 12, 74)}, rim = rgb(255, 220, 120), ink = rgb(255, 232, 150), text = rgb(222, 170, 255), ring = true, shine = true, glow = rgb(190, 120, 255)},
	{bg = {rgb(255, 90, 90), rgb(255, 200, 60)}, rim = rgb(255, 250, 220), ink = rgb(255, 255, 255), text = rgb(255, 214, 90), ring = true, shine = true, glow = rgb(255, 210, 90), rainbow = true},
}
RankBadge.Tiers = TIERS

-- анимированные части всех значков (слабые ссылки: удалённый значок сам выпадет)
local spinning = setmetatable({}, {__mode = "k"}) -- UIGradient -> скорость, °/с
local pulsing = setmetatable({}, {__mode = "k"})  -- Frame сияния -> базовая прозрачность
if RunService:IsClient() then
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for g, speed in pairs(spinning) do
			if g.Parent then g.Rotation = (t * speed) % 360 end
		end
		for f, base in pairs(pulsing) do
			if f.Parent then f.BackgroundTransparency = base + 0.18 * (1 + math.sin(t * 3)) end
		end
	end)
end

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end
local function round(f) new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, f) return f end

-- полоска рисунка: центр (x, y), размер (w, h) и поворот — в долях значка
local function stroke(parent, ink, x, y, w, h, rot)
	local f = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
		Rotation = rot or 0, BackgroundColor3 = ink, BorderSizePixel = 0, ZIndex = 4}, parent)
	new("UICorner", {CornerRadius = UDim.new(0.35, 0)}, f)
	return f
end
local function glyph(parent, ink, text, x, y, s)
	return new("TextLabel", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(s, s),
		BackgroundTransparency = 1, Text = text, TextScaled = true, Font = Enum.Font.GothamBlack, TextColor3 = ink, ZIndex = 4}, parent)
end

local function drawInsignia(face, ins, ink, accent)
	local kind, n = ins[1], ins[2] or 1
	if kind == "dot" then
		round(new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.24, 0.24),
			BackgroundColor3 = ink, BorderSizePixel = 0, ZIndex = 4}, face))
	elseif kind == "chevron" then
		-- шевроны «^» стопкой, под ними полоски, над ними звезда
		local bars = ins.bars or 0
		local h = (n - 1) * 0.13 + bars * 0.09 + (ins.star and 0.16 or 0)
		local y = 0.53 - h / 2
		if ins.star then
			glyph(face, accent or ink, "★", 0.5, y - 0.02, 0.2)
			y += 0.16
		end
		for i = 1, n do
			local cy = y + (i - 1) * 0.13
			stroke(face, ink, 0.385, cy, 0.3, 0.085, -38)
			stroke(face, ink, 0.615, cy, 0.3, 0.085, 38)
		end
		y += (n - 1) * 0.13 + 0.13
		for i = 1, bars do
			stroke(face, ink, 0.5, y + (i - 1) * 0.09, 0.44, 0.06)
		end
		if ins.wreath then
			local r = round(new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.84, 0.84),
				BackgroundTransparency = 1, ZIndex = 3}, face))
			new("UIStroke", {Color = accent or ink, Thickness = 1.5, Transparency = 0.2}, r)
		end
	elseif kind == "bar" then
		-- офицерские вертикальные планки
		for i = 1, n do
			stroke(face, ink, 0.5 + (i - (n + 1) / 2) * 0.17, 0.5, 0.1, 0.46)
		end
	elseif kind == "diamond" then
		-- глиф ◆ в шрифте мелкий — рисуем ромб повёрнутым квадратом
		local s = n == 1 and 0.3 or (n == 2 and 0.22 or 0.17)
		local step = n == 3 and 0.27 or 0.32
		for i = 1, n do
			local d = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + (i - (n + 1) / 2) * step, 0.5),
				Size = UDim2.fromScale(s, s), Rotation = 45, BackgroundColor3 = ink, BorderSizePixel = 0, ZIndex = 4}, face)
			new("UICorner", {CornerRadius = UDim.new(0.12, 0)}, d)
		end
	elseif kind == "star" then
		local rows = ({{1}, {2}, {1, 2}, {2, 2}, {2, 3}})[n] or {n}
		local s = n == 1 and 0.5 or (n == 2 and 0.34 or 0.27)
		local top = 0.5 - (#rows - 1) * s * 0.42
		for r, cnt in ipairs(rows) do
			for i = 1, cnt do
				glyph(face, ink, "★", 0.5 + (i - (cnt + 1) / 2) * s * 0.9, top + (r - 1) * s * 0.84, s)
			end
		end
	elseif kind == "marshal" then
		glyph(face, ink, "★", 0.5, 0.5, 0.56)
		for i = 0, 4 do
			local a = math.rad(i * 72)
			glyph(face, ink, "★", 0.5 + math.sin(a) * 0.33, 0.5 - math.cos(a) * 0.33, 0.15)
		end
	end
end

-- цвет названия ранга (для подписей)
function RankBadge.textColor(rank)
	local def = Config.Ranks.List[rank] or Config.Ranks.List[1]
	return TIERS[def.Tier].text
end

-- значок ранга rank в parent; props — Position/AnchorPoint/Size (квадрат), px — примерный размер
-- в пикселях (для толщины обода). Возвращает внешний Frame.
function RankBadge.build(parent, rank, props, px)
	local def = Config.Ranks.List[rank] or Config.Ranks.List[1]
	local st = TIERS[def.Tier]
	px = px or 40
	local holder = new("Frame", {Name = "RankBadge", BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px)}, parent)
	for k, v in pairs(props or {}) do holder[k] = v end
	holder:SetAttribute("Rank", rank)
	-- сияние за значком
	if st.glow then
		local g = round(new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.38, 1.38),
			BackgroundColor3 = st.glow, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 1}, holder))
		pulsing[g] = 0.55
		local g2 = round(new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.18, 1.18),
			BackgroundColor3 = st.glow, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 1}, holder))
		pulsing[g2] = 0.35
	end
	-- внешнее кольцо (старшие офицеры и выше)
	if st.ring then
		local ring = round(new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.12, 1.12),
			BackgroundColor3 = st.rim, BorderSizePixel = 0, ZIndex = 2}, holder))
		if st.shine then
			local g = new("UIGradient", {Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, st.rim), ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.55, st.rim), ColorSequenceKeypoint.new(1, st.rim:Lerp(Color3.new(0, 0, 0), 0.35)),
			})}, ring)
			spinning[g] = 90
		end
	end
	local face = round(new("Frame", {Name = "Face", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3}, holder))
	local grad
	if st.rainbow then
		grad = new("UIGradient", {Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 80, 90)), ColorSequenceKeypoint.new(0.25, rgb(255, 190, 50)),
			ColorSequenceKeypoint.new(0.5, rgb(120, 220, 255)), ColorSequenceKeypoint.new(0.75, rgb(180, 110, 255)),
			ColorSequenceKeypoint.new(1, rgb(255, 80, 90)),
		})}, face)
		spinning[grad] = 60
	else
		grad = new("UIGradient", {Rotation = 90, Color = ColorSequence.new(st.bg[1], st.bg[2])}, face)
	end
	new("UIStroke", {Color = st.rim, Thickness = math.max(1, px / (st.ring and 26 or 18)), ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, face)
	-- у маршала поверх переливания — тёмная сердцевина, чтобы звёзды читались
	local ink = st.ink
	if st.rainbow then
		local core = round(new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.82, 0.82),
			BackgroundColor3 = rgb(30, 18, 60), BorderSizePixel = 0, ZIndex = 3}, face))
		new("UIStroke", {Color = st.rim, Thickness = math.max(1, px / 40)}, core)
		ink = rgb(255, 215, 90)
	end
	drawInsignia(face, def.Insignia, ink, st.accent)
	return holder
end

return RankBadge
