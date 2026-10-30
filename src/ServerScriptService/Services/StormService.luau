-- Грозовые облака (Config.Storms): Count облаков бродят по карте между базами (над базами не бывают),
-- каждое — от точки к случайной точке. Под облаком бьют молнии: в землю или море, часть ударов — прицельно
-- в игроков и ботов под облаком; урон — тем, кто рядом с местом удара. Самолёт внутри облака теряет здоровье,
-- ему ставится атрибут InStorm — клиент пилота (PlaneClient) трясёт его турбулентностью.
-- Положение облаков — атрибуты GameState Storm<i>_Pos (клиент StormFx рисует облако), удары — Remotes.StormStrike.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local PlaneService = require(Services.PlaneService)
local Notifier = require(Services.Notifier)

local StormService = {}
local S = Config.Storms
local storms = {}
local GameState = ReplicatedStorage:WaitForChild("GameState")
local remote

local function randomPoint()
	return Vector3.new(math.random(-S.Bounds.X, S.Bounds.X), S.Height, math.random(-S.Bounds.Z, S.Bounds.Z))
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false

-- живые цели: {гуманоид, корень, игрок или nil}
local function targets()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hum and hrp and hum.Health > 0 and p:GetAttribute("State") == "Deployed" then table.insert(list, {hum, hrp, p}) end
	end
	local bots = workspace:FindFirstChild("Bots")
	for _, b in ipairs(bots and bots:GetChildren() or {}) do
		local hum = b:FindFirstChildOfClass("Humanoid")
		local hrp = b:FindFirstChild("HumanoidRootPart")
		if hum and hrp and hum.Health > 0 then table.insert(list, {hum, hrp}) end
	end
	return list
end

local function strike(i, st)
	-- куда: иногда — в того, кто под облаком, иначе — в случайную точку под ним
	local point
	local under = {}
	for _, t in ipairs(targets()) do
		if flat(t[2].Position - st.pos).Magnitude < S.Radius and t[2].Position.Y < st.pos.Y then table.insert(under, t) end
	end
	if #under > 0 and math.random() < S.TargetChance then
		local t = under[math.random(1, #under)]
		point = t[2].Position + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6))
	else
		local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * S.Radius * 0.9
		point = st.pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end
	local from = Vector3.new(point.X, st.pos.Y - S.Thickness / 2, point.Z)
	local hit = workspace:Raycast(from, Vector3.new(0, -from.Y - 50, 0), groundParams)
	local impact = hit and hit.Position or Vector3.new(point.X, 0, point.Z)
	remote:FireAllClients(i, from, impact)
	-- урон: прямо у места удара — сильный, рядом — слабее
	for _, t in ipairs(targets()) do
		local d = (t[2].Position - impact).Magnitude
		local dmg = d < S.StrikeRadius and S.StrikeDamage or d < S.SplashRadius and S.SplashDamage or 0
		if dmg > 0 then
			t[1]:TakeDamage(dmg)
			if t[3] then Notifier.send(t[3], ("Struck by lightning! −%d HP"):format(dmg), "error") end
		end
	end
end

-- самолёты внутри облака: урон и турбулентность (атрибут InStorm читает клиент пилота)
local function planesStep(step)
	local f = workspace.Map:FindFirstChild("Planes")
	for _, m in ipairs(f and f:GetChildren() or {}) do
		local root = m.PrimaryPart
		if root and m:GetAttribute("IsPlane") then
			local p = root.Position
			local inside = false
			for _, st in ipairs(storms) do
				if flat(p - st.pos).Magnitude < S.Radius and math.abs(p.Y - st.pos.Y) < S.Thickness / 2 then inside = true end
			end
			if inside ~= (m:GetAttribute("InStorm") == true) then
				m:SetAttribute("InStorm", inside)
				if inside then
					local seat = m:FindFirstChild("PilotSeat", true)
					local hum = seat and seat:IsA("Seat") and seat.Occupant
					local pilot = hum and Players:GetPlayerFromCharacter(hum.Parent)
					if pilot then Notifier.send(pilot, "Storm cloud — turbulence! Fly out of it", "error") end
				end
			end
			if inside then PlaneService.damage(m, S.TurbulenceDPS * step, nil) end
		end
	end
end

function StormService.init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = Remotes:FindFirstChild("StormStrike")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "StormStrike"
		remote.Parent = Remotes
	end
	GameState:SetAttribute("StormCount", S.Count)
	for i = 1, S.Count do
		local st = {pos = randomPoint(), target = randomPoint(), nextStrike = os.clock() + math.random() * 3}
		storms[i] = st
		GameState:SetAttribute("Storm" .. i .. "_Pos", st.pos)
	end
	local acc, pub = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		pub += dt
		if acc < 0.1 then return end
		local step = acc
		acc = 0
		local now = os.clock()
		for i, st in ipairs(storms) do
			local d = flat(st.target - st.pos)
			if d.Magnitude < 20 then
				st.target = randomPoint()
			else
				st.pos += d.Unit * math.min(d.Magnitude, S.Speed * step)
			end
			if now >= st.nextStrike then
				st.nextStrike = now + S.StrikeEvery[1] + math.random() * (S.StrikeEvery[2] - S.StrikeEvery[1])
				local ok, err = pcall(strike, i, st)
				if not ok then warn("[StormService] " .. tostring(err)) end
			end
		end
		if pub >= 0.25 then
			pub = 0
			for i, st in ipairs(storms) do GameState:SetAttribute("Storm" .. i .. "_Pos", st.pos) end
		end
		planesStep(step)
	end)
end

return StormService
