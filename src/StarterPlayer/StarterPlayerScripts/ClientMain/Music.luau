-- Фоновая музыка: свой плейлист в лобби и в бою, треки вперемешку, при смене — плавный переход.
-- Громкость всей музыки — SoundService.Music.Volume.
local TweenService = game:GetService("TweenService")
local SoundFx = require(script.Parent:WaitForChild("SoundFx"))

local PLAYLISTS = {
	Lobby = {"MusicLobby1"},
	Battle = {"MusicBattle1", "MusicBattle2", "MusicBattle3", "MusicBattle4", "MusicBattle5"},
}
local FADE = 2.5
local GAP = 4 -- тишина между треками, с

return function(ctx)
	local current -- {sound, list}
	local want -- "Lobby" | "Battle"
	local token = 0

	local function fadeOut(s)
		if not s then return end
		local tw = TweenService:Create(s, TweenInfo.new(FADE), {Volume = 0})
		tw.Completed:Once(function() s:Destroy() end)
		tw:Play()
	end

	local function shuffled(list)
		local t = table.clone(list)
		for i = #t, 2, -1 do
			local j = math.random(i)
			t[i], t[j] = t[j], t[i]
		end
		return t
	end

	-- играет плейлист по кругу, пока не сменится token
	local function run(name, my)
		while my == token do
			local played = false
			for _, track in ipairs(shuffled(PLAYLISTS[name])) do
				if my ~= token then return end
				local s, e = SoundFx.loop(track, nil, false)
				if s then
					played = true
					current = s
					s:Play()
					TweenService:Create(s, TweenInfo.new(FADE), {Volume = e.volume}):Play()
					-- ждём конца трека или смены режима (тогда трек гасит fadeOut)
					local ended = false
					local conn = s.Ended:Once(function() ended = true end)
					repeat task.wait(0.5) until ended or my ~= token or not s.Parent
					conn:Disconnect()
					if my ~= token then return end
					if current == s then current = nil end
					s:Destroy()
					task.wait(GAP)
				end
			end
			if not played then return end -- в плейлисте нет ни одного трека с id
		end
	end

	local api = {}
	function api.onState(state)
		local name = state == "Lobby" and "Lobby" or "Battle"
		if name == want then return end
		want = name
		token += 1
		local old = current
		current = nil
		fadeOut(old)
		task.spawn(run, name, token)
	end
	return api
end
