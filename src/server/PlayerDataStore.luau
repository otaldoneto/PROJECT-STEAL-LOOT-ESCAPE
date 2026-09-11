local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionConfig"))

local DataStoreManager = {}
local playerStore = DataStoreService:GetDataStore("StealLootEscapePlayerData_v2")
local legacyPlayerStore = DataStoreService:GetDataStore("StealLootEscapePlayerData_v1")
local legacyCurrencyStore = DataStoreService:GetDataStore("StealLootEscapeCurrency_v1")
local legacyProgressionStore = DataStoreService:GetDataStore("StealLootEscapeProgression_v1")
local legacyInventoryStore = DataStoreService:GetDataStore("StealLootEscapeInventory_v1")
local sessions = {}
local saveLocks = {}
local aliasConnections = {}
local publishing = {}
local moneyDeltas = {}
local pointsDeltas = {}
local pendingSaleDeltas = {}
local running = false

local DEFAULT_DATA = { Money = 0, Points = 0, SprintLevel = 0, BackpackLevel = 0, Inventory = { Items = {}, PendingValue = 0 }, PendingSaleAmount = 0, PendingSaleRewardType = "Money" }
local MAX_CURRENCY = 1000000000
local MAX_BACKPACK_LEVEL = 100
local RETRIES = 3
local AUTOSAVE_INTERVAL = 5 * 60
local PLAYER_REMOVING_SAVE_WAIT_TIMEOUT = 15

local function getKey(player) return "Player_" .. player.UserId end

local function isPlayerActive(player)
	return player.Parent == Players
end

local function isInteger(value, minimum, maximum)
	return typeof(value) == "number" and value >= minimum and value <= maximum and value % 1 == 0
end

local function cloneDefault()
	return { Money = 0, Points = 0, SprintLevel = 0, BackpackLevel = 0, Inventory = { Items = {}, PendingValue = 0 }, PendingSaleAmount = 0, PendingSaleRewardType = "Money" }
end

local function sanitizeInventoryItems(items)
	local result = {}
	if typeof(items) ~= "table" then return result end
	for itemId, amount in pairs(items) do
		local item = InventoryConfig.Items[itemId]
		-- This field only ever holds PendingSale (already-escaped, no
		-- longer at-risk) stacks, never CurrentRound - those can legitimately
		-- exceed a single item's MaxStack once merged across multiple
		-- escapes without a sale in between (see InventoryService.
		-- MarkPendingSale), so only a generic sanity ceiling is enforced
		-- here, not the per-carry stack limit that gates picking items up.
		if item and isInteger(amount, 1, 999) then result[itemId] = amount end
	end
	return result
end

-- Inventory holds a PendingSale snapshot: { Items = {[itemId]=amount},
-- PendingValue = number } - escaped-but-unsold loot (InventoryService.
-- MarkPendingSale/ClearPendingSale keep this in sync; CurrentRound, the
-- at-risk loot of the round in progress, is never persisted here), so it
-- survives a disconnect instead of only living in InventoryService's
-- in-memory PendingSale group.
-- Older saves (and the legacy inventory store used by migrate()) only ever
-- held the flat { [itemId] = amount } shape, from before PendingValue was
-- tracked here - both shapes are accepted and always normalized to the
-- current { Items, PendingValue } shape, so no separate format-version flag
-- or migration step is needed.
local function sanitizeInventory(inventory)
	if typeof(inventory) ~= "table" then
		return { Items = {}, PendingValue = 0 }
	end
	if typeof(inventory.Items) == "table" or typeof(inventory.PendingValue) == "number" then
		return {
			Items = sanitizeInventoryItems(inventory.Items),
			PendingValue = isInteger(inventory.PendingValue, 0, MAX_CURRENCY) and inventory.PendingValue or 0,
		}
	end
	return { Items = sanitizeInventoryItems(inventory), PendingValue = 0 }
end

local function sanitize(data)
	local result = cloneDefault()
	if typeof(data) ~= "table" then return result end
	if isInteger(data.Money, 0, MAX_CURRENCY) then result.Money = data.Money end
	if isInteger(data.Points, 0, MAX_CURRENCY) then result.Points = data.Points end
	if isInteger(data.SprintLevel, 0, ProgressionConfig.MaxSprintLevel) then result.SprintLevel = data.SprintLevel end
	if isInteger(data.BackpackLevel, 0, MAX_BACKPACK_LEVEL) then result.BackpackLevel = data.BackpackLevel end
	result.Inventory = sanitizeInventory(data.Inventory)
	if isInteger(data.PendingSaleAmount, 0, MAX_CURRENCY) then result.PendingSaleAmount = data.PendingSaleAmount end
	if data.PendingSaleRewardType == "Money" or data.PendingSaleRewardType == "Points" then
		result.PendingSaleRewardType = data.PendingSaleRewardType
	end
	return result
end

local function tryGet(store, key)
	local success, value
	for attempt = 1, RETRIES do
		success, value = pcall(function() return store:GetAsync(key) end)
		if success then return true, value end
		task.wait(attempt)
	end
	return false, nil
end

local function migrate(player)
	local migrated = cloneDefault()
	local migrationSafe = true
	local key = getKey(player)
	local success, oldData = tryGet(legacyPlayerStore, key)
	if not success then migrationSafe = false end
	if success and typeof(oldData) == "table" then
		if isInteger(oldData.Moedas, 0, MAX_CURRENCY) then migrated.Money = oldData.Moedas end
		if isInteger(oldData.MochilaNivel, 0, MAX_BACKPACK_LEVEL) then migrated.BackpackLevel = oldData.MochilaNivel end
	end
	local currencySuccess, currencyData = tryGet(legacyCurrencyStore, key)
	if not currencySuccess then migrationSafe = false end
	if currencySuccess and typeof(currencyData) == "table" then
		if isInteger(currencyData.Money, 0, MAX_CURRENCY) then migrated.Money = currencyData.Money end
		if isInteger(currencyData.Points, 0, MAX_CURRENCY) then migrated.Points = currencyData.Points end
	end
	local progressionSuccess, progressionData = tryGet(legacyProgressionStore, key)
	if not progressionSuccess then migrationSafe = false end
	if progressionSuccess and typeof(progressionData) == "table" and isInteger(progressionData.SprintLevel, 0, ProgressionConfig.MaxSprintLevel) then
		migrated.SprintLevel = progressionData.SprintLevel
	end
	local inventorySuccess, inventoryData = tryGet(legacyInventoryStore, key)
	if not inventorySuccess then migrationSafe = false end
	if inventorySuccess and typeof(inventoryData) == "table" then migrated.Inventory = sanitizeInventory(inventoryData.Items) end
	return migrated, migrationSafe
end

local function publish(player, data)
	if not isPlayerActive(player) then
		return false
	end
	publishing[player] = true
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local values = {
		Money = data.Money, Points = data.Points, SprintLevel = data.SprintLevel,
		BackpackLevel = data.BackpackLevel, Moedas = data.Money, MochilaNivel = data.BackpackLevel,
	}
	for name, amount in pairs(values) do
		local value = leaderstats:FindFirstChild(name)
		if not value or not value:IsA("IntValue") then
			if value then value:Destroy() end
			value = Instance.new("IntValue")
			value.Name = name
			value.Parent = leaderstats
		end
		value.Value = amount
		player:SetAttribute(name, amount)
	end
	if not aliasConnections[player] then
		aliasConnections[player] = {}
		for name in pairs(values) do
			local value = leaderstats:FindFirstChild(name)
			if value and value:IsA("IntValue") then
				aliasConnections[player][name] = value.Changed:Connect(function()
					if not publishing[player] and sessions[player] then
						publish(player, sessions[player])
					end
				end)
			end
		end
	end
	publishing[player] = nil
	player:SetAttribute("DataStoreReady", true)
	player:SetAttribute("PersistentDataReady", true)
	return true
end

local function loadPlayer(player)
	local success, data = tryGet(playerStore, getKey(player))
	if not isPlayerActive(player) then
		return
	end
	if not success then
		if not isPlayerActive(player) then return end
		player:SetAttribute("DataStoreReady", false)
		player:SetAttribute("PersistentDataReady", false)
		warn(string.format("Could not load canonical data for %s; saving is disabled", player.Name))
		return
	end
	local loadedData
	if data == nil then
		local migrationSafe
		loadedData, migrationSafe = migrate(player)
		if not isPlayerActive(player) then return end
		if not migrationSafe then
			player:SetAttribute("DataStoreReady", false)
			player:SetAttribute("PersistentDataReady", false)
			warn(string.format("Could not safely migrate data for %s; saving is disabled", player.Name))
			return
		end
	else
		loadedData = sanitize(data)
	end
	if not isPlayerActive(player) then
		return
	end
	sessions[player] = loadedData
	if not publish(player, loadedData) then
		sessions[player] = nil
	end
end

local function savePlayer(player)
	local data = sessions[player]
	if saveLocks[player] or not data then return false end
	saveLocks[player] = true
	-- Captured once, before any retry/yield, so every attempt of this save
	-- applies exactly the same delta. Operations that happen while this save
	-- is in flight accumulate into moneyDeltas/pointsDeltas normally and are
	-- only subtracted (not zeroed) below, once this exact captured amount is
	-- confirmed persisted.
	local capturedMoneyDelta = moneyDeltas[player] or 0
	local capturedPointsDelta = pointsDeltas[player] or 0
	local capturedPendingSaleDelta = pendingSaleDeltas[player] or 0
	local success = false
	for attempt = 1, RETRIES do
		success = pcall(function()
			playerStore:UpdateAsync(getKey(player), function(oldValue)
				local nextData = sanitize(data)
				local oldData = sanitize(oldValue)
				nextData.SprintLevel = math.max(nextData.SprintLevel, oldData.SprintLevel)
				nextData.BackpackLevel = math.max(nextData.BackpackLevel, oldData.BackpackLevel)
				if typeof(oldValue) == "table" then
					-- A canonical record already exists: apply only what this
					-- server added/spent since its last confirmed save on top
					-- of whatever is currently stored, instead of overwriting
					-- it with this session's absolute snapshot. PendingSale
					-- follows the exact same delta discipline as Money/Points:
					-- a sale is represented as a negative delta (consumption),
					-- a new escape reward as a positive delta (gain).
					nextData.Money = math.clamp(oldData.Money + capturedMoneyDelta, 0, MAX_CURRENCY)
					nextData.Points = math.clamp(oldData.Points + capturedPointsDelta, 0, MAX_CURRENCY)
					nextData.PendingSaleAmount = math.clamp(oldData.PendingSaleAmount + capturedPendingSaleDelta, 0, MAX_CURRENCY)
				end
				-- No canonical record yet (first save, e.g. right after a
				-- migration): nextData.Money/.Points/.PendingSaleAmount already
				-- hold this session's full snapshot from sanitize(data) above,
				-- which is the correct baseline since there is nothing else to
				-- merge against. PendingSaleRewardType is always taken from
				-- this session's own understanding (never merged numerically),
				-- since the project only ever runs a single EscapeZone/
				-- RewardType per server for the lifetime of a deployment.
				return nextData
			end)
		end)
		if success then break end
		task.wait(attempt)
	end
	if success then
		moneyDeltas[player] = (moneyDeltas[player] or 0) - capturedMoneyDelta
		pointsDeltas[player] = (pointsDeltas[player] or 0) - capturedPointsDelta
		pendingSaleDeltas[player] = (pendingSaleDeltas[player] or 0) - capturedPendingSaleDelta
	else
		warn(string.format("Could not save canonical data for %s", player.Name))
	end
	saveLocks[player] = nil
	return success
end

function DataStoreManager.IsReady(player) return sessions[player] ~= nil and player:GetAttribute("PersistentDataReady") == true end
function DataStoreManager.Get(player, field) local data = sessions[player] return data and data[field] or nil end

function DataStoreManager.Set(player, field, value)
	local data = sessions[player]
	if not data or not DataStoreManager.IsReady(player) then return false end
	if field == "Money" or field == "Points" then
		if not isInteger(value, 0, MAX_CURRENCY) then return false end
	elseif field == "SprintLevel" then
		if not isInteger(value, 0, ProgressionConfig.MaxSprintLevel) then return false end
	elseif field == "BackpackLevel" then
		if not isInteger(value, 0, MAX_BACKPACK_LEVEL) then return false end
	elseif field == "Inventory" then
		value = sanitizeInventory(value)
	elseif field == "PendingSaleAmount" then
		if not isInteger(value, 0, MAX_CURRENCY) then return false end
	elseif field == "PendingSaleRewardType" then
		if value ~= "Money" and value ~= "Points" then return false end
	else
		return false
	end
	data[field] = value
	publish(player, data)
	return true
end

function DataStoreManager.Add(player, field, amount)
	local current = DataStoreManager.Get(player, field)
	if not current or not isInteger(amount, 1, MAX_CURRENCY) then return false end
	local success = DataStoreManager.Set(player, field, current + amount)
	if success then
		if field == "Money" then
			moneyDeltas[player] = (moneyDeltas[player] or 0) + amount
		elseif field == "Points" then
			pointsDeltas[player] = (pointsDeltas[player] or 0) + amount
		elseif field == "PendingSaleAmount" then
			pendingSaleDeltas[player] = (pendingSaleDeltas[player] or 0) + amount
		end
	end
	return success
end

function DataStoreManager.Spend(player, field, amount)
	local current = DataStoreManager.Get(player, field)
	if not current or not isInteger(amount, 1, MAX_CURRENCY) or current < amount then return false end
	local success = DataStoreManager.Set(player, field, current - amount)
	if success then
		if field == "Money" then
			moneyDeltas[player] = (moneyDeltas[player] or 0) - amount
		elseif field == "Points" then
			pointsDeltas[player] = (pointsDeltas[player] or 0) - amount
		elseif field == "PendingSaleAmount" then
			pendingSaleDeltas[player] = (pendingSaleDeltas[player] or 0) - amount
		end
	end
	return success
end

-- Consumes the player's entire PendingSaleAmount and credits the matching
-- currency field, atomically, against whatever the DataStore truly holds
-- at commit time (oldValue) rather than this session's local belief. This
-- is what makes two servers unable to both sell the same underlying
-- balance: whichever UpdateAsync call commits first zeroes PendingSale in
-- the canonical record, so the second one to run always sees a fresh
-- oldValue.PendingSaleAmount of 0 and correctly finds nothing left to sell.
--
-- Deliberately bypasses moneyDeltas/pointsDeltas/pendingSaleDeltas: the
-- credited amount is already durably persisted by the time this function
-- returns success, so recording it as a *pending* delta as well would make
-- the next savePlayer() apply it a second time on top of a DataStore value
-- that already reflects it.
--
-- Shares saveLocks with savePlayer() so a sale and a save can never issue
-- concurrent UpdateAsync calls for the same player from this server; if a
-- save is already in flight, the sale is rejected immediately (the caller
-- can just ask the player to try again) rather than queued, to keep this
-- gameplay-triggered handler's worst-case latency bounded.
function DataStoreManager.SellPending(player, itemValue)
	-- itemValue is the caller's already-computed, already-captured value of
	-- whatever is physically sitting in InventoryService right now (see
	-- EscapeService.SellPendingReward). It is a plain number by the time it
	-- reaches here, so referencing it inside the UpdateAsync callback below
	-- introduces no yield.
	itemValue = (typeof(itemValue) == "number" and itemValue >= 0 and itemValue % 1 == 0) and itemValue or 0
	local data = sessions[player]
	if not data or not DataStoreManager.IsReady(player) then
		return false, 0, "Money"
	end
	if saveLocks[player] then
		return false, 0, "Money"
	end
	saveLocks[player] = true
	local success = false
	local soldAmount = 0
	local soldType = "Money"
	for attempt = 1, RETRIES do
		soldAmount = 0
		soldType = "Money"
		success = pcall(function()
			playerStore:UpdateAsync(getKey(player), function(oldValue)
				-- No canonical record yet (first save for this player): this
				-- server's own session is the only known truth, matching the
				-- same first-save fallback savePlayer() already relies on.
				local baseline = typeof(oldValue) == "table" and sanitize(oldValue) or sanitize(data)
				-- Combines the banked Stay-carryover (baseline.PendingSaleAmount)
				-- with the freshly computed physical-inventory value passed in
				-- by the caller; a normal escape no longer pre-adds itemValue
				-- into PendingSaleAmount, so this is the one place the two are
				-- ever summed - each unit of value is consumed exactly once.
				local amount = baseline.PendingSaleAmount + itemValue
				if amount <= 0 then
					return nil -- nothing to sell; cancel the write entirely
				end
				local rewardType = baseline.PendingSaleRewardType
				local currentCurrency = rewardType == "Money" and baseline.Money or baseline.Points
				if currentCurrency + amount > MAX_CURRENCY then
					-- Crediting the full amount would overflow the cap: reject
					-- the whole sale (leave PendingSale and the caller's
					-- inventory untouched) instead of silently clamping and
					-- losing the difference.
					return nil
				end
				soldAmount = amount
				soldType = rewardType
				local nextData = baseline
				nextData.PendingSaleAmount = 0
				-- Cleared in the same atomic write as the credit and
				-- PendingSaleAmount: if this weren't here, a server that
				-- crashes (skipping BindToClose/the next autosave) between a
				-- successful sale and its next savePlayer() would leave the
				-- just-paid-for items sitting in the canonical Inventory
				-- record, restoring them on the player's next login on top
				-- of currency they were already credited for.
				nextData.Inventory = { Items = {}, PendingValue = 0 }
				if rewardType == "Money" then
					nextData.Money = currentCurrency + amount
				else
					nextData.Points = currentCurrency + amount
				end
				return nextData
			end)
		end)
		if success then break end
		task.wait(attempt)
	end
	saveLocks[player] = nil
	if not success then
		warn(string.format("Could not process sale for %s", player.Name))
		return false, 0, "Money"
	end
	if soldAmount > 0 then
		-- Mirror the now-durably-persisted result into the local session for
		-- HUD/gameplay consistency only; the delta tables are intentionally
		-- left untouched (see comment above).
		data.PendingSaleAmount = 0
		data.Inventory = { Items = {}, PendingValue = 0 }
		if soldType == "Money" then
			data.Money = math.clamp((data.Money or 0) + soldAmount, 0, MAX_CURRENCY)
		else
			data.Points = math.clamp((data.Points or 0) + soldAmount, 0, MAX_CURRENCY)
		end
		publish(player, data)
	end
	return true, soldAmount, soldType
end

function DataStoreManager.Start()
	if running then return end
	running = true
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("DataStoreReady", false)
		player:SetAttribute("PersistentDataReady", false)
		task.spawn(loadPlayer, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		if saveLocks[player] then
			local deadline = os.clock() + PLAYER_REMOVING_SAVE_WAIT_TIMEOUT
			while saveLocks[player] and os.clock() < deadline do
				task.wait(0.1)
			end
		end
		if saveLocks[player] then
			warn(string.format("Timed out waiting for an in-progress save for %s; skipping final save to avoid a concurrent UpdateAsync", player.Name))
		else
			savePlayer(player)
		end
		if aliasConnections[player] then
			for _, connection in pairs(aliasConnections[player]) do
				connection:Disconnect()
			end
		end
		aliasConnections[player] = nil
		publishing[player] = nil
		sessions[player] = nil
		moneyDeltas[player] = nil
		pointsDeltas[player] = nil
		pendingSaleDeltas[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("DataStoreReady", false)
		player:SetAttribute("PersistentDataReady", false)
		task.spawn(loadPlayer, player)
	end
	task.spawn(function()
		while running do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do task.spawn(savePlayer, player) end
		end
	end)
	game:BindToClose(function()
		local deadline = os.clock() + 25
		local remaining = 0
		for _, player in Players:GetPlayers() do
			remaining = remaining + 1
			task.spawn(function()
				if saveLocks[player] then
					while saveLocks[player] and os.clock() < deadline do
						task.wait(0.1)
					end
				else
					savePlayer(player)
				end
				remaining = remaining - 1
			end)
		end
		while remaining > 0 and os.clock() < deadline do task.wait(0.1) end
	end)
end

return DataStoreManager
