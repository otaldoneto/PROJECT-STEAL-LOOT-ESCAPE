local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InventoryService = require(script:WaitForChild("InventoryService"))
local LootService = require(script:WaitForChild("LootService"))
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

local lootFolder = Workspace:FindFirstChild("Loot") or Instance.new("Folder")
lootFolder.Name = "Loot"
lootFolder.Parent = Workspace

InventoryService.Start(inventoryUpdated, inventorySnapshot)
LootService.Start(InventoryService, lootFolder)

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
