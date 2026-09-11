local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConfig"))

local InventoryService = {}
local inventories = {}
local inventoryUpdated
local snapshotTimestamps = {}
local roundActive = false
local DataStoreManager
local playerConnections = {}

local function isPositiveInteger(value)
	return typeof(value) == "number" and value > 0 and value % 1 == 0 and value < 1000
end

-- One of the two physical groups a player's backpack is split into:
-- CurrentRound (at-risk loot from this round, lost on capture, wiped every
-- ResetRound) and PendingSale (already escaped via the Lobby, survives
-- capture/round transitions/disconnects, only cleared by a successful sale).
-- Both groups share the same shape so AddItem/GetSnapshot/value math can
-- treat either one identically; only which group a mutation targets differs.
local function newGroup()
	return { Items = {}, PendingValue = 0, Weight = 0, SlotCount = 0 }
end

local function getInventory(player)
	local inventory = inventories[player]
	if inventory then return inventory end
	inventory = { CurrentRound = newGroup(), PendingSale = newGroup(), Selling = false }
	inventories[player] = inventory
	return inventory
end

local function groupValue(group)
	local totalValue = group.PendingValue or 0
	for itemId, amount in pairs(group.Items) do
		local item = InventoryConfig.Items[itemId]
		if item and typeof(item.EscapeValue) == "number" then totalValue = totalValue + item.EscapeValue * amount end
	end
	return totalValue
end

function InventoryService.GetMaxWeight(player)
	local level = 0
	if DataStoreManager then
		level = DataStoreManager.Get(player, "BackpackLevel") or 0
	end
	local capacities = InventoryConfig.BackpackCapacities
	if level < 1 then
		return capacities[1]
	end
	if level > #capacities then
		-- Above the highest configured tier (BackpackLevel can be set up to
		-- PlayerDataStore.MAX_BACKPACK_LEVEL=100, well past the 5 tiers
		-- defined today): use the highest known capacity rather than
		-- silently falling back to the lowest one.
		return capacities[#capacities]
	end
	return capacities[level]
end

function InventoryService.GetCurrentWeight(player)
	local inventory = inventories[player]
	if not inventory then return 0 end
	return inventory.CurrentRound.Weight + inventory.PendingSale.Weight
end

-- Distinct item types across BOTH groups combined, deduplicated by itemId.
-- A group's own SlotCount only counts types within that one group, so
-- naively adding CurrentRound.SlotCount + PendingSale.SlotCount overcounts
-- an itemId held in both at once - this is what InventorySlots and the
-- slot-capacity gate actually need: the same merged line GetSnapshot/
-- publish already show for that itemId must only count once.
local function combinedSlotCount(inventory)
	local seen = {}
	for itemId in pairs(inventory.CurrentRound.Items) do
		seen[itemId] = true
	end
	for itemId in pairs(inventory.PendingSale.Items) do
		seen[itemId] = true
	end
	local count = 0
	for _ in pairs(seen) do
		count += 1
	end
	return count
end

local function publish(player)
	local inventory = inventories[player]
	if not inventory then return end
	-- CurrentRound and PendingSale are merged into one flat list here so the
	-- client's existing snapshot rendering needs no changes: PendingSale
	-- items stay visible in the backpack exactly like before, just no longer
	-- erased by capture/round transitions. Server-side, the two groups stay
	-- fully separate (InventoryService.GetSnapshot below does the same merge
	-- for the same reason).
	local merged = {}
	for itemId, amount in pairs(inventory.CurrentRound.Items) do
		merged[itemId] = (merged[itemId] or 0) + amount
	end
	for itemId, amount in pairs(inventory.PendingSale.Items) do
		merged[itemId] = (merged[itemId] or 0) + amount
	end
	local snapshot = {}
	local slotCount = 0
	for itemId, amount in pairs(merged) do
		table.insert(snapshot, { ItemId = itemId, Amount = amount })
		slotCount += 1
	end
	table.sort(snapshot, function(left, right) return left.ItemId < right.ItemId end)
	player:SetAttribute("InventoryWeight", InventoryService.GetCurrentWeight(player))
	-- slotCount here is merged's key count - distinct itemIds across both
	-- groups, deduplicated - the same thing combinedSlotCount computes, just
	-- reusing the merge already built above instead of a second pass.
	player:SetAttribute("InventorySlots", slotCount)
	player:SetAttribute("InventorySlotsMax", InventoryConfig.MaxSlots)
	player:SetAttribute("InventoryWeightMax", InventoryService.GetMaxWeight(player))
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
	mochila.Value = slotCount
	if inventoryUpdated then inventoryUpdated:FireClient(player, snapshot) end
end

-- Loot picked up during Active always lands in CurrentRound - it never
-- becomes PendingSale automatically; only MarkPendingSale (called from
-- EscapeService when the player actually escapes via the Lobby) transfers
-- it. Weight is validated against the combined CurrentRound+PendingSale
-- total: PendingSale items are still physically carried and still occupy
-- capacity, they just aren't at risk of being lost to a capture anymore.
function InventoryService.AddItem(player, itemId, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "Invalid player" end
	if typeof(itemId) ~= "string" or not isPositiveInteger(amount) then return false, "Invalid item request" end
	if not inventories[player] or not roundActive or inventories[player].Selling or player:GetAttribute("PersistentDataReady") ~= true then return false, "Round inventory is not ready" end
	local item = InventoryConfig.Items[itemId]
	if not item then return false, "Unknown item" end
	local inventory = getInventory(player)
	local currentRound = inventory.CurrentRound
	local currentAmount = currentRound.Items[itemId] or 0
	if currentAmount + amount > item.MaxStack then return false, "Stack limit reached" end
	-- A new slot is only actually consumed if itemId doesn't already exist
	-- anywhere in the combined inventory: if it's already held in
	-- PendingSale (even though CurrentRound doesn't have it yet), it's
	-- still the same merged line the player already sees, not a new one.
	local existsElsewhere = currentAmount > 0 or inventory.PendingSale.Items[itemId] ~= nil
	if not existsElsewhere and combinedSlotCount(inventory) >= InventoryConfig.MaxSlots then
		return false, "No free inventory slot"
	end
	local addedWeight = item.Weight * amount
	if InventoryService.GetCurrentWeight(player) + addedWeight > InventoryService.GetMaxWeight(player) then return false, "Inventory is too heavy" end
	currentRound.Items[itemId] = currentAmount + amount
	currentRound.Weight = currentRound.Weight + addedWeight
	if currentAmount == 0 then currentRound.SlotCount = currentRound.SlotCount + 1 end
	publish(player)
	return true
end

-- Loose currency-type loot (e.g. a Money/Points pickup, not a stackable
-- item) has never occupied Weight/SlotCount in this project - it stays
-- weightless here too, consistent with AddItem's own weight accounting.
function InventoryService.AddValue(player, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false, "Invalid player" end
	if typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 or amount > 1000000000 then return false, "Invalid value request" end
	if not inventories[player] or not roundActive or inventories[player].Selling or player:GetAttribute("PersistentDataReady") ~= true then return false, "Round inventory is not ready" end
	local inventory = getInventory(player)
	inventory.CurrentRound.PendingValue = inventory.CurrentRound.PendingValue + amount
	publish(player)
	return true
end

-- Scoped to CurrentRound only: this is reachable exclusively while
-- RoundPhase=="Active" and the player is not InLobby (see the gate below),
-- which structurally never overlaps with PendingSale being relevant, so
-- there is no case where a player should be able to voluntarily discard
-- already-escaped loot through this path.
function InventoryService.RemoveItem(player, itemId, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(itemId) ~= "string" or not isPositiveInteger(amount) then return false, "Invalid item request" end
	if player:GetAttribute("PersistentDataReady") ~= true or not roundActive or Workspace:GetAttribute("RoundPhase") ~= "Active" or player:GetAttribute("InLobby") or player:GetAttribute("Caught") then return false, "Round inventory is not editable" end
	local item = InventoryConfig.Items[itemId]
	local inventory = inventories[player]
	local currentRound = inventory and inventory.CurrentRound
	local currentAmount = currentRound and currentRound.Items[itemId]
	if not item or not currentRound or not currentAmount or amount > currentAmount then return false, "Item is not in inventory" end
	local remaining = currentAmount - amount
	if remaining == 0 then
		currentRound.Items[itemId] = nil
		currentRound.SlotCount = currentRound.SlotCount - 1
	else
		currentRound.Items[itemId] = remaining
	end
	currentRound.Weight = currentRound.Weight - item.Weight * amount
	publish(player)
	return true
end

-- Same merged shape as publish() above, for the InventorySnapshot
-- RemoteFunction (the client's initial load) - CurrentRound and PendingSale
-- items appear together, matching what the live-updated snapshot already
-- shows during play.
function InventoryService.GetSnapshot(player)
	local inventory = getInventory(player)
	local merged = {}
	for itemId, amount in pairs(inventory.CurrentRound.Items) do
		merged[itemId] = (merged[itemId] or 0) + amount
	end
	for itemId, amount in pairs(inventory.PendingSale.Items) do
		merged[itemId] = (merged[itemId] or 0) + amount
	end
	local snapshot = {}
	for itemId, amount in pairs(merged) do table.insert(snapshot, { ItemId = itemId, Amount = amount }) end
	return snapshot
end

-- Value of loot still at risk this round - what EscapeService's trigger
-- computes a fresh Stay/Lobby reward from. Deliberately excludes
-- PendingSale, so an already-escaped item can never be re-offered as a new
-- reward or multiplied again by Stay.
function InventoryService.GetCurrentRoundValue(player)
	local inventory = inventories[player]
	if not inventory then return 0 end
	return groupValue(inventory.CurrentRound)
end

-- Value of loot already escaped and awaiting sale - what
-- EscapeService.SellPendingReward/GetPendingSale read. Deliberately
-- excludes CurrentRound, so at-risk loot from this round can never be sold
-- (or previewed as sellable) before it has actually escaped.
function InventoryService.GetPendingSaleValue(player)
	local inventory = inventories[player]
	if not inventory then return 0 end
	return groupValue(inventory.PendingSale)
end

-- Returns a copy (never the live table) of the PendingSale group: the
-- Items/PendingValue that back an escaped-but-unsold Lobby delivery. Empty
-- when the player has nothing pending - callers don't need to special-case
-- that, an empty snapshot is a valid, persistable state.
function InventoryService.GetPendingSaleSnapshot(player)
	local inventory = inventories[player]
	if not inventory then
		return { Items = {}, PendingValue = 0 }
	end
	local group = inventory.PendingSale
	local items = {}
	for itemId, amount in pairs(group.Items) do
		items[itemId] = amount
	end
	return { Items = items, PendingValue = group.PendingValue }
end

-- Clears only the at-risk loot of the current round. Used by capture
-- (ThreatService) and by every new round's reset (InventoryService.
-- ResetRound) - PendingSale is a physically separate table and is never
-- touched here, so neither caller can destroy already-escaped loot, without
-- either of them needing to know PendingSale exists.
function InventoryService.ClearCurrentRound(player)
	local inventory = inventories[player]
	if not inventory then return false end
	local group = inventory.CurrentRound
	table.clear(group.Items)
	group.SlotCount = 0
	group.Weight = 0
	group.PendingValue = 0
	publish(player)
	return true
end

-- Clears only PendingSale, and only after a confirmed, paid sale
-- (EscapeService.SellPendingReward calls this after DataStoreManager.
-- SellPending already durably credited the currency). Also clears the
-- persisted snapshot in the same step, for the same reason ClearCurrentRound
-- never touches PendingSale: a value this function didn't just get called
-- for must never disappear, and a value it did get called for must never
-- come back from a stale save.
function InventoryService.ClearPendingSale(player)
	local inventory = inventories[player]
	if not inventory then return false end
	local group = inventory.PendingSale
	local hadContent = next(group.Items) ~= nil or group.PendingValue > 0
	table.clear(group.Items)
	group.SlotCount = 0
	group.Weight = 0
	group.PendingValue = 0
	if hadContent and DataStoreManager and DataStoreManager.IsReady(player) then
		DataStoreManager.Set(player, "Inventory", { Items = {}, PendingValue = 0 })
	end
	publish(player)
	return true
end

-- Called when a player actually escapes via the Lobby: transfers whatever
-- is currently in CurrentRound into PendingSale (merging with anything
-- already pending from an earlier, unsold escape) and persists the result.
-- The combined weight is unchanged by this move (items aren't gained or
-- lost, only reclassified), so no weight re-validation is needed here.
-- Stacks can end up above a single item's MaxStack once merged across
-- multiple escapes - that's fine, MaxStack only limits how much can be
-- picked up at once during an active round (see AddItem), it isn't a cap on
-- already-secured, no-longer-at-risk value.
function InventoryService.MarkPendingSale(player)
	local inventory = inventories[player]
	if not inventory then return false end
	local currentRound = inventory.CurrentRound
	local pendingSale = inventory.PendingSale
	for itemId, amount in pairs(currentRound.Items) do
		pendingSale.Items[itemId] = (pendingSale.Items[itemId] or 0) + amount
	end
	pendingSale.PendingValue = pendingSale.PendingValue + currentRound.PendingValue
	pendingSale.Weight = pendingSale.Weight + currentRound.Weight
	pendingSale.SlotCount = 0
	for _ in pairs(pendingSale.Items) do
		pendingSale.SlotCount += 1
	end
	table.clear(currentRound.Items)
	currentRound.Weight = 0
	currentRound.SlotCount = 0
	currentRound.PendingValue = 0
	if DataStoreManager and DataStoreManager.IsReady(player) then
		DataStoreManager.Set(player, "Inventory", InventoryService.GetPendingSaleSnapshot(player))
	end
	-- Combined weight/value/snapshot content are unchanged by this move
	-- (see comment above), but the *distinct-type* slot count can change
	-- when the merge deduplicates an itemId that existed in both groups -
	-- publish so InventorySlots/InventoryUpdated never lag behind a real
	-- escape until some unrelated later mutation happens to republish them.
	publish(player)
	return true
end

-- Restores a PendingSale snapshot loaded from persistence (PlayerData.
-- Inventory - which only ever represents PendingSale; CurrentRound is never
-- persisted) into this session's PendingSale group. Called once, right
-- after PersistentDataReady turns true - before the player can act - so
-- this always overwrites a freshly-created, still-empty group; the explicit
-- table.clear beforehand also makes a second call idempotent rather than
-- additive, so it can never duplicate items. Never touches CurrentRound, so
-- it can't clobber anything this session has already collected.
-- Amounts are only sanity-bounded (not clamped to a single item's
-- MaxStack), matching MarkPendingSale's own merge rule above.
function InventoryService.RestorePendingSale(player, data)
	if typeof(data) ~= "table" then
		return false
	end
	local inventory = getInventory(player)
	local group = inventory.PendingSale
	table.clear(group.Items)
	local weight = 0
	local slotCount = 0
	local items = typeof(data.Items) == "table" and data.Items or {}
	for itemId, amount in pairs(items) do
		local item = InventoryConfig.Items[itemId]
		if item and isPositiveInteger(amount) then
			group.Items[itemId] = amount
			weight += item.Weight * amount
			slotCount += 1
		end
	end
	local pendingValue = data.PendingValue
	group.PendingValue = (typeof(pendingValue) == "number" and pendingValue >= 0) and pendingValue or 0
	group.Weight = weight
	group.SlotCount = slotCount
	publish(player)
	return slotCount > 0 or group.PendingValue > 0
end

-- Locks a player's inventory against new CurrentRound pickups (AddItem/
-- AddValue) for the duration of a sale attempt. With PendingSale physically
-- separate from CurrentRound, a sale can no longer discard CurrentRound
-- loot the way the original single-inventory design could - this lock is
-- kept as defense-in-depth against a concurrent sale attempt racing itself,
-- not because it's still the only thing protecting CurrentRound.
function InventoryService.TryLockSelling(player)
	local inventory = inventories[player]
	if not inventory or inventory.Selling then return false end
	inventory.Selling = true
	return true
end

function InventoryService.UnlockSelling(player)
	local inventory = inventories[player]
	if inventory then inventory.Selling = false end
end

-- Every new round wipes CurrentRound for everyone, unconditionally -
-- PendingSale is a separate table this function never touches, so it no
-- longer needs (or has) a per-player condition to decide who gets to keep
-- their loot.
function InventoryService.ResetRound()
	for player in pairs(inventories) do
		InventoryService.ClearCurrentRound(player)
	end
end

function InventoryService.SetRoundActive(isActive)
	roundActive = isActive == true
	if roundActive then InventoryService.ResetRound() end
end

function InventoryService.Start(inventoryUpdatedRemote, snapshotRemote, dataStoreManager)
	assert(inventoryUpdatedRemote and inventoryUpdatedRemote:IsA("RemoteEvent"), "InventoryUpdated must be a RemoteEvent")
	assert(snapshotRemote and snapshotRemote:IsA("RemoteFunction"), "InventorySnapshot must be a RemoteFunction")
	inventoryUpdated = inventoryUpdatedRemote
	DataStoreManager = dataStoreManager
	snapshotRemote.OnServerInvoke = function(player)
		local now = os.clock()
		local previous = snapshotTimestamps[player] or 0
		if now - previous < 0.1 then return {} end
		snapshotTimestamps[player] = now
		return InventoryService.GetSnapshot(player)
	end
	-- Restores a PendingSale snapshot the instant this player's persisted
	-- data is actually available, never before - PersistentDataReady is the
	-- same readiness signal every other system in the project already keys
	-- off of (EscapeService.syncEscapeRewardDisplay, RoundService.
	-- syncPlayerParticipation, ...), so this doesn't invent a new one.
	local function hydratePendingSale(player)
		if not DataStoreManager or not DataStoreManager.IsReady(player) then
			return
		end
		local persisted = DataStoreManager.Get(player, "Inventory")
		if typeof(persisted) == "table" then
			InventoryService.RestorePendingSale(player, persisted)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		inventories[player] = { CurrentRound = newGroup(), PendingSale = newGroup(), Selling = false }
		publish(player)
		playerConnections[player] = player:GetAttributeChangedSignal("PersistentDataReady"):Connect(function()
			hydratePendingSale(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
		snapshotTimestamps[player] = nil
		if playerConnections[player] then
			playerConnections[player]:Disconnect()
			playerConnections[player] = nil
		end
	end)
	for _, player in Players:GetPlayers() do
		inventories[player] = { CurrentRound = newGroup(), PendingSale = newGroup(), Selling = false }
		publish(player)
		playerConnections[player] = player:GetAttributeChangedSignal("PersistentDataReady"):Connect(function()
			hydratePendingSale(player)
		end)
		hydratePendingSale(player)
	end
end

return InventoryService
