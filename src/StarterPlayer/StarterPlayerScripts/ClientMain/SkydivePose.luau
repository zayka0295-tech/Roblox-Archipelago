-- Позы десанта для всех игроков с атрибутом Parachute (CargoDropService):
--  fall — свободное падение лицом вниз, руки и ноги раскинуты («коробка»);
--  open — под куполом: руки вверху на клевантах, ноги вместе.
-- Как GunPose: суставы (AnimationConstraint / Motor6D) поворачиваем через Transform после анимации (Stepped).
-- Корень физики (HumanoidRootPart) остаётся стоячим — поворачивается только тело (сустав Root).
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local RANGE = 400
local r = math.rad
local POSES = {
	fall = {
		Root = CFrame.Angles(r(-80), 0, 0),
		Waist = CFrame.Angles(r(-12), 0, 0),
		Neck = CFrame.Angles(r(45), 0, 0), -- голова приподнята, смотрит вперёд-вниз
		RightShoulder = CFrame.Angles(r(100), 0, r(75)),
		LeftShoulder = CFrame.Angles(r(100), 0, r(-75)),
		RightElbow = CFrame.Angles(r(55), 0, 0),
		LeftElbow = CFrame.Angles(r(55), 0, 0),
		RightHip = CFrame.Angles(r(-20), 0, r(25)),
		LeftHip = CFrame.Angles(r(-20), 0, r(-25)),
		RightKnee = CFrame.Angles(r(-65), 0, 0),
		LeftKnee = CFrame.Angles(r(-65), 0, 0),
	},
	open = {
		RightShoulder = CFrame.Angles(r(160), 0, r(-12)),
		LeftShoulder = CFrame.Angles(r(160), 0, r(12)),
		RightElbow = CFrame.Angles(r(25), 0, 0),
		LeftElbow = CFrame.Angles(r(25), 0, 0),
		RightHip = CFrame.Angles(r(12), 0, r(4)),
		LeftHip = CFrame.Angles(r(12), 0, r(-4)),
		RightKnee = CFrame.Angles(r(-18), 0, 0),
		LeftKnee = CFrame.Angles(r(-18), 0, 0),
		Neck = CFrame.Angles(r(-10), 0, 0),
	},
}

return function(ctx)
	local joints = setmetatable({}, {__mode = "k"}) -- [персонаж] = {[имя] = сустав}
	local weight = setmetatable({}, {__mode = "k"}) -- [персонаж] = {pose, w}: плавный вход в позу

	local function jointsOf(char)
		local j = joints[char]
		if j then return j end
		j = {}
		for _, d in ipairs(char:GetDescendants()) do
			if (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) and (POSES.fall[d.Name] or POSES.open[d.Name]) then j[d.Name] = d end
		end
		joints[char] = j
		return j
	end

	RunService.Stepped:Connect(function(_, dt)
		local cam = workspace.CurrentCamera
		local eye = cam and cam.CFrame.Position
		for _, p in ipairs(Players:GetPlayers()) do
			local state = p:GetAttribute("Parachute")
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local pose = state and POSES[state]
			if pose and root and (not eye or (root.Position - eye).Magnitude < RANGE) then
				local st = weight[char]
				if not st or st.pose ~= state then
					st = {pose = state, w = 0}
					weight[char] = st
					joints[char] = nil -- персонаж мог пересобраться
				end
				st.w = math.min(1, st.w + dt * 4)
				for name, joint in pairs(jointsOf(char)) do
					local want = pose[name] or CFrame.identity
					joint.Transform = joint.Transform:Lerp(want, st.w)
				end
			elseif char then
				weight[char] = nil
			end
		end
	end)
	return {}
end
