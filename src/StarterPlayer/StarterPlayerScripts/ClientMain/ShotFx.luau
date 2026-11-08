-- Пули-трассеры на клиенте: короткая светящаяся «пуля» летит от ствола к точке попадания
local RunService = game:GetService("RunService")
local SoundFx = require(script.Parent:WaitForChild("SoundFx"))

return function(ctx)
	local player = ctx.player
	local folder = Instance.new("Folder")
	folder.Name = "ClientFx"
	folder.Parent = workspace
	local SPEED, LEN = 1400, 7
	local pool, active = {}, {}

	local function getPart()
		local p = table.remove(pool)
		if not p then
			p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(255, 210, 110)
			p.Size = Vector3.new(0.2, 0.2, LEN)
		end
		p.Parent = folder
		return p
	end

	local api = {}
	-- cls — класс оружия (Rifle / AA / PlaneGun) для звука выстрела
	function api.streak(a, b, cls)
		if cls then SoundFx.play(cls, a) end
		if #active > 250 then return end
		local d = (b - a).Magnitude
		if d < 1 then return end
		table.insert(active, {p = getPart(), a = a, dir = (b - a) / d, len = d, t = 0})
	end

	RunService.RenderStepped:Connect(function(dt)
		for i = #active, 1, -1 do
			local s = active[i]
			if s.fxPart then
				s.t += dt
				local k = s.t / 0.5
				if k >= 1 then
					s.fxPart:Destroy()
					table.remove(active, i)
				else
					if s.water then
						s.fxPart.Size = Vector3.new(2 + 12 * k, 4 + 3 * k, 4 + 3 * k)
						s.fxPart.CFrame = CFrame.new(s.base + Vector3.new(0, 1 + 6 * k, 0)) * CFrame.Angles(0, 0, math.pi / 2)
					else
						s.fxPart.Size = Vector3.one * (3 + (s.grow or 14) * k)
					end
					s.fxPart.Transparency = k
				end
				continue
			end
			s.t += dt * SPEED
			if s.t - LEN >= s.len then
				s.p.Parent = nil
				table.insert(pool, s.p)
				table.remove(active, i)
			else
				local head = math.min(s.t, s.len)
				local tail = math.clamp(s.t - LEN, 0, s.len)
				local mid = s.a + s.dir * ((head + tail) / 2)
				s.p.Size = Vector3.new(0.2, 0.2, math.max(0.3, head - tail))
				s.p.CFrame = CFrame.lookAt(mid, mid + s.dir)
			end
		end
	end)

	-- снаряды: ядро летит по той же баллистике, что и на сервере
	local shells = {}
	local shellParams = RaycastParams.new()
	shellParams.FilterType = Enum.RaycastFilterType.Exclude
	-- облако дыма: выхлоп РПГ и дым от взрыва (встроенная текстура Roblox)
	local function smokeBurst(cf, count, speed, spread, size, life)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.CFrame = cf
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Enabled = false
		e.EmissionDirection = Enum.NormalId.Front
		e.Speed = speed
		e.SpreadAngle = Vector2.new(spread, spread)
		e.Lifetime = NumberRange.new(life * 0.6, life)
		e.Drag = 3
		e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size * 0.3), NumberSequenceKeypoint.new(1, size)})
		e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1)})
		e.Color = ColorSequence.new(Color3.fromRGB(200, 195, 185), Color3.fromRGB(110, 110, 110))
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-30, 30)
		e.Parent = p
		p.Parent = folder
		e:Emit(count)
		task.delay(life + 0.2, function() p:Destroy() end)
	end

	local function impact(pos, water, big)
		if big and not water then smokeBurst(CFrame.lookAt(pos, pos + Vector3.yAxis), 30, NumberRange.new(6, 16), 80, 9, 3) end
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Shape = water and Enum.PartType.Cylinder or Enum.PartType.Ball
		p.Color = water and Color3.fromRGB(235, 245, 255) or Color3.fromRGB(255, 170, 70)
		p.Size = water and Vector3.new(2, 4, 4) or Vector3.new(3, 3, 3)
		p.CFrame = water and (CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2)) or CFrame.new(pos)
		p.Parent = folder
		table.insert(active, {fxPart = p, t = 0, water = water, base = pos, grow = big and 24 or 14})
	end
	RunService.RenderStepped:Connect(function(dt)
		if #shells == 0 then return end
		local char = player.Character
		shellParams.FilterDescendantsInstances = char and {folder, char} or {folder} -- раз за кадр, а не на каждый снаряд
		for i = #shells, 1, -1 do
			local s = shells[i]
			s.t += dt
			local t = s.t
			local pos = s.o + s.v * t + Vector3.new(0, -0.5 * s.g * t * t, 0)
			local hit = workspace:Raycast(s.last, pos - s.last, shellParams)
			if hit or pos.Y < 0 or t > 15 then
				table.remove(shells, i)
				if s.whistle then s.whistle:Stop() end
				if s.rocket then
					-- дым из следа догорает сам, ракету прячем
					for _, d in ipairs(s.part:GetDescendants()) do
						if d:IsA("ParticleEmitter") or d:IsA("Light") then d.Enabled = false
						elseif d:IsA("BasePart") then d.Transparency = 1 end
					end
					local m = s.part
					task.delay(2.5, function() m:Destroy() end)
				else
					s.part:Destroy()
				end
				if hit then impact(hit.Position, false, s.rocket) elseif pos.Y < 0 then impact(Vector3.new(pos.X, 0, pos.Z), true) end
			else
				if s.rocket then
					local vel = s.v + Vector3.new(0, -s.g * t, 0)
					s.part:PivotTo(CFrame.lookAt(pos, pos + vel))
				else
					s.part.CFrame = CFrame.new(pos)
				end
				s.last = pos
			end
		end
	end)
	ctx.Remotes:WaitForChild("ShellFx").OnClientEvent:Connect(function(o, v, g, cls)
		if typeof(o) ~= "Vector3" or typeof(v) ~= "Vector3" or type(g) ~= "number" then return end
		-- авиабомба падает молча (взрыв озвучит Explosion)
		if cls ~= "Bomb" then
			SoundFx.play(cls == "Heavy" and "CannonHeavy" or cls == "RPG" and "RPGLaunch" or "CannonMedium", o)
		end
		if #shells > 60 then return end
		local templates = game:GetService("ReplicatedStorage"):FindFirstChild("FxTemplates")
		-- бомба: модель, носом по траектории (как ракета, только без дыма)
		local bombTpl = cls == "Bomb" and templates and templates:FindFirstChild("AerialBomb")
		if bombTpl then
			local m = bombTpl:Clone()
			m:PivotTo(CFrame.lookAt(o, o + (v.Magnitude > 1 and v or Vector3.new(0, -1, 0.01))))
			m.Parent = folder
			-- свист летит вместе с бомбой (3D), на ударе стихает
			-- без PrimaryPart звук ушёл бы в SoundService: свистел бы «в ушах» у всех и не удалялся вместе с бомбой
			local whistle, we
			if m.PrimaryPart then whistle, we = SoundFx.loop("BombWhistle", m.PrimaryPart, false) end
			if whistle then
				whistle.Volume = we.volume
				whistle.PlaybackSpeed = we.pitch[1] + math.random() * (we.pitch[2] - we.pitch[1])
				whistle:Play()
			end
			table.insert(shells, {o = o, v = v, g = g, t = 0, last = o, part = m, rocket = true, whistle = whistle})
			return
		end
		-- РПГ: настоящая ракета с дымным следом, выхлоп назад из трубы
		local tpl = cls == "RPG" and v.Magnitude > 1 and templates
		tpl = tpl and tpl:FindFirstChild("RPGRocket")
		if tpl then
			local dir = v.Unit
			local m = tpl:Clone()
			m:PivotTo(CFrame.lookAt(o, o + dir))
			m.Parent = folder
			smokeBurst(CFrame.lookAt(o - dir * 4, o - dir * 10), 26, NumberRange.new(18, 34), 22, 6, 2.2)
			smokeBurst(CFrame.lookAt(o, o + dir), 8, NumberRange.new(4, 8), 30, 3, 1.2)
			table.insert(shells, {o = o, v = v, g = g, t = 0, last = o, part = m, rocket = true})
			return
		end
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Shape = Enum.PartType.Ball
		p.Color = Color3.fromRGB(255, 200, 120)
		p.Size = Vector3.new(1.4, 1.4, 1.4)
		p.CFrame = CFrame.new(o)
		p.Parent = folder
		table.insert(shells, {o = o, v = v, g = g, t = 0, last = o, part = p})
	end)

	ctx.Remotes:WaitForChild("ShotFx").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then return end
		local me = player.UserId
		for i = 1, #batch - 3, 4 do
			local a, b, skip, cls = batch[i], batch[i + 1], batch[i + 2], batch[i + 3]
			if skip ~= me and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
				api.streak(a, b, type(cls) == "string" and cls or nil)
			end
		end
	end)

	-- взрывы создаёт сервер (Explosion прямо в workspace) — звучим их здесь
	workspace.ChildAdded:Connect(function(c)
		if c:IsA("Explosion") then SoundFx.explosion(c) end
	end)
	-- торпеды и глубинные бомбы появляются в workspace.Effects
	task.spawn(function()
		local effects = workspace:WaitForChild("Effects", 30)
		if not effects then return end
		effects.ChildAdded:Connect(function(c)
			if not c:IsA("BasePart") then return end
			if c.Name == "Torpedo" or c.Name == "DepthCharge" then
				task.delay(0.15, function() -- торпеду сервер ставит на место только следующим кадром
					if c.Parent then SoundFx.play(c.Name == "Torpedo" and "TorpedoLaunch" or "DepthChargeDrop", c.Position) end
				end)
			end
		end)
	end)
	return api
end
