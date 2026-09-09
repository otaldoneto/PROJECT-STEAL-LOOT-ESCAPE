local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local EscapeService = {}
local InventoryService
local CurrencyService
local LootService
local escapeZone
local lobbySpawn
local deliveryInProgress = {}
local pendingChoices = {}
local carryoverRewards = {}
local pendingSales = {}
local bankedValues = {}
local playerConnections = {}

local function canUseZone(player, zone)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local localPosition = zone.CFrame:PointToObjectSpace(root.Position)
	local horizontalPadding = 3
	return math.abs(localPosition.X) <= zone.Size.X / 2 + horizontalPadding
		and math.abs(localPosition.Z) <= zone.Size.Z / 2 + horizontalPadding
		and math.abs(localPosition.Y) <= 8
end

local function moveToLobby(player)
	local character = player.Character
	if character and lobbySpawn then
		character:PivotTo(lobbySpawn.CFrame + Vector3.new(0, 3, 0))
	end
	player:SetAttribute("InLobby", true)
end

local function clearChoice(player)
	pendingChoices[player] = nil
	player:SetAttribute("EscapeChoicePending", false)
end

local function initializePlayer(player)
	player:SetAttribute("EscapeStatus", "Collect loot and reach the escape zone")
	player:SetAttribute("EscapeChoicePending", false)
	player:SetAttribute("CarryoverReward", 0)
	player:SetAttribute("LobbyStatus", "Use the lobby counter to sell escaped loot")
end

local function finishDelivery(player, rewardType, reward, decision)
	if decision == "Stay" then
		player:SetAttribute("InLobby", false)
		player:SetAttribute("Escaped", false)
		carryoverRewards[player] = ((carryoverRewards[player] or 0) + reward) * 2
		bankedValues[player] = (bankedValues[player] or 0) + reward
		player:SetAttribute("CarryoverReward", carryoverRewards[player])
		player:SetAttribute("EscapeStatus", string.format("Loot saved at 2x: %d %s next escape", carryoverRewards[player], rewardType))
		return true
	end
	local totalReward = reward + (carryoverRewards[player] or 0)
	carryoverRewards[player] = 0
	bankedValues[player] = nil
	player:SetAttribute("CarryoverReward", 0)
	player:SetAttribute("EscapeReward", totalReward)
	pendingSales[player] = {
		Amount = totalReward,
		RewardType = rewardType,
	}
	player:SetAttribute("EscapeStatus", "Robbery complete. Return to the lobby counter to sell.")
	player:SetAttribute("Escaped", true)
	moveToLobby(player)
	return true
end

local function setupPrompt()
	assert(escapeZone and escapeZone:IsA("BasePart"), "EscapeZone must be a BasePart")

	local rewardType = escapeZone:GetAttribute("RewardType") or "Money"
	assert(rewardType == "Money" or rewardType == "Points", "EscapeZone RewardType must be Money or Points")

	local prompt = escapeZone:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Escape"
	prompt.ObjectText = "Escape Zone"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = escapeZone

	prompt.Triggered:Connect(function(player)
		if deliveryInProgress[player] or player.Parent ~= Players or player:GetAttribute("PersistentDataReady") ~= true or player:GetAttribute("InLobby") or player:GetAttribute("Caught") or player:GetAttribute("Hidden") == true or not canUseZone(player, escapeZone) then
			player:SetAttribute("EscapeStatus", "Move closer to the escape zone")
			return
		end
		deliveryInProgress[player] = true

		local totalValue = InventoryService.GetDepositValue(player)
		local alreadyBanked = bankedValues[player] or 0
		local reward = math.max(0, totalValue - alreadyBanked)
		if Workspace:GetAttribute("RoundPhase") ~= "Active" then
			player:SetAttribute("EscapeStatus", "Escape is available during Active only")
			deliveryInProgress[player] = nil
			return
		end
		local carryover = carryoverRewards[player] or 0
		if reward < 1 and carryover < 1 then
			player:SetAttribute("EscapeStatus", "Collect loot before escaping")
			deliveryInProgress[player] = nil
			return
		end
		local _, _, allLootCollected = LootService.GetRoundStatus(player)
		if allLootCollected and reward > 0 then
			pendingChoices[player] = {
				Reward = reward,
				RewardType = rewardType,
			}
			player:SetAttribute("EscapeChoicePending", true)
			player:SetAttribute("EscapeStatus", "Choose: Stay for 2x loot or return to Lobby")
			deliveryInProgress[player] = nil
			return
		end
		if not CurrencyService.CanAdd(player, rewardType, reward + carryover) then
			player:SetAttribute("EscapeStatus", "Currency is not ready or full")
			deliveryInProgress[player] = nil
			return
		end

		if not InventoryService.ClearItems(player) then
			player:SetAttribute("EscapeStatus", "Inventory is not ready")
			deliveryInProgress[player] = nil
			return
		end
		if not finishDelivery(player, rewardType, reward, "Lobby") then
			player:SetAttribute("EscapeStatus", "Could not deliver loot")
			deliveryInProgress[player] = nil
			return
		end

		deliveryInProgress[player] = nil
	end)
end

function EscapeService.Start(inventoryService, currencyService, lootService, zone, lobby)
	InventoryService = inventoryService
	CurrencyService = currencyService
	LootService = lootService
	escapeZone = zone
	lobbySpawn = lobby
	setupPrompt()

	Players.PlayerRemoving:Connect(function(player)
		deliveryInProgress[player] = nil
		pendingChoices[player] = nil
		carryoverRewards[player] = nil
		pendingSales[player] = nil
		bankedValues[player] = nil
		local connections = playerConnections[player]
		if connections then
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			playerConnections[player] = nil
		end
	end)

	local function setupPlayer(player)
		playerConnections[player] = {
			player:GetAttributeChangedSignal("Caught"):Connect(function()
				if player:GetAttribute("Caught") == true then
					EscapeService.ClearCarryover(player)
					bankedValues[player] = nil
				end
			end),
		}
	end

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
		player:SetAttribute("EscapeStatus", "Collect loot and reach the escape zone")
		player:SetAttribute("EscapeChoicePending", false)
		player:SetAttribute("CarryoverReward", 0)
		player:SetAttribute("LobbyStatus", "Use the lobby counter to sell escaped loot")
	end
end

function EscapeService.ResetRound()
	deliveryInProgress = {}
	pendingChoices = {}
	carryoverRewards = {}
	bankedValues = {}
	if escapeZone then
		local prompt = escapeZone:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = true
		end
	end
	for _, player in Players:GetPlayers() do
		player:SetAttribute("EscapeStatus", "Collect loot and reach the escape zone")
		player:SetAttribute("EscapeChoicePending", false)
		player:SetAttribute("CarryoverReward", 0)
		player:SetAttribute("InLobby", player:GetAttribute("InLobby") == true)
		player:SetAttribute("LobbyStatus", "Use the lobby counter to sell escaped loot")
	end
end

function EscapeService.Decide(player, decision)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or (decision ~= "Stay" and decision ~= "Lobby") then
		return false
	end
	local pendingChoice = pendingChoices[player]
	if not pendingChoice or player.Parent ~= Players or player:GetAttribute("InLobby") or player:GetAttribute("Caught") or player:GetAttribute("Hidden") == true or not canUseZone(player, escapeZone) then
		return false
	end
	if decision == "Lobby" and not CurrencyService.CanAdd(player, pendingChoice.RewardType, pendingChoice.Reward + (carryoverRewards[player] or 0)) then
		player:SetAttribute("EscapeStatus", "Currency is not ready or full")
		return false
	end
	if decision == "Lobby" and not InventoryService.ClearItems(player) then
		return false
	end
	clearChoice(player)
	local success, message = finishDelivery(player, pendingChoice.RewardType, pendingChoice.Reward, decision)
	if not success then
		player:SetAttribute("EscapeStatus", message)
		return false
	end
	return true
end

function EscapeService.GetPendingSale(player)
	local sale = pendingSales[player]
	if not sale then
		return 0, "Money"
	end
	return sale.Amount, sale.RewardType
end

function EscapeService.ClearPendingSale(player)
	pendingSales[player] = nil
	player:SetAttribute("EscapeReward", 0)
end

function EscapeService.ClearCarryover(player)
	carryoverRewards[player] = nil
	player:SetAttribute("CarryoverReward", 0)
end

return EscapeService