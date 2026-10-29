-- Все параметры игры. Меняй значения здесь, код трогать не нужно.
local Config = {}

Config.GameName = "ISLAND WAR"

Config.Economy = {
	StartGold = 500,       -- стартовый личный баланс нового игрока
	KillReward = 40,       -- личная награда за убийство игрока
	BotKillReward = 5,     -- за убийство бота (чтобы не фармили ботов)
	CarrierPrice = 2500,   -- цена авианосца (из командной казны)
	CarrierDestroyReward = 500, -- личная награда за уничтожение вражеского авианосца
	MaxGold = 1000000000,
	-- личные награды (золото игрока)
	Rewards = {
		PlaneKill = 100,       -- сбитый вражеский самолёт
		ShipSink = {Gunboat = 80, Submarine = 80, Battleship = 300}, -- потопленный корабль
		CaptureParticipant = 50, -- каждому, кто стоял в зоне в момент захвата острова
		-- техника ботов стоит в 10 раз меньше (чтобы не фармили ботов)
		BotPlaneKill = 10,
		BotShipSink = {Gunboat = 8, Submarine = 8, Battleship = 30},
	},
}

-- Командная казна: из неё покупается командная техника (авианосец, линкоры).
-- Живёт в пределах сервера (как и захваченные острова), стартует с нуля.
Config.Treasury = {
	Start = 0,
	PassiveAmount = 15,      -- база сама пополняет казну...
	PassiveInterval = 30,    -- ...раз в N сек. (≈30 в минуту — без островов техника почти недоступна)
	BattleshipSinkBonus = 200, -- в казну за потопленный вражеский линкор
	CarrierDestroyBonus = 600, -- в казну за уничтоженный вражеский авианосец
}

Config.TeamOrder = {"Blue", "Red"}
Config.Teams = {
	Blue = {DisplayName = "Alpha", Color = Color3.fromRGB(56, 128, 255), BrickColor = BrickColor.new("Bright blue")},
	Red  = {DisplayName = "Bravo",     Color = Color3.fromRGB(235, 64, 52),  BrickColor = BrickColor.new("Bright red")},
}
-- Военная форма (UniformService): камуфляж команды (шаблоны Shirt/Pants) + шлем и нарукавники.
-- Helmet — цвет каски, полоса на ней и нарукавники — цвет команды. В лобби форму можно снять (свой скин).
Config.Uniforms = {
	Blue = {Shirt = 7416311240, Pants = 7416346617, Helmet = Color3.fromRGB(78, 92, 62)},  -- лесной цифровой
	Red  = {Shirt = 762983797,  Pants = 715550781,  Helmet = Color3.fromRGB(150, 128, 88)}, -- песочный цифровой
}

-- Суд (плита JUDGE в лобби, JudgeService): голосование за изгнание с этого сервера.
-- Нужно голосов: max(MinVotes, доля Share от остальных игроков). Голос сгорает через VoteTTL.
-- Голосовать можно проведя на сервере MinPlaySec (против твинков). Изгнанный не вернётся на этот сервер.
Config.Judge = {
	MinVotes = 3,
	Share = 0.5, -- половина тиммейтов: в команде из 8 нужно 4 голоса, а не 3
	VoteTTL = 10 * 60,
	MinPlaySec = 2 * 60,
}

Config.Balance = {
	MaxTeamDifference = 2, -- нельзя вступить в команду, если в ней уже на столько больше игроков
}

Config.Spawn = {
	ProtectionSeconds = 8,   -- ForceField после появления
	RespawnTime = 5,
	SafeZoneTag = "SafeZone",
	WalkSpeed = 32,          -- скорость ходьбы игрока (стандарт Roblox — 16)
}

Config.Carrier = {
	Name = "Carrier",
	Description = "Shared team carrier: a deck for allies to spawn on, a bridge and room for future vehicles.",
	MaxHealth = 6000,
	RebuyCooldown = 120,       -- сек. до повторной покупки после уничтожения
	TerminalMaxDistance = 45,  -- насколько близко к терминалу нужно стоять
	-- управление кораблём
	WaterlineY = 4,        -- высота корабля над морем
	MaxSpeed = 40,         -- макс. ход вперёд (студ/с)
	MaxReverseSpeed = 12,  -- макс. задний ход
	Acceleration = 6,      -- разгон/торможение (студ/с²)
	TurnRate = 7,          -- скорость поворота (°/с) на полном ходу
	MinTurnFactor = 0.35,  -- доля поворота на малом ходу
	BoundsX = 4500,        -- границы плавания
	BoundsZ = 2250,
}

Config.Combat = {
	FriendlyFire = false,
	KillCreditWindow = 10, -- сек. после последнего урона, когда убийство ещё засчитывается
	Rifle = {Damage = 25, Range = 700, Cooldown = 0.15},
	Turret = {Damage = 12, CarrierDamageMultiplier = 1, Range = 1200, Cooldown = 0.09, TurnSpeed = 140, MinPitch = -10, MaxPitch = 75},
	-- Классы целей: Infantry — люди и боты; Plane — самолёты; Light — катер, подлодка, грузовое судно;
	-- Heavy — линкор; Carrier — авианосец. Винтовка почти не берёт корабли, главный калибр — для кораблей.
	DamageMatrix = {
		Rifle    = {Infantry = 1,   Plane = 0.4, Light = 0.06, Heavy = 0.02, Carrier = 0.01},
		AA       = {Infantry = 0.7, Plane = 1,   Light = 0.35, Heavy = 0.08, Carrier = 0.06},
		PlaneGun = {Infantry = 1,   Plane = 1,   Light = 0.6,  Heavy = 0.25, Carrier = 0.2},
		Medium   = {Infantry = 1,   Plane = 0.8, Light = 1,    Heavy = 0.5,  Carrier = 0.4},
		Heavy    = {Infantry = 1,   Plane = 1,   Light = 1,    Heavy = 1,    Carrier = 0.9},
		Torpedo  = {Infantry = 0,   Plane = 0,   Light = 1,    Heavy = 1.72, Carrier = 2},
		RPG      = {Infantry = 1,   Plane = 0.8, Light = 1,    Heavy = 0.5,  Carrier = 0.2},
		Bomb     = {Infantry = 1,   Plane = 0.3, Light = 1,    Heavy = 1,    Carrier = 0.8},
	},
}

Config.Data = {
	PlayerStore = "PlayerData_v1",
	LeaderboardStore = "KillsLeaderboard_v1",
	AutosaveSeconds = 60,
	LeaderboardRefreshSeconds = 60,
	LeaderboardBroadcastSeconds = 5,
	LeaderboardSize = 20,
	LobbyBoardRows = 10,
}

-- минимальный интервал между вызовами Remote одним игроком (сек.)
Config.RateLimits = {
	SelectTeam = 0.6,
	SelectSpawn = 0.4,
	Deploy = 1.5,
	BuyCarrier = 1.0,
	GetLeaderboard = 2,
	Fire = 0.05,
	ReturnToLobby = 2,
	Quests = 0.3,
	QuestsGet = 1,
	BuyPlane = 1,
}


-- Корабли (кроме авианосца). Team = true — один на команду (как авианосец), false — личный.
Config.Ships = {
	Battleship = {
		DisplayName = "Battleship", Price = 1200, Team = true, TeamLimit = 3,
		Description = "Two triple-gun main battery turrets. A captain on the bridge and a gunner in each turret.",
		MaxHealth = 4000, MaxSpeed = 30, MaxReverseSpeed = 10, Acceleration = 5, TurnRate = 9, MinTurnFactor = 0.35,
		Length = 200, Beam = 34, Draft = 9,
	},
	Gunboat = {
		DisplayName = "Gunboat", Price = 200, Team = false,
		Description = "Fast single-seat gunboat. The driver aims the bow gun with the mouse.",
		MaxHealth = 600, MaxSpeed = 55, MaxReverseSpeed = 15, Acceleration = 14, TurnRate = 45, MinTurnFactor = 0.4,
		Length = 50, Beam = 14, Draft = 3,
	},
	Submarine = {
		DisplayName = "Submarine", Price = 350, Team = false,
		Description = "Ship hunter: 2 torpedoes (periscope depth only). About 90 s of air underwater.",
		MaxHealth = 800, MaxSpeed = 26, MaxReverseSpeed = 8, Acceleration = 6, TurnRate = 18, MinTurnFactor = 0.4,
		Length = 80, Beam = 10, Draft = 9, CanDive = true, DiveDepth = 50, DiveRate = 5, -- море до −88: на глубине лодка проходит под кораблями
		SubmergedSpeed = 16,  -- под водой медленнее
		PeriscopeDepth = 8,   -- мельче — можно стрелять (и по лодке можно попасть)
		Air = 90,             -- сек. под водой (глубже перископной)
		AirRefillRate = 3,    -- на поверхности воздух восполняется в 3 раза быстрее
	},
}
-- Диаманты — премиальная валюта (позже — за донат и на эксклюзивы). Пока начисляются за победу в раунде.
Config.Diamonds = {
	Max = 1000000000,
}

-- Раунды: идут строго по времени (досрочной победы нет — чтобы не фармили диаманты).
-- Очки: каждые ScoreTick сек. команда получает PointsPerIsland за каждый свой остров.
-- Ничья по очкам — решают убийства за раунд; и тут ничья — никто не получает диаманты.
Config.Round = {
	Duration = 30 * 60,   -- сек.
	Intermission = 15,    -- сек. между раундами (баннер победителя)
	ScoreTick = 5,
	PointsPerIsland = 1,
	WinDiamonds = 10,     -- каждому игроку победившей команды
	MinPlaySec = 5 * 60,  -- столько надо отыграть за победившую команду в этом раунде (не зайти в конце)
}

-- Обучение у Капитана (стоит у доски заданий): полёт → море → передача должности.
-- Шаги (DataService.Tutorial): 0 — не говорил, 1 — задание «полёт», 2 — «море», 3 — пройдено.
-- 1 км = 1000 студов (как на метках карты).
Config.Tutorial = {
	FlyDistance = 1000,
	SailDistance = 1000,
	FlyReward = 600,
	SailReward = 600,
}

-- Покупки за робуксы: ID Developer Product из Creator Dashboard (Monetization → Developer Products).
-- 0 — ещё не создан: в Studio плита запускает покупку бесплатно (тест), в игре пишет «скоро».
Config.Products = {
	ParachuteDrop = 3723087774, -- «Parachute», 10 R$
	DonateBattleship = 3723380172, -- «Battleship», 100 R$
	DonateCarrier = 3723380249,    -- «Aircraft Carrier», 200 R$
}

-- VIP (геймпасс, покупается один раз навсегда): ×2 опыт и ×2 золото за бой (убийства, техника, захваты,
-- грузы), корона и золотое имя над головой, тег [VIP] в чате и в таблице лидеров, объявление при входе.
-- GamepassId — из Creator Dashboard (Monetization → Passes); 0 — ещё не создан: в Studio плита выдаёт VIP бесплатно на сессию (тест),
-- в игре пишет «скоро». Price — только для подписи на плите (цену самого пасса ставят в Dashboard).
Config.Vip = {
	GamepassId = 2060483251, -- «VIP», 299 R$
	Price = 299,
	XPMult = 2,
	GoldMult = 2,
}

-- Техника за донат (плиты лобби Battleship / Carrier): покупатель сразу вступает в команду плиты
-- и садится за штурвал. Линкор — сверх обычного TeamLimit, но не больше ExtraPerTeam донатных на команду
-- и одного на игрока. Авианосец в игре один на команду — донат лишь заменяет казну, когда его нет.
Config.DonateShips = {
	Battleship = {ExtraPerTeam = 2, PerPlayer = 1},
}

-- Десант на парашюте (донат): грузовой самолёт летит от своей базы (StartX для синих,
-- у красных зеркально) через точку, выбранную на мини-карте. Парашют раскрывается сам на OpenHeight
-- над землёй/водой — команду даёт клиент падающего (он знает свою высоту точно, сервер видит
-- его с задержкой на сеть); если команда не пришла — сервер раскрывает сам на ServerOpenHeight.
Config.ParachuteDrop = {
	Altitude = 650,
	Speed = 90,
	FallSpeed = 170,        -- предельная скорость свободного падения (сопротивление воздуха), студ/с
	StartX = -3300,
	OpenHeight = 180,       -- клиент просит раскрыть (на деле купол тормозит на пинг ниже)
	ServerOpenHeight = 90,  -- запасной вариант, если клиент не прислал
	DescentSpeed = 16,
}

-- Урон от падения: по скорости удара (студ/с, гравитация 196.2). До SafeSpeed — без урона (падение ~14 студов),
-- дальше DamagePerSpeed за каждую единицу: 40 студов ≈ −55 HP, 70 и выше — смерть. В воду — WaterMult от этого.
Config.FallDamage = {
	SafeSpeed = 75,
	DamagePerSpeed = 1.1,
	WaterMult = 0.6,
}

-- Ежедневная рулетка: один бесплатный спин раз в Cooldown сек. Weight — шанс в % (сумма 100).
-- Порядок = порядок секторов на колесе (по часовой). В среднем ~555 золота и ~2 💎 в день.
Config.DailySpin = {
	Cooldown = 24 * 3600,
	Prizes = {
		{Kind = "Gold", Amount = 10, Weight = 30},
		{Kind = "Diamonds", Amount = 10, Weight = 12},
		{Kind = "Gold", Amount = 100, Weight = 32},
		{Kind = "Gold", Amount = 10000, Weight = 3},
		{Kind = "Gold", Amount = 1000, Weight = 22},
		{Kind = "Diamonds", Amount = 100, Weight = 1},
	},
}

Config.ShipOrder = {"Carrier", "Battleship", "Gunboat", "Submarine"}
Config.ShipAbandonDespawn = 60 -- корабль (личный или линкор), в котором никого нет, самоуничтожается через N сек. (авианосец — нет)

-- Морские орудия (снаряды летят по баллистике и взрываются)
Config.Weapons = {
	Heavy = {Class = "Heavy", Damage = 180, SplashRadius = 28, ShellSpeed = 700, Gravity = 25, Cooldown = 3.5, TurnSpeed = 50, MinPitch = -5, MaxPitch = 65, CarrierDamageMultiplier = 3, Spread = 0.8, AimTolerance = 3},
	Medium = {Class = "Medium", Damage = 70, SplashRadius = 14, ShellSpeed = 800, Gravity = 25, Cooldown = 1.0, TurnSpeed = 90, MinPitch = -8, MaxPitch = 70, CarrierDamageMultiplier = 2, Spread = 0.4, AimTolerance = 4},
}

-- Самолёты (скорость в студах/с; на приборах ×4 = км/ч).
-- Model — шаблон в ServerStorage.Vehicles; Bombs — сколько бомб на борту (см. Config.Bombs);
-- CamDistance — камера пилота за самолётом; SpawnBox / CrashBox — габариты для проверки ВПП и удара.
Config.Planes = {
	Fighter = {
		DisplayName = "Hawk fighter",
		Description = "Fast and agile. Four wing machine guns and one bomb under the fuselage.",
		Model = "Fighter",
		Bombs = 1,               -- одна бомба под фюзеляжем
		CamDistance = 34,
		SpawnBox = Vector3.new(36, 14, 34),
		CrashBox = Vector3.new(34, 3, 26),
		Price = 300,
		SpawnCooldown = 8,       -- сек. между вызовами самолёта одним игроком
		MaxHealth = 300,
		MaxSpeed = 150,
		StallSpeed = 45,         -- ниже — сваливание
		TakeoffSpeed = 62,       -- скорость отрыва
		Acceleration = 16,
		GroundBrake = 25,
		TurnRate = 120,          -- °/с (манёвренность)
		RollRate = 260,          -- °/с
		ReverseSpeed = 10,       -- задний ход на земле (S при нулевом газе)
		MaxBank = 75,
		GunDamage = 9,
		GunCooldown = 0.07,
		GunRange = 900,
		CrashSpeed = 30,         -- удар быстрее этого = крушение
		AbandonDespawn = 60,     -- брошенный самолёт исчезает через N сек.
		MaxAltitude = 900,       -- потолок (лобби выше)
		BoundsX = 4200,          -- у границы карты самолёт сам разворачивается
		BoundsZ = 2150,
	},
	-- бомбардировщик: крупнее, медленнее и неповоротливее истребителя, 10 бомб, сзади — место стрелка с турелью
	Bomber = {
		DisplayName = "Albatross bomber",
		Description = "Heavy and sturdy: 10 bombs and a seat for a tail gunner. Slow — bring an escort.",
		Model = "Bomber",
		Price = 900,
		SpawnCooldown = 20,
		Bombs = 10,
		MaxHealth = 900,
		MaxSpeed = 115,
		StallSpeed = 40,
		TakeoffSpeed = 56,
		Acceleration = 11,
		GroundBrake = 20,
		TurnRate = 60,
		RollRate = 120,
		ReverseSpeed = 8,
		MaxBank = 50,
		GunDamage = 6,           -- курсовой пулемёт пилота слабее, чем у истребителя
		GunCooldown = 0.1,
		GunRange = 800,
		CrashSpeed = 30,
		AbandonDespawn = 60,
		MaxAltitude = 900,
		BoundsX = 4200,
		BoundsZ = 2150,
		CamDistance = 52,
		SpawnBox = Vector3.new(56, 20, 44),
		CrashBox = Vector3.new(50, 4, 38),
	},
}
Config.PlaneOrder = {"Fighter", "Bomber"}

-- Авиабомбы (истребитель — 1, бомбардировщик — 10): сброс на E / кнопка BOMB, падают по баллистике
-- со скоростью самолёта. Урон по площади (таблица Combat.DamageMatrix.Bomb): полный залп бомбардировщика
-- при точном попадании — ~65% линкора или ~35% авианосца. Перезарядка — только на земле / палубе:
-- самолёт стоит (скорость < RearmMaxSpeed) — по бомбе раз в RearmTime сек.
Config.Bombs = {
	Damage = 260,
	SplashRadius = 22,
	Gravity = 50,          -- студ/с² (с 300 м падает ~3,5 с)
	DropInterval = 0.35,   -- сек. между бомбами в серии
	MinHeight = 20,        -- ниже (над землёй/водой) сброс нельзя
	RearmTime = 4,
	RearmMaxSpeed = 8,
}

-- Боты: заполняют пустой сервер, каждый игрок в команде занимает место одного бота
Config.Bots = {
	Enabled = true,
	StudioOnly = false,    -- true — боты только в Studio
	PerTeam = 16,          -- ботов + игроков в команде (игроков больше — ботов нет)
	Health = 100,
	WalkSpeed = 14,
	Damage = 8,
	FireInterval = 0.5,    -- сек. между выстрелами
	Spread = 3,            -- разброс по людям, °
	PlaneSpread = 6,       -- разброс по самолётам, °
	DetectRange = 320,     -- видят пехоту
	PlaneRange = 300,      -- стреляют по самолётам ближе этого
	EngageRange = 140,     -- дальше — подходят, ближе — маневрируют и стреляют
	RespawnTime = 6,
	ArenaRadius = 200,     -- центральный остров
	-- роли в каждой команде (остальные — пехота на центральном острове)
	-- боты летают только на истребителях, ходят только на катерах и сидят в зенитках своей базы (BotService пропускает любые другие роли)
	Roles = {BaseGunners = 2, Pilots = 7, Gunboats = 7},
	BuyBattleship = false, -- бот-командир спускает на воду линкор, если его нет
	BuyCarrier = false,    -- бот-командир покупает авианосец, если его нет
	CarrierBuyDelay = 15,  -- сек. после старта
	CruiseSpeed = 22,      -- ход авианосца под ботом
	GunnerRange = 900,     -- турели ботов: дальность по самолётам
	GunnerPlaneSpread = 4, -- разброс турелей ботов по самолётам, °
	PilotRange = 1800,     -- пилоты ищут вражеские самолёты
}

-- Только для тестов в Studio (в опубликованной игре не действует)
Config.Dev = {
	StudioGold = 1000000,
	StudioTreasury = 1000000, -- только в Studio: казна каждой команды на старте -- золото при каждом запуске Play в Studio; 0 = выключить
	StudioWalkSpeed = 0, -- скорость бега в Studio; 0 = обычная
}

-- Захват островов
Config.Capture = {
	Time = 15,              -- сек.: захват нейтрального острова (от вражеского — сначала нейтрализация, ещё столько же)
	DecayTime = 30,         -- сек.: если в зоне никого — прогресс плавно возвращается к владельцу
	Radius = 45,            -- радиус зоны захвата (у центрального форта свой)
	CenterRadius = 70,
	ExtraPlayerBonus = 0.25, -- каждый следующий игрок в зоне ускоряет захват на 25%
	MaxSpeedMultiplier = 2,
	BotsCount = false,      -- острова захватывают только игроки
	MaxHeightAboveGround = 25, -- самолёты над зоной не захватывают
}

-- Острова: Id, модель аванпоста, название, сторона причала (направление от центра острова)
Config.Islands = {
	{Id = "Center", Outpost = "Outpost_Center", Name = "Central Fort", IsCenter = true, DockDir = Vector3.new(0, 0, -1)},
	{Id = "North", Outpost = "Outpost_North", Name = "North Island", DockDir = Vector3.new(0, 0, 1)},
	{Id = "South", Outpost = "Outpost_South", Name = "South Island", DockDir = Vector3.new(0, 0, -1)},
	{Id = "NW", Outpost = "Outpost_NW", Name = "Northwest Isle", DockDir = Vector3.new(0, 0, 1)},
	{Id = "SW", Outpost = "Outpost_SW", Name = "Southwest Isle", DockDir = Vector3.new(0, 0, -1)},
	{Id = "NE", Outpost = "Outpost_NE", Name = "Northeast Isle", DockDir = Vector3.new(0, 0, 1)},
	{Id = "SE", Outpost = "Outpost_SE", Name = "Southeast Isle", DockDir = Vector3.new(0, 0, -1)},
}

-- Морская логистика: острова команды отправляют грузовые суда на её базу
Config.Logistics = {
	Interval = 60,          -- сек.: стоянка у острова между рейсами
	ShipSpeed = 30,         -- скорость грузового судна
	TurnRate = 30,          -- °/с
	UnloadTime = 12,
	LoadTime = 12,          -- сек.: погрузка краном острова двух контейнеров        -- сек.: разгрузка краном двух контейнеров (кран сам подстраивает скорость)
	Reward = 150,           -- золота В КАЗНУ команды за доставку
	PersonalShare = 25,     -- плюс каждому игроку команды лично
	CenterBonusMultiplier = 2, -- рейсы с центрального форта приносят в 2 раза больше
	LostIslandRule = "Cancel", -- остров потерян в пути: "Cancel" — судно возвращается без выплаты; "Complete" — груз довозится
	ShipHealth = 700,
	RespawnDelay = 30,      -- сек.: новое судно у острова после потопления
	SinkReward = 60,        -- золота тому, кто потопил вражеское грузовое судно
	-- грузовик: кран ставит на него контейнеры, выплата — только когда он доедет до ангара
	TruckHealth = 350,
	TruckSpeed = 26,        -- студов/с
	TruckKillReward = 50,   -- золота тому, кто уничтожил вражеский грузовик
	YardSlots = 6,          -- мест на складе контейнеров у крана
}

-- Метки техники над головой: союзники видны всегда, противник — только вблизи
Config.Markers = {
	EnemyRevealDistance = 300, -- ближе — над противником появляется красная метка
	HideCloserThan = 70,       -- совсем рядом метка не нужна
	MaxDistance = 12000,
}

-- Торпеды подлодки и глубинные бомбы катера
Config.SubWeapons = {
	Torpedo = {
		Damage = 350,        -- база; по таблице урона: катер/подлодка/грузовое 350, линкор ~600, авианосец 700
		Speed = 60, Range = 900, RunDepth = 4, HitRadius = 8,
		Tubes = 2, Reload = 15, -- 2 торпеды, затем перезарядка обоих аппаратов
		RevealTime = 6,      -- после пуска лодку видит противник
	},
	DepthCharge = {
		Count = 3, Reload = 12, -- 3 бомбы, по одной восполняется раз в 12 с
		SinkTime = 6, SinkSpeed = 7, Radius = 30, Damage = 350, -- взрыв на глубине ~42, урон по подлодкам
	},
	SonarRadius = 250,       -- катер, линкор и авианосец видят подлодку на глубине в этом радиусе
}

-- Лимиты техники (защита от спама; боты их тоже соблюдают)
Config.Limits = {
	PlanesPerTeam = 12,          -- у каждого игрока при этом не больше 1 своего самолёта
	BombersPerTeam = 3,          -- из них бомбардировщиков
	GunboatsPerTeam = 8,
	SubmarinesPerTeam = 6,
	PersonalShipsPerPlayer = 2,  -- катера + подлодки одного игрока одновременно
}

-- Ручное оружие пехоты (инструменты в ServerStorage.Weapons, атрибут Gun = ключ тут).
-- Class — строка DamageMatrix; RPM — выстрелов в минуту; Hip/Aim — разброс в градусах без прицела и в прицеле;
-- Bloom — рост разброса за выстрел; Recoil — подброс ствола (градусы) и боковой увод; AimFOV — поле зрения в прицеле.
Config.Guns = {
	AK47 = {DisplayName = "AK-47", Class = "Rifle", Damage = 34, RPM = 600, Range = 800, Mag = 30, Reload = 2.5,
		Hip = 2.2, Aim = 0.3, Bloom = 0.22, Recoil = 0.55, RecoilYaw = 0.22, RecoilDrift = 1.3, Shake = 0.6, AimFOV = 52, Sound = "AK47"},
	M4A1 = {DisplayName = "M4A1", Class = "Rifle", Damage = 28, RPM = 750, Range = 800, Mag = 30, Reload = 2.1,
		Hip = 1.8, Aim = 0.22, Bloom = 0.15, Recoil = 0.38, RecoilYaw = 0.15, RecoilDrift = 0.6, Shake = 0.4, AimFOV = 48, Sound = "M4A1"},
	RPG7 = {DisplayName = "RPG-7", Class = "RPG", Rocket = true, Damage = 250, SplashRadius = 14, RPM = 30, Range = 1000,
		Mag = 1, Reserve = 4, Reload = 3, ShellSpeed = 280, Gravity = 8, Hip = 1.5, Aim = 0.3, Bloom = 0, Recoil = 3, RecoilYaw = 0.5, Shake = 2.5,
		AimFOV = 45, Price = 400, Sound = "RPGLaunch"},
	-- старая винтовка (теперь только у ботов)
	Rifle = {DisplayName = "Rifle", Class = "Rifle", Damage = 25, RPM = 400, Range = 700, Mag = 30, Reload = 2,
		Hip = 2.5, Aim = 0.6, Bloom = 0.3, Recoil = 1, RecoilYaw = 0.4, AimFOV = 55, Sound = "Rifle"},
}
-- стартовое оружие команд
Config.TeamGun = {Blue = "M4A1", Red = "AK47"}

-- Задания на доске объявлений (у оружейного стенда базы). Каждое — один раз на игрока.
-- Bit — флаг выполнения в сохранении (QuestDone), не менять у существующих заданий.
Config.Quests = {
	GroupId = 610058879,      -- ID группы Roblox для задания «вступи в группу» (0 — задание выключено)
	GroupName = "DartSols | Island War", -- как группа называется в тексте задания
	List = {
		{Id = "group", Bit = 1, Reward = 500},
		{Id = "play", Bit = 2, Reward = 200, Goal = 20 * 60}, -- секунд в игре (суммарно, можно за несколько заходов)
		{Id = "kills", Bit = 4, Reward = 1000, Goal = 10},  -- убийств с момента появления задания
	},
}

-- Воздушная тревога на базах: сирена воет, пока живой вражеский самолёт над островом базы
Config.AirRaid = {
	Margin = 250,     -- насколько дальше габаритов базы считается «рядом с островом», студы
	Interval = 0.5,   -- как часто проверять, с
}

-- Ранги (только косметика: значок над головой и в меню). Опыт (XP) копится сам,
-- повышение игрок подтверждает кнопкой ранга (RankService, RankUI). Insignia — что рисовать на значке
-- (Shared.RankBadge): dot / chevron ×n (+bars — полоски под ними) / bar ×n / diamond ×n / star ×n / marshal.
-- Tier — цвет и «богатство» значка: чем выше, тем красивее.
Config.Ranks = {
	List = {
		{Name = "Recruit",                    XP = 0,      Tier = 1, Insignia = {"dot"}},
		{Name = "Private",                    XP = 500,    Tier = 1, Insignia = {"chevron", 1}},
		{Name = "Private First Class",        XP = 1500,   Tier = 1, Insignia = {"chevron", 2}},
		{Name = "Lance Corporal",             XP = 3000,   Tier = 1, Insignia = {"chevron", 3}},
		{Name = "Corporal",                   XP = 5000,   Tier = 2, Insignia = {"chevron", 2, bars = 1}},
		{Name = "Sergeant",                   XP = 8000,   Tier = 2, Insignia = {"chevron", 3, bars = 1}},
		{Name = "Staff Sergeant",             XP = 12000,  Tier = 2, Insignia = {"chevron", 3, bars = 2}},
		{Name = "Sergeant First Class",       XP = 17000,  Tier = 3, Insignia = {"chevron", 3, bars = 3}},
		{Name = "Master Sergeant",            XP = 23000,  Tier = 3, Insignia = {"chevron", 3, bars = 3, star = true}},
		{Name = "Sergeant Major",             XP = 30000,  Tier = 3, Insignia = {"chevron", 3, bars = 3, star = true, wreath = true}},
		{Name = "Warrant Officer",            XP = 40000,  Tier = 4, Insignia = {"bar", 1}},
		{Name = "Ensign",                     XP = 52000,  Tier = 4, Insignia = {"bar", 2}},
		{Name = "Lieutenant",                 XP = 66000,  Tier = 4, Insignia = {"bar", 3}},
		{Name = "Lieutenant Commander",       XP = 82000,  Tier = 5, Insignia = {"diamond", 1}},
		{Name = "Commander",                  XP = 100000, Tier = 5, Insignia = {"diamond", 2}},
		{Name = "Captain",                    XP = 125000, Tier = 5, Insignia = {"diamond", 3}},
		{Name = "Commodore",                  XP = 155000, Tier = 6, Insignia = {"star", 1}},
		{Name = "Rear Admiral",               XP = 190000, Tier = 6, Insignia = {"star", 2}},
		{Name = "Vice Admiral",               XP = 230000, Tier = 6, Insignia = {"star", 3}},
		{Name = "Admiral",                    XP = 280000, Tier = 7, Insignia = {"star", 4}},
		{Name = "Fleet Admiral",              XP = 340000, Tier = 7, Insignia = {"star", 5}},
		{Name = "Marshal of the Archipelago", XP = 420000, Tier = 8, Insignia = {"marshal"}},
	},
	-- за что даём опыт (ключи — RankService.award)
	XP = {
		Kill = 100,            -- вражеский игрок
		BotKill = 25,          -- бот (не больше BotKillCap за раунд)
		PlaneKill = 50,        -- сбитый самолёт (бомбардировщик ×1,5; самолёт бота — вдвое меньше)
		Sink = {Gunboat = 100, Submarine = 150, Battleship = 400}, -- корабль бота — вдвое меньше
		CarrierKill = 800,
		Capture = 200,         -- каждому в зоне захвата
		Neutralize = 100,
		Delivery = 75,         -- груз доставлен (всем в бою в команде)
		CargoKill = 150,       -- потоплено вражеское грузовое судно
		TruckKill = 75,
		Quest = 150,
		Tutorial = 100,        -- шаг обучения у Капитана
		RoundWin = 500,        -- если в бою за команду не меньше Round.MinPlaySec
		RoundLoss = 150,
		PlayMinute = 5,        -- каждая минута в бою (не в лобби)
	},
	BotKillCap = 50,           -- ботов с опытом за раунд
	RepeatKillWindow = 300,    -- сек.: третье и дальше убийство одного и того же игрока за это время…
	RepeatKillMult = 0.25,     -- …даёт столько опыта
}

return Config
