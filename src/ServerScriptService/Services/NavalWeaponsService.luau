-- Морское оружие: торпеды подлодки, глубинные бомбы катера, сонар кораблей.
-- Всё считает сервер; клиент только просит выстрелить (ShipWeapon) и видит результат.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local TeamService = require(Services.TeamService)
local CombatService = require(Services.CombatService)
local ShipService = require(Services.ShipService)
local CarrierService = require(Services.CarrierService)
local Notifier = require(Services.Notifier)

local NavalWeaponsService = {}
local SW = Config.SubWeapons
local TORP, DC = SW.Torpedo, SW.DepthCharge
local torpedoes = {}
local charges = {}
local ammo = {} -- [модель] = {torps, reloadAt, charges, nextCharge}

local function now() return workspace:GetServerTimeNow() end
local function fx()
	local f = workspace:FindFirstChild("Effects")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Effects"
		f.Parent = workspace
	end
	return f
end
local function teamOfActor(a) return a and TeamService.getTeamName(a) end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function ammoOf(model)
	local a = ammo[model]
	if not a then
		a = {torps = TORP.Tubes, reloadAt = 0, charges = DC.Count, nextCharge = 0}
		ammo[model] = a
		model:SetAttribute("Torpedoes", a.torps)
		model:SetAttribute("DepthCharges", a.charges)
	end
	return a
end

-- sfx — какой звук играет клиент (ключ SoundFx); nil — клиент выберет по размеру
local function boom(pos, radius, sfx)
	local e = Instance.new("Explosion")
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.BlastRadius = radius
	e.Position = pos
	if sfx then e:SetAttribute("Sfx", sfx) end
	e.Parent = workspace
end

------------------------------------------------------------------ торпеды
local hitOverlap = OverlapParams.new()
hitOverlap.FilterType = Enum.RaycastFilterType.Include
hitOverlap.CollisionGroup = "Weapons" -- иначе не видит грузовые суда (их группа не сталкивается с Default)
local landRay = RaycastParams.new()
landRay.FilterType = Enum.RaycastFilterType.Include
landRay.IgnoreWater = true

local function launchTorpedo(st, actor)
	local cf = st.model:GetPivot()
	local fwd = flat(cf.LookVector * -1) -- нос модели = +Z
	if fwd.Magnitude < 0.1 then return end
	fwd = fwd.Unit
	local start = Vector3.new(cf.X, -TORP.RunDepth, cf.Z) + fwd * 36
	local body = Instance.new("Part")
	body.Name = "Torpedo"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(6, 1.2, 1.2)
	body.Color = Color3.fromRGB(40, 44, 50)
	body.Material = Enum.Material.Metal
	body.Anchored, body.CanCollide, body.CanQuery, body.CanTouch = true, false, false, false
	body.Parent = fx()
	local wake = Instance.new("Part")
	wake.Name = "TorpedoWake"
	wake.Size = Vector3.new(2.2, 0.15, 16)
	wake.Color = Color3.fromRGB(240, 248, 255)
	wake.Material = Enum.Material.SmoothPlastic
	wake.Transparency = 0.25
	wake.Anchored, wake.CanCollide, wake.CanQuery, wake.CanTouch = true, false, false, false
	wake.Parent = fx()
	table.insert(torpedoes, {pos = start, dir = fwd, left = TORP.Range, actor = actor, team = teamOfActor(actor), shooter = st.model, body = body, wake = wake})
end

local function stepTorpedoes(dt)
	for i = #torpedoes, 1, -1 do
		local t = torpedoes[i]
		local move = TORP.Speed * dt
		local newPos = t.pos + t.dir * move
		t.left -= move
		local hitPart, done
		-- берег
		landRay.FilterDescendantsInstances = {workspace.Terrain}
		if workspace:Raycast(t.pos + Vector3.new(0, 3, 0), t.dir * move, landRay) then done = true end
		-- корабли противника
		if not done then
			local list = {}
			for _, n in ipairs({"Vessels", "Carriers", "Cargo"}) do
				local f = workspace.Map:FindFirstChild(n)
				if f then table.insert(list, f) end
			end
			hitOverlap.FilterDescendantsInstances = list
			for _, part in ipairs(workspace:GetPartBoundsInRadius(newPos, TORP.HitRadius, hitOverlap)) do
				if not part:IsDescendantOf(t.shooter) then
					local kind, model = CombatService.resolveHit(part)
					local mt = model and model:GetAttribute("Team")
					if kind and mt and mt ~= t.team then hitPart = part break end
				end
			end
		end
		if hitPart or done or t.left <= 0 then
			table.remove(torpedoes, i)
			t.body:Destroy()
			t.wake:Destroy()
			if hitPart then
				boom(Vector3.new(newPos.X, 0, newPos.Z), 14, "TorpedoHit")
				CombatService.applyHit(t.actor, hitPart, TORP.Damage, nil, "Torpedo", Vector3.new(newPos.X, 3, newPos.Z))
			elseif done then
				boom(Vector3.new(newPos.X, 0, newPos.Z), 6, "Underwater")
			end
		else
			t.pos = newPos
			local look = CFrame.lookAt(newPos, newPos + t.dir)
			t.body.CFrame = look * CFrame.Angles(0, math.pi / 2, 0)
			t.wake.CFrame = CFrame.lookAt(Vector3.new(newPos.X, 0.1, newPos.Z) - t.dir * 8, Vector3.new(newPos.X, 0.1, newPos.Z) + t.dir)
		end
	end
end

------------------------------------------------------------------ глубинные бомбы
local function dropCharge(st, actor)
	local cf = st.model:GetPivot()
	local back = flat(cf.LookVector) -- корма модели = -Z → LookVector
	local pos = Vector3.new(cf.X, 1, cf.Z) + back.Unit * 27
	local p = Instance.new("Part")
	p.Name = "DepthCharge"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(2.4, 2, 2)
	p.Color = Color3.fromRGB(60, 64, 70)
	p.Material = Enum.Material.Metal
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CFrame = CFrame.new(pos)
	p.Parent = fx()
	table.insert(charges, {part = p, pos = pos, t = 0, actor = actor, team = teamOfActor(actor)})
end

local function stepCharges(dt)
	for i = #charges, 1, -1 do
		local c = charges[i]
		c.t += dt
		c.pos -= Vector3.new(0, DC.SinkSpeed * dt, 0)
		c.part.CFrame = CFrame.new(c.pos) * CFrame.Angles(0, 0, c.t * 2)
		if c.t >= DC.SinkTime then
			table.remove(charges, i)
			c.part:Destroy()
			boom(Vector3.new(c.pos.X, 0, c.pos.Z), 10, "Underwater")
			-- урон подлодкам противника рядом
			for model, sst in pairs(ShipService.getAll()) do
				if not sst.dead and sst.kind == "Submarine" and sst.team ~= c.team then
					local d = (sst.root.Position - c.pos).Magnitude
					if d <= DC.Radius then
						local dmg = DC.Damage * (1 - 0.5 * d / DC.Radius)
						ShipService.damage(model, dmg, c.actor)
						CombatService.showDamage(c.actor, model, Vector3.new(c.pos.X, 2, c.pos.Z), dmg)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------ выстрел (игрок или бот)
function NavalWeaponsService.fire(actor, kind)
	-- корабль, за штурвалом которого сидит actor
	local st
	for _, s in pairs(ShipService.getAll()) do
		if s.driver == actor and not s.dead then st = s break end
	end
	if not st then return false, "You are not at the helm" end
	local a = ammoOf(st.model)
	local t = now()
	if kind == "torpedo" then
		if st.kind ~= "Submarine" then return false end
		if (st.depth or 0) > (st.cfg.PeriscopeDepth or 8) then return false, "Too deep — rise to periscope depth" end
		if a.torps <= 0 then return false, ("Reloading torpedoes · %d s"):format(math.ceil(a.reloadAt - t)) end
		a.torps -= 1
		if a.torps <= 0 then a.reloadAt = t + TORP.Reload end
		st.model:SetAttribute("Torpedoes", a.torps)
		st.model:SetAttribute("TorpedoReloadAt", a.reloadAt)
		st.model:SetAttribute("RevealedUntil", t + TORP.RevealTime)
		launchTorpedo(st, actor)
		return true
	elseif kind == "depthcharge" then
		if st.kind ~= "Gunboat" then return false end
		if a.charges <= 0 then return false, "Out of charges — they refill in a few seconds" end
		a.charges -= 1
		if a.nextCharge < t then a.nextCharge = t + DC.Reload end
		st.model:SetAttribute("DepthCharges", a.charges)
		dropCharge(st, actor)
		return true
	end
	return false
end

------------------------------------------------------------------ сонар
local SONAR_SHIPS = {Gunboat = true, Battleship = true}
local function sonarStep()
	local sources = {Blue = {}, Red = {}}
	for _, s in pairs(ShipService.getAll()) do
		if not s.dead and SONAR_SHIPS[s.kind] and sources[s.team] then
			table.insert(sources[s.team], s.root.Position)
		end
	end
	for _, team in ipairs(Config.TeamOrder) do
		local info = CarrierService.getInfo(team)
		if info and info.state == "Active" and info.model and info.model:FindFirstChild("Hull") then
			table.insert(sources[team], info.model.Hull.Position)
		end
	end
	local r2 = SW.SonarRadius * SW.SonarRadius
	for model, s in pairs(ShipService.getAll()) do
		if s.kind == "Submarine" and not s.dead then
			local p = s.root.Position
			for team, list in pairs(sources) do
				if team ~= s.team then
					local seen = false
					for _, q in ipairs(list) do
						local dx, dz = p.X - q.X, p.Z - q.Z
						if dx * dx + dz * dz <= r2 then seen = true break end
					end
					if model:GetAttribute("Sonar_" .. team) ~= seen then model:SetAttribute("Sonar_" .. team, seen) end
				end
			end
		end
	end
end

function NavalWeaponsService.init()
	local remote = ReplicatedStorage.Remotes:WaitForChild("ShipWeapon")
	local last = {}
	remote.OnServerEvent:Connect(function(player, kind)
		if kind ~= "torpedo" and kind ~= "depthcharge" then return end
		local t = os.clock()
		if last[player] and t - last[player] < 0.3 then return end
		last[player] = t
		local ok, msg = NavalWeaponsService.fire(player, kind)
		if not ok and msg then Notifier.send(player, msg, "error") end
	end)
	Players.PlayerRemoving:Connect(function(p) last[p] = nil end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		stepTorpedoes(dt)
		stepCharges(dt)
		acc += dt
		if acc >= 0.5 then
			acc = 0
			sonarStep()
			-- перезарядка
			local t = now()
			for model, a in pairs(ammo) do
				if not model.Parent then
					ammo[model] = nil
				else
					if a.torps <= 0 and t >= a.reloadAt then
						a.torps = TORP.Tubes
						model:SetAttribute("Torpedoes", a.torps)
					end
					if a.charges < DC.Count and t >= a.nextCharge then
						a.charges += 1
						a.nextCharge = t + DC.Reload
						model:SetAttribute("DepthCharges", a.charges)
					end
				end
			end
			-- новые подлодки/катера сразу получают боезапас (для интерфейса)
			for model, s in pairs(ShipService.getAll()) do
				if (s.kind == "Submarine" or s.kind == "Gunboat") and not ammo[model] then ammoOf(model) end
			end
		end
	end)
end

return NavalWeaponsService
