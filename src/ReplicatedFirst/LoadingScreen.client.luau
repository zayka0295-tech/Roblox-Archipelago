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

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = BG
bg.BorderSizePixel = 0
bg.Parent = gui
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
label("ARCHIPELAGO", 46, TEXT, -70)
label("WAR & TRADE", 18, GOLD, -30)
local status = label("Loading…", 15, MUTED, 52, Enum.Font.GothamMedium)
local barBg = Instance.new("Frame")
barBg.AnchorPoint = Vector2.new(0.5, 0.5)
barBg.Position = UDim2.new(0.5, 0, 0.5, 20)
barBg.Size = UDim2.new(0, 360, 0, 8)
barBg.BackgroundColor3 = PANEL
barBg.BorderSizePixel = 0
barBg.Parent = bg
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = GOLD
bar.BorderSizePixel = 0
bar.Parent = barBg
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- полоса едет плавно к текущей цели
local progress, shown = 0, 0
local conn = RunService.RenderStepped:Connect(function(dt)
	shown += (progress - shown) * math.min(1, dt * 6)
	bar.Size = UDim2.fromScale(shown, 1)
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
TweenService:Create(bg, info, {BackgroundTransparency = 1}):Play()
for _, d in ipairs(bg:GetDescendants()) do
	if d:IsA("TextLabel") then
		TweenService:Create(d, info, {TextTransparency = 1}):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, info, {BackgroundTransparency = 1}):Play()
	end
end
task.wait(0.7)
conn:Disconnect()
gui:Destroy()
