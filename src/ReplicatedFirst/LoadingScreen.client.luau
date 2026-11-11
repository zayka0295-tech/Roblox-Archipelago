-- Экран загрузки: держится, пока игра не загружена, персонаж не появился, карта вокруг него
-- не подгружена (StreamingEnabled) и не скачаны звуки / эффекты / текстуры — иначе первые секунды лагают.
-- Каждый этап с таймаутом: дольше MAX_TIME экран не держим.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MIN_TIME, MAX_TIME = 1.5, 25
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local t0 = os.clock()

local BG = Color3.fromRGB(12, 17, 24)
local PANEL = Color3.fromRGB(26, 33, 44)
local TEXT = Color3.fromRGB(232, 238, 245)
local MUTED = Color3.fromRGB(140, 152, 168)
local GOLD = Color3.fromRGB(255, 205, 90)

-- Два слоя: арт на весь экран (под панелью Roblox и чёлкой) и подписи с полосой в безопасной зоне.
-- Арт заполняет экран целиком (без полей): на широком экране (телефон) лишнее по высоте срезается в основном
-- снизу — логотип наверху остаётся; на узком (планшет) — поровну с боков. Только на вертикальном экране арт
-- вписывается целиком, а поля заполняет он же, затемнённый.
local ART = "rbxassetid://71909187303311" -- тот же id, что Icons.KeyArt (ReplicatedStorage здесь ещё может быть не загружен)
-- Roblox ужимает любую картинку до 1024 пикселей по большей стороне — арт 1672×941 одним файлом на большом
-- экране мылится. Поэтому он загружен четырьмя плитками 2×2 и собирается обратно в полном разрешении.
-- У каждой плитки запас 4 пикселя от соседей (ox/oy — где в файле начинается её часть): без запаса на стыке видна линия.
local ART_W, ART_H = 1672, 941
local TILES = {
	{id = 101258587333500, x = 0, y = 0, w = 836, h = 470, ox = 0, oy = 0},
	{id = 85022625253475, x = 836, y = 0, w = 836, h = 470, ox = 4, oy = 0},
	{id = 133069170251856, x = 0, y = 470, w = 836, h = 471, ox = 0, oy = 4},
	{id = 85315244586944, x = 836, y = 470, w = 836, h = 471, ox = 4, oy = 4},
}
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = BG
back.BorderSizePixel = 0
back.Parent = gui
local backArt = Instance.new("ImageLabel")
backArt.Size = UDim2.fromScale(1, 1)
backArt.BackgroundTransparency = 1
backArt.Image = ART
backArt.ScaleType = Enum.ScaleType.Crop
backArt.ImageColor3 = Color3.fromRGB(90, 100, 120) -- приглушённый, чтобы основной арт выделялся
backArt.Parent = back
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = BG
dim.BackgroundTransparency = 0.25 -- виден, пока плитки не скачаны, и на полях вертикального экрана
dim.BorderSizePixel = 0
dim.Parent = back
-- арт в полном разрешении: рамка с пропорциями арта, плитки в ней — в долях
local artBox = Instance.new("Frame")
artBox.BackgroundTransparency = 1
artBox.BorderSizePixel = 0
artBox.ZIndex = 2
artBox.Parent = back
-- под плитками — тот же арт одним файлом (низкое разрешение): он лёгкий и появляется первым,
-- плитки проявляются поверх по мере загрузки
local artLow = Instance.new("ImageLabel")
artLow.Size = UDim2.fromScale(1, 1)
artLow.BackgroundTransparency = 1
artLow.BorderSizePixel = 0
artLow.Image = ART
artLow.Parent = artBox
local tiles = {}
for _, t in ipairs(TILES) do
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = "rbxassetid://" .. t.id
	img.ImageRectOffset = Vector2.new(t.ox, t.oy)
	img.ImageRectSize = Vector2.new(t.w, t.h)
	img.Position = UDim2.fromScale(t.x / ART_W, t.y / ART_H)
	img.Size = UDim2.new(t.w / ART_W, 1, t.h / ART_H, 1) -- +1 пиксель внахлёст: при дробном масштабе между плитками нет щели
	img.ZIndex = 2
	img.Parent = artBox
	table.insert(tiles, img)
end
local function layoutArt()
	local v = gui.AbsoluteSize
	if v.X < 1 or v.Y < 1 then return end
	local cover = v.X / v.Y >= 1.2
	local k = cover and math.max(v.X / ART_W, v.Y / ART_H) or math.min(v.X / ART_W, v.Y / ART_H)
	local w, h = math.ceil(ART_W * k), math.ceil(ART_H * k)
	-- лишнее по высоте: десятая часть сверху, остальное снизу (там волны и ящики, а наверху логотип)
	local y = h > v.Y and -(h - v.Y) * 0.03 or (v.Y - h) / 2
	artBox.Size = UDim2.fromOffset(w, h)
	artBox.Position = UDim2.fromOffset(math.floor((v.X - w) / 2), math.floor(y))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutArt)
-- затемнение снизу под полосу загрузки — на всю ширину экрана
local shade = Instance.new("Frame")
shade.AnchorPoint = Vector2.new(0, 1)
shade.Position = UDim2.fromScale(0, 1)
shade.Size = UDim2.fromScale(1, 0.3)
shade.BackgroundColor3 = BG
shade.BorderSizePixel = 0
shade.ZIndex = 3
shade.Parent = back
local grad = Instance.new("UIGradient")
grad.Rotation = -90
grad.Transparency = NumberSequence.new(0.1, 1)
grad.Parent = shade

local safe = Instance.new("ScreenGui")
safe.Name = "LoadingScreenSafe"
safe.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- не под кнопками Roblox и не под чёлкой
safe.ResetOnSpawn = false
safe.DisplayOrder = 1001
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundTransparency = 1
bg.BorderSizePixel = 0
bg.Parent = safe
local function label(text, size, color, y, font)
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.new(0.5, 0, 0.5, y)
	l.Size = UDim2.new(0.9, 0, 0, size + 6)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = font or Enum.Font.GothamBold
	l.Parent = bg
	return l
end
-- надпись, пока арт не скачан (на самом арте ARCHIPELAGO уже есть)
local titles = {label("ARCHIPELAGO", 46, TEXT, -40), label("WAR & TRADE", 18, GOLD, 0)}
local function artShown()
	local loaded = artLow.IsLoaded
	if not loaded then
		loaded = true
		for _, img in ipairs(tiles) do
			if not img.IsLoaded then loaded = false break end
		end
	end
	for _, l in ipairs(titles) do l.Visible = not loaded end
end
artShown() -- сигнал IsLoaded приходит не всегда — ещё и каждый кадр ниже
task.spawn(function()
	pcall(ContentProvider.PreloadAsync, ContentProvider, {artLow})
	pcall(ContentProvider.PreloadAsync, ContentProvider, tiles)
end)
local status = label("Loading…", 16, TEXT, 0, Enum.Font.GothamBold)
status.AnchorPoint = Vector2.new(0.5, 1)
status.Position = UDim2.new(0.5, 0, 1, -54)
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Parent = status
local barBg = Instance.new("Frame")
barBg.AnchorPoint = Vector2.new(0.5, 1)
barBg.Position = UDim2.new(0.5, 0, 1, -36)
-- 360 пикселей, но на узком экране — с отступом 16 по краям
barBg.Size = UDim2.new(1, -32, 0, 10)
barBg.BackgroundColor3 = PANEL
barBg.BorderSizePixel = 0
barBg.Parent = bg
local barMax = Instance.new("UISizeConstraint")
barMax.MaxSize = Vector2.new(360, math.huge)
barMax.Parent = barBg
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = GOLD
bar.BorderSizePixel = 0
bar.Parent = barBg
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
gui.Parent = playerGui
safe.Parent = playerGui
layoutArt()
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- полоса едет плавно к текущей цели
local progress, shown = 0, 0
local conn = RunService.RenderStepped:Connect(function(dt)
	shown += (progress - shown) * math.min(1, dt * 6)
	bar.Size = UDim2.fromScale(shown, 1)
	artShown()
end)
local function stage(text, p)
	status.Text = text
	progress = math.max(progress, p)
end
local function timeLeft() return math.max(0, MAX_TIME - (os.clock() - t0)) end
-- ждать fn() не дольше limit сек.
local function waitUntil(fn, limit)
	local untilT = os.clock() + math.min(limit, timeLeft())
	while not fn() and os.clock() < untilT do task.wait(0.1) end
end

-- 1. сама игра
stage("Loading game…", 0.1)
if not game:IsLoaded() then
	local done = false
	task.spawn(function() game.Loaded:Wait() done = true end)
	waitUntil(function() return done end, 15)
end

-- 2. персонаж (сервер создаёт его сам, CharacterAutoLoads = false)
stage("Joining the server…", 0.3)
waitUntil(function()
	local c = player.Character
	return c ~= nil and c:FindFirstChild("HumanoidRootPart") ~= nil
end, 12)

-- 3. карта вокруг персонажа
stage("Loading the island…", 0.5)
local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if hrp and workspace.StreamingEnabled then
	local done = false
	task.spawn(function()
		pcall(function() player:RequestStreamAroundAsync(hrp.Position, math.min(8, timeLeft())) end)
		done = true
	end)
	waitUntil(function() return done end, 8)
end

-- 4. звуки, эффекты, текстуры интерфейса и то, что уже видно на карте
stage("Loading sounds and effects…", 0.6)
-- на телефоне карту не предзагружаем (много памяти и долго) — только интерфейс, звуки и эффекты
local UserInputService = game:GetService("UserInputService")
local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local list = mobile and {ReplicatedStorage, playerGui} or {ReplicatedStorage, workspace, playerGui}
local total = math.max(1, ContentProvider.RequestQueueSize)
local done = false
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync(list, function()
			local left = ContentProvider.RequestQueueSize
			total = math.max(total, left)
			progress = math.max(progress, 0.6 + 0.35 * (1 - left / total))
		end)
	end)
	done = true
end)
waitUntil(function() return done end, mobile and 6 or 12)

-- готово: короткая пауза, чтобы экран не мигнул, и плавное исчезновение
stage("Ready", 1)
local rest = MIN_TIME - (os.clock() - t0)
if rest > 0 then task.wait(rest) end
task.wait(0.3)
local info = TweenInfo.new(0.6)
local all = {back}
for _, root in ipairs({back, bg}) do
	for _, d in ipairs(root:GetDescendants()) do table.insert(all, d) end
end
for _, d in ipairs(all) do
	if d:IsA("UIGradient") then
		continue
	elseif d:IsA("TextLabel") then
		TweenService:Create(d, info, {TextTransparency = 1}):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, info, {Transparency = 1}):Play()
	elseif d:IsA("ImageLabel") then
		TweenService:Create(d, info, {ImageTransparency = 1}):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, info, {BackgroundTransparency = 1}):Play()
	end
end
task.wait(0.7)
conn:Disconnect()
gui:Destroy()
safe:Destroy()
