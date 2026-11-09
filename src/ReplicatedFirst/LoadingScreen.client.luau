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

-- Два слоя: фон на весь экран (под панелью Roblox и чёлкой) и содержимое в безопасной зоне.
-- Арт целиком (Fit) в безопасной зоне — при любом соотношении сторон логотип и края не обрезаются;
-- поля вокруг заполняет тот же арт на весь экран (Crop), затемнённый к краям, а не чёрные полосы.
local ART = "rbxassetid://71909187303311" -- тот же id, что Icons.KeyArt (ReplicatedStorage здесь ещё может быть не загружен)
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
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
dim.BackgroundTransparency = 0.25 -- поля (сбоку на широких экранах, сверху и снизу на планшетах) — затемнённые
dim.BorderSizePixel = 0
dim.Parent = back

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
-- арт игры целиком по центру безопасной зоны, снизу затемнение под полосу загрузки;
-- надпись ARCHIPELAGO уже на самом арте
local art = Instance.new("ImageLabel")
art.Size = UDim2.fromScale(1, 1)
art.BackgroundTransparency = 1
art.Image = ART
art.ScaleType = Enum.ScaleType.Fit
art.Parent = bg
local shade = Instance.new("Frame")
shade.AnchorPoint = Vector2.new(0, 1)
shade.Position = UDim2.fromScale(0, 1)
shade.Size = UDim2.fromScale(1, 0.3)
shade.BackgroundColor3 = BG
shade.BorderSizePixel = 0
shade.Parent = bg
local grad = Instance.new("UIGradient")
grad.Rotation = -90
grad.Transparency = NumberSequence.new(0.1, 1)
grad.Parent = shade
-- надпись, пока арт не скачан
local titles = {label("ARCHIPELAGO", 46, TEXT, -40), label("WAR & TRADE", 18, GOLD, 0)}
local function artShown()
	for _, l in ipairs(titles) do l.Visible = not art.IsLoaded end
end
artShown() -- сигнал IsLoaded приходит не всегда — ещё и каждый кадр ниже
task.spawn(function() pcall(ContentProvider.PreloadAsync, ContentProvider, {art}) end)
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
