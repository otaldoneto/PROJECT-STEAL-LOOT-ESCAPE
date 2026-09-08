--!nocheck
---@diagnostic disable: undefined-global

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Server = script.Parent
while Workspace:GetAttribute("ServicesReady") ~= true do
	task.wait()
end

local InventoryService = require(Server:WaitForChild("InventoryService"))
local LootService = require(Server:WaitForChild("LootService"))
local EscapeService = require(Server:WaitForChild("EscapeService"))
local ThreatService = require(Server:WaitForChild("ThreatService"))
local HideoutService = require(Server:WaitForChild("HideoutService"))
local ProgressionService = require(Server:WaitForChild("ProgressionService"))
local RoundService = require(Server:WaitForChild("RoundService"))

local lobbySpawn = Workspace:WaitForChild("Lobby"):WaitForChild("SpawnLocation")
local mapSpawn = Workspace:WaitForChild("Map"):WaitForChild("SpawnLocation")

local matchTime = ReplicatedStorage:FindFirstChild("MatchTime") or Instance.new("StringValue")
matchTime.Name = "MatchTime"
matchTime.Value = "Intermission: 20:00"
matchTime.Parent = ReplicatedStorage

RoundService.Start(
	InventoryService,
	LootService,
	EscapeService,
	ThreatService,
	HideoutService,
	ProgressionService,
	lobbySpawn,
	mapSpawn
)

while true do
	local seconds = Workspace:GetAttribute("RoundTimeLeft")
	local phase = Workspace:GetAttribute("RoundPhase") or "Loading"
	if typeof(seconds) == "number" then
		seconds = math.max(0, math.floor(seconds))
		matchTime.Value = string.format("%s: %02d:%02d", phase, math.floor(seconds / 60), seconds % 60)
	else
		matchTime.Value = phase
	end
	task.wait(0.2)
end