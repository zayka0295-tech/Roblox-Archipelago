-- Хват оружия двумя руками (R15). Оружие держится у плеча и смотрит туда, куда целится стрелок;
-- руки тянутся к рукояти и цевью (IK из двух звеньев). Позу считает каждый клиент для всех персонажей
-- с оружием: свой — по камере, чужие — по атрибутам AimPitch / Aiming на персонаже (их ставит GunService).
-- Точки хвата: вложения RightGripPoint / LeftGripPoint в Handle, иначе детали Grip и Handguard / Grip2.
-- Атрибут HoldOffset инструмента сдвигает хват (РПГ держится на плече).
-- Суставы — AnimationConstraint (или Motor6D): C0/C1 только читаем, позу задаём через Transform
-- после анимации (Stepped): Part1 = Part0 * C0 * Transform * C1⁻¹.
-- Крепление RightGrip не трогаем (иначе сервер «роняет» оружие): правая кисть ставится так,
-- чтобы оружие в ней оказалось в нужном месте.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local PIVOT = Vector3.new(0.5, 0.55, 0)            -- «плечевой шарнир» в осях торса: вокруг него оружие наклоняется за прицелом
local HOLD_HIP = Vector3.new(0.05, -0.75, -1.05)   -- где рукоять от шарнира: от бедра
local HOLD_AIM = Vector3.new(-0.3, -0.35, -1.0)    -- и при прицеливании (выше, к щеке)
-- свой персонаж от первого лица: оружие выше, чтобы ствол был виден справа снизу, а не ушёл за край экрана
local HOLD_FP = Vector3.new(0.15, -0.1, -1.1)
local HOLD_FP_AIM = Vector3.new(-0.4, 0.55, -1.0)
local KICK_BACK = 0.25                              -- насколько оружие уходит назад на выстреле
local WRIST_BACK = 0.3                              -- запястье чуть ближе к плечу, чем точка хвата (ладонь вокруг рукояти)
local SEND_EVERY = 0.1
local POSE_RANGE = 250                              -- чужие дальше от камеры не позируем: рук там не видно, а ботов десятки

return function(ctx)
	local player = ctx.player
	local gunState = ctx.gunState or {kick = 0, aiming = false}
	local AimRemote = ctx.Remotes:WaitForChild("GunAim")
	local rigs = setmetatable({}, {__mode = "k"})
	local tools = setmetatable({}, {__mode = "k"})

	-- IK двух звеньев: плоскость руки и углы плеча и локтя (рука в покое висит вдоль -Y)
	local function solveIK(originCF, targetPos, l1, l2)
		local localized = originCF:PointToObjectSpace(targetPos)
		local l3 = localized.Magnitude
		if l3 < 1e-3 then return originCF, 0, 0 end
		local unit = localized / l3
		local axis = Vector3.new(0, 0, -1):Cross(unit)
		local angle = math.acos(math.clamp(-unit.Z, -1, 1))
		local planeCF = axis.Magnitude > 1e-4 and originCF * CFrame.fromAxisAngle(axis.Unit, angle) or originCF
		if l3 < math.abs(l1 - l2) then
			return planeCF * CFrame.new(0, 0, math.abs(l1 - l2) - l3), -math.pi / 2, math.pi
		elseif l3 > l1 + l2 then
			return planeCF * CFrame.new(0, 0, l1 + l2 - l3), math.pi / 2, 0
		end
		local a1 = -math.acos(math.clamp((-(l2 * l2) + l1 * l1 + l3 * l3) / (2 * l1 * l3), -1, 1))
		local a2 = math.acos(math.clamp((l2 * l2 - l1 * l1 + l3 * l3) / (2 * l2 * l3), -1, 1))
		return planeCF, a1 + math.pi / 2, a2 - a1
	end

	local function rigOf(char)
		local r = rigs[char]
		if r then return r end
		local function j(part, name)
			local p = char:FindFirstChild(part)
			return p and p:FindFirstChild(name)
		end
		r = {
			ut = char:FindFirstChild("UpperTorso"), hrp = char:FindFirstChild("HumanoidRootPart"), hand = char:FindFirstChild("RightHand"),
			R = {s = j("RightUpperArm", "RightShoulder"), e = j("RightLowerArm", "RightElbow"), w = j("RightHand", "RightWrist")},
			L = {s = j("LeftUpperArm", "LeftShoulder"), e = j("LeftLowerArm", "LeftElbow"), w = j("LeftHand", "LeftWrist")},
			pitch = 0, aim = 0, posed = false,
		}
		if not (r.ut and r.hrp and r.hand and r.R.s and r.R.e and r.R.w and r.L.s and r.L.e and r.L.w) then
			return nil -- R6 или персонаж ещё не догрузился — попробуем в следующий раз
		end
		for _, a in ipairs({r.R, r.L}) do
			a.s0, a.e0 = a.s.C0, a.e.C0
			a.l1 = (a.s.C1.Position - a.e.C0.Position).Magnitude
			a.l2 = (a.e.C1.Position - a.w.C0.Position).Magnitude
		end
		rigs[char] = r
		return r
	end

	local function toolInfo(tool)
		local i = tools[tool]
		if i then return i end
		local h = tool:FindFirstChild("Handle")
		if not h then return nil end
		local function point(att, names)
			local a = h:FindFirstChild(att)
			if a and a:IsA("Attachment") then return a.Position end
			for _, n in ipairs(names) do
				local p = tool:FindFirstChild(n)
				if p and p:IsA("BasePart") then return h.CFrame:PointToObjectSpace(p.Position) end
			end
		end
		local muzzle = tool:FindFirstChild("Muzzle")
		local z = muzzle and h.CFrame:PointToObjectSpace(muzzle.Position).Z or -1
		i = {
			right = point("RightGripPoint", {"Grip"}) or Vector3.zero,
			left = point("LeftGripPoint", {"Handguard", "Grip2"}) or Vector3.new(0, 0, z > 0 and 1.2 or -1.2),
			-- ствол должен смотреть вперёд (-Z): если он у ручки вдоль +Z — разворот
			rot = z > 0 and CFrame.Angles(0, math.pi, 0) or CFrame.identity,
			hold = tool:GetAttribute("HoldOffset") or Vector3.zero,
			-- куда тянется левая рука при перезарядке: магазин (или граната РПГ)
			mag = point("MagPoint", {"Mag", "Warhead"}),
		}
		tools[tool] = i
		return i
	end

	local function release(r)
		if not r.posed then return end
		r.posed = false -- Transform дальше снова задаёт анимация
	end

	-- wrist — куда поставить шарнир запястья; handCF — если задан, кисть разворачивается точно так
	local function arm(a, utCF, wrist, handCF)
		local plane, sa, ea = solveIK(utCF * a.s0, wrist, a.l1, a.l2)
		-- нужный «новый C0» плеча = utCF⁻¹ * plane * поворот → Transform = C0⁻¹ * новый C0
		local ts = a.s0:Inverse() * utCF:ToObjectSpace(plane) * CFrame.Angles(sa, 0, 0)
		local te = CFrame.Angles(ea, 0, 0)
		a.s.Transform, a.e.Transform = ts, te
		if handCF then
			local upper = utCF * a.s0 * ts * a.s.C1:Inverse()
			local lower = upper * a.e0 * te * a.e.C1:Inverse()
			a.w.Transform = a.w.C0:Inverse() * lower:ToObjectSpace(handCF) * a.w.C1
		else
			a.w.Transform = CFrame.identity
		end
	end

	local function pose(char, isLocal, dt)
		local tool = char:FindFirstChildOfClass("Tool")
		local r = rigs[char] or (tool and tool:GetAttribute("Gun") and rigOf(char))
		if not r then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local weld = r.hand:FindFirstChild("RightGrip")
		local info = tool and tool:GetAttribute("Gun") and weld and hum and hum.Health > 0 and not hum.SeatPart and toolInfo(tool)
		if not info then release(r) return end
		local pitch, aiming
		if isLocal then
			local cam = workspace.CurrentCamera
			-- от третьего лица GunClient даёт наклон к точке прицела (курсор/касание), от первого — по камере
			pitch = gunState.aimPitch or (cam and math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1))) or 0
			aiming = gunState.aiming
		else
			pitch = char:GetAttribute("AimPitch") or 0
			aiming = char:GetAttribute("Aiming") == true
		end
		r.pitch += (math.clamp(pitch, -1.2, 1.2) - r.pitch) * math.min(1, dt * 18)
		r.aim += ((aiming and 1 or 0) - r.aim) * math.min(1, dt * 10)
		r.rl = (r.rl or 0) + ((tool:GetAttribute("Reloading") and 1 or 0) - (r.rl or 0)) * math.min(1, dt * 8)
		local kick = isLocal and gunState.kick or 0
		-- рукоять: от торса (без покачивания анимации — берём поворот корня), наклон за прицелом, толчок назад
		local base = CFrame.new(r.ut.Position) * r.hrp.CFrame.Rotation
		local fp = isLocal and gunState.firstPerson
		local hold = (fp and HOLD_FP:Lerp(HOLD_FP_AIM, r.aim) or HOLD_HIP:Lerp(HOLD_AIM, r.aim) + info.hold) + Vector3.new(0, 0, kick * KICK_BACK)
		local holdCF = base * CFrame.new(PIVOT) * CFrame.Angles(r.pitch + kick * 0.04, 0, 0) * CFrame.new(hold)
		-- перезарядка: оружие опускается и заваливается на бок
			* CFrame.new(-0.15 * r.rl, -0.3 * r.rl, 0.2 * r.rl) * CFrame.Angles(math.rad(-20) * r.rl, 0, math.rad(35) * r.rl)
		local handleCF = holdCF * info.rot * CFrame.new(-info.right)
		local utCF = r.ut.CFrame
		r.posed = true
		-- правая кисть там, где оружие в ней встанет в handleCF (RightHand * C0 = Handle * C1)
		local handCF = handleCF * weld.C1 * weld.C0:Inverse()
		arm(r.R, utCF, handCF:PointToWorldSpace(r.R.w.C1.Position), handCF)
		-- левая — на цевье, запястье чуть ближе к плечу (ладонь обхватывает снизу)
		local left = handleCF * info.left
		if info.mag and r.rl > 0.01 then left = left:Lerp(handleCF * info.mag, r.rl) end
		local back = (utCF * r.L.s0).Position - left
		arm(r.L, utCF, back.Magnitude > 0.01 and left + back.Unit * WRIST_BACK or left)
	end

	-- NPC с оружием (тег GunHolder): список держим по сигналам тега, а не запрашиваем каждый кадр
	local holders = {}
	for _, m in ipairs(CollectionService:GetTagged("GunHolder")) do holders[m] = true end
	CollectionService:GetInstanceAddedSignal("GunHolder"):Connect(function(m) holders[m] = true end)
	CollectionService:GetInstanceRemovedSignal("GunHolder"):Connect(function(m) holders[m] = nil end)

	local sendAcc, sentPitch, sentAim = 0, nil, nil
	RunService.Stepped:Connect(function(_, dt)
		gunState.kick -= gunState.kick * math.min(1, dt * 14)
		local cam = workspace.CurrentCamera
		local eye = cam and cam.CFrame.Position
		local function near(char)
			local root = char.PrimaryPart or char:FindFirstChild("HumanoidRootPart")
			return root ~= nil and (not eye or (root.Position - eye).Magnitude < POSE_RANGE)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if char and (p == player or near(char)) then pose(char, p == player, dt) end
		end
		-- NPC с оружием (тег GunHolder): наклон — по их атрибуту AimPitch
		for m in pairs(holders) do
			if m:IsA("Model") and m.Parent and near(m) then pose(m, false, dt) end
		end
		-- свой наклон прицела — на сервер, чтобы остальные видели позу
		sendAcc += dt
		local char = player.Character
		local r = char and rigs[char]
		if r and r.posed and sendAcc >= SEND_EVERY then
			sendAcc = 0
			local aim = gunState.aiming == true
			if not sentPitch or math.abs(r.pitch - sentPitch) > 0.03 or aim ~= sentAim then
				sentPitch, sentAim = r.pitch, aim
				AimRemote:FireServer(r.pitch, aim)
			end
		end
	end)
	return {}
end
