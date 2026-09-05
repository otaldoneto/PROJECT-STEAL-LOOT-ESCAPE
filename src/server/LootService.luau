local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConfig"))

local LootService = {}
local InventoryService
local activeLoot = {}

local function canCollect(player, lootPart)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and (root.Position - lootPart.Position).Magnitude <= 14
end

local function setupLootPart(lootPart)
	if not lootPart:IsA("BasePart") or activeLoot[lootPart] then
		return
	end

	local itemId = lootPart:GetAttribute("ItemId")
	local amount = lootPart:GetAttribute("Amount")
	local item = typeof(itemId) == "string" and InventoryConfig.Items[itemId]
	if not item or typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 or amount > item.MaxStack then
		warn(string.format("Ignoring invalid loot part %s", lootPart:GetFullName()))
		return
	end

	local prompt = lootPart:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect"
	prompt.ObjectText = item.DisplayName
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = lootPart
	activeLoot[lootPart] = prompt

	prompt.Triggered:Connect(function(player)
		if not activeLoot[lootPart] or player.Parent ~= Players or not canCollect(player, lootPart) then
			return
		end

		local added = InventoryService.AddItem(player, itemId, amount)
		if added then
			activeLoot[lootPart] = nil
			prompt.Enabled = false
			lootPart.Transparency = 1
			lootPart.CanCollide = false
		end
	end)
end

function LootService.Start(inventoryService, lootFolder)
	InventoryService = inventoryService
	for _, descendant in lootFolder:GetDescendants() do
		setupLootPart(descendant)
	end
	lootFolder.DescendantAdded:Connect(setupLootPart)
end

return LootService