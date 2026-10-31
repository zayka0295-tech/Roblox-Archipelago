-- Звуки на клиенте: каталог (id из официальной библиотеки Roblox) и проигрывание в точке мира.
-- id = 0 — звук ещё не выбран, вызов молча пропускается.
local SoundService = game:GetService("SoundService")

local SoundFx = {}

-- group — SoundGroup в SoundService; range — дальше не слышно; near — до этой дистанции громкость полная;
-- region — какой кусок файла играть (обрезаем длинные хвосты); len — сколько держать звук живым;
-- gap — не чаще раза в gap секунд (защита от каши при очередях)
local CATALOG = {
	-- выстрелы
	Rifle        = {id = 9118173739, -- Rifle Single Shots 1 (ProSoundEffects)
		 group = "Weapons", volume = 0.5, pitch = {0.95, 1.05}, near = 15, range = 350, region = {0, 0.7}, gap = 0.03},
	AA           = {id = 9116358625, -- Machine Gun Bursts 5 (ProSoundEffects)
		 group = "Weapons", volume = 0.55, pitch = {0.9, 1.0}, near = 25, range = 700, region = {0, 0.5}, gap = 0.04},
	PlaneGun     = {id = 9116358625, -- тот же файл, тон выше
		 group = "Weapons", volume = 0.45, pitch = {1.0, 1.1}, near = 25, range = 600, region = {0, 0.4}, gap = 0.05},
	CannonMedium = {id = 3149249837, -- ВРЕМЕННО: Cannon_Explode (Roblox), нужен настоящий выстрел орудия
		 group = "Weapons", volume = 0.8, pitch = {0.95, 1.05}, near = 40, range = 1400, len = 3},
	CannonHeavy  = {id = 3149249837, -- ВРЕМЕННО: Cannon_Explode (Roblox), тон ниже
		 group = "Weapons", volume = 1, pitch = {0.7, 0.8}, near = 60, range = 2200, len = 4.5},
	TorpedoLaunch   = {id = 0, -- не выбран
		 group = "Weapons", volume = 0.7, pitch = {0.9, 1.0}, near = 30, range = 500, len = 3},
	DepthChargeDrop = {id = 9125703162, -- Mud Puddle Splash (ProSoundEffects)
		 group = "Weapons", volume = 0.6, pitch = {0.9, 1.1}, near = 20, range = 400, len = 1.5},
	-- свист падающей авиабомбы (звучит на самой бомбе, см. ShotFx)
	BombWhistle = {id = 116150406781332, -- Falling whistle sound effect (Creator Store)
		 group = "Weapons", volume = 0.8, pitch = {0.95, 1.05}, near = 40, range = 700},
	-- попадания и взрывы
	BulletHit      = {id = 0, -- не выбран и пока не подключён
		 group = "Explosions", volume = 0.35, pitch = {0.9, 1.15}, near = 10, range = 150, len = 1, gap = 0.05},
	ExplosionSmall = {id = 3149249837, -- Cannon_Explode (Roblox), тон выше
		 group = "Explosions", volume = 0.7, pitch = {1.1, 1.25}, near = 30, range = 900, len = 5},
	ExplosionMedium= {id = 3149249837, -- Cannon_Explode (Roblox)
		 group = "Explosions", volume = 0.9, pitch = {0.95, 1.05}, near = 50, range = 1600, len = 6},
	ExplosionLarge = {id = 9114224354, -- Earthquake Explosion 1 (ProSoundEffects)
		 group = "Explosions", volume = 1, pitch = {0.75, 0.85}, near = 80, range = 2600, len = 8},
	Thunder        = {id = 9114224354, -- тот же звук ниже тоном: гром молнии, слышен только поблизости
		 group = "Explosions", volume = 0.75, pitch = {0.55, 0.65}, near = 40, range = 700, len = 9},
	Splash         = {id = 9125703162, -- Mud Puddle Splash (ProSoundEffects)
		 group = "Explosions", volume = 0.6, pitch = {0.9, 1.1}, near = 25, range = 700, len = 2},
	SplashBig      = {id = 9120585252, -- Water Splash Big (ProSoundEffects)
		 group = "Explosions", volume = 0.9, pitch = {0.8, 0.9}, near = 40, range = 1200, len = 4},
	Underwater     = {id = 9120314397, -- Underwater Explosion 1 (ProSoundEffects)
		 group = "Explosions", volume = 0.9, pitch = {0.9, 1.0}, near = 40, range = 1200, len = 6},
	TorpedoHit     = {id = 9120314649, -- Underwater Explosion 2 (ProSoundEffects)
		 group = "Explosions", volume = 1, pitch = {0.8, 0.9}, near = 60, range = 2000, len = 7},
	-- двигатели (петли, см. EngineSounds): pitch = {на месте, на полном ходу}, idle — доля громкости на месте
	EnginePlane      = {id = 9112750448, -- ВРЕМЕННО: дизель Bow Wash с высоким тоном, нужен пропеллер
		 group = "Engines", volume = 0.25, pitch = {1.6, 2.4}, idle = 0.5, near = 20, range = 450},
	EngineGunboat    = {id = 9112750448, -- Bow Wash Slow Trolling Speed 1 (ProSoundEffects)
		 group = "Engines", volume = 0.45, pitch = {0.9, 1.25}, idle = 0.35, near = 25, range = 500},
	EngineBattleship = {id = 9112812185, -- Landing Craft Interior 1 (ProSoundEffects)
		 group = "Engines", volume = 0.6, pitch = {0.7, 0.9}, idle = 0.4, near = 50, range = 700},
	EngineCarrier    = {id = 9118747824, -- Rumble Constant Roar Energy Building 1 (ProSoundEffects)
		 group = "Engines", volume = 0.7, pitch = {0.6, 0.8}, idle = 0.4, near = 80, range = 900},
	EngineSubmarine  = {id = 9112750448, -- Bow Wash (ProSoundEffects), свой тон
		 group = "Engines", volume = 0.35, pitch = {0.8, 1.0}, idle = 0.3, near = 20, range = 350},
	EngineCargo      = {id = 9112750448, -- Bow Wash (ProSoundEffects), свой тон
		 group = "Engines", volume = 0.35, pitch = {0.75, 0.95}, idle = 0.3, near = 30, range = 450},
	-- грузовой самолёт десанта: низкий гул + тихий свист турбин (турбовинтовой транспортник)
	EngineCargoPlane      = {id = 9112812233, -- Landing Craft Interior 3 (ProSoundEffects)
		 group = "Engines", volume = 0.7, pitch = {0.75, 0.85}, idle = 0.6, near = 120, range = 1300},
	EngineCargoPlaneWhine = {id = 9112839511, -- Oil Refinery Ambience 2: свист турбин (ProSoundEffects)
		 group = "Engines", volume = 0.22, pitch = {1.05, 1.2}, idle = 0.6, near = 80, range = 900},
	-- воздушная тревога на базах (см. AirRaid)
	AirRaidSiren = {id = 9113073742, -- Air Raid Siren Old Fashioned 1 (ProSoundEffects)
		group = "Ambient", volume = 1, near = 150, range = 2600},
	-- музыка (см. Music): играет «в ушах», не предзагружается
	-- ручное оружие (см. GunClient): тот же выстрел винтовки, у АК ниже и гуще, у M4 звонче
	AK47      = {id = 9118173739, group = "Weapons", volume = 0.6, pitch = {0.8, 0.88}, near = 15, range = 400, region = {0, 0.6}, gap = 0.05},
	M4A1      = {id = 9118173739, group = "Weapons", volume = 0.5, pitch = {1.02, 1.1}, near = 15, range = 380, region = {0, 0.5}, gap = 0.04},
	RPGLaunch = {uri = "rbxasset://sounds/Rocket shot.wav", -- встроенный звук Roblox
		group = "Weapons", volume = 1, pitch = {0.85, 0.95}, near = 25, range = 700, len = 2},
	Reload    = {id = 9116357621, -- Machine Gun Bolt 4 (ProSoundEffects)
		group = "Weapons", volume = 0.5, pitch = {1.1, 1.2}, len = 2.2},
	HitMarker = {uri = "rbxasset://sounds/electronicpingshort.wav", group = "UI", volume = 0.35, pitch = {1.3, 1.4}, len = 0.5, gap = 0.05},
	MusicLobby1  = {id = 9040111018, -- Large Scale Maneuvers - Remastered (APM)
		 group = "Music", volume = 0.5},
	MusicBattle1 = {id = 1847601287, -- War History (APM)
		 group = "Music", volume = 0.4},
	MusicBattle2 = {id = 1839689629, -- Famous Battle (APM)
		 group = "Music", volume = 0.4},
	MusicBattle3 = {id = 1840899338, -- The Regiment (APM)
		 group = "Music", volume = 0.4},
	MusicBattle4 = {id = 1847389104, -- Frontline C (APM)
		 group = "Music", volume = 0.4},
	MusicBattle5 = {id = 1836332538, -- Forward Advance Submix (APM)
		 group = "Music", volume = 0.4},
}
SoundFx.CATALOG = CATALOG

-- образцы: по одному загруженному Sound на id. Клон загруженного звучит сразу,
-- а новый Sound каждый раз грузится заново (0.2–0.4 с) — выстрелы бы опаздывали
-- адрес звука: id из библиотеки или встроенный файл Roblox (uri); nil — звук не выбран
local function uriOf(e)
	if e.uri then return e.uri end
	if e.id and e.id ~= 0 then return "rbxassetid://" .. e.id end
	return nil
end

local templates = {}
do
	local folder = Instance.new("Folder")
	folder.Name = "SoundFxTemplates"
	for _, e in pairs(CATALOG) do
		local uri = uriOf(e)
		if uri and e.group ~= "Music" and not templates[uri] then
			local s = Instance.new("Sound")
			s.Name = uri
			s.SoundId = uri
			s.Parent = folder
			templates[uri] = s
		end
	end
	folder.Parent = SoundService
end

local MAX_ACTIVE = 40
local active = 0
local lastPlay = {}

local function groupOf(name)
	local g = SoundService:FindFirstChild(name)
	return g and g:IsA("SoundGroup") and g or nil
end

-- pos = nil — звук «в ушах» (без 3D)
function SoundFx.play(name, pos)
	local e = CATALOG[name]
	local uri = e and uriOf(e)
	if not uri then return end
	local now = os.clock()
	if e.gap and lastPlay[name] and now - lastPlay[name] < e.gap then return end
	if active >= MAX_ACTIVE then return end
	if pos then
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - pos).Magnitude > e.range then return end
	end
	lastPlay[name] = now

	local tpl = templates[uri]
	local s = tpl and tpl:Clone() or Instance.new("Sound")
	if not tpl then s.SoundId = uri end
	s.Volume = e.volume
	s.PlaybackSpeed = e.pitch and (e.pitch[1] + math.random() * (e.pitch[2] - e.pitch[1])) or 1
	s.SoundGroup = groupOf(e.group)
	if e.region then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(e.region[1], e.region[2])
	end
	local holder = s
	if pos then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = e.near or 20
		s.RollOffMaxDistance = e.range
		holder = Instance.new("Attachment")
		holder.Name = "Sfx_" .. name
		holder.Position = pos -- Terrain стоит в начале координат
		s.Parent = holder
		holder.Parent = workspace.Terrain
	else
		s.Parent = SoundService
	end
	active += 1
	s:Play()
	local dur = e.region and (e.region[2] - e.region[1]) or e.len or 6
	task.delay(dur / s.PlaybackSpeed + 0.25, function()
		active -= 1
		holder:Destroy()
	end)
end

-- долгий звук (двигатель, музыка): создаёт Sound, но не запускает — управляет вызывающий.
-- parent = деталь — звук в 3D на ней; nil — «в ушах». Возвращает Sound и запись каталога или nil.
function SoundFx.loop(name, parent, looped)
	local e = CATALOG[name]
	local uri = e and uriOf(e)
	if not uri then return nil end
	local tpl = templates[uri]
	local s = tpl and tpl:Clone() or Instance.new("Sound")
	if not tpl then s.SoundId = uri end
	s.Name = name
	s.Looped = looped ~= false
	s.Volume = 0
	s.SoundGroup = groupOf(e.group)
	if parent then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = e.near or 20
		s.RollOffMaxDistance = e.range or 500
	end
	s.Parent = parent or SoundService
	return s, e
end

-- взрыв, созданный сервером (Instance Explosion): тип по атрибуту Sfx, иначе по размеру и высоте
function SoundFx.explosion(e)
	local pos, r = e.Position, e.BlastRadius
	local kind = e:GetAttribute("Sfx")
	if kind then
		SoundFx.play(kind, pos)
		return
	end
	if pos.Y <= 1.5 then -- снаряд упал в воду
		SoundFx.play(r >= 12 and "SplashBig" or "Splash", pos)
		return
	end
	SoundFx.play(r >= 20 and "ExplosionLarge" or r >= 10 and "ExplosionMedium" or "ExplosionSmall", pos)
end

return SoundFx
