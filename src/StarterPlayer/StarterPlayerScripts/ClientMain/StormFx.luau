-- Грозовые облака (StormService): облако из тёмных клубов с тенью и дождём плывёт за позицией с сервера
-- (GameState Storm<i>_Pos), молния (Remotes.StormStrike) — ломаная неоновая линия от облака до земли,
-- вспышка, гром с задержкой по расстоянию, рядом — тряска камеры. Всё только у этого клиента.
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local SoundFx = require(script.Parent:WaitForChild("SoundFx"))

local PUFFS = 44

return function(ctx)
	local S = ctx.Config.Storms
	local GameState = ctx.GameState
	local folder = Instance.new("Folder")
	folder.Name = "Storms"
	folder.Parent = workspace
	local clouds = {}

	local function part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		for k, v in pairs(props) do p[k] = v end
		p.Parent = folder
		return p
	end

	local function buildCloud(i)
		local rng = Random.new(i * 7919)
		local k = S.Radius / 170 -- клубы растут вместе с облаком
		local c = {puffs = {}, pos = nil}
		for n = 1, PUFFS do
			local a, r = rng:NextNumber() * math.pi * 2, math.sqrt(rng:NextNumber()) * S.Radius * 0.85
			local size = rng:NextNumber(70, 150) * k
			local top = n > PUFFS * 0.65
			local off = Vector3.new(math.cos(a) * r, (top and rng:NextNumber(10, 35) or rng:NextNumber(-25, 5)) * k, math.sin(a) * r)
			local p = part({
				Name = "Puff", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size * 0.6, size),
				Color = top and Color3.fromRGB(118, 122, 132) or Color3.fromRGB(62, 66, 76),
				Material = Enum.Material.SmoothPlastic, Transparency = top and 0.2 or 0.1, CastShadow = true,
			})
			table.insert(c.puffs, {part = p, off = off, bob = rng:NextNumber() * 10})
		end
		-- дождь из-под облака
		local rain = part({Name = "Rain", Size = Vector3.new(S.Radius * 1.6, 1, S.Radius * 1.6), Transparency = 1})
		local e = Instance.new("ParticleEmitter")
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Rate = 520
		e.Lifetime = NumberRange.new(2.2, 2.8)
		e.Speed = NumberRange.new(110, 130)
		e.Size = NumberSequence.new(0.35)
		e.Squash = NumberSequence.new(-4)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Color = ColorSequence.new(Color3.fromRGB(170, 185, 205))
		e.Transparency = NumberSequence.new(0.35)
		e.LightEmission = 0.1
		e.Parent = rain
		c.rain = rain
		clouds[i] = c
		return c
	end

	-- вспышка экрана, если удар рядом
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "StormFlash"
	cc.Parent = Lighting
	local shakeUntil, shakePower = 0, 0

	local function bolt(from, to)
		local pts = {from}
		local n = 9
		for k = 1, n - 1 do
			local t = k / n
			local p = from:Lerp(to, t)
			table.insert(pts, p + Vector3.new(math.random(-14, 14), math.random(-4, 4), math.random(-14, 14)) * (1 - t * 0.5))
		end
		table.insert(pts, to)
		local made = {}
		local function seg(a, b, w)
			local p = part({
				Size = Vector3.new(w, w, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b),
				Color = Color3.fromRGB(200, 225, 255), Material = Enum.Material.Neon, CastShadow = false,
			})
			table.insert(made, p)
		end
		for k = 1, #pts - 1 do seg(pts[k], pts[k + 1], 1.1) end
		-- ответвление
		local b0 = pts[math.random(3, 5)]
		seg(b0, b0 + Vector3.new(math.random(-40, 40), -math.random(30, 60), math.random(-40, 40)), 0.6)
		local flash = part({Size = Vector3.new(1, 1, 1), Position = to + Vector3.new(0, 4, 0), Transparency = 1})
		local light = Instance.new("PointLight")
		light.Range = 120
		light.Brightness = 12
		light.Color = Color3.fromRGB(200, 220, 255)
		light.Parent = flash
		table.insert(made, flash)
		task.delay(0.08, function()
			for _, p in ipairs(made) do if p:IsA("BasePart") and p ~= flash then p.Transparency = 0.6 end end
		end)
		task.delay(0.22, function()
			for _, p in ipairs(made) do p:Destroy() end
		end)
	end

	ctx.Remotes:WaitForChild("StormStrike").OnClientEvent:Connect(function(i, from, impact)
		if typeof(from) ~= "Vector3" or typeof(impact) ~= "Vector3" then return end
		bolt(from, impact)
		local cam = workspace.CurrentCamera
		local dist = cam and (cam.CFrame.Position - impact).Magnitude or 1e9
		if dist < 900 then
			cc.Brightness = math.clamp(0.5 * (1 - dist / 900), 0.05, 0.5)
			TweenService:Create(cc, TweenInfo.new(0.35), {Brightness = 0}):Play()
		end
		if dist < 260 then
			shakeUntil = os.clock() + 0.5
			shakePower = (1 - dist / 260) * 1.2
		end
		if dist < 700 then
			task.delay(dist / 1100, function()
				SoundFx.play("Thunder", impact)
			end)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for i = 1, GameState:GetAttribute("StormCount") or 0 do
			local target = GameState:GetAttribute("Storm" .. i .. "_Pos")
			if typeof(target) == "Vector3" then
				local c = clouds[i] or buildCloud(i)
				c.pos = c.pos and c.pos:Lerp(target, math.min(1, dt * 2)) or target
				for _, p in ipairs(c.puffs) do
					p.part.CFrame = CFrame.new(c.pos + p.off + Vector3.new(0, math.sin(t * 0.4 + p.bob) * 2, 0))
				end
				c.rain.CFrame = CFrame.new(c.pos - Vector3.new(0, S.Thickness / 2, 0))
			end
		end
		-- тряска камеры от близкого удара
		if t < shakeUntil then
			local cam = workspace.CurrentCamera
			local k = shakePower * (shakeUntil - t) / 0.5
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * 2 * k), math.rad((math.random() - 0.5) * 2 * k), 0)
		end
	end)

	return {}
end
