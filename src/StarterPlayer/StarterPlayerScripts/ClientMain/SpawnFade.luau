-- Затемнение при появлении: новый персонаж сначала стоит на SpawnLocation, а сервер (SpawnService)
-- переносит его на точку только после подгрузки места (до ~3 сек.). Чтобы не было видно прыжка камеры
-- и как дорисовывается остров, мир закрыт чёрным, пока у персонажа нет атрибута Placed, потом плавно открывается.
-- Интерфейс (DisplayOrder выше) остаётся поверх затемнения.
local TweenService = game:GetService("TweenService")

local MAX_WAIT = 6 -- сек.: не держим экран тёмным дольше, даже если сервер не ответил
local SETTLE = 0.35 -- сек. после переноса: дать догрузиться ближним деталям
local FADE_OUT = 0.5

return function(ctx)
	local UI = ctx.UI
	local player = ctx.player
	local gui = UI.screen("SpawnFade", 1)
	local cover = UI.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0}, gui)
	local tween

	local function onCharacter(char)
		if char:GetAttribute("Placed") then return end
		if tween then tween:Cancel() end
		cover.BackgroundTransparency = 0
		local t0 = os.clock()
		while char.Parent and player.Character == char and not char:GetAttribute("Placed") and os.clock() - t0 < MAX_WAIT do
			task.wait()
		end
		if player.Character ~= char then return end -- уже следующий персонаж: им займётся свой вызов
		task.wait(SETTLE)
		if player.Character ~= char then return end
		tween = TweenService:Create(cover, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
		tween:Play()
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then task.spawn(onCharacter, player.Character) end

	return {}
end
