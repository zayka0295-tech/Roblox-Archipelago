-- Генератор рельефа: два острова команд + нейтральные острова. Симметрия: поворот на 180° вокруг центра.
local M = {}
M.HALF_X, M.HALF_Z = 5120, 2560

local function smooth(a, b, v)
	local t = math.clamp((v - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

M.ellipses = {}
local function E(cx, cz, rx, rz)
	for _, sx in ipairs(cx == 0 and {1} or {1, -1}) do
		table.insert(M.ellipses, {x = cx * sx, z = cz, rx = rx, rz = rz, lim = (math.max(rx, rz) * 1.15) ^ 2})
	end
end
-- острова команд (E зеркалит по X, по Z список симметричен)
E(-3038, 0, 650, 500) E(-3038, 380, 380, 250) E(-3038, -380, 380, 250)
E(-2438, 0, 230, 190) E(-3488, 0, 260, 420)
-- нейтральные острова
E(0, 0, 260, 260) E(0, 1418, 200, 170) E(0, -1418, 200, 170)
E(1352, 878, 130, 110) E(1352, -878, 130, 110)

function M.landField(x, z)
	local F = -1
	for _, e in ipairs(M.ellipses) do
		local dx, dz = x - e.x, z - e.z
		if dx * dx + dz * dz < e.lim then
			local f = 1 - math.sqrt((dx / e.rx) ^ 2 + (dz / e.rz) ^ 2)
			if f > F then F = f end
		end
	end
	local ax, az = math.abs(x), math.abs(z)
	return F + 0.05 * math.noise(ax / 260, az / 260, 5) + 0.02 * math.noise(ax / 70, az / 70, 9)
end

function M.heightAt(x, z)
	local F = M.landField(x, z)
	if F <= -0.1 then return -8, F end
	if F <= 0 then return math.max(-8, 400 * F - 3), F end
	return 8 * smooth(0, 0.12, F), F
end

function M.matAt(h, F)
	if F < 0.07 then return Enum.Material.Sand end
	return Enum.Material.LeafyGrass
end

function M.landChunks(size)
	size = size or 256
	local list = {}
	local nx, nz = math.ceil(2 * M.HALF_X / size), math.ceil(2 * M.HALF_Z / size)
	for i = 0, nx - 1 do
		for k = 0, nz - 1 do
			local x0, z0 = -M.HALF_X + i * size, -M.HALF_Z + k * size
			local land = false
			for sx = 0, size, 16 do
				for sz = 0, size, 16 do
					if M.landField(x0 + sx, z0 + sz) > -0.1 then land = true break end
				end
				if land then break end
			end
			if land then table.insert(list, Vector2.new(x0, z0)) end
		end
	end
	return list
end

function M.buildChunk(x0, z0, size)
	size = size or 256
	local n = size / 4
	local H, U = table.create(n), table.create(n)
	local maxh = -8
	for i = 1, n do
		local Hi, Ui = table.create(n), table.create(n)
		for k = 1, n do
			local h, u = M.heightAt(x0 + (i - 0.5) * 4, z0 + (k - 0.5) * 4)
			Hi[k], Ui[k] = h, u
			if h > maxh then maxh = h end
		end
		H[i], U[i] = Hi, Ui
	end
	local ymin = -8
	local ymax = math.max(0, math.ceil((maxh + 4) / 4) * 4)
	local ny = (ymax - ymin) / 4
	local AIR, WATER, SAND = Enum.Material.Air, Enum.Material.Water, Enum.Material.Sand
	local mats, occs = table.create(n), table.create(n)
	for i = 1, n do
		local mi, oi = table.create(ny), table.create(ny)
		for j = 1, ny do
			mi[j] = table.create(n, AIR)
			oi[j] = table.create(n, 0)
		end
		for k = 1, n do
			local h, u = H[i][k], U[i][k]
			local land = M.matAt(h, u)
			for j = 1, ny do
				local y0 = ymin + (j - 1) * 4
				local frac = (h - y0) / 4
				if y0 < 0 then
					if frac >= 0.5 then
						mi[j][k] = (h < 0) and SAND or land
						oi[j][k] = 1
					else
						mi[j][k] = WATER
						oi[j][k] = 1
					end
				elseif frac > 0.02 then
					mi[j][k] = land
					oi[j][k] = math.min(1, frac)
				end
			end
		end
		mats[i], occs[i] = mi, oi
	end
	workspace.Terrain:WriteVoxels(Region3.new(Vector3.new(x0, ymin, z0), Vector3.new(x0 + size, ymax, z0 + size)), 4, mats, occs)
end

-- полная генерация: вода + рельеф
function M.generate()
	local terrain = workspace.Terrain
	terrain:Clear()
	local T, n = 400, 0
	for x = -M.HALF_X, M.HALF_X - 1, T do
		for z = -M.HALF_Z, M.HALF_Z - 1, T do
			terrain:FillBlock(CFrame.new(x + T / 2, -4, z + T / 2), Vector3.new(T, 8, T), Enum.Material.Water)
			n += 1
			if n % 16 == 0 then task.wait() end
		end
	end
	local list = M.landChunks()
	for idx = 1, #list do
		M.buildChunk(list[idx].X, list[idx].Y)
		task.wait()
	end
	return #list
end

return M
