-- Военная форма команд (Config.Uniforms) — на игроках и ботах.
--  • Камуфляж команды (Shirt/Pants), шлем с полосой и нарукавники цвета команды. Снимаем со скина
--    одежду, футболку-картинку и аксессуары, кроме волос и лица (лицо, цвет кожи — свои).
--  • В форме тело классическое «кубическое» (стандартные части и пропорции): на нём шаблоны Shirt/Pants
--    ложатся ровно. Риг остаётся R15 — анимации и позы оружия не меняются.
--  • Атрибут игрока UniformOff = true — играет в своём скине. Переключается только в лобби
--    (Remotes.Uniform, кнопка UniformUI): персонаж перезагружается и надевает нужное.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local Guard = require(Services.RemoteGuard)

local UniformService = {}
local GEAR = "UniformGear"
-- с формой остаются только волосы и аксессуары лица (ауры, крылья, шляпы и т.п. снимаем)
local KEEP = {
	[Enum.AccessoryType.Hair] = true, [Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true, [Enum.AccessoryType.Eyelash] = true,
}

local function gearPart(parent, attachTo, name, size, cf, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	if shape then
		local m = Instance.new("SpecialMesh")
		m.MeshType = shape
		m.Parent = p
	end
	p.Parent = parent
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = attachTo, p
	w.Parent = p
	return p
end

-- надеть форму команды team на модель персонажа (R15 или R6)
function UniformService.dress(char, team)
	local u = Config.Uniforms[team]
	if not u or not char then return end
	local old = char:FindFirstChild(GEAR)
	if old then old:Destroy() end
	for _, d in ipairs(char:GetChildren()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") then
			d:Destroy()
		elseif d:IsA("Accessory") then
			local handle = d:FindFirstChild("Handle")
			local layered = handle and handle:FindFirstChildOfClass("WrapLayer")
			if layered or not KEEP[d.AccessoryType] then d:Destroy() end
		end
	end
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = "rbxassetid://" .. u.Shirt
	shirt.Parent = char
	local pants = Instance.new("Pants")
	pants.PantsTemplate = "rbxassetid://" .. u.Pants
	pants.Parent = char

	local gear = Instance.new("Folder")
	gear.Name = GEAR
	local tc = Config.Teams[team].Color
	local head = char:FindFirstChild("Head")
	if head then
		local s = head.Size
		-- каска: приплюснутая полусфера над лбом, полоса цвета команды по краю
		gearPart(gear, head, "Helmet", Vector3.new(s.X * 1.22, s.Y * 0.78, s.Z * 1.26), head.CFrame * CFrame.new(0, s.Y * 0.28, 0.02), u.Helmet, Enum.MeshType.Sphere)
		gearPart(gear, head, "HelmetBand", Vector3.new(s.Y * 0.14, s.X * 1.2, s.X * 1.2), head.CFrame * CFrame.new(0, s.Y * 0.2, 0.02) * CFrame.Angles(0, 0, math.rad(90)), tc, Enum.MeshType.Cylinder)
	end
	for _, n in ipairs({"LeftUpperArm", "RightUpperArm", "Left Arm", "Right Arm"}) do
		local arm = char:FindFirstChild(n)
		if arm and arm:IsA("BasePart") then
			local s = arm.Size
			local y = n:find("Upper") and s.Y * 0.12 or s.Y * 0.3
			gearPart(gear, arm, "Armband", Vector3.new(s.X * 1.08, s.Y * (n:find("Upper") and 0.22 or 0.14), s.Z * 1.08), arm.CFrame * CFrame.new(0, y, 0), tc)
		end
	end
	gear.Parent = char
end

-- классическое тело: стандартные части, пропорции 1:1, без одежды и аксессуаров кроме KEEP
-- (лицо, цвет кожи и волосы — свои). Ждёт ApplyDescription.
local function blocky(hum)
	local ok, d = pcall(function() return hum:GetAppliedDescription() end)
	if not ok or not d then return end
	d = d:Clone()
	d.Head, d.Torso, d.LeftArm, d.RightArm, d.LeftLeg, d.RightLeg = 0, 0, 0, 0, 0, 0
	d.BodyTypeScale, d.ProportionScale = 0, 0
	d.HeightScale, d.WidthScale, d.DepthScale, d.HeadScale = 1, 1, 1, 1
	d.Shirt, d.Pants, d.GraphicTShirt = 0, 0, 0
	local keep = {}
	for _, a in ipairs(d:GetAccessories(true)) do
		if not a.IsLayered and KEEP[a.AccessoryType] then table.insert(keep, a) end
	end
	pcall(function() d:SetAccessories(keep, true) end)
	pcall(function() hum:ApplyDescription(d) end)
end

local function apply(player)
	local char = player.Character
	local team = TeamService.getTeamName(player)
	if not char or not team or player:GetAttribute("UniformOff") then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then blocky(hum) end
	if player.Character ~= char then return end
	UniformService.dress(char, team)
end

function UniformService.init()
	local function hook(player)
		player.CharacterAppearanceLoaded:Connect(function() apply(player) end)
	end
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerAdded:Connect(hook)

	ReplicatedStorage.Remotes.Uniform.OnServerInvoke = function(player)
		if not Guard.bucket(player, "Uniform", 0.5, 2) then return {ok = false, msg = "Too fast, please wait"} end
		if player:GetAttribute("State") ~= "Lobby" then return {ok = false, msg = "You can change clothes only in the lobby"} end
		local off = not player:GetAttribute("UniformOff")
		player:SetAttribute("UniformOff", off or nil)
		task.spawn(function() player:LoadCharacter() end)
		return {ok = true, msg = off and "Uniform off — your own outfit" or "Uniform on"}
	end
end

return UniformService
