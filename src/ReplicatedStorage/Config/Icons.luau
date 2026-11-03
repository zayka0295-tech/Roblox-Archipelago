-- Иконки интерфейса (картинки из assets/icons, загружены в Roblox)
local Icons = {
	-- кнопки HUD
	Spin = "rbxassetid://131599450337815",
	Rewards = "rbxassetid://73270038420810",
	Shop = "rbxassetid://91378327169823",
	Bazaar = "rbxassetid://92156441659783",
	Quests = "rbxassetid://81849075709867",
	Career = "rbxassetid://79200926846851",
	Leaderboard = "rbxassetid://121423638015156",
	Hangar = "rbxassetid://130291090747066",
	Uniform = "rbxassetid://105901312079195",
	Islands = "rbxassetid://127697120867983",
	-- валюта
	Gold = "rbxassetid://81477845283657",
	Diamond = "rbxassetid://71026682826985",
	-- уведомления
	Kill = "rbxassetid://73992095784847",
	PlaneDown = "rbxassetid://78027639762380",
	ShipSunk = "rbxassetid://114122227586048",
	Capture = "rbxassetid://123005934159566",
	Cargo = "rbxassetid://127630366580885",
	Win = "rbxassetid://97228839887721",
	RankUp = "rbxassetid://128666851413129",
	AirRaid = "rbxassetid://74261249815902",
	Storm = "rbxassetid://113900713711409",
	Warning = "rbxassetid://127532268414727",
	-- мелкие для списков и наград
	Bag = "rbxassetid://70628658857789",
	XP = "rbxassetid://75457660079540",
	Check = "rbxassetid://96534760677044",
	Lock = "rbxassetid://88506856495968",
	Timer = "rbxassetid://83162828566285",
	Flame = "rbxassetid://108183619110701",
	Crown = "rbxassetid://93546826664671",
	Chest = "rbxassetid://84439032667036",
	Close = "rbxassetid://128571711354825",
	-- бой (assets/icons/combat)
	Crosshair = "rbxassetid://131307799202001",
	Hit = "rbxassetid://82436977040482",
	HitKill = "rbxassetid://72725232228794",
	DamageArc = "rbxassetid://84796175075926",
	Skull = "rbxassetid://101657127725475",
	Reload = "rbxassetid://90587021698909",
}

-- сенсорные кнопки на телефоне (assets/icons/touch): круг целиком, вместе с фоном
Icons.Touch = {
	Fire = "rbxassetid://108880000622404",
	Aim = "rbxassetid://73628601041918",
	Reload = "rbxassetid://70562987340197",
	Up = "rbxassetid://124690198858597",
	Down = "rbxassetid://114246921321998",
	Bomb = "rbxassetid://95694184496906",
	Sight = "rbxassetid://118531165966459",
	Torpedo = "rbxassetid://120975444380768",
	Dive = "rbxassetid://103016451303335",
	Surface = "rbxassetid://90631147629485",
	Zoom = "rbxassetid://73169588669336",
	Charge = "rbxassetid://136544473564832",
}

-- эмблемы команд (ключи Config.Teams)
Icons.Teams = {
	Blue = "rbxassetid://88268956971958",
	Red = "rbxassetid://117069525121444",
}
-- баннеры итогов раунда (assets/ui/round), картинки примерно 2:1
Icons.Round = {
	Victory = "rbxassetid://137935233763756",
	Defeat = "rbxassetid://123366070082137",
	Draw = "rbxassetid://98626501552838",
}
-- арт игры для экрана загрузки (assets/ui/keyart.jpg, 16:9)
Icons.KeyArt = "rbxassetid://71909187303311"

-- детали окон (assets/ui), растягиваются 9-slice: image, size — размер картинки, slice — SliceCenter
-- (углы и края вне его не тянутся), h — высота картинки, по которой подгоняется SliceScale
local function skin(id, w, h, l, t, r, b)
	return {image = id, size = Vector2.new(w, h), slice = Rect.new(l, t, w - r, h - b), h = h}
end
Icons.Skin = {
	Panel = skin("rbxassetid://109354171249959", 512, 512, 112, 112, 112, 112),
	Plate = skin("rbxassetid://75728053718504", 648, 128, 62, 60, 62, 60),
	Ribbon = skin("rbxassetid://117682749095849", 1024, 220, 250, 100, 250, 100),
	Track = skin("rbxassetid://132920341362037", 410, 64, 32, 30, 32, 30),
	Fill = skin("rbxassetid://81443964598831", 438, 64, 32, 30, 32, 30),
	Green = skin("rbxassetid://86366616441265", 463, 128, 64, 60, 64, 60),
	Blue = skin("rbxassetid://95206174724791", 465, 128, 64, 60, 64, 60),
	Red = skin("rbxassetid://138305558321064", 469, 128, 64, 60, 64, 60),
	Gold = skin("rbxassetid://108544421459907", 473, 128, 64, 60, 64, 60),
	Gray = skin("rbxassetid://82858821469814", 503, 128, 64, 60, 64, 60),
}

-- значки званий по порядку Config.Ranks.List (1 — Recruit … 22 — Marshal of the Archipelago)
Icons.Ranks = {
	"rbxassetid://135759181890136", -- Recruit
	"rbxassetid://108906366893335", -- Private
	"rbxassetid://84993701230300", -- Private First Class
	"rbxassetid://120730944275842", -- Lance Corporal
	"rbxassetid://129799953624391", -- Corporal
	"rbxassetid://117189920670138", -- Sergeant
	"rbxassetid://110339229623218", -- Staff Sergeant
	"rbxassetid://89947138406215", -- Sergeant First Class
	"rbxassetid://105281928035014", -- Master Sergeant
	"rbxassetid://129830264504808", -- Sergeant Major
	"rbxassetid://81625457074140", -- Warrant Officer
	"rbxassetid://111361853933564", -- Ensign
	"rbxassetid://133666006496204", -- Lieutenant
	"rbxassetid://75864759846040", -- Lieutenant Commander
	"rbxassetid://117071023695253", -- Commander
	"rbxassetid://80877620505323", -- Captain
	"rbxassetid://124747724634184", -- Commodore
	"rbxassetid://119302186988264", -- Rear Admiral
	"rbxassetid://121281624903671", -- Vice Admiral
	"rbxassetid://132385306658283", -- Admiral
	"rbxassetid://133763467895878", -- Fleet Admiral
	"rbxassetid://101604038348238", -- Marshal of the Archipelago
}

return Icons
