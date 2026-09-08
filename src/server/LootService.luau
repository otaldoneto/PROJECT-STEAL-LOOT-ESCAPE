local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConfig"))
local RiskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RiskConfig"))

local LootService = {}
local InventoryService
local CurrencyService
local ThreatService
local lootContainer
local activeLoot = {}
local lootStates = {}
local originalProperties = {}
local roundLoot = {}
local collecting = {}

local function canCollect(player, lootPart)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - lootPart.Position).Magnitude <= 12
end

local function getRoundLoot(player)
	local state = roundLoot[player]
	if state then return state end
	state = {
		collectedItems = {},
		totalValue = 0,
		weight = 0,
	}
	roundLoot[player] = state
	return state
end

local function setupLootPart(lootPart)
	if not lootPart:IsA("BasePart") or activeLoot[lootPart] then
		return
	end

	local itemId = lootPart:GetAttribute("ItemId")
	local amount = lootPart:GetAttribute("Amount")
	local rewardType = lootPart:GetAttribute("RewardType")
	local reward = lootPart:GetAttribute("Reward")
	local configuredRiskLevel = lootPart:GetAttribute("RiskLevel")
	local configuredRiskDuration = lootPart:GetAttribute("RiskDuration")
	local item = typeof(itemId) == "string" and InventoryConfig.Items[itemId]
	local isItemLoot = item ~= nil
	local isCurrencyLoot = rewardType == "Money" or rewardType == "Points"
	local validItemLoot = isItemLoot and typeof(amount) == "number" and amount >= 1 and amount % 1 == 0 and amount <= item.MaxStack
	local validCurrencyLoot = isCurrencyLoot and typeof(reward) == "number" and reward >= 1 and reward % 1 == 0 and reward <= 1000000000
	local riskLevel = isItemLoot and item.RiskLevel or configuredRiskLevel or 0
	local riskDuration = isItemLoot and item.RiskDuration or configuredRiskDuration or 0
	local validRisk = RiskConfig.IsValid(riskLevel, riskDuration)
	if (isItemLoot and not validItemLoot) or (not isItemLoot and not validCurrencyLoot) or (isItemLoot and isCurrencyLoot) or not validRisk then
		warn(string.format("Ignoring invalid loot part %s", lootPart:GetFullName()))
		return
	end

	local prompt = lootPart:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	originalProperties[lootPart] = originalProperties[lootPart] or {
		Transparency = lootPart.Transparency,
		CanCollide = lootPart.CanCollide,
	}
	prompt.ActionText = "Collect"
	prompt.ObjectText = isItemLoot and item.DisplayName or string.format("%s +%d", rewardType, reward)
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = lootPart
	local lootState = {
		Prompt = prompt,
		Collecting = false,
		Collected = false,
	}
	lootStates[lootPart] = lootState
	activeLoot[lootPart] = lootState

	prompt.Triggered:Connect(function(player)
		local lootState = activeLoot[lootPart]
		local playerLoot = getRoundLoot(player)
		if not lootState or playerLoot.collectedItems[lootPart] or collecting[player] or Workspace:GetAttribute("RoundPhase") ~= "Active" or player.Parent ~= Players or player:GetAttribute("InLobby") or not lootPart:IsDescendantOf(lootContainer) or not canCollect(player, lootPart) then
			return
		end
		collecting[player] = true

		local added
		if isItemLoot then
			added = InventoryService.AddItem(player, itemId, amount)
		else
			added = CurrencyService.Add(player, rewardType, reward)
		end
		if added then
			ThreatService.MarkRisk(player, riskLevel, riskDuration)
			playerLoot.collectedItems[lootPart] = true
			playerLoot.totalValue = playerLoot.totalValue + (isItemLoot and item.EscapeValue * amount or reward)
			playerLoot.weight = playerLoot.weight + (isItemLoot and item.Weight * amount or 0)
			player:SetAttribute("Escaped", false)
			player:SetAttribute("EscapeReward", 0)
			player:SetAttribute("EscapeStatus", "Loot collected. Reach the escape zone")
			collecting[player] = nil
		else
			collecting[player] = nil
		end
	end)
end

function LootService.Start(inventoryService, currencyService, threatService, lootFolder)
	InventoryService = inventoryService
	CurrencyService = currencyService
	ThreatService = threatService
	lootContainer = lootFolder
	for _, descendant in lootFolder:GetDescendants() do
		setupLootPart(descendant)
	end
	lootFolder.DescendantAdded:Connect(setupLootPart)
	Players.PlayerRemoving:Connect(function(player)
		roundLoot[player] = nil
		collecting[player] = nil
	end)
end

function LootService.ResetRound()
	roundLoot = {}
	collecting = {}
	for lootPart, state in pairs(lootStates) do
		if lootPart:IsDescendantOf(lootContainer) then
			state.Collecting = false
			activeLoot[lootPart] = state
			state.Prompt.Enabled = true
			local properties = originalProperties[lootPart]
			lootPart.Transparency = properties.Transparency
			lootPart.CanCollide = properties.CanCollide
		end
	end
end

function LootService.GetRoundStatus(player)
	local total = 0
	for lootPart in pairs(lootStates) do
		if lootPart:IsDescendantOf(lootContainer) then
			total += 1
		end
	end
	local playerLoot = getRoundLoot(player)
	local collected = 0
	for _ in pairs(playerLoot.collectedItems) do
		collected += 1
	end
	return total, collected, total > 0 and collected >= total, playerLoot
end

return LootService