local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local EscapeService = {}
local InventoryService
local CurrencyService
local LootService
local ProgressionService
local DataStoreManager
local escapeZone
local lobbySpawn
local mapSpawn
local deliveryInProgress = {}
local pendingChoices = {}
local carryoverRewards = {}
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

local function moveToMapSpawn(player)
	local character = player.Character
	if character and mapSpawn then
		character:PivotTo(mapSpawn.CFrame + Vector3.new(0, 3, 0))
	end
end

local function clearChoice(player)
	pendingChoices[player] = nil
	player:SetAttribute("EscapeChoicePending", false)
end

-- Single place that writes the EscapeReward HUD attribute from the real,
-- persisted PendingSaleAmount. Anything that resets round/loot state and
-- would otherwise be tempted to force EscapeReward to 0 directly should
-- call EscapeService.SyncEscapeReward(player) instead, so a real pending
-- sale is never visually erased by an unrelated reset.
local function syncEscapeRewardDisplay(player)
	if DataStoreManager and DataStoreManager.IsReady(player) then
		player:SetAttribute("EscapeReward", DataStoreManager.Get(player, "PendingSaleAmount") or 0)
	end
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
		-- reward is the entirety of GetCurrentRoundValue(player) not yet
		-- banked (see bankedValues below and the trigger handler in
		-- setupPrompt). Consume the physical CurrentRound loot backing it
		-- now, in the same synchronous step as banking the carryover, so
		-- this value can never be counted again later: GetCurrentRoundValue
		-- never includes PendingSale, so this can't touch (or multiply)
		-- loot that already escaped in an earlier trigger.
		InventoryService.ClearCurrentRound(player)
		carryoverRewards[player] = ((carryoverRewards[player] or 0) + reward) * 2
		player:SetAttribute("CarryoverReward", carryoverRewards[player])
		player:SetAttribute("EscapeStatus", string.format("Loot saved at 2x: %d %s next escape", carryoverRewards[player], rewardType))
		bankedValues[player] = 0
		moveToMapSpawn(player)
		return true
	end
	local carryover = carryoverRewards[player] or 0
	carryoverRewards[player] = 0
	bankedValues[player] = nil
	player:SetAttribute("CarryoverReward", 0)
	-- Only the Stay carryover (a pure currency bonus, never backed by a
	-- physical item) is banked into PendingSaleAmount here, exactly as
	-- before. The freshly escaped items themselves are deliberately NOT
	-- pre-credited: a normal escape leaves them physically in
	-- InventoryService (see the MarkPendingSale calls at the two call
	-- sites of finishDelivery), and their value is computed fresh from the
	-- inventory at sale time (EscapeService.SellPendingReward), so the
	-- same item can never be counted both as a physical item and as an
	-- already-banked PendingSaleAmount.
	if DataStoreManager and carryover > 0 then
		-- PendingSale is tracked as a delta-safe field in PlayerDataStore
		-- (same discipline as Money/Points), so a sale amount accumulated
		-- here is never lost to a naive cross-server snapshot overwrite,
		-- and survives a disconnect automatically because it is part of
		-- sessions[player], persisted by the existing save machinery.
		DataStoreManager.Set(player, "PendingSaleRewardType", rewardType)
		if DataStoreManager.Add(player, "PendingSaleAmount", carryover) then
			syncEscapeRewardDisplay(player)
		end
	end
	player:SetAttribute("EscapeStatus", "Robbery complete. Return to the lobby counter to sell.")
	player:SetAttribute("Escaped", true)
	if ProgressionService then
		ProgressionService.ResetSprintForPlayer(player)
	end
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

		local totalValue = InventoryService.GetCurrentRoundValue(player)
		local alreadyBanked = bankedValues[player] or 0
		local reward = math.max(0, totalValue - alreadyBanked)
		if Workspace:GetAttribute("RoundPhase") ~= "Active" then
			player:SetAttribute("EscapeStatus", "Escape is available during Active only")
			deliveryInProgress[player] = nil
			return
		end
		local carryover = carryoverRewards[player] or 0
		local totalReward = reward + carryover
		if reward > 0 then
			pendingChoices[player] = {
				Reward = reward,
				RewardType = rewardType,
			}
			player:SetAttribute("EscapeChoicePending", true)
			player:SetAttribute("EscapeStatus", "Choose: Stay for 2x loot or return to Lobby")
			deliveryInProgress[player] = nil
			return
		end
		if totalReward > 0 and not CurrencyService.CanAdd(player, rewardType, totalReward) then
			player:SetAttribute("EscapeStatus", "Currency is not ready or full")
			deliveryInProgress[player] = nil
			return
		end

		if not InventoryService.MarkPendingSale(player) then
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

function EscapeService.Start(inventoryService, currencyService, lootService, zone, lobby, progressionService, dataStoreManager)
	InventoryService = inventoryService
	CurrencyService = currencyService
	LootService = lootService
	ProgressionService = progressionService
	DataStoreManager = dataStoreManager
	escapeZone = zone
	lobbySpawn = lobby
	mapSpawn = Workspace:WaitForChild("Map"):WaitForChild("SpawnLocation")
	setupPrompt()

	Players.PlayerRemoving:Connect(function(player)
		deliveryInProgress[player] = nil
		pendingChoices[player] = nil
		carryoverRewards[player] = nil
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
			-- Reflects a PendingSale restored from persistence (across a
			-- disconnect/reconnect) in the HUD as soon as data finishes
			-- loading, since it is no longer re-created locally on join.
			player:GetAttributeChangedSignal("PersistentDataReady"):Connect(function()
				syncEscapeRewardDisplay(player)
			end),
		}
		syncEscapeRewardDisplay(player)
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
		player:SetAttribute("CarryoverReward", carryoverRewards[player] or 0)
		player:SetAttribute("InLobby", player:GetAttribute("InLobby") == true)
		player:SetAttribute("LobbyStatus", "Use the lobby counter to sell escaped loot")
	end
end

function EscapeService.Decide(player, decision)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or (decision ~= "Stay" and decision ~= "Lobby") then
		return false
	end
	local pendingChoice = pendingChoices[player]
	if not pendingChoice or player.Parent ~= Players or Workspace:GetAttribute("RoundPhase") ~= "Active" or player:GetAttribute("InLobby") or player:GetAttribute("Caught") or player:GetAttribute("Hidden") == true or not canUseZone(player, escapeZone) then
		return false
	end
	if decision == "Lobby" and not CurrencyService.CanAdd(player, pendingChoice.RewardType, pendingChoice.Reward + (carryoverRewards[player] or 0)) then
		player:SetAttribute("EscapeStatus", "Currency is not ready or full")
		return false
	end
	if decision == "Lobby" and not InventoryService.MarkPendingSale(player) then
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

-- Forfeits any Escape state that must not outlive the Active phase it was
-- created in: an unfinalized Stay bonus (carryoverRewards) and an unresolved
-- Stay/Lobby choice (pendingChoices). Called by RoundService.finishActiveRound
-- in the same synchronous step that decides TimeExpired, so no decision made
-- after this point (Results, Intermission, or a later round) can ever see a
-- leftover choice or bonus from a round that already ended. Deliberately
-- leaves PendingSaleAmount, PendingSale items, the physical inventory, and
-- Money/Points untouched - those are handled by their own systems and are not
-- part of what an unfinished Stay/Lobby decision forfeits.
function EscapeService.EndRound()
	for _, player in Players:GetPlayers() do
		clearChoice(player)
		EscapeService.ClearCarryover(player)
	end
end

function EscapeService.GetPendingSale(player)
	if not DataStoreManager then
		return 0, "Money"
	end
	local amount = DataStoreManager.Get(player, "PendingSaleAmount") or 0
	local rewardType = DataStoreManager.Get(player, "PendingSaleRewardType") or "Money"
	-- Combine the banked Stay-carryover with whatever is physically sitting
	-- in the PendingSale group right now (escaped-but-unsold items), since
	-- the latter is no longer pre-converted into PendingSaleAmount at escape
	-- time. Deliberately PendingSale only, never CurrentRound - loot still
	-- at risk this round must never be previewed as sellable.
	if InventoryService then
		amount = amount + InventoryService.GetPendingSaleValue(player)
	end
	return amount, rewardType
end

-- Public entry point for other services (RoundService, LootService, ...) to
-- refresh the EscapeReward HUD attribute instead of writing to it directly.
-- EscapeService remains the sole reader of PendingSaleAmount for display.
function EscapeService.SyncEscapeReward(player)
	syncEscapeRewardDisplay(player)
end

-- Sells the player's entire pending reward atomically: consuming
-- PendingSale and crediting Money/Points happen inside a single
-- DataStoreManager.SellPending call, so two servers can never both
-- credit the same underlying balance (see PlayerDataStore.luau).
-- Returns (success, amountSold, rewardType).
function EscapeService.SellPendingReward(player)
	if not DataStoreManager then
		return false, 0, "Money"
	end
	-- Item value is read fresh from the PendingSale group right here - the
	-- authoritative source now that escaping no longer pre-credits it into
	-- PendingSaleAmount - never CurrentRound, so at-risk loot from this
	-- round can never be sold by accident. TryLockSelling still guards
	-- against a concurrent sale attempt racing itself (see InventoryService.
	-- TryLockSelling); it's no longer what protects CurrentRound, since
	-- ClearPendingSale below can only ever touch the PendingSale group.
	local itemValue = 0
	if InventoryService then
		if not InventoryService.TryLockSelling(player) then
			return false, 0, "Money"
		end
		itemValue = InventoryService.GetPendingSaleValue(player)
	end
	local success, amount, rewardType = DataStoreManager.SellPending(player, itemValue)
	if InventoryService then
		if success and amount > 0 then
			-- Only clear PendingSale once the sale is durably confirmed AND
			-- actually credited something; a declined sale (e.g. currency
			-- cap) or a persistence failure must leave the items untouched
			-- so the player can try again. Any CurrentRound loot collected
			-- in the meantime is untouched either way - ClearPendingSale
			-- never reaches it.
			InventoryService.ClearPendingSale(player)
		else
			InventoryService.UnlockSelling(player)
		end
	end
	if success then
		syncEscapeRewardDisplay(player)
	end
	return success, amount, rewardType
end

function EscapeService.ClearCarryover(player)
	carryoverRewards[player] = nil
	player:SetAttribute("CarryoverReward", 0)
end

return EscapeService