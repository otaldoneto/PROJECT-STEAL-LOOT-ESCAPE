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
local roundNumber = 0
local running = false

local INTERMISSION_DURATION = GameConfig.Round.IntermissionDuration
local ROUND_DURATION = GameConfig.Round.ActiveDuration
local RESULTS_DURATION = GameConfig.Round.ResultsDuration
local TIMER_WARNING_SECONDS = GameConfig.Round.TimerWarningSeconds

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
	end
end

local function countdown(duration, expectedPhase)
	for timeLeft = duration, 1, -1 do
		if Workspace:GetAttribute("RoundPhase") ~= expectedPhase then
			return false
		end
		Workspace:SetAttribute("RoundTimeLeft", timeLeft)
		Workspace:SetAttribute("TimerWarning", expectedPhase == "Active" and timeLeft <= TIMER_WARNING_SECONDS)
		task.wait(1)
	end
	return Workspace:GetAttribute("RoundPhase") == expectedPhase
end

local function runRound()
	while running do
		roundNumber += 1
		setPhase("Intermission", INTERMISSION_DURATION)
		resetPlayers()
		InventoryService.SetRoundActive(false)
		ProgressionService.ResetSprint()
		ThreatService.SetRoundActive(false)
		countdown(INTERMISSION_DURATION, "Intermission")

		if not running then
			break
		end

		HideoutService.ResetRound()
		resetPlayers()
		InventoryService.SetRoundActive(true)
		LootService.ResetRound()
		EscapeService.ResetRound()
		ThreatService.ResetRound(ROUND_DURATION)
		ThreatService.SetRoundActive(true)
		setPhase("Active", ROUND_DURATION)
		countdown(ROUND_DURATION, "Active")

		if Workspace:GetAttribute("RoundPhase") == "Active" then
			for _, player in Players:GetPlayers() do
				if not player:GetAttribute("Escaped") then
					player:SetAttribute("TimeExpired", true)
				end
			end
			HideoutService.ResetRound()
			ProgressionService.ResetSprint()
			ThreatService.SetRoundActive(false)
			setPhase("Results", RESULTS_DURATION)
			countdown(RESULTS_DURATION, "Results")
		end
	end
end

function RoundService.Start(inventoryService, lootService, escapeService, threatService, hideoutService, progressionService)
	assert(inventoryService and lootService and escapeService and threatService and hideoutService and progressionService, "RoundService dependencies are required")
	InventoryService = inventoryService
	LootService = lootService
	EscapeService = escapeService
	ThreatService = threatService
	HideoutService = hideoutService
	ProgressionService = progressionService
	if running then
		return
	end
	running = true
	task.spawn(runRound)
end

return RoundService