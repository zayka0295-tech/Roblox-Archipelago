-- Урон от падения (Config.FallDamage). Скорость персонажа сервер видит сглаженной (им управляет
-- клиент), поэтому считаем по высоте: запоминаем, с какой высоты начался быстрый спуск (быстрее
-- START_VY — по лестнице или склону так не спускаются), и при приземлении переводим высоту в скорость
-- удара. Земля, палуба — полный урон, вода — WaterMult. В кресле, в лобби и при серверных переносах
-- (AntiCheat.inGrace) не считаем; выпрыгнул из самолёта — падение считается с высоты выхода.
-- Удар после чужого попадания засчитывается стрелвшему (CombatService: lastHit в пределах KillCreditWindow).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Config.GameConfig)

local Services = script.Parent
local AntiCheat = require(Services.AntiCheatService)

local FallDamageService = {}
local F = Config.FallDamage
local G = workspace.Gravity
local START_VY = 30 -- студ/с: медленнее — ещё не падение (вершина прыжка, лестница, склон)
local fallFrom = {} -- [игрок] = высота, с которой падает (Y корня)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false

-- под ногами опора (земля, палуба, поверхность воды)?
local function groundUnder(char, hum, hrp)
	groundParams.FilterDescendantsInstances = {char}
	return workspace:Raycast(hrp.Position, Vector3.new(0, -(hum.HipHeight + hrp.Size.Y / 2 + 1.5), 0), groundParams)
end

local function impact(hum, height, water)
	local speed = math.sqrt(START_VY * START_VY + 2 * G * height)
	local dmg = (speed - F.SafeSpeed) * F.DamagePerSpeed
	if water then dmg *= F.WaterMult end
	if dmg >= 1 then hum:TakeDamage(math.floor(dmg)) end
end

function FallDamageService.init()
	RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hum or not hrp or hum.Health <= 0 or hum.SeatPart or player:GetAttribute("State") ~= "Deployed"
				or AntiCheat.inGrace(player) or player:GetAttribute("Parachute") == "open" then -- под куполом не падает
				fallFrom[player] = nil
			else
				local y = hrp.Position.Y
				local ground = groundUnder(char, hum, hrp)
				if ground then
					local from = fallFrom[player]
					fallFrom[player] = nil
					if from and from - y > 0 then impact(hum, from - y, ground.Material == Enum.Material.Water) end
				elseif hrp.AssemblyLinearVelocity.Y > -START_VY then
					fallFrom[player] = y -- ещё не падает (или вершина прыжка): счёт отсюда
				elseif not fallFrom[player] then
					fallFrom[player] = y -- сразу быстро падает (вышел из пикирующего самолёта)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p) fallFrom[p] = nil end)
end

return FallDamageService
