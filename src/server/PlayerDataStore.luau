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
local running = false

local DEFAULT_DATA = { Money = 0, Points = 0, SprintLevel = 0, BackpackLevel = 0, Inventory = {} }
local MAX_CURRENCY = 1000000000
local MAX_BACKPACK_LEVEL = 100
local RETRIES = 3
local AUTOSAVE_INTERVAL = 5 * 60

local function getKey(player) return "Player_" .. player.UserId end

local function isInteger(value, minimum, maximum)
	return typeof(value) == "number" and value >= minimum and value <= maximum and value % 1 == 0
end

local function cloneDefault()
	return { Money = 0, Points = 0, SprintLevel = 0, BackpackLevel = 0, Inventory = {} }
end

local function sanitizeInventory(items)
	local result = {}
	if typeof(items) ~= "table" then return result end
	for itemId, amount in pairs(items) do
		local item = InventoryConfig.Items[itemId]
		if item and isInteger(amount, 1, item.MaxStack) then result[itemId] = amount end
	end
	return result
end

local function sanitize(data)
	local result = cloneDefault()
	if typeof(data) ~= "table" then return result end
	if isInteger(data.Money, 0, MAX_CURRENCY) then result.Money = data.Money end
	if isInteger(data.Points, 0, MAX_CURRENCY) then result.Points = data.Points end
	if isInteger(data.SprintLevel, 0, ProgressionConfig.MaxSprintLevel) then result.SprintLevel = data.SprintLevel end
	if isInteger(data.BackpackLevel, 0, MAX_BACKPACK_LEVEL) then result.BackpackLevel = data.BackpackLevel end
	result.Inventory = sanitizeInventory(data.Inventory)
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
	player:SetAttribute("DataStoreReady", true)
	player:SetAttribute("PersistentDataReady", true)
end

local function loadPlayer(player)
	local success, data = tryGet(playerStore, getKey(player))
	if not success then
		player:SetAttribute("DataStoreReady", false)
		player:SetAttribute("PersistentDataReady", false)
		warn(string.format("Could not load canonical data for %s; saving is disabled", player.Name))
		return
	end
	local loadedData
	if data == nil then
		local migrationSafe
		loadedData, migrationSafe = migrate(player)
		if not migrationSafe then
			player:SetAttribute("DataStoreReady", false)
			player:SetAttribute("PersistentDataReady", false)
			warn(string.format("Could not safely migrate data for %s; saving is disabled", player.Name))
			return
		end
	else
		loadedData = sanitize(data)
	end
	sessions[player] = loadedData
	publish(player, loadedData)
end

local function savePlayer(player)
	local data = sessions[player]
	if saveLocks[player] or not data then return false end
	saveLocks[player] = true
	local success = false
	for attempt = 1, RETRIES do
		success = pcall(function()
			playerStore:UpdateAsync(getKey(player), function() return sanitize(data) end)
		end)
		if success then break end
		task.wait(attempt)
	end
	if not success then warn(string.format("Could not save canonical data for %s", player.Name)) end
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
	return DataStoreManager.Set(player, field, current + amount)
end

function DataStoreManager.Spend(player, field, amount)
	local current = DataStoreManager.Get(player, field)
	if not current or not isInteger(amount, 1, MAX_CURRENCY) or current < amount then return false end
	return DataStoreManager.Set(player, field, current - amount)
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
		savePlayer(player)
		sessions[player] = nil
		saveLocks[player] = nil
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
		local remaining = 0
		for _, player in Players:GetPlayers() do
			remaining = remaining + 1
			task.spawn(function()
				savePlayer(player)
				remaining = remaining - 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do task.wait(0.1) end
	end)
end

return DataStoreManager
