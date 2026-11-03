-- Кнопка в лобби: снять / надеть военную форму (UniformService, Remotes.Uniform). В бою скрыта.
return function(ctx)
	local UI, T = ctx.UI, ctx.UI.T
	local player = ctx.player
	local gui = UI.screen("UniformUI", 12)
	local btn = UI.button(gui, "", T.Panel2, {
		-- на телефоне внизу слева джойстик — кнопка выше, у левого края
		AnchorPoint = Vector2.new(0, 1), Position = UI.touchOnly and UDim2.new(0, 16, 0.55, 0) or UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(190, 46), TextSize = 15,
	})
	UI.scale(btn, 0.8)
	UI.stroke(btn)

	local function refresh()
		btn.Text = player:GetAttribute("UniformOff") and "WEAR UNIFORM" or "TAKE OFF UNIFORM"
	end
	local busy = false
	btn.Activated:Connect(function()
		if busy then return end
		busy = true
		local res = ctx.invoke("Uniform")
		busy = false
		UI.toast(res.msg, res.ok and "success" or "error")
	end)
	player:GetAttributeChangedSignal("UniformOff"):Connect(refresh)
	refresh()

	local api = {}
	function api.onState(state)
		btn.Visible = state == "Lobby"
	end
	return api
end
