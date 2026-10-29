-- Цифры урона: всплывают над местом попадания и тают — видно, что попал и сколько снял.
-- Только у стрелявшего; сервер (CombatService) шлёт пачкой за кадр: {позиция, урон, позиция, урон, …}.
local TweenService = game:GetService("TweenService")

local MAX = 40          -- больше одновременно не рисуем
local LIFE = 0.9
local COLOR = Color3.fromRGB(255, 225, 90)
local BIG = Color3.fromRGB(255, 120, 70) -- крупный удар (снаряд, торпеда)

return function(ctx)
	local remote = ctx.Remotes:WaitForChild("DamageNumbers")
	local playerGui = ctx.player:WaitForChild("PlayerGui")
	local active = 0

	local function pop(pos, amount)
		if active >= MAX or typeof(pos) ~= "Vector3" or type(amount) ~= "number" then return end
		active += 1
		local att = Instance.new("Attachment")
		att.Parent = workspace.Terrain
		att.WorldPosition = pos
		local cam = workspace.CurrentCamera
		local dist = cam and (cam.CFrame.Position - pos).Magnitude or 50
		local bb = Instance.new("BillboardGui")
		bb.Adornee = att
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.ResetOnSpawn = false
		bb.Size = UDim2.fromOffset(90, 28)
		-- немного вбок, чтобы цифры очереди не ложились друг на друга; подъём зависит от дальности
		local k = math.max(1, dist / 40)
		bb.StudsOffset = Vector3.new((math.random() - 0.5) * 1.2 * k, 0.6 * k, 0)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBlack
		l.TextSize = amount >= 100 and 20 or 16
		l.TextColor3 = amount >= 100 and BIG or COLOR
		l.TextStrokeTransparency = 0.25
		l.Text = tostring(amount)
		l.Parent = bb
		bb.Parent = playerGui
		TweenService:Create(bb, TweenInfo.new(LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {StudsOffset = bb.StudsOffset + Vector3.new(0, 2 * k, 0)}):Play()
		TweenService:Create(l, TweenInfo.new(LIFE * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, LIFE * 0.45), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		task.delay(LIFE, function()
			bb:Destroy()
			att:Destroy()
			active -= 1
		end)
	end

	remote.OnClientEvent:Connect(function(list)
		if type(list) ~= "table" then return end
		for i = 1, #list - 1, 2 do pop(list[i], list[i + 1]) end
	end)
	return {}
end
