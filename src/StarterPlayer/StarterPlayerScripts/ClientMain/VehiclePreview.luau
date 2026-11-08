-- Мини-фото техники для строк ангара и верфи: ViewportFrame с копией из ReplicatedStorage.VehiclePreviews
-- (их готовит PreviewService). paint(team) красит детали TeamPaint в цвет команды.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehiclePreview = {}

-- «небо» за моделью: рамка с градиентом, сам ViewportFrame внутри прозрачный (градиент на ViewportFrame
-- красил бы и модель). props (позиция, размер, Active…) — на рамку; возвращает ViewportFrame.
function VehiclePreview.frame(UI, parent, props)
	local bg = UI.new("Frame", {Name = "PreviewBg", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, parent)
	for k, v in pairs(props or {}) do bg[k] = v end
	UI.new("UIGradient", {Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(150, 205, 250), Color3.fromRGB(40, 95, 165))}, bg)
	UI.corner(bg, 6)
	UI.stroke(bg, UI.Outline, 2)
	return UI.new("ViewportFrame", {
		Name = "Preview", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = bg.Active,
		Ambient = Color3.fromRGB(200, 200, 210), LightColor = Color3.fromRGB(255, 250, 240), LightDirection = Vector3.new(-1, -2, -1),
	}, bg)
end

-- zoom > 1 — камера ближе (широкие рамки, где модель иначе выходит мелкой)
function VehiclePreview.new(UI, T, Config, parent, kind, props, zoom)
	local vp = VehiclePreview.frame(UI, parent, props)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam

	local api = {frame = vp}
	local model
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("VehiclePreviews", 30)
		local tpl = folder and folder:WaitForChild(kind, 10)
		-- окно с превью могли закрыть (уничтожить), пока ждали шаблон: Parent у уничтоженного заблокирован
		if not tpl or not vp.Parent then return end
		model = tpl:Clone()
		model.Parent = vp
		-- вид 3/4 сверху-спереди, вся модель в кадре
		local cf, size = model:GetBoundingBox()
		local dir = cf:VectorToWorldSpace(Vector3.new(1, 0.45, -1).Unit)
		local radius = size.Magnitude / 2
		local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 0.66 / (zoom or 1)
		cam.CFrame = CFrame.lookAt(cf.Position + dir * dist, cf.Position)
		if api.team then api.paint(api.team) end
	end)

	function api.paint(team)
		api.team = team
		local tc = team and Config.Teams[team]
		if not model or not tc then return end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("TeamPaint") then d.Color = tc.Color end
		end
	end
	return api
end

return VehiclePreview
