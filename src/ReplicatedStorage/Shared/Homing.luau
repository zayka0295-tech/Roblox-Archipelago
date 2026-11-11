-- Самонаведение ракет военного базара: Javelin (Homing = "Naval") — по кораблям, грузовым судам и авианосцам,
-- Игла (Homing = "Air") — по самолётам и вертолётам. Кого захватывает прицел — одно правило для клиента
-- (рамка захвата в GunClient) и сервера (цель ракеты в GunService), чтобы оба выбирали одну и ту же цель:
-- ближайшая к линии прицела вражеская техника в конусе coneDeg и дальше 8 студов. Подлодка на глубине не захватывается.
local Homing = {}

-- папка в workspace.Map, атрибут «живая техника», деталь, на которую идёт ракета
local KINDS = {
	Air = {{"Planes", "IsPlane", "Root"}},
	Naval = {{"Vessels", "IsVessel", "Hull"}, {"Carriers", "IsCarrier", "Hull"}, {"Cargo", "IsCargo", "Hull"}},
}

function Homing.find(kind, origin, dir, team, range, coneDeg)
	local map = workspace:FindFirstChild("Map")
	local list = KINDS[kind]
	if not map or not list or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then return nil end
	dir = dir.Unit
	local cosC = math.cos(math.rad(coneDeg or 12))
	local best, bestPart, bestC
	for _, f in ipairs(list) do
		local folder = map:FindFirstChild(f[1])
		for _, m in ipairs(folder and folder:GetChildren() or {}) do
			local part = m:FindFirstChild(f[3])
			local t = m:GetAttribute("Team")
			if part and part:IsA("BasePart") and m:GetAttribute(f[2]) and t ~= nil and t ~= team and (m:GetAttribute("Depth") or 0) <= 6 then
				local to = part.Position - origin
				local d = to.Magnitude
				if d > 8 and d <= (range or 1500) then
					local c = dir:Dot(to / d)
					if c >= cosC and (not bestC or c > bestC) then best, bestPart, bestC = m, part, c end
				end
			end
		end
	end
	return best, bestPart
end

-- цель model всё ещё годится для захвата из origin по направлению dir: деталь наведения или nil
function Homing.check(model, kind, origin, dir, team, range, coneDeg)
	if typeof(model) ~= "Instance" or not model.Parent or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then return nil end
	for _, f in ipairs(KINDS[kind] or {}) do
		local part = model:GetAttribute(f[2]) and model.Parent.Name == f[1] and model:FindFirstChild(f[3])
		local t = model:GetAttribute("Team")
		if part and part:IsA("BasePart") and t ~= nil and t ~= team and (model:GetAttribute("Depth") or 0) <= 6 then
			local to = part.Position - origin
			local d = to.Magnitude
			if d > 8 and d <= (range or 1500) and dir.Unit:Dot(to / d) >= math.cos(math.rad(coneDeg or 12)) then return part end
		end
	end
	return nil
end

-- цель ещё жива (не сбита, не утонула)
function Homing.alive(model, kind)
	if not model or not model.Parent then return false end
	for _, f in ipairs(KINDS[kind] or {}) do
		if model:GetAttribute(f[2]) then return true end
	end
	return false
end

return Homing
