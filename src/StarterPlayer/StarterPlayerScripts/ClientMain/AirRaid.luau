-- Воздушная тревога: пока GameState.AirRaid_<команда> = true (вражеский самолёт над островом, см. AirRaidService),
-- на мачте AirRaidSiren этой базы воет сирена, горит красный маяк и крутится прожектор.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundFx = require(script.Parent:WaitForChild("SoundFx"))

local FADE = 1.5
local SPIN = 3.5 -- рад/с
local BEACON_OFF = Color3.fromRGB(150, 20, 20)
local BEACON_ON = Color3.fromRGB(255, 35, 25)

return function(ctx)
	local GameState = ctx.GameState
	local sirens = {} -- [модель] = {team, sound, e, on}

	local function add(m)
		if sirens[m] or not m:IsA("Model") or m.Name ~= "AirRaidSiren" then return end
		local team = m:GetAttribute("Team")
		local horns = m:WaitForChild("Horns", 10)
		if not team or not horns then return end
		local s, e = SoundFx.loop("AirRaidSiren", horns)
		sirens[m] = {team = team, sound = s, e = e, on = false}
	end

	local function setLights(m, on)
		local beacon = m:FindFirstChild("Beacon")
		local spinner = m:FindFirstChild("Spinner")
		if beacon then
			beacon.Material = on and Enum.Material.Neon or Enum.Material.Glass
			beacon.Color = on and BEACON_ON or BEACON_OFF
			local glow = beacon:FindFirstChild("Glow")
			if glow then glow.Enabled = on end
		end
		local sweep = spinner and spinner:FindFirstChild("Sweep")
		if sweep then sweep.Enabled = on end
	end

	local function switch(m, st, on)
		st.on = on
		setLights(m, on)
		local s = st.sound
		if not s then return end
		if on then
			if not s.Playing then
				s.Volume = 0
				s:Play()
			end
			TweenService:Create(s, TweenInfo.new(FADE), {Volume = st.e.volume}):Play()
		else
			local tw = TweenService:Create(s, TweenInfo.new(FADE * 2), {Volume = 0})
			tw.Completed:Once(function()
				if not st.on then s:Stop() end
			end)
			tw:Play()
		end
	end

	task.spawn(function()
		local teams = workspace:WaitForChild("Map"):WaitForChild("Teams")
		for _, d in ipairs(teams:GetDescendants()) do add(d) end
		teams.DescendantAdded:Connect(function(d)
			if d.Name == "AirRaidSiren" then task.defer(add, d) end
		end)
	end)

	local clock = 0
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		for m, st in pairs(sirens) do
			if not m.Parent then
				sirens[m] = nil
				continue
			end
			local active = GameState:GetAttribute("AirRaid_" .. st.team) == true
			if active ~= st.on then switch(m, st, active) end
			if st.on then
				local spinner = m:FindFirstChild("Spinner")
				if spinner then
					spinner.CFrame = CFrame.new(spinner.Position) * CFrame.Angles(0, clock * SPIN, 0) * CFrame.Angles(-0.3, 0, 0)
				end
				local glow = m:FindFirstChild("Beacon") and m.Beacon:FindFirstChild("Glow")
				if glow then glow.Brightness = 2 + 2 * math.abs(math.sin(clock * 4)) end
			end
		end
	end)

	return {}
end
