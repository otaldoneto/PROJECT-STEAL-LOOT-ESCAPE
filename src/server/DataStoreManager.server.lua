--!nocheck
---@diagnostic disable: undefined-global

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local playerDataStore = DataStoreService:GetDataStore("StealLootEscapePlayerData_v1")
local sessions = {}
local saveLocks = {}

local DEFAULT_COINS = 0
local DEFAULT_BACKPACK_LEVEL = 0
local MAX_COINS = 1000000000
local MAX_BACKPACK_LEVEL = 100

local function getKey(player)
	return "Player_" .. player.UserId
end

local function isValidInteger(value, minimum, maximum)
	return typeof(value) == "number"
		and value >= minimum
		and value <= maximum
		and value % 1 == 0
end

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function getOrCreateIntValue(parent, name, defaultValue)
	local value = parent:FindFirstChild(name)
	if value and value:IsA("IntValue") then
		return value
	end
	if value then
		value:Destroy()
	end
	value = Instance.new("IntValue")
	value.Name = name
	value.Value = defaultValue
	value.Parent = parent
	return value
end

local function getLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats and leaderstats:IsA("Folder") then
		return leaderstats
	end
	if leaderstats then
		leaderstats:Destroy()
	end
	leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	return leaderstats
end

local function publish(player, data)
	local leaderstats = getLeaderstats(player)
	local coins = getOrCreateIntValue(leaderstats, "Moedas", data.Moedas)
	local backpackLevel = getOrCreateIntValue(leaderstats, "MochilaNivel", data.MochilaNivel)
	coins.Value = data.Moedas
	backpackLevel.Value = data.MochilaNivel
	player:SetAttribute("DataStoreReady", true)
	player:SetAttribute("Moedas", data.Moedas)
	player:SetAttribute("MochilaNivel", data.MochilaNivel)
end

local function loadPlayer(player)
	local data = {
		Moedas = DEFAULT_COINS,
		MochilaNivel = DEFAULT_BACKPACK_LEVEL,
	}
	local success, savedData
	for attempt = 1, 3 do
		success, savedData = pcall(function()
			return playerDataStore:GetAsync(getKey(player))
		end)
		if success then
			break
		end
		task.wait(attempt)
	end

	if not success then
		player:SetAttribute("DataStoreReady", false)
		warn(string.format("Could not load player data for %s; saving is disabled", player.Name))
		return
	end

	if typeof(savedData) == "table" then
		if isValidInteger(savedData.Moedas, 0, MAX_COINS) then
			data.Moedas = savedData.Moedas
		end
		if isValidInteger(savedData.MochilaNivel, 0, MAX_BACKPACK_LEVEL) then
			data.MochilaNivel = savedData.MochilaNivel
		end
	end

	sessions[player] = data
	publish(player, data)
end

local function savePlayer(player)
	if saveLocks[player] or not sessions[player] then
		return false
	end
	saveLocks[player] = true

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Moedas")
	local backpackLevel = leaderstats and leaderstats:FindFirstChild("MochilaNivel")
	local data = {
		Moedas = coins and coins:IsA("IntValue") and clamp(coins.Value, 0, MAX_COINS) or sessions[player].Moedas,
		MochilaNivel = backpackLevel and backpackLevel:IsA("IntValue") and clamp(backpackLevel.Value, 0, MAX_BACKPACK_LEVEL) or sessions[player].MochilaNivel,
	}

	local success = false
	for attempt = 1, 3 do
		success = pcall(function()
			playerDataStore:UpdateAsync(getKey(player), function()
				return data
			end)
		end)
		if success then
			break
		end
		task.wait(attempt)
	end
	if not success then
		warn(string.format("Could not save player data for %s", player.Name))
	end
	saveLocks[player] = nil
	return success
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("DataStoreReady", false)
	task.spawn(loadPlayer, player)
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayer(player)
	sessions[player] = nil
	saveLocks[player] = nil
end)

for _, player in Players:GetPlayers() do
	player:SetAttribute("DataStoreReady", false)
	task.spawn(loadPlayer, player)
end

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
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)