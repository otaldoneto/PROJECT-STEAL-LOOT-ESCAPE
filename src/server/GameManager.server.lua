--!nocheck
---@diagnostic disable: undefined-global

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

local lobbySpawn = Workspace:WaitForChild("LobbySpawn")
local mapSpawn = Workspace:WaitForChild("MapSpawn")

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