-- Мини-фото техники для строк ангара и верфи: ViewportFrame с копией из ReplicatedStorage.VehiclePreviews
-- (их готовит PreviewService). paint(team) красит детали TeamPaint в цвет команды.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehiclePreview = {}

-- zoom > 1 — камера ближе (широкие рамки, где модель иначе выходит мелкой)
function VehiclePreview.new(UI, T, Config, parent, kind, props, zoom)
	local vp = UI.new("ViewportFrame", {
		Name = "Preview", BackgroundColor3 = T.Panel, BorderSizePixel = 0,
		Ambient = Color3.fromRGB(170, 170, 180), LightColor = Color3.fromRGB(255, 250, 240), LightDirection = Vector3.new(-1, -2, -1),
	}, parent)
	for k, v in pairs(props or {}) do vp[k] = v end
	UI.corner(vp, 6)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam

	local api = {frame = vp}
	local model
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("VehiclePreviews", 30)
		local tpl = folder and folder:WaitForChild(kind, 10)
		if not tpl then return end
		model = tpl:Clone()
		model.Parent = vp
		-- вид 3/4 сверху-спереди, вся модель в кадре
		local cf, size = model:GetBoundingBox()
		local dir = cf:VectorToWorldSpace(Vector3.new(1, 0.55, -1).Unit)
		local radius = size.Magnitude / 2
		local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 0.82 / (zoom or 1)
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
