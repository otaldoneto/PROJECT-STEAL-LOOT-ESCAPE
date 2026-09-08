local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InventoryService = require(script:WaitForChild("InventoryService"))
local LootService = require(script:WaitForChild("LootService"))
local CurrencyService = require(script:WaitForChild("CurrencyService"))
local EscapeService = require(script:WaitForChild("EscapeService"))
local ThreatService = require(script:WaitForChild("ThreatService"))
local RoundService = require(script:WaitForChild("RoundService"))
local HideoutService = require(script:WaitForChild("HideoutService"))
local ProgressionService = require(script:WaitForChild("ProgressionService"))
local LobbyService = require(script:WaitForChild("LobbyService"))
local requestTimestamps = {}

local function isRateLimited(player)
	local now = os.clock()
	local previous = requestTimestamps[player] or 0
	if now - previous < 0.1 then
		return true
	end
	requestTimestamps[player] = now
	return false
end

local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local inventoryUpdated = remotes:FindFirstChild("InventoryUpdated") or Instance.new("RemoteEvent")
inventoryUpdated.Name = "InventoryUpdated"
inventoryUpdated.Parent = remotes

local inventoryRequest = remotes:FindFirstChild("InventoryRequest") or Instance.new("RemoteEvent")
inventoryRequest.Name = "InventoryRequest"
inventoryRequest.Parent = remotes

local inventorySnapshot = remotes:FindFirstChild("InventorySnapshot") or Instance.new("RemoteFunction")
inventorySnapshot.Name = "InventorySnapshot"
inventorySnapshot.Parent = remotes

local progressionUpdated = remotes:FindFirstChild("ProgressionUpdated") or Instance.new("RemoteEvent")
progressionUpdated.Name = "ProgressionUpdated"
progressionUpdated.Parent = remotes

local progressionRequest = remotes:FindFirstChild("ProgressionRequest") or Instance.new("RemoteEvent")
progressionRequest.Name = "ProgressionRequest"
progressionRequest.Parent = remotes

local sprintRequest = remotes:FindFirstChild("SprintRequest") or Instance.new("RemoteEvent")
sprintRequest.Name = "SprintRequest"
sprintRequest.Parent = remotes

local escapeDecisionRequest = remotes:FindFirstChild("EscapeDecisionRequest") or Instance.new("RemoteEvent")
escapeDecisionRequest.Name = "EscapeDecisionRequest"
escapeDecisionRequest.Parent = remotes

local lootFolder = Workspace:FindFirstChild("Loot") or Instance.new("Folder")
lootFolder.Name = "Loot"
lootFolder.Parent = Workspace

local escapeZone = Workspace:FindFirstChild("EscapeZone") or Instance.new("Part")
escapeZone.Name = "EscapeZone"
escapeZone.Anchored = true
escapeZone.Size = Vector3.new(10, 1, 10)
escapeZone.Position = Vector3.new(0, 0.5, -12)
escapeZone.Color = Color3.fromRGB(70, 190, 120)
escapeZone.Material = Enum.Material.Neon
escapeZone:SetAttribute("RewardType", "Money")
escapeZone.Parent = Workspace

local guards = Workspace:FindFirstChild("Guards") or Instance.new("Folder")
guards.Name = "Guards"
guards.Parent = Workspace

local guardWaypoints = Workspace:FindFirstChild("GuardWaypoints") or Instance.new("Folder")
guardWaypoints.Name = "GuardWaypoints"
guardWaypoints.Parent = Workspace

if #guardWaypoints:GetChildren() == 0 then
	for index, position in ipairs({
		Vector3.new(22, 2, 18),
		Vector3.new(38, 2, 18),
		Vector3.new(38, 2, 34),
		Vector3.new(22, 2, 34),
	}) do
		local waypoint = Instance.new("Part")
		waypoint.Name = string.format("Waypoint%02d", index)
		waypoint.Anchored = true
		waypoint.CanCollide = false
		waypoint.Transparency = 1
		waypoint.Size = Vector3.new(1, 1, 1)
		waypoint.Position = position
		waypoint.Parent = guardWaypoints
	end
end

local securityCameras = Workspace:FindFirstChild("SecurityCameras") or Instance.new("Folder")
securityCameras.Name = "SecurityCameras"
securityCameras.Parent = Workspace

local hideouts = Workspace:FindFirstChild("Hideouts") or Instance.new("Folder")
hideouts.Name = "Hideouts"
hideouts.Parent = Workspace

local lobbySpawn = Workspace:FindFirstChild("LobbySpawn") or Instance.new("Part")
lobbySpawn.Name = "LobbySpawn"
lobbySpawn.Anchored = true
lobbySpawn.CanCollide = false
lobbySpawn.Transparency = 0.5
lobbySpawn.Size = Vector3.new(8, 1, 8)
lobbySpawn.Position = Vector3.new(-20, 0.5, -12)
lobbySpawn.Color = Color3.fromRGB(80, 130, 220)
lobbySpawn.Parent = Workspace

local mapSpawn = Workspace:FindFirstChild("MapSpawn") or Instance.new("Part")
mapSpawn.Name = "MapSpawn"
mapSpawn.Anchored = true
mapSpawn.CanCollide = false
mapSpawn.Transparency = 0.5
mapSpawn.Size = Vector3.new(8, 1, 8)
mapSpawn.Position = Vector3.new(-18, 0.5, 18)
mapSpawn.Color = Color3.fromRGB(190, 70, 70)
mapSpawn.Parent = Workspace

local lootCounter = Workspace:FindFirstChild("LootCounter") or Instance.new("Part")
lootCounter.Name = "LootCounter"
lootCounter.Anchored = true
lootCounter.Size = Vector3.new(8, 3, 3)
lootCounter.Position = Vector3.new(-20, 2, -6)
lootCounter.Color = Color3.fromRGB(190, 150, 60)
lootCounter.Parent = Workspace

local leaderboardBoard = Workspace:FindFirstChild("LeaderboardBoard") or Instance.new("Part")
leaderboardBoard.Name = "LeaderboardBoard"
leaderboardBoard.Anchored = true
leaderboardBoard.Size = Vector3.new(12, 8, 1)
leaderboardBoard.Position = Vector3.new(-30, 4, -12)
leaderboardBoard.Color = Color3.fromRGB(30, 35, 50)
leaderboardBoard.Parent = Workspace

InventoryService.Start(inventoryUpdated, inventorySnapshot)
CurrencyService.Start()
ProgressionService.Start(progressionUpdated, CurrencyService)
LootService.Start(InventoryService, CurrencyService, ThreatService, lootFolder)
EscapeService.Start(InventoryService, CurrencyService, LootService, escapeZone, lobbySpawn)
ThreatService.Start(guards, securityCameras, InventoryService, lobbySpawn)
HideoutService.Start(hideouts)
LobbyService.Start(EscapeService, CurrencyService, lootCounter, leaderboardBoard)
Workspace:SetAttribute("ServicesReady", true)

escapeDecisionRequest.OnServerEvent:Connect(function(player, decision)
	if isRateLimited(player) then
		return
	end
	EscapeService.Decide(player, decision)
end)

progressionRequest.OnServerEvent:Connect(function(player, action)
	if isRateLimited(player) then
		return
	end
	if action == "BuySprint" then
		ProgressionService.BuySprint(player)
	end
end)

sprintRequest.OnServerEvent:Connect(function(player, isSprinting)
	if isRateLimited(player) then
		return
	end
	if typeof(isSprinting) == "boolean" then
		ProgressionService.SetSprinting(player, isSprinting)
	end
end)

inventoryRequest.OnServerEvent:Connect(function(player, action, itemId, amount)
	if isRateLimited(player) then
		return
	end
	if action == "Remove" then
		InventoryService.RemoveItem(player, itemId, amount)
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	requestTimestamps[player] = nil
end)
