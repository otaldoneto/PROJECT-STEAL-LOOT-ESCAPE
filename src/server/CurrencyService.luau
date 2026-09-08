local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local CurrencyService = {}
local currencyStore = DataStoreService:GetDataStore("StealLootEscapeCurrency_v1")
local balances = {}
local loaded = {}
local saveAllowed = {}

local CURRENCY_TYPES = {
	Money = true,
	Points = true,
}

local function isCurrencyType(currencyType)
	return typeof(currencyType) == "string" and CURRENCY_TYPES[currencyType] == true
end

local function isNonNegativeInteger(value)
	return typeof(value) == "number" and value >= 0 and value % 1 == 0 and value <= 1000000000
end

local function getKey(player)
	return "Player_" .. player.UserId
end

local function publish(player)
	local playerBalances = balances[player]
	if not playerBalances then
		return
	end

	for currencyType, amount in pairs(playerBalances) do
		player:SetAttribute(currencyType, amount)
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	for currencyType, amount in pairs(playerBalances) do
		local value = leaderstats:FindFirstChild(currencyType)
		if not value then
			value = Instance.new("IntValue")
			value.Name = currencyType
			value.Parent = leaderstats
		end
		value.Value = amount
	end
end

local function loadCurrency(player)
	local playerBalances = {
		Money = 0,
		Points = 0,
	}
	balances[player] = playerBalances

	local success, data
	for attempt = 1, 3 do
		success, data = pcall(function()
			return currencyStore:GetAsync(getKey(player))
		end)
		if success then
			break
		end
		task.wait(attempt)
	end

	if success then
		if typeof(data) == "table" then
			for currencyType in pairs(CURRENCY_TYPES) do
				if isNonNegativeInteger(data[currencyType]) then
					playerBalances[currencyType] = data[currencyType]
				end
			end
		end
		saveAllowed[player] = true
	else
		warn(string.format("Could not load currency for %s; saving is disabled for this session", player.Name))
		saveAllowed[player] = false
	end

	loaded[player] = true
	publish(player)
end

local function saveCurrency(player)
	local playerBalances = balances[player]
	if not playerBalances or not loaded[player] or not saveAllowed[player] then
		return false
	end

	local data = {
		Money = playerBalances.Money,
		Points = playerBalances.Points,
	}
	local success = false
	for attempt = 1, 3 do
		success = pcall(function()
			currencyStore:UpdateAsync(getKey(player), function()
				return data
			end)
		end)
		if success then
			break
		end
		task.wait(attempt)
	end
	if not success then
		warn(string.format("Could not save currency for %s", player.Name))
	end
	return success
end

function CurrencyService.Add(player, currencyType, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not isCurrencyType(currencyType) or typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 then
		return false, "Invalid currency reward"
	end
	if not loaded[player] then
		return false, "Currency is not ready"
	end

	local playerBalances = balances[player]
	local currentAmount = playerBalances[currencyType]
	if currentAmount + amount > 1000000000 then
		return false, "Currency limit reached"
	end

	playerBalances[currencyType] = currentAmount + amount
	publish(player)
	return true
end

function CurrencyService.CanAdd(player, currencyType, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not isCurrencyType(currencyType) then
		return false
	end
	if typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 or not loaded[player] then
		return false
	end

	local playerBalances = balances[player]
	return playerBalances[currencyType] + amount <= 1000000000
end

function CurrencyService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadCurrency, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		saveCurrency(player)
		balances[player] = nil
		loaded[player] = nil
		saveAllowed[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(loadCurrency, player)
	end

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			saveCurrency(player)
		end
	end)
end

return CurrencyService