-- Защита от телепорта и спидхака персонажа. Персонажем физически управляет клиент, поэтому сервер
-- раз в CHECK сек. сравнивает, сколько персонаж прошёл, с тем, сколько мог:
--  • по горизонтали — бег (WalkSpeed с запасом) + скорость опоры под ногами (палуба идущего корабля;
--    спрыгнув с неё, персонаж ещё немного летит по инерции — поэтому она «затухает» постепенно);
--  • вверх — прыжок; вниз (падение) не ограничено;
--  • полёт: без опоры под ногами — не выше прыжка над последней опорой и не дольше HOVER_TIME без снижения
--    (возврат — на последнюю опору, с учётом её движения: палуба идущего корабля);
--  • сквозь стены: раз в NOCLIP_STEP сек. путь между точками проверяется тремя лучами (ноги,
--    корпус, голова) по неподвижной застройке (Map.Teams, Map.Neutral); упёрлись все три — сквозь стену.
-- Превысил — возвращаем на последнюю честную точку. Не кикаем: при лаге ложное срабатывание безобидно.
-- Не проверяем: в кресле (самолёт, корабль), в лобби, после появления; полёт — ещё и в воде,
-- на лестнице (Climbing), на парашюте (атрибут Parachute) и SEAT_GRACE сек. после кресла.
-- После кресла скорость проверяется сразу, но с запасом на скорость техники (прыжок из летящего самолёта):
-- иначе можно сесть в зенитку, встать и 5 секунд телепортироваться без проверки.
-- Серверные перемещения персонажа: трапы — AntiCheat.moveTo (персонаж обязан остаться у точки переноса),
-- посадка в кресло — AntiCheat.grace перед PivotTo. «Сидит», но далеко от кресла — снимаем с кресла.
local Players = game:GetService("Players")

local AntiCheat = {}
local CHECK = 0.5          -- сек. между проверками
local SPEED_MARGIN = 1.35  -- запас к WalkSpeed
local EXTRA = 6            -- студов на проверку: погрешность и лаг
local UP_LIMIT = 16        -- студов вверх за проверку (прыжок ≈ 7)
local FLOOR_DECAY = 0.6    -- скорость опоры «затухает» за проверку (инерция после прыжка с палубы)
local SEAT_GRACE = 5       -- сек. после выхода из кресла (прыжок из летящего самолёта)
local SPAWN_GRACE = 5      -- сек. после появления персонажа
local RISE_EXTRA = 4       -- студов сверх высоты прыжка над последней опорой
local HOVER_TIME = 1.5     -- сек. без опоры...
local HOVER_DROP = 2       -- ...и не снизился хотя бы на столько — висит в воздухе
local NOCLIP_STEP = 0.1    -- сек. между проверками пути сквозь стены
local NOCLIP_RAYS = {-1, 0, 1.5} -- высоты лучей от корня: перепрыгнул перила — верхний свободен
local SEAT_MAX_DIST = 12   -- студов от кресла: дальше — «сидит» только на сервере (сварку удалили у себя)
local DEST_SLACK = 12      -- студов запаса у точки серверного переноса (персонаж оседает на палубу)
local WATER_TOP = 4        -- море — вода террейна ниже Y=0: «плывёт» выше — состояние подделано клиентом (fly-чит)

local track = {} -- [игрок] = {last = CFrame, graceUntil, floor, strikes, ground*, air*, nc}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false -- поверхность воды — тоже опора
groundParams.CollisionGroup = "Characters" -- опора — то, на чём персонаж может стоять (не самолёт)
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include
wallParams.IgnoreWater = true
wallParams.RespectCanCollide = true

local function stateOf(player)
	local s = track[player]
	if not s then
		s = {graceUntil = 0, floor = 0, strikes = 0}
		track[player] = s
	end
	return s
end

-- сервер сам переносит персонажа: не считать это телепортом
function AntiCheat.grace(player, seconds)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local s = stateOf(player)
	s.graceUntil = math.max(s.graceUntil, os.clock() + (seconds or 2))
	s.movedUntil = math.max(s.movedUntil or 0, os.clock() + (seconds or 2)) -- только серверные переносы (без льготы после кресла)
	s.last = nil
	s.nc = nil
	s.dest = nil
	s.groundY, s.airT, s.highT = nil, nil, nil
end

-- серверный перенос персонажа в точку cf (трап, лестница). ref — деталь, с которой точка движется
-- (корпус идущего корабля). Пока идёт льгота, персонаж должен оставаться у точки переноса:
-- иначе любой трап — телепорт куда угодно (льгота сбрасывает последнюю честную точку).
function AntiCheat.moveTo(player, char, cf, ref)
	AntiCheat.grace(player)
	local s = stateOf(player)
	s.dest = {cf = cf, part = ref, off = ref and ref.CFrame:ToObjectSpace(cf), t = os.clock()}
	char:PivotTo(cf)
end

-- кнопка трапа/лестницы у воды (авианосец, корабли, нефтяные платформы): подъём на палубу.
-- maxDist — от площадки plat; target() → CFrame наверху и деталь, с которой он движется (или nil — нельзя);
-- canUse() — дополнительное условие (корабль цел и т.п.)
function AntiCheat.ladder(prompt, plat, maxDist, target, canUse)
	prompt.Triggered:Connect(function(player)
		if canUse and not canUse() then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or not hrp or hum.SeatPart then return end
		if (hrp.Position - plat.Position).Magnitude > maxDist then return end
		local cf, ref = target()
		if cf then AntiCheat.moveTo(player, char, cf, ref) end
	end)
end

-- игрок не дальше dist от точки pos (кресла и кнопки: ProximityPrompt читом жмут с любого расстояния)
function AntiCheat.near(player, pos, dist)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp ~= nil and (hrp.Position - pos).Magnitude <= dist
end

-- игрок у кнопки prompt (её дальность + запас на лаг и движение палубы)
function AntiCheat.atPrompt(player, prompt)
	local p = prompt.Parent
	local pos = p and (p:IsA("Attachment") and p.WorldPosition or p:IsA("BasePart") and p.Position)
	if not pos then return false end
	return AntiCheat.near(player, pos, prompt.MaxActivationDistance + 12)
end

-- идёт ли сейчас серверный перенос / возврат персонажа (резкая остановка — не падение)
function AntiCheat.inGrace(player)
	local s = track[player]
	return s ~= nil and (os.clock() < (s.movedUntil or 0) or (s.pulledAt ~= nil and os.clock() - s.pulledAt < 1))
end

-- скорость опоры под ногами (палуба, грузовик), студ/с
local function floorVelocity(char, hrp)
	rayParams.FilterDescendantsInstances = {char}
	local r = workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), rayParams)
	if r and r.Instance:IsA("BasePart") then
		return r.Instance:GetVelocityAtPosition(r.Position)
	end
	return Vector3.zero
end

local function jumpHeight(hum)
	if hum.UseJumpPower then return hum.JumpPower ^ 2 / (2 * workspace.Gravity) end
	return hum.JumpHeight
end

-- вернуть персонажа в точку cf (не кикаем: при лаге ложное срабатывание безобидно)
local function pull(player, s, char, hrp, cf, what)
	s.strikes += 1
	if s.strikes % 5 == 1 then
		warn(("[AntiCheat] %s: %s — pulled back (x%d)"):format(player.Name, what, s.strikes))
	end
	char:PivotTo(cf)
	hrp.AssemblyLinearVelocity = Vector3.zero
	s.pulledAt = os.clock()
	s.last, s.lastT = cf, os.clock()
	s.nc = cf.Position
	s.airT, s.highT = nil, nil
end

-- последняя опора с учётом её движения (палуба идущего корабля уже ушла дальше)
local function groundCF(s)
	if s.groundPart and s.groundPart.Parent and s.groundOff then return s.groundPart.CFrame * s.groundOff end
	return s.groundCF
end

-- полёт и зависание: true, если персонажа вернули.
-- Проверка редкая (раз в CHECK), а прыжки подряд (зажат прыжок) длятся примерно столько же: замер почти
-- всегда попадает на полёт. Поэтому «в воздухе» — только выше высоты прыжка над опорой под ногами:
-- обычный прыжок туда не достаёт, сколько бы раз подряд ни прыгал.
local function checkAir(player, s, now, char, hum, hrp)
	local state = hum:GetState()
	-- состояние гуманоида присылает клиент: Swimming засчитываем только у воды
	local swimming = state == Enum.HumanoidStateType.Swimming and hrp.Position.Y < WATER_TOP
	if swimming or state == Enum.HumanoidStateType.Climbing or player:GetAttribute("Parachute") ~= nil then
		s.groundY, s.groundCF, s.groundPart, s.airT, s.highT = hrp.Position.Y, hrp.CFrame, nil, nil, nil
		return false
	end
	local feet = hum.HipHeight + hrp.Size.Y / 2
	local jh = jumpHeight(hum)
	local y = hrp.Position.Y
	groundParams.FilterDescendantsInstances = {char}
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -(feet + jh + 3), 0), groundParams)
	if hit then
		-- опора в пределах прыжка: запоминаем, куда вернуть (стоя на ней)
		local stand = hit.Position.Y + feet
		s.groundY = stand
		s.groundCF = CFrame.new(hit.Position.X, stand + 0.5, hit.Position.Z) * hrp.CFrame.Rotation
		local part = hit.Instance
		if part:IsA("BasePart") and not part.Anchored then
			s.groundPart, s.groundOff = part, part.CFrame:ToObjectSpace(s.groundCF)
		else
			s.groundPart, s.groundOff = nil, nil
		end
		s.airT = nil
		-- долго выше прыжка над опорой (завис низко над землёй)
		if y - stand > jh + 1.5 then
			s.highT = s.highT or now
			if now - s.highT > HOVER_TIME then
				pull(player, s, char, hrp, groundCF(s), ("hovering %.0f studs above ground"):format(y - stand))
				return true
			end
		else
			s.highT = nil
		end
		return false
	end
	s.highT = nil
	-- опоры в пределах прыжка нет: либо падает (с обрыва, с палубы), либо летит
	if not s.groundY then
		-- старую опору забываем: иначе groundCF(s) вернёт палубу корабля, с которой сошли давно (возврат «телепортом» к ней)
		s.groundY, s.groundCF, s.groundPart, s.groundOff = y, hrp.CFrame, nil, nil
	end
	if not s.airT then s.airT, s.airY = now, y end
	if y - s.groundY > jh + RISE_EXTRA then
		pull(player, s, char, hrp, groundCF(s), ("flew %.0f studs above ground"):format(y - s.groundY))
		return true
	end
	if now - s.airT > HOVER_TIME and y > s.airY - HOVER_DROP then
		pull(player, s, char, hrp, groundCF(s), ("hovering %.1f s"):format(now - s.airT))
		return true
	end
	return false
end

-- сквозь стены неподвижной застройки (часто, своим циклом)
local function checkNoclip(player, s, now)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local seated = hum and hrp and hum.SeatPart and (hrp.Position - hum.SeatPart.Position).Magnitude <= SEAT_MAX_DIST
	if not hum or not hrp or hum.Health <= 0 or seated or player:GetAttribute("State") ~= "Deployed" or now < s.graceUntil then
		s.nc = nil
		return
	end
	local pos = hrp.Position
	local prev = s.nc
	s.nc = pos
	if not prev then return end
	local d = pos - prev
	if d.Magnitude < 0.3 then return end
	local map = workspace:FindFirstChild("Map")
	local list = {}
	for _, n in ipairs({"Teams", "Neutral"}) do
		local f = map and map:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	if #list == 0 then return end
	wallParams.FilterDescendantsInstances = list
	for _, dy in ipairs(NOCLIP_RAYS) do
		local o = Vector3.new(0, dy, 0)
		if not workspace:Raycast(prev + o, d, wallParams) then return end
	end
	pull(player, s, char, hrp, CFrame.new(prev) * hrp.CFrame.Rotation, "walked through a wall")
end

local function check(player, s, now)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 or player:GetAttribute("State") ~= "Deployed" then
		s.last = nil
		return
	end
	local seatPart = hum.SeatPart
	if seatPart and (hrp.Position - seatPart.Position).Magnitude > SEAT_MAX_DIST then
		-- «сидит», но далеко от кресла: клиент удалил сварку у себя — снимаем с кресла и возвращаем к нему
		local w = seatPart:FindFirstChild("SeatWeld")
		if w then w:Destroy() end
		hum.Sit = false
		s.dest = nil
		pull(player, s, char, hrp, seatPart.CFrame + Vector3.new(0, 4, 0), "away from the seat while seated")
		return
	end
	if seatPart then
		s.dest = nil
		-- запоминаем скорость техники: выпрыгнув, персонаж ещё летит по инерции
		local v = seatPart.AssemblyLinearVelocity
		s.seatH = Vector3.new(v.X, 0, v.Z).Magnitude
		s.seatUp = math.max(0, v.Y)
		s.seatUntil = now + SEAT_GRACE
		s.last = nil
		return
	end
	local fv = floorVelocity(char, hrp)
	s.floor = math.max(Vector3.new(fv.X, 0, fv.Z).Magnitude, s.floor * FLOOR_DECAY)
	local dest = s.dest
	if dest then
		-- после переноса трапом персонаж обязан быть у точки переноса (с учётом бега за прошедшее время)
		local cf = dest.part and dest.part.Parent and dest.part.CFrame * dest.off or dest.cf
		local allow = hum.WalkSpeed * SPEED_MARGIN * (now - dest.t) + EXTRA + DEST_SLACK
		if (hrp.Position - cf.Position).Magnitude > allow then
			s.dest = nil
			pull(player, s, char, hrp, cf, "moved away from the ladder top")
			return
		end
		if now < s.graceUntil then return end
		s.dest = nil
	end
	if now < s.graceUntil or not s.last then
		s.last, s.lastT = hrp.CFrame, now
		s.groundY, s.airT, s.highT = nil, nil, nil
		return
	end
	local afterSeat = now < (s.seatUntil or 0)
	-- полёт сразу после техники не проверяем (выпрыгнул из самолёта — падает, опоры долго нет)
	if afterSeat then
		s.groundY, s.airT, s.highT = nil, nil, nil
	elseif checkAir(player, s, now, char, hum, hrp) then
		return
	end
	local dt = math.max(now - s.lastT, CHECK)
	local d = hrp.Position - s.last.Position
	local horiz = Vector3.new(d.X, 0, d.Z).Magnitude
	local floorSpeed = afterSeat and math.max(s.floor, (s.seatH or 0) * 1.2) or s.floor
	local allowH = (hum.WalkSpeed * SPEED_MARGIN + floorSpeed) * dt + EXTRA
	local allowUp = UP_LIMIT + math.max(0, fv.Y, afterSeat and s.seatUp or 0) * dt
	if horiz > allowH or d.Y > allowUp then
		-- телепорт / спидхак: назад на последнюю честную точку
		s.strikes += 1
		if s.strikes % 5 == 1 then
			warn(("[AntiCheat] %s moved %.0f studs (allowed %.0f), up %.0f — pulled back (x%d)"):format(player.Name, horiz, allowH, d.Y, s.strikes))
		end
		char:PivotTo(s.last)
		hrp.AssemblyLinearVelocity = Vector3.zero
		s.pulledAt = os.clock()
		s.lastT = now
		s.nc, s.airT = nil, nil
		return
	end
	s.last, s.lastT = hrp.CFrame, now
end

function AntiCheat.init()
	local function watch(player)
		player.CharacterAdded:Connect(function()
			AntiCheat.grace(player, SPAWN_GRACE)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerRemoving:Connect(function(p) track[p] = nil end)

	task.spawn(function()
		while true do
			task.wait(CHECK)
			local now = os.clock()
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(check, p, stateOf(p), now)
				if not ok then warn("[AntiCheat] " .. tostring(err)) end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(NOCLIP_STEP)
			local now = os.clock()
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(checkNoclip, p, stateOf(p), now)
				if not ok then warn("[AntiCheat] " .. tostring(err)) end
			end
		end
	end)
end

return AntiCheat
