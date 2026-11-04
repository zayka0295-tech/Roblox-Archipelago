-- В море персонаж плывёт медленнее, чем бежит по суше (Config.Spawn.SwimSpeed), и не может «скакать» по воде:
-- прыжок из воды — не чаще раза в SwimJumpCooldown сек., а пока он снова не встал на твёрдую опору,
-- скорость остаётся «водной» (иначе серия прыжков несёт его со скоростью бега).
-- Скорость на суше — та, что выставил сервер (SpawnService); её запоминаем и возвращаем, когда вышел на берег.
local RunService = game:GetService("RunService")

local S = Enum.HumanoidStateType
local ON_FEET = {[S.Running] = true, [S.RunningNoPhysics] = true, [S.Landed] = true}
local ALWAYS_DRY = {[S.Climbing] = true, [S.Seated] = true}
-- на поверхности воды Humanoid на миг тоже бывает Running — суша только если под ногами не вода
local function isDry(h, state)
	if ALWAYS_DRY[state] then return true end
	local m = h.FloorMaterial
	return ON_FEET[state] and m ~= Enum.Material.Water and m ~= Enum.Material.Air
end

return function(ctx)
	local cfg = ctx.Config.Spawn
	local SWIM = cfg.SwimSpeed or 12
	local COOLDOWN = cfg.SwimJumpCooldown or 1.5

	local hum, wet, landSpeed, lastJump, jumpOff = nil, false, nil, 0, false

	local function setJump(on)
		if hum and jumpOff == on then
			jumpOff = not on
			hum:SetStateEnabled(S.Jumping, on)
		end
	end

	local function dry()
		if not wet then return end
		wet = false
		if hum and landSpeed and hum.WalkSpeed == SWIM then hum.WalkSpeed = landSpeed end
		landSpeed = nil
		setJump(true)
	end

	local function bind(char)
		wet, landSpeed, jumpOff = false, nil, false
		hum = char:WaitForChild("Humanoid", 10)
		if not hum then return end
		local h = hum
		h.StateChanged:Connect(function(old, new)
			if h ~= hum then return end
			if new == S.Swimming then
				if not wet then
					wet = true
					if h.WalkSpeed ~= SWIM then landSpeed = h.WalkSpeed end
				end
				h.WalkSpeed = SWIM
			elseif new == S.Jumping and old == S.Swimming then
				lastJump = os.clock()
				setJump(false)
			elseif wet and isDry(h, new) then
				dry()
			end
		end)
	end

	RunService.Heartbeat:Connect(function()
		if not hum or not wet then return end
		if isDry(hum, hum:GetState()) then dry() return end
		-- сервер мог сменить скорость (например, при появлении) — запоминаем её как сухопутную
		if hum.WalkSpeed ~= SWIM then
			landSpeed = hum.WalkSpeed
			hum.WalkSpeed = SWIM
		end
		if jumpOff and os.clock() - lastJump >= COOLDOWN then setJump(true) end
	end)

	if ctx.player.Character then task.spawn(bind, ctx.player.Character) end
	ctx.player.CharacterAdded:Connect(bind)
	return {}
end
