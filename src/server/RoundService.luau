local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local RoundService = {}
local LootService
local EscapeService
local ThreatService
local InventoryService
local HideoutService
local ProgressionService
local lobbySpawn
local mapSpawn
local roundNumber = 0
local running = false
local playerConnections = {}

local INTERMISSION_DURATION = GameConfig.Round.IntermissionDuration
local ROUND_DURATION = GameConfig.Round.ActiveDuration
local RESULTS_DURATION = GameConfig.Round.ResultsDuration
local TIMER_WARNING_SECONDS = GameConfig.Round.TimerWarningSeconds

local function hasActiveParticipant()
	if Workspace:GetAttribute("RoundPhase") ~= "Active" then
		return false
	end
	for _, player in Players:GetPlayers() do
		if player.Parent == Players
			and player:GetAttribute("PersistentDataReady") == true
			and player:GetAttribute("RoundParticipation") == true
			and not player:GetAttribute("InLobby")
			and not player:GetAttribute("Caught")
			and not player:GetAttribute("Escaped") then
			return true
		end
	end
	return false
end

local function countParticipants()
	local total = 0
	for _, player in Players:GetPlayers() do
		if player.Parent == Players
			and player:GetAttribute("PersistentDataReady") == true
			and player:GetAttribute("RoundParticipation") == true
			and not player:GetAttribute("Caught")
			and not player:GetAttribute("Escaped") then
			total += 1
		end
	end
	return total
end

local function resetRoundParticipation()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("RoundParticipation", false)
	end
end

local function setPhase(phase, duration)
	Workspace:SetAttribute("RoundPhase", phase)
	Workspace:SetAttribute("RoundTimeLeft", duration)
	Workspace:SetAttribute("TimerWarning", phase == "Active" and duration <= TIMER_WARNING_SECONDS)
	Workspace:SetAttribute("RoundActive", phase == "Active")
	Workspace:SetAttribute("RoundNumber", roundNumber)
end

local function resetPlayers()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Escaped", false)
		player:SetAttribute("EscapeReward", 0)
		player:SetAttribute("Detected", false)
		player:SetAttribute("ThreatLevel", "Safe")
		player:SetAttribute("TimeExpired", false)
		player:SetAttribute("Caught", false)
		player:SetAttribute("Hidden", false)
		player:SetAttribute("Hideout", "")
		player:SetAttribute("HideoutWasSprinting", false)
		player:SetAttribute("EscapeStatus", "Collect loot and reach the escape zone")
		player:SetAttribute("EscapeChoicePending", false)
		player:SetAttribute("CaughtCount", 0)
		player:SetAttribute("ItemsLost", false)
		player:SetAttribute("CaptureStatus", "")
		player:SetAttribute("LobbyStatus", "Use the lobby counter to sell escaped loot")
	end
end

local function teleportPlayer(player, spawnPart)
	local character = player.Character
	if character and spawnPart then
		character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3, 0))
	end
end

local function teleportAll(spawnPart, inLobby)
	for _, player in Players:GetPlayers() do
		local eligible = player:GetAttribute("PersistentDataReady") == true
		if inLobby then
			teleportPlayer(player, spawnPart)
			player:SetAttribute("InLobby", true)
		elseif eligible and player:GetAttribute("RoundParticipation") == true then
			teleportPlayer(player, spawnPart)
			player:SetAttribute("InLobby", false)
		else
			teleportPlayer(player, lobbySpawn)
			player:SetAttribute("InLobby", true)
		end
	end
end

local function setupPlayer(player)
	player:SetAttribute("InLobby", true)
	local function syncPlayerParticipation()
		local ready = player:GetAttribute("PersistentDataReady") == true
		if Workspace:GetAttribute("RoundPhase") == "Active" and ready and player:GetAttribute("RoundParticipation") == true and not player:GetAttribute("Caught") then
			teleportPlayer(player, mapSpawn)
			player:SetAttribute("InLobby", false)
		else
			teleportPlayer(player, lobbySpawn)
			player:SetAttribute("InLobby", true)
		end
	end
	playerConnections[player] = {
		player:GetAttributeChangedSignal("PersistentDataReady"):Connect(syncPlayerParticipation),
		player.CharacterAdded:Connect(function()
		task.defer(function()
				syncPlayerParticipation()
		end)
		end),
	}
	syncPlayerParticipation()
end

local function countdown(duration, expectedPhase)
	for timeLeft = duration, 1, -1 do
		if Workspace:GetAttribute("RoundPhase") ~= expectedPhase then
			return false
		end
		if expectedPhase == "Active" and not hasActiveParticipant() then
			return false
		end
		Workspace:SetAttribute("RoundTimeLeft", timeLeft)
		Workspace:SetAttribute("TimerWarning", expectedPhase == "Active" and timeLeft <= TIMER_WARNING_SECONDS)
		task.wait(1)
	end
	return Workspace:GetAttribute("RoundPhase") == expectedPhase
end

local function finishActiveRound()
	if Workspace:GetAttribute("RoundPhase") ~= "Active" then
		return false
	end
	for _, player in Players:GetPlayers() do
		if not player:GetAttribute("Escaped") and not player:GetAttribute("Caught") then
			player:SetAttribute("TimeExpired", true)
		end
	end
	HideoutService.ResetRound()
	ProgressionService.ResetSprint()
	ThreatService.SetRoundActive(false)
	setPhase("Results", RESULTS_DURATION)
	return true
end

local function runRound()
	while running do
		roundNumber += 1
		setPhase("Intermission", INTERMISSION_DURATION)
		teleportAll(lobbySpawn, true)
		resetPlayers()
		resetRoundParticipation()
		InventoryService.SetRoundActive(false)
		ProgressionService.ResetSprint()
		ThreatService.SetRoundActive(false)
		countdown(INTERMISSION_DURATION, "Intermission")

		if not running then
			break
		end

		if countParticipants() < 1 then
			continue
		end

		HideoutService.ResetRound()
		teleportAll(mapSpawn, false)
		resetPlayers()
		InventoryService.SetRoundActive(true)
		LootService.ResetRound()
		EscapeService.ResetRound()
		ThreatService.ResetRound(ROUND_DURATION)
		ThreatService.SetRoundActive(true)
		setPhase("Active", ROUND_DURATION)
		countdown(ROUND_DURATION, "Active")

		if Workspace:GetAttribute("RoundPhase") == "Active" then
			finishActiveRound()
		end

		if Workspace:GetAttribute("RoundPhase") == "Results" then
			countdown(RESULTS_DURATION, "Results")
		end
	end
end

function RoundService.NotifyCapture()
	if Workspace:GetAttribute("RoundPhase") == "Active" and not hasActiveParticipant() then
		finishActiveRound()
	end
end

function RoundService.Start(inventoryService, lootService, escapeService, threatService, hideoutService, progressionService, lobbyPart, mapPart)
	assert(inventoryService and lootService and escapeService and threatService and hideoutService and progressionService and lobbyPart and mapPart, "RoundService dependencies are required")
	InventoryService = inventoryService
	LootService = lootService
	EscapeService = escapeService
	ThreatService = threatService
	HideoutService = hideoutService
	ProgressionService = progressionService
	lobbySpawn = lobbyPart
	mapSpawn = mapPart
	ThreatService.SetCaptureHandler(RoundService.NotifyCapture)
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local connections = playerConnections[player]
		if connections then
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			playerConnections[player] = nil
		end
		task.defer(function()
			if Workspace:GetAttribute("RoundPhase") == "Active" and not hasActiveParticipant() then
				finishActiveRound()
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	if running then
		return
	end
	running = true
	task.spawn(runRound)
end

return RoundService