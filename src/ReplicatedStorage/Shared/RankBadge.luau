-- Значок ранга (только клиент): картинка из Config.Icons.Ranks[i] (assets/icons/ranks).
-- Всё в долях размера — одинаково в кнопке, списке и BillboardGui над головой. Tier задаёт цвет подписи,
-- у адмиралов и маршала (7–8) за значком пульсирует сияние.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)
local Icons = require(ReplicatedStorage.Config.Icons)

local RankBadge = {}
local rgb = Color3.fromRGB

-- text — цвет названия ранга, glow — сияние за значком
local TIERS = {
	{text = rgb(200, 206, 216)},
	{text = rgb(178, 192, 210)},
	{text = rgb(222, 230, 242)},
	{text = rgb(255, 210, 90)},
	{text = rgb(255, 214, 110)},
	{text = rgb(255, 226, 130)},
	{text = rgb(255, 220, 120), glow = rgb(255, 200, 80)},
	{text = rgb(255, 214, 90), glow = rgb(120, 190, 255)},
}
RankBadge.Tiers = TIERS

-- сияние всех значков (слабые ссылки: удалённый значок сам выпадет)
local pulsing = setmetatable({}, {__mode = "k"}) -- Frame сияния -> базовая прозрачность
if RunService:IsClient() then
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for f, base in pairs(pulsing) do
			if f.Parent then f.BackgroundTransparency = base + 0.15 * (1 + math.sin(t * 3)) end
		end
	end)
end

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end

-- цвет названия ранга (для подписей)
function RankBadge.textColor(rank)
	local def = Config.Ranks.List[rank] or Config.Ranks.List[1]
	return TIERS[def.Tier].text
end

-- значок ранга rank в parent; props — Position/AnchorPoint/Size (квадрат), px — примерный размер
-- в пикселях (если Size не задан). Возвращает внешний Frame.
function RankBadge.build(parent, rank, props, px)
	local def = Config.Ranks.List[rank] or Config.Ranks.List[1]
	local st = TIERS[def.Tier]
	px = px or 40
	local holder = new("Frame", {Name = "RankBadge", BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px)}, parent)
	for k, v in pairs(props or {}) do holder[k] = v end
	holder:SetAttribute("Rank", rank)
	if st.glow then
		local g = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.05, 1.05),
			BackgroundColor3 = st.glow, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 1}, holder)
		new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, g)
		-- мягкий край: к краю круга сияние тает
		new("UIGradient", {Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1),
		})}, g)
		pulsing[g] = 0.6
	end
	new("ImageLabel", {Name = "Face", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.1, 1.1),
		BackgroundTransparency = 1, Image = Icons.Ranks[rank] or Icons.Ranks[1], ScaleType = Enum.ScaleType.Fit, ZIndex = 3}, holder)
	return holder
end

return RankBadge
