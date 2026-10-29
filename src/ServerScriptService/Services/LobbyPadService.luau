-- Плиты лобби (Map.Lobby / Map.LobbyRed → Pads; у каждой команды своё лобби).
-- Команду игрок получает автоматически (SpawnService), плиты — за неё.
--  • Deploy (зелёная, под таблицей лидеров): встал — открывается выбор, где появиться (база / авианосец).
--  • Judge (фиолетовая): встал — окно голосования за изгнание игрока (JudgeService).
--  • Drop (парашют): встал — окно покупки десанта за свою команду (не чаще PROMPT_COOLDOWN).
--  • Battleship / Carrier: так же, покупка корабля за донат (DonateShipService) — если его сейчас можно спустить.
--  • VIP (золотая, с короной): окно покупки геймпасса VIP (VipService).
-- Кто на какой плите — считает сервер по позиции (не Touched: тот не скажет, что игрок ушёл с плиты).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Services = script.Parent
local TeamService = require(Services.TeamService)
local SpawnService = require(Services.SpawnService)
local MonetizationService = require(Services.MonetizationService)
local CargoDropService = require(Services.CargoDropService)
local DonateShipService = require(Services.DonateShipService)
local DataService = require(Services.DataService)
local Notifier = require(Services.Notifier)
local VipService = require(Services.VipService)

local LobbyPadService = {}
local TICK = 0.15
local PROMPT_COOLDOWN = 4

local pads = {}     -- {part, kind}
local on = {}       -- [игрок] = плита, на которой стоит
local prompted = {} -- [игрок] = время последнего окна покупки

local function padAt(pos)
	for _, p in ipairs(pads) do
		local lp = p.part.CFrame:PointToObjectSpace(pos)
		local h = p.part.Size / 2
		if math.abs(lp.X) <= h.X and math.abs(lp.Z) <= h.Z and lp.Y >= 0 and lp.Y <= h.Y + 8 then return p end
	end
	return nil
end

local function onEnter(player, p)
	local team = TeamService.getTeamName(player)
	if not team then return end
	if p.kind == "Deploy" then
		ReplicatedStorage.Remotes.OpenSpawnMenu:FireClient(player)
		return
	elseif p.kind == "Judge" then
		ReplicatedStorage.Remotes.OpenJudge:FireClient(player)
		return
	end
	if CargoDropService.isBusy(player) then return end -- уже выбирает маршрут / летит
	local t = os.clock()
	if prompted[player] and t - prompted[player] < PROMPT_COOLDOWN then return end
	prompted[player] = t
	if not DataService.isLoaded(player) then
		Notifier.send(player, "Data is still loading…", "error")
		return
	end
	if p.kind == "VIP" then
		VipService.prompt(player)
		return
	end
	if p.kind == "Drop" then
		CargoDropService.setPendingTeam(player, team)
		MonetizationService.prompt(player, "ParachuteDrop")
		return
	end
	local why = DonateShipService.check(p.kind, team, player)
	if why then
		Notifier.send(player, why, "error")
		return
	end
	DonateShipService.prompt(player, p.kind, team)
end

local function step()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local p = hrp and player:GetAttribute("State") == "Lobby" and padAt(hrp.Position) or nil
		if on[player] ~= p then
			on[player] = p
			if p then onEnter(player, p) end
		end
	end
end

function LobbyPadService.init()
	for _, lobby in ipairs(SpawnService.lobbies()) do
		local folder = lobby:FindFirstChild("Pads")
		for _, m in ipairs(folder and folder:GetChildren() or {}) do
			local part = m:FindFirstChild("Pad")
			local kind = part and part:GetAttribute("Kind")
			if part and (kind == "Deploy" or kind == "Judge" or kind == "Drop" or kind == "VIP" or DonateShipService.Products[kind]) then
				table.insert(pads, {part = part, kind = kind})
			end
		end
	end
	if #pads == 0 then warn("[LobbyPadService] no lobby pads found") end
	Players.PlayerRemoving:Connect(function(p)
		on[p] = nil
		prompted[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			step()
		end
	end)
end

return LobbyPadService
