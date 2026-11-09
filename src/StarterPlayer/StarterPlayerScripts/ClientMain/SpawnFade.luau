-- Затемнение при появлении: новый персонаж сначала стоит на SpawnLocation, а сервер (SpawnService)
-- переносит его на точку только после подгрузки места (до ~3 сек.). Чтобы не было видно прыжка камеры
-- и как дорисовывается остров, мир закрыт чёрным, пока у персонажа нет атрибута Placed, потом плавно открывается.
-- Интерфейс (DisplayOrder выше) остаётся поверх затемнения.
--
-- Погиб далеко от базы (остров, море) — база успела выгрузиться стримингом (вдали она рисуется упрощённой
-- копией, LevelOfDetail). После возрождения тысячи её деталей догружаются ещё секунду-другую и подменяют
-- копию прямо на глазах — «мерцает вся база». Поэтому после Placed ждём, пока подгрузка вокруг утихнет.
local TweenService = game:GetService("TweenService")

local MAX_WAIT = 6 -- сек.: не держим экран тёмным дольше, даже если сервер не ответил
local SETTLE = 0.35 -- сек. после переноса: дать догрузиться ближним деталям
local QUIET = 0.4 -- сек. без новых деталей карты — подгрузка вокруг закончилась
local MAX_STREAM_WAIT = 4 -- сек. после переноса: дольше подгрузку не ждём
local BASE_LOADED = 0.85 -- доля деталей базы, после которой она считается подгруженной
local FADE_OUT = 0.5

return function(ctx)
	local UI = ctx.UI
	local player = ctx.player
	local gui = UI.screen("SpawnFade", 1)
	local cover = UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0}, gui)
	local tween

	-- когда в последний раз пришла деталь неподвижной застройки (стриминг). Техника, боты и снаряды
	-- (Planes, Vessels…) приходят и уходят постоянно — их не считаем, иначе тишины не дождаться
	local STATIC = {Teams = true, Neutral = true, Nature = true, Lobby = true, LobbyRed = true}
	local lastStream = 0
	local map = workspace:FindFirstChild("Map")
	local function watchFolder(f)
		f.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then lastStream = os.clock() end
		end)
	end
	local function watchMap(m)
		for _, f in ipairs(m:GetChildren()) do
			if STATIC[f.Name] then watchFolder(f) end
		end
		m.ChildAdded:Connect(function(f)
			if STATIC[f.Name] then watchFolder(f) end
		end)
	end
	if map then
		watchMap(map)
	else
		task.spawn(function()
			local m = workspace:WaitForChild("Map", 30)
			if m then watchMap(m) end
		end)
	end

	-- база, внутри которой появился персонаж (у модели базы есть атрибуты от сервера)
	local function baseAround(char)
		local root = char:FindFirstChild("HumanoidRootPart")
		local m = workspace:FindFirstChild("Map")
		local teams = m and m:FindFirstChild("Teams")
		if not root or not teams then return nil end
		for _, b in ipairs(teams:GetChildren()) do
			local c, r, n = b:GetAttribute("Center"), b:GetAttribute("Radius"), b:GetAttribute("PartCount")
			if typeof(c) == "Vector3" and type(r) == "number" and type(n) == "number" and n > 0 then
				local d = root.Position - c
				if Vector3.new(d.X, 0, d.Z).Magnitude <= r then return b end
			end
		end
		return nil
	end
	local function countParts(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 end
		end
		return n
	end

	local function onCharacter(char)
		if char:GetAttribute("Placed") then
			-- сервер успел поставить персонажа до того, как он пришёл на клиент: прыжка камеры не будет,
			-- но база вокруг могла ещё не подгрузиться — тогда всё равно закрываем, пока догружается
			local base = baseAround(char)
			if not base or countParts(base) >= base:GetAttribute("PartCount") * BASE_LOADED then return end
		end
		if tween then tween:Cancel() end
		cover.BackgroundTransparency = 0
		local t0 = os.clock()
		while char.Parent and player.Character == char and not char:GetAttribute("Placed") and os.clock() - t0 < MAX_WAIT do
			task.wait()
		end
		if player.Character ~= char then return end -- уже следующий персонаж: им займётся свой вызов
		task.wait(SETTLE)
		-- база вокруг ещё догружается — открываем мир, когда у клиента почти все её детали
		-- (число, центр и радиус базы публикует сервер, SpawnService), иначе — когда подгрузка утихнет
		local t1 = os.clock()
		local base = baseAround(char)
		if base then
			local need = base:GetAttribute("PartCount") * BASE_LOADED
			while player.Character == char and os.clock() - t1 < MAX_STREAM_WAIT and countParts(base) < need do
				task.wait(0.1)
			end
		end
		while player.Character == char and os.clock() - lastStream < QUIET and os.clock() - t1 < MAX_STREAM_WAIT do
			task.wait(0.05)
		end
		if player.Character ~= char then return end
		tween = TweenService:Create(cover, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
		tween:Play()
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then task.spawn(onCharacter, player.Character) end

	return {}
end
