local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConfig"))

local InventoryService = {}
local inventories = {}
local inventoryUpdated
local snapshotTimestamps = {}
local roundActive = false

local function isPositiveInteger(value)
	return typeof(value) == "number" and value > 0 and value % 1 == 0 and value < 1000
end

local function getInventory(player)
	local inventory = inventories[player]
	if inventory then return inventory end
	inventory = { Items = {}, SlotCount = 0, Weight = 0 }
	inventories[player] = inventory
	return inventory
end

local function publish(player)
	local inventory = inventories[player]
	if not inventory then return end
	local snapshot = {}
	for itemId, amount in pairs(inventory.Items) do
		table.insert(snapshot, { ItemId = itemId, Amount = amount })
	end
	table.sort(snapshot, function(left, right) return left.ItemId < right.ItemId end)
	player:SetAttribute("InventoryWeight", inventory.Weight)
	player:SetAttribute("InventorySlots", inventory.SlotCount)
	player:SetAttribute("InventorySlotsMax", InventoryConfig.MaxSlots)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local mochila = leaderstats:FindFirstChild("Mochila")
	if not mochila then
		mochila = Instance.new("IntValue")
		mochila.Name = "Mochila"
		mochila.Parent = leaderstats
	end
	mochila.Value = inventory.SlotCount
	if inventoryUpdated then inventoryUpdated:FireClient(player, snapshot) end
end

function InventoryService.AddItem(player, itemId, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "Invalid player" end
	if typeof(itemId) ~= "string" or not isPositiveInteger(amount) then return false, "Invalid item request" end
	if not inventories[player] or not roundActive or player:GetAttribute("PersistentDataReady") ~= true then return false, "Round inventory is not ready" end
	local item = InventoryConfig.Items[itemId]
	if not item then return false, "Unknown item" end
	local inventory = getInventory(player)
	local currentAmount = inventory.Items[itemId] or 0
	if currentAmount + amount > item.MaxStack then return false, "Stack limit reached" end
	if currentAmount == 0 and inventory.SlotCount >= InventoryConfig.MaxSlots then return false, "No free inventory slot" end
	local addedWeight = item.Weight * amount
	if inventory.Weight + addedWeight > InventoryConfig.MaxWeight then return false, "Inventory is too heavy" end
	inventory.Items[itemId] = currentAmount + amount
	inventory.Weight = inventory.Weight + addedWeight
	if currentAmount == 0 then inventory.SlotCount = inventory.SlotCount + 1 end
	publish(player)
	return true
end

function InventoryService.RemoveItem(player, itemId, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(itemId) ~= "string" or not isPositiveInteger(amount) then return false, "Invalid item request" end
	if player:GetAttribute("PersistentDataReady") ~= true or not roundActive or Workspace:GetAttribute("RoundPhase") ~= "Active" then return false, "Round inventory is not editable" end
	local item = InventoryConfig.Items[itemId]
	local inventory = inventories[player]
	local currentAmount = inventory and inventory.Items[itemId]
	if not item or not inventory or not currentAmount or amount > currentAmount then return false, "Item is not in inventory" end
	local remaining = currentAmount - amount
	if remaining == 0 then
		inventory.Items[itemId] = nil
		inventory.SlotCount = inventory.SlotCount - 1
	else
		inventory.Items[itemId] = remaining
	end
	inventory.Weight = inventory.Weight - item.Weight * amount
	publish(player)
	return true
end

function InventoryService.GetSnapshot(player)
	local inventory = getInventory(player)
	local snapshot = {}
	for itemId, amount in pairs(inventory.Items) do table.insert(snapshot, { ItemId = itemId, Amount = amount }) end
	return snapshot
end

function InventoryService.GetDepositValue(player)
	local inventory = inventories[player]
	if not inventory or not roundActive then return 0 end
	local totalValue = 0
	for itemId, amount in pairs(inventory.Items) do
		local item = InventoryConfig.Items[itemId]
		if item and typeof(item.EscapeValue) == "number" then totalValue = totalValue + item.EscapeValue * amount end
	end
	return totalValue
end

function InventoryService.ClearItems(player)
	local inventory = inventories[player]
	if not inventory then return false end
	table.clear(inventory.Items)
	inventory.SlotCount = 0
	inventory.Weight = 0
	publish(player)
	return true
end

function InventoryService.ResetRound()
	for player in pairs(inventories) do InventoryService.ClearItems(player) end
end

function InventoryService.SetRoundActive(isActive)
	roundActive = isActive == true
	if roundActive then InventoryService.ResetRound() end
end

function InventoryService.Start(inventoryUpdatedRemote, snapshotRemote)
	assert(inventoryUpdatedRemote and inventoryUpdatedRemote:IsA("RemoteEvent"), "InventoryUpdated must be a RemoteEvent")
	assert(snapshotRemote and snapshotRemote:IsA("RemoteFunction"), "InventorySnapshot must be a RemoteFunction")
	inventoryUpdated = inventoryUpdatedRemote
	snapshotRemote.OnServerInvoke = function(player)
		local now = os.clock()
		local previous = snapshotTimestamps[player] or 0
		if now - previous < 0.1 then return {} end
		snapshotTimestamps[player] = now
		return InventoryService.GetSnapshot(player)
	end
	Players.PlayerAdded:Connect(function(player)
		inventories[player] = { Items = {}, SlotCount = 0, Weight = 0 }
		publish(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
		snapshotTimestamps[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		inventories[player] = { Items = {}, SlotCount = 0, Weight = 0 }
		publish(player)
	end
end

return InventoryService
