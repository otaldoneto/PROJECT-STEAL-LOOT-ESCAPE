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

local securityCameras = Workspace:FindFirstChild("SecurityCameras") or Instance.new("Folder")
securityCameras.Name = "SecurityCameras"
securityCameras.Parent = Workspace

local hideouts = Workspace:FindFirstChild("Hideouts") or Instance.new("Folder")
hideouts.Name = "Hideouts"
hideouts.Parent = Workspace

InventoryService.Start(inventoryUpdated, inventorySnapshot)
CurrencyService.Start()
ProgressionService.Start(progressionUpdated, CurrencyService)
LootService.Start(InventoryService, CurrencyService, ThreatService, lootFolder)
EscapeService.Start(InventoryService, CurrencyService, escapeZone)
ThreatService.Start(guards, securityCameras)
HideoutService.Start(hideouts)
RoundService.Start(InventoryService, LootService, EscapeService, ThreatService, HideoutService, ProgressionService)

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
