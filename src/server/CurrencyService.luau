local CurrencyService = {}
local DataStoreManager

local CURRENCY_TYPES = {
	Money = true,
	Points = true,
}

local function isCurrencyType(currencyType)
	return typeof(currencyType) == "string" and CURRENCY_TYPES[currencyType] == true
end

local function publishLegacyAliases(player)
	local money = DataStoreManager.Get(player, "Money") or 0
	local points = DataStoreManager.Get(player, "Points") or 0
	player:SetAttribute("Money", money)
	player:SetAttribute("Points", points)
end

function CurrencyService.Add(player, currencyType, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player"
	end
	if not isCurrencyType(currencyType) or typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 then
		return false, "Invalid currency reward"
	end
	if not DataStoreManager.IsReady(player) then
		return false, "Currency is not ready"
	end
	local current = DataStoreManager.Get(player, currencyType) or 0
	if current + amount > 1000000000 then
		return false, "Currency limit reached"
	end
	local success = DataStoreManager.Add(player, currencyType, amount)
	if success then publishLegacyAliases(player) end
	return success
end

function CurrencyService.CanAdd(player, currencyType, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not isCurrencyType(currencyType) then
		return false
	end
	if typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 or not DataStoreManager.IsReady(player) then
		return false
	end
	return (DataStoreManager.Get(player, currencyType) or 0) + amount <= 1000000000
end

function CurrencyService.Spend(player, currencyType, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not isCurrencyType(currencyType) then
		return false, "Invalid currency request"
	end
	if typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 or not DataStoreManager.IsReady(player) then
		return false, "Currency is not ready"
	end
	if not DataStoreManager.Spend(player, currencyType, amount) then
		return false, "Not enough currency"
	end
	publishLegacyAliases(player)
	return true
end

function CurrencyService.Start(dataStoreManager)
	DataStoreManager = dataStoreManager
	assert(DataStoreManager, "DataStoreManager is required")
end

return CurrencyService
