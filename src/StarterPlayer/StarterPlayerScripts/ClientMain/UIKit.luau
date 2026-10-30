-- Общий стиль интерфейса и помощники
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = {}
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

UI.T = {
	Panel = Color3.fromRGB(16, 21, 29),
	Panel2 = Color3.fromRGB(26, 33, 44),
	Line = Color3.fromRGB(54, 66, 84),
	Text = Color3.fromRGB(232, 238, 245),
	Muted = Color3.fromRGB(140, 152, 168),
	Accent = Color3.fromRGB(110, 200, 255),
	Gold = Color3.fromRGB(255, 205, 90),
	Good = Color3.fromRGB(80, 200, 110),
	Bad = Color3.fromRGB(235, 85, 75),
	Disabled = Color3.fromRGB(52, 58, 68),
}
UI.Bold = Enum.Font.GothamBold
UI.Medium = Enum.Font.GothamMedium

function UI.new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end

function UI.corner(inst, r)
	return UI.new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, inst)
end

function UI.stroke(inst, color, thickness)
	return UI.new("UIStroke", {Color = color or UI.T.Line, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, inst)
end

function UI.padding(inst, p)
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p),
		PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p),
	}, inst)
end

-- масштаб под экран: телефон / планшет / ПК
local scales = {}
local function viewportScale()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return math.clamp(math.min(vp.X / 1100, vp.Y / 680), 0.5, 1.3)
end
local function rescale()
	local v = viewportScale()
	for _, s in ipairs(scales) do s.Scale = math.max(v, s:GetAttribute("MinScale") or 0) end
end
local replaceRounds -- см. сенсорные кнопки ниже
local function bindCamera()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			rescale()
			if replaceRounds then replaceRounds() end
		end)
		rescale()
	end
end
bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

-- minScale: нижний предел (кнопки для пальцев на телефоне не должны сжиматься вместе с панелями)
function UI.scale(frame, minScale)
	local s = UI.new("UIScale", {Scale = math.max(viewportScale(), minScale or 0)}, frame)
	if minScale then s:SetAttribute("MinScale", minScale) end
	table.insert(scales, s)
	return s
end

------------------------------------------------------------------ сенсорное управление
-- Как в мобильных шутерах: слева джойстик, справа круглые кнопки дугой вокруг стандартной
-- кнопки прыжка Roblox (она же — выход из техники). Пешком ходим стандартным джойстиком Roblox,
-- в технике поверх него встаёт свой (тот же вид и место) и рулит кораблём / самолётом.
-- В Studio можно включить на ПК атрибутом ReplicatedStorage.DebugTouchUI (для проверки мышью).
UI.touchOnly = (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
	or (RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugTouchUI") == true)

local SHEET = "rbxasset://textures/ui/TouchControlsSheet.png" -- спрайты стандартного джойстика

local function viewport()
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(844, 390)
end
-- где Roblox рисует кнопку прыжка и джойстик (центр от нижнего правого / левого угла, размер)
local function stdGeometry()
	local vp = viewport()
	if math.min(vp.X, vp.Y) <= 500 then
		return Vector2.new(-60, -55), 70
	end
	return Vector2.new(-110, -150), 120
end

-- места кнопок: угол от кнопки прыжка (°, 180 — слева, 90 — сверху), кольцо, диаметр,
-- доп. отступ от прыжка. main — большая кнопка слева от прыжка; a1/a2 — ближний ряд; b1/b2 — внешний.
-- gun* — раскладка пехоты: большая FIRE выше-слева от прыжка, R слева, AIM над прыжком
local SLOTS = {
	main = {180, 1, 84},
	a1 = {128, 1, 60},
	a2 = {80, 1, 60},
	b1 = {155, 2, 56},
	b2 = {108, 2, 56},
	gunFire = {132, 1, 84},
	gunReload = {180, 1, 60, 9},
	gunAim = {78, 1, 60, 3},
	zoom = {80, 1, 46}, -- маленькая «приблизить» над прыжком (турели, катер)
	zoomHigh = {85, 2, 46}, -- то же во втором ряду: в самолёте и на подлодке место a2 занято (GAS+ / UP)
}
local rounds = {}
local function place(b)
	local def = SLOTS[b:GetAttribute("Slot")]
	local j, s = stdGeometry()
	local k = math.min(s / 70, 1.4)
	local d = def[3] * k
	local r = s / 2 + 14 * k + d / 2 + (def[4] or 0) * k
	if def[2] == 2 then r = s / 2 + 14 * k + SLOTS.main[3] * k + 14 * k + d / 2 end
	local a = math.rad(def[1])
	b.Size = UDim2.fromOffset(d, d)
	b.Position = UDim2.new(1, j.X + math.cos(a) * r, 1, j.Y - math.sin(a) * r)
end
local function replaceAll()
	for i = #rounds, 1, -1 do
		if rounds[i].Parent then place(rounds[i]) else table.remove(rounds, i) end
	end
end
replaceRounds = replaceAll

-- круглая кнопка в месте slot (см. SLOTS); видна только когда её покажут
function UI.roundButton(parent, slot, text, color)
	color = color or Color3.fromRGB(22, 27, 36)
	local b = UI.new("TextButton", {
		Name = "Touch_" .. slot, AnchorPoint = Vector2.new(0.5, 0.5), AutoButtonColor = false,
		BackgroundColor3 = color, BackgroundTransparency = 0.3, Text = text, TextColor3 = Color3.new(1, 1, 1),
		Font = UI.Bold, TextScaled = true, Visible = false,
	}, parent)
	UI.new("UICorner", {CornerRadius = UDim.new(1, 0)}, b)
	UI.new("UIStroke", {Color = Color3.new(1, 1, 1), Transparency = 0.4, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, b)
	local p = UDim.new(0.2, 0)
	UI.new("UIPadding", {PaddingTop = p, PaddingBottom = p, PaddingLeft = UDim.new(0.12, 0), PaddingRight = UDim.new(0.12, 0)}, b)
	UI.new("UITextSizeConstraint", {MaxTextSize = 20}, b)
	b:SetAttribute("Slot", slot)
	b:SetAttribute("BaseColor", color)
	b:SetAttribute("Enabled", true)
	place(b)
	table.insert(rounds, b)
	-- отклик на нажатие
	b.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then b.BackgroundTransparency = 0.05 end
	end)
	b.InputEnded:Connect(function(i)
		-- зажатую кнопку (onHold) не «отжимаем», когда палец съехал с неё
		if b:GetAttribute("Held") then return end
		if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then b.BackgroundTransparency = 0.3 end
	end)
	return b
end

-- поворот камеры пальцем, зажавшим кнопку (FIRE турели и т.п.): сдвиги копятся и применяются
-- после стандартной камеры (она берёт направление из текущего cam.CFrame, так что поворот сохраняется)
UI.TOUCH_DEG = 0.22 -- градусов на пиксель сдвига пальца
local dragX, dragY = 0, 0
function UI.cameraDrag(delta)
	dragX += delta.X
	dragY += delta.Y
end
RunService:BindToRenderStep("TouchCameraDrag", Enum.RenderPriority.Camera.Value + 2, function()
	if dragX == 0 and dragY == 0 then return end
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
		local cf = cam.CFrame
		local look = cf.LookVector
		-- с приближением палец ведёт медленнее, чтобы точно целиться
		local k = UI.TOUCH_DEG * math.clamp(cam.FieldOfView / 70, 0.2, 1)
		local pitch = math.clamp(math.asin(look.Y) - math.rad(dragY * k), math.rad(-80), math.rad(80))
		local yaw = math.atan2(-look.X, -look.Z) - math.rad(dragX * k)
		cam.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(pitch, yaw, 0)
	end
	dragX, dragY = 0, 0
end)

-- удержание кнопки: down(input) при нажатии, up() только когда палец отпущен — если он съехал
-- с кнопки (крутит камеру с зажатым огнём), кнопка остаётся зажатой.
-- move(delta) — если задано, получает сдвиги зажавшего пальца (например, UI.cameraDrag)
-- Палец узнаём не только по объекту касания, но и по месту: на телефонах события движения/отпускания
-- иногда приходят другим объектом, и кнопка «залипала» — камера переставала крутиться.
local TOUCH = Enum.UserInputType.Touch
local NEAR = 140 -- пикселей: насколько далеко палец может уйти между двумя событиями
function UI.onHold(b, down, up, move)
	local held, lastPos
	local function isTouch() return held and held.UserInputType == TOUCH end
	local function ours(i)
		if i == held then return true end
		if i.UserInputType ~= TOUCH or not isTouch() or not lastPos then return false end
		return (Vector2.new(i.Position.X, i.Position.Y) - lastPos).Magnitude < NEAR
	end
	local function release()
		if not held then return end
		held, lastPos = nil, nil
		b:SetAttribute("Held", false)
		b.BackgroundTransparency = 0.3
		if up then up() end
	end
	local function track(p)
		p = Vector2.new(p.X, p.Y)
		if lastPos and move then
			local d = p - lastPos
			if d.Magnitude > 0 and d.Magnitude < NEAR then move(d) end
		end
		lastPos = p
	end
	b.InputBegan:Connect(function(i)
		if not (i.UserInputType == TOUCH or i.UserInputType == Enum.UserInputType.MouseButton1) then return end
		-- новое нажатие всегда перехватывает кнопку (старое «залипшее» касание сбрасываем)
		if held then
			if i == held then return end
			release()
		end
		held = i
		lastPos = Vector2.new(i.Position.X, i.Position.Y)
		b:SetAttribute("Held", true)
		down(i)
	end)
	local function ended(i)
		if not held then return end
		if held.UserInputType == Enum.UserInputType.MouseButton1 then
			if i.UserInputType == Enum.UserInputType.MouseButton1 then release() end
		elseif ours(i) then
			release()
		end
	end
	UserInputService.InputEnded:Connect(ended)
	UserInputService.TouchEnded:Connect(ended)
	local function changed(i)
		if isTouch() and i.UserInputType == TOUCH and ours(i) then track(i.Position) end
	end
	UserInputService.InputChanged:Connect(changed)
	UserInputService.TouchMoved:Connect(changed)
	-- страховка каждый кадр: касание закончилось или его объект обновился без событий
	RunService.Heartbeat:Connect(function()
		if not isTouch() then return end
		local s = held.UserInputState
		if s == Enum.UserInputState.End or s == Enum.UserInputState.Cancel then
			release()
		else
			track(held.Position)
		end
	end)
	-- кнопку спрятали с зажатым пальцем — отпускаем
	b:GetPropertyChangedSignal("Visible"):Connect(function()
		if not b.Visible and held then release() end
	end)
end

-- джойстик для техники (один на всех): stick.request(кто, вкл), stick.vector() → Vector2 (x — вправо, y — вперёд)
local stick
function UI.joystick()
	if stick then return stick end
	local g = UI.screen("VehicleStick", 30)
	g.Enabled = false
	-- зона касания — вся левая нижняя часть экрана; джойстик встаёт под палец
	local zone = UI.new("TextButton", {Name = "Zone", Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
		Position = UDim2.fromScale(0, 0.3), Size = UDim2.fromScale(0.42, 0.7)}, g)
	local base = UI.new("ImageLabel", {Name = "Base", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
		Image = SHEET, ImageRectOffset = Vector2.new(0, 0), ImageRectSize = Vector2.new(220, 220)}, g)
	local knob = UI.new("ImageLabel", {Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
		Image = SHEET, ImageRectOffset = Vector2.new(220, 0), ImageRectSize = Vector2.new(111, 111),
		Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)}, base)

	local owners, touch, center, vec = {}, nil, nil, Vector2.zero
	local function home()
		local c, s = stdGeometry()
		local size = s * 1.6
		local vp = viewport()
		-- центр стандартного джойстика — зеркало кнопки прыжка
		return Vector2.new(-c.X, vp.Y + c.Y), size
	end
	local function reset()
		touch, vec = nil, Vector2.zero
		local pos, size = home()
		center = pos
		base.Size = UDim2.fromOffset(size, size)
		base.Position = UDim2.fromOffset(pos.X, pos.Y)
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end
	reset()
	-- координаты ввода — без верхней полосы, а этот экран её игнорирует
	local function guiPos(i)
		local p = i.UserInputType == Enum.UserInputType.Touch and i.Position or UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		return Vector2.new(p.X, p.Y) + GuiService:GetGuiInset()
	end
	local function update(p)
		local _, size = home()
		local r = size / 2
		local d = p - center
		if d.Magnitude > r then d = d.Unit * r end
		knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
		vec = Vector2.new(d.X / r, -d.Y / r)
	end
	zone.InputBegan:Connect(function(i)
		if touch or not (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1) then return end
		touch = i
		local p = guiPos(i)
		local hp, size = home()
		-- далеко от кольца — кольцо приходит под палец
		center = (p - hp).Magnitude <= size * 0.65 and hp or p
		base.Position = UDim2.fromOffset(center.X, center.Y)
		update(p)
	end)
	UserInputService.InputChanged:Connect(function(i)
		if not touch then return end
		if i == touch or (touch.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseMovement) then
			update(guiPos(i))
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if touch and (i == touch or (touch.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseButton1)) then reset() end
	end)
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if not touch then reset() end end) end

	stick = {}
	function stick.request(who, on)
		owners[who] = on or nil
		local want = next(owners) ~= nil
		if g.Enabled ~= want then
			g.Enabled = want
			reset()
		end
	end
	function stick.vector()
		return g.Enabled and vec or Vector2.zero
	end
	return stick
end

function UI.screen(name, order)
	local old = playerGui:FindFirstChild(name)
	if old then old:Destroy() end
	return UI.new("ScreenGui", {
		Name = name, ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = order or 0,
	}, playerGui)
end

function UI.panel(parent, props)
	local f = UI.new("Frame", {BackgroundColor3 = UI.T.Panel, BackgroundTransparency = 0.06, BorderSizePixel = 0}, parent)
	for k, v in pairs(props or {}) do f[k] = v end
	UI.corner(f, 10)
	UI.stroke(f)
	return f
end

function UI.label(parent, text, props)
	local l = UI.new("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = UI.T.Text, Font = UI.Bold,
		TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 22),
	}, parent)
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end

function UI.button(parent, text, color, props)
	local b = UI.new("TextButton", {
		AutoButtonColor = false, BackgroundColor3 = color or UI.T.Panel2, Text = text,
		TextColor3 = UI.T.Text, Font = UI.Bold, TextSize = 18, Size = UDim2.new(1, 0, 0, 46),
	}, parent)
	for k, v in pairs(props or {}) do b[k] = v end
	UI.corner(b, 6)
	b:SetAttribute("BaseColor", b.BackgroundColor3)
	b:SetAttribute("Enabled", true)
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Enabled") then
			b.BackgroundColor3 = b:GetAttribute("BaseColor"):Lerp(Color3.new(1, 1, 1), 0.12)
		end
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = b:GetAttribute("Enabled") and b:GetAttribute("BaseColor") or UI.T.Disabled
	end)
	return b
end

function UI.setEnabled(b, enabled, color, text)
	if color then b:SetAttribute("BaseColor", color) end
	b:SetAttribute("Enabled", enabled)
	b.BackgroundColor3 = enabled and b:GetAttribute("BaseColor") or UI.T.Disabled
	b.TextColor3 = enabled and UI.T.Text or UI.T.Muted
	if text then b.Text = text end
end

-- всплывающие уведомления: тёмная стеклянная карточка с цветом вида — влетает сверху с пружинкой,
-- по ней пробегает блик, вокруг иконки расходится кольцо, снизу тает полоска времени.
-- Награда — переливающаяся золотая рамка, ошибка — короткая встряска. Соседние карточки раздвигаются
-- и смыкаются плавно (у каждой своя обёртка, высота которой анимируется). Тот же текст повторно
-- не плодит копии — карточка подпрыгивает, на ней счётчик «×2», таймер начинается заново.
-- Виды: success, error, info, safe (безопасная зона), reward (награда золотом).
local TextService = game:GetService("TextService")
local TOAST_W, TOAST_TIME, TOAST_MAX, TOAST_GAP = 440, 4, 4, 8
local TOAST_KINDS = {
	success = {color = Color3.fromRGB(80, 215, 130), icon = "check", title = "DONE"},
	error = {color = Color3.fromRGB(255, 95, 80), icon = "!", title = "HEADS UP", shake = true},
	info = {color = Color3.fromRGB(110, 190, 255), icon = "i", title = "INFO"},
	safe = {color = Color3.fromRGB(60, 225, 130), icon = "shield", title = "SAFE ZONE", tint = 0.5},
	reward = {color = Color3.fromRGB(255, 200, 70), icon = "+", title = "REWARD", gold = true},
}
local toastHolder
local toastN = 0
local toastByKey = {}
local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function toastIcon(parent, spec)
	local dark = Color3.fromRGB(14, 20, 26)
	local holder = UI.new("Frame", {Size = UDim2.fromOffset(36, 36), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 32, 0.5, 0),
		BackgroundTransparency = 1}, parent)
	-- кольцо, которое расходится при появлении
	local ring = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1}, holder)
	UI.corner(ring, 100)
	local ringStroke = UI.new("UIStroke", {Color = spec.color, Thickness = 3, Transparency = 0.1}, ring)
	local c = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, holder)
	UI.corner(c, 100)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(spec.color:Lerp(Color3.new(1, 1, 1), 0.25), spec.color:Lerp(Color3.new(0, 0, 0), 0.15))}, c)
	local glyphScale = UI.new("UIScale", {Scale = 0}, c)
	if spec.icon == "check" then
		-- галочка из двух палочек: символа ✓ в шрифте нет
		UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(12, 20), Size = UDim2.fromOffset(10, 3.5), Rotation = 45, BackgroundColor3 = dark, BorderSizePixel = 0}, c)
		UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(20, 17), Size = UDim2.fromOffset(17, 3.5), Rotation = -50, BackgroundColor3 = dark, BorderSizePixel = 0}, c)
	elseif spec.icon == "shield" then
		UI.new("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "🛡️", TextSize = 19, Font = UI.Bold}, c)
	else
		UI.new("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = spec.icon, TextSize = 22, Font = UI.Bold, TextColor3 = dark}, c)
	end
	return function()
		glyphScale.Scale = 0
		tween(glyphScale, 0.45, {Scale = 1}, Enum.EasingStyle.Back)
		ring.Size = UDim2.fromScale(1, 1)
		ringStroke.Transparency = 0.1
		tween(ring, 0.7, {Size = UDim2.fromScale(2.1, 2.1)})
		tween(ringStroke, 0.7, {Transparency = 1})
	end
end
function UI.toast(text, kind, title)
	text = tostring(text)
	local spec = TOAST_KINDS[kind] or TOAST_KINDS.info
	-- «+N gold» — золотая карточка награды
	if kind == "success" and text:find("%+%d") and text:lower():find("gold") then spec = TOAST_KINDS.reward end
	title = title or spec.title
	if not toastHolder then
		local g = UI.screen("Notifications", 50)
		toastHolder = UI.new("Frame", {
			Name = "Holder", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 106),
			Size = UDim2.fromOffset(TOAST_W, 320), BackgroundTransparency = 1,
		}, g)
		UI.new("UIListLayout", {Padding = UDim.new(0, 0), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder}, toastHolder)
		UI.scale(toastHolder)
	end

	local key = (title or "") .. "\0" .. text
	local old = toastByKey[key]
	if old and old.card.Parent then
		old.restart(true)
		return
	end

	local textW = TOAST_W - 72 - 18
	local msgH = TextService:GetTextSize(text, 16, UI.Medium, Vector2.new(textW, 1000)).Y
	local titleH = title and 16 or 0
	local h = math.max(56, msgH + titleH + 26)

	toastN += 1
	-- обёртка: её высота плавно растёт / схлопывается — соседи сдвигаются без рывков
	local wrap = UI.new("Frame", {Name = "Toast", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, LayoutOrder = toastN}, toastHolder)
	local slot = UI.new("Frame", {Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1}, wrap)
	-- тень под карточкой
	local shadow = UI.new("Frame", {Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0}, slot)
	UI.corner(shadow, 14)
	local card = UI.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, GroupTransparency = 1,
	}, slot)
	UI.corner(card, 14)
	local pop = UI.new("UIScale", {Scale = 0.82}, card)
	-- стекло: тёмный градиент сверху вниз и цвет вида, разлитый слева (градиент — на отдельной рамке:
	-- UIGradient прямо в CanvasGroup тонировал бы всё содержимое, включая текст)
	local glass = UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, card)
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(34, 40, 52), Color3.fromRGB(16, 19, 26))}, glass)
	local wash = UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = spec.color, BackgroundTransparency = 0, BorderSizePixel = 0}, card)
	UI.new("UIGradient", {Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spec.tint or 0.72), NumberSequenceKeypoint.new(0.45, 0.94), NumberSequenceKeypoint.new(1, 1),
	})}, wash)
	-- блеск сверху
	UI.new("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0}, card)
	-- рамка внутри (снаружи CanvasGroup её обрезал бы); у награды — переливается золотом
	local edge = UI.new("Frame", {Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), BackgroundTransparency = 1}, card)
	UI.corner(edge, 13)
	local stroke = UI.new("UIStroke", {Color = spec.gold and Color3.new(1, 1, 1) or spec.color, Thickness = spec.gold and 2 or 1.5, Transparency = spec.gold and 0 or 0.45}, edge)
	if spec.gold then
		local g = UI.new("UIGradient", {Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 40)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 245, 190)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 245, 190)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 40)),
		})}, stroke)
		TweenService:Create(g, TweenInfo.new(2.2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), {Rotation = 360}):Play()
	end
	-- пробегающий блик
	local shine = UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, card)
	local shineGrad = UI.new("UIGradient", {Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, spec.gold and 0.55 or 0.78),
		NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
	})}, shine)
	local playIcon = toastIcon(card, spec)
	if title then
		UI.label(card, title, {Position = UDim2.fromOffset(62, 10), Size = UDim2.new(1, -110, 0, 14), TextSize = 12, Font = UI.Bold, TextColor3 = spec.color})
	end
	UI.label(card, text, {
		Position = UDim2.fromOffset(62, 10 + titleH), Size = UDim2.new(1, -78, 1, -(titleH + 20)),
		TextSize = 16, Font = UI.Medium, TextWrapped = true, TextYAlignment = title and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
	})
	-- счётчик повторов «×2»
	local count = UI.label(card, "", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(40, 16),
		TextSize = 13, Font = UI.Bold, TextColor3 = spec.color, TextXAlignment = Enum.TextXAlignment.Right})
	local countScale = UI.new("UIScale", {}, count)
	-- полоска оставшегося времени: тает к центру
	local bar = UI.new("Frame", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.new(1, -24, 0, 3),
		BackgroundColor3 = spec.color, BorderSizePixel = 0}, card)
	UI.corner(bar, 2)
	UI.new("UIGradient", {Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.7),
	})}, bar)

	local entry = {card = wrap, token = 0, n = 1}
	toastByKey[key] = entry
	local closing = false
	local function close()
		if toastByKey[key] == entry then toastByKey[key] = nil end
		if closing or not wrap.Parent then return end
		closing = true
		-- уезжает вверх и тает, потом обёртка схлопывается — соседи плавно подтягиваются
		tween(card, 0.25, {GroupTransparency = 1})
		tween(shadow, 0.25, {BackgroundTransparency = 1})
		tween(slot, 0.3, {Position = UDim2.fromOffset(0, -14)})
		tween(pop, 0.3, {Scale = 0.92})
		task.delay(0.2, function()
			tween(wrap, 0.25, {Size = UDim2.new(1, 0, 0, 0)})
			task.delay(0.26, function() wrap:Destroy() end)
		end)
	end
	local function sweep()
		shineGrad.Offset = Vector2.new(-1, 0)
		tween(shineGrad, 0.7, {Offset = Vector2.new(1, 0)}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	function entry.restart(again)
		entry.token += 1
		local tok = entry.token
		if again then
			entry.n += 1
			count.Text = "×" .. entry.n
			countScale.Scale = 1.6
			tween(countScale, 0.35, {Scale = 1}, Enum.EasingStyle.Back)
			pop.Scale = 1.06
			tween(pop, 0.3, {Scale = 1}, Enum.EasingStyle.Back)
			playIcon()
			sweep()
		end
		bar.Size = UDim2.new(1, -24, 0, 3)
		tween(bar, TOAST_TIME, {Size = UDim2.new(0, 0, 0, 3)}, Enum.EasingStyle.Linear)
		task.delay(TOAST_TIME, function()
			if entry.token == tok then close() end
		end)
	end
	-- появление: место раздвигается, карточка падает сверху с пружинкой
	tween(wrap, 0.28, {Size = UDim2.new(1, 0, 0, h + TOAST_GAP)})
	slot.Position = UDim2.fromOffset(0, -22)
	tween(slot, 0.45, {Position = UDim2.fromOffset(0, 0)}, Enum.EasingStyle.Back)
	tween(card, 0.22, {GroupTransparency = 0})
	tween(shadow, 0.3, {BackgroundTransparency = 0.6})
	tween(pop, 0.45, {Scale = 1}, Enum.EasingStyle.Back)
	playIcon()
	task.delay(0.15, sweep)
	if spec.shake then
		-- короткая встряска для предупреждений
		task.spawn(function()
			task.wait(0.42) -- после того как карточка упала на место
			for _, dx in ipairs({-7, 6, -4, 3, 0}) do
				task.wait(0.05)
				if not slot.Parent then return end
				tween(slot, 0.05, {Position = UDim2.fromOffset(dx, 0)})
			end
		end)
	end
	entry.restart(false)

	local cards = {}
	for _, c in ipairs(toastHolder:GetChildren()) do
		if c:IsA("GuiObject") then table.insert(cards, c) end
	end
	table.sort(cards, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	while #cards > TOAST_MAX do
		table.remove(cards, 1):Destroy()
	end
end

------------------------------------------------------------------ подсказка по управлению техникой (ПК)
-- Одна общая панель в левом нижнем углу, пока игрок в технике: строки {клавиши, действие}.
-- UI.controls(owner, rows) — показать (owner — кто показал: самолёт / корабль / турель),
-- UI.controls(owner, nil) — убрать, если сейчас показана этим owner. H — свернуть / развернуть.
local ctlGui, ctlPanel, ctlList, ctlTitle
local ctlOwner, ctlKey, ctlCollapsed = nil, nil, false
local CTL_W, CTL_KEY_W, CTL_ROW = 270, 84, 20
local function ctlRefresh()
	if not ctlPanel then return end
	ctlList.Visible = not ctlCollapsed
	ctlTitle.Text = ctlCollapsed and "CONTROLS  ·  H — show" or "CONTROLS  ·  H — hide"
	local n = 0
	for _, r in ipairs(ctlList:GetChildren()) do
		if r:IsA("Frame") then n += 1 end
	end
	ctlPanel.Size = UDim2.fromOffset(CTL_W, 30 + (ctlCollapsed and 0 or n * CTL_ROW + 4))
end
function UI.controls(owner, rows)
	if UI.touchOnly then return end
	if not rows then
		if ctlOwner == owner and ctlPanel then
			ctlPanel.Visible = false
			ctlOwner, ctlKey = nil, nil
		end
		return
	end
	if not ctlGui then
		ctlGui = UI.screen("ControlsHint", 14)
		ctlPanel = UI.panel(ctlGui, {Name = "Panel", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Visible = false})
		ctlPanel.BackgroundTransparency = 0.3
		UI.scale(ctlPanel, 0.75)
		ctlTitle = UI.label(ctlPanel, "", {Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 16), TextSize = 13, TextColor3 = UI.T.Accent})
		ctlList = UI.new("Frame", {Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 1, -30), BackgroundTransparency = 1}, ctlPanel)
		UI.new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, ctlList)
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or input.KeyCode ~= Enum.KeyCode.H or not ctlOwner then return end
			ctlCollapsed = not ctlCollapsed
			ctlRefresh()
		end)
	end
	-- перестраиваем строки, только если набор поменялся (вызывают каждый кадр)
	local key = owner
	for _, r in ipairs(rows) do key ..= "\0" .. r[1] .. "\1" .. r[2] end
	ctlOwner = owner
	ctlPanel.Visible = true
	if key == ctlKey then return end
	ctlKey = key
	for _, r in ipairs(ctlList:GetChildren()) do
		if r:IsA("Frame") then r:Destroy() end
	end
	for i, r in ipairs(rows) do
		local row = UI.new("Frame", {Size = UDim2.new(1, 0, 0, CTL_ROW), BackgroundTransparency = 1, LayoutOrder = i}, ctlList)
		UI.label(row, r[1], {Size = UDim2.new(0, CTL_KEY_W, 1, 0), TextSize = 13, TextColor3 = UI.T.Gold})
		UI.label(row, r[2], {Position = UDim2.fromOffset(CTL_KEY_W, 0), Size = UDim2.new(1, -CTL_KEY_W, 1, 0), TextSize = 13, Font = UI.Medium, TextTruncate = Enum.TextTruncate.AtEnd})
	end
	ctlRefresh()
end

return UI
