local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ProgressionConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionConfig"))

local ProgressionService = {}
local progressionStore = DataStoreService:GetDataStore("StealLootEscapeProgression_v1")
local progressions = {}
local loaded = {}
local saveAllowed = {}
local progressionUpdated
local CurrencyService

local function getKey(player)
	return "Player_" .. player.UserId
end

local function isValidLevel(value)
	return typeof(value) == "number" and value >= 0 and value % 1 == 0 and value <= ProgressionConfig.MaxSprintLevel
end

local function getSprintSpeed(level)
	return level > 0 and ProgressionConfig.SprintSpeeds[level] or ProgressionConfig.BaseWalkSpeed
end

local function getNextCost(level)
	return ProgressionConfig.SprintCosts[level + 1] or 0
end

local function publish(player, message)
	local progression = progressions[player]
	if not progression then
		return
	end

	player:SetAttribute("ProgressionReady", loaded[player] == true and saveAllowed[player] == true)
	player:SetAttribute("SprintLevel", progression.SprintLevel)
	player:SetAttribute("SprintSpeed", getSprintSpeed(progression.SprintLevel))
	player:SetAttribute("SprintUpgradeCost", getNextCost(progression.SprintLevel))
	player:SetAttribute("MaxSprintLevel", ProgressionConfig.MaxSprintLevel)
	if progressionUpdated then
		progressionUpdated:FireClient(player, {
			SprintLevel = progression.SprintLevel,
			SprintSpeed = getSprintSpeed(progression.SprintLevel),
			SprintUpgradeCost = getNextCost(progression.SprintLevel),
			MaxSprintLevel = ProgressionConfig.MaxSprintLevel,
			Message = message or "",
		})
	end
end

local function loadProgression(player)
	local progression = { SprintLevel = 0 }
	progressions[player] = progression

	local success, data
	for attempt = 1, 3 do
		success, data = pcall(function()
			return progressionStore:GetAsync(getKey(player))
		end)
		if success then
			break
		end
		task.wait(attempt)
	end

	if success then
		if typeof(data) == "table" and isValidLevel(data.SprintLevel) then
			progression.SprintLevel = data.SprintLevel
		end
		saveAllowed[player] = true
	else
		warn(string.format("Could not load progression for %s; saving and purchases are disabled", player.Name))
		saveAllowed[player] = false
	end

	loaded[player] = true
	publish(player)
end

local function setupPlayer(player)
	player:SetAttribute("Sprinting", false)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.WalkSpeed = ProgressionConfig.BaseWalkSpeed
			player:SetAttribute("Sprinting", false)
		end
	end)
	task.spawn(loadProgression, player)
end

local function saveProgression(player)
	local progression = progressions[player]
	if not progression or not loaded[player] or not saveAllowed[player] then
		return false
	end

	local data = { SprintLevel = progression.SprintLevel }
	local success = false
	for attempt = 1, 3 do
		success = pcall(function()
			progressionStore:UpdateAsync(getKey(player), function()
				return data
			end)
		end)
		if success then
			break
		end
		task.wait(attempt)
	end
	if not success then
		warn(string.format("Could not save progression for %s", player.Name))
	end
	return success
end

function ProgressionService.BuySprint(player)
	local progression = progressions[player]
	if not progression or not loaded[player] or not saveAllowed[player] then
		publish(player, "Progression is not ready")
		return false, "Progression is not ready"
	end

	local currentLevel = progression.SprintLevel
	if currentLevel >= ProgressionConfig.MaxSprintLevel then
		publish(player, "Sprint is fully upgraded")
		return false, "Sprint is fully upgraded"
	end

	local cost = getNextCost(currentLevel)
	if not CurrencyService.Spend(player, "Money", cost) then
		publish(player, "Not enough Money")
		return false, "Not enough Money"
	end

	progression.SprintLevel = currentLevel + 1
	publish(player, "Sprint upgraded")
	return true
end

function ProgressionService.SetSprinting(player, isSprinting)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not loaded[player] then
		return false
	end
	local progression = progressions[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not progression or not humanoid or humanoid.Health <= 0 or player:GetAttribute("Hidden") or player:GetAttribute("Escaped") then
		return false
	end

	local sprinting = isSprinting == true and Workspace:GetAttribute("RoundPhase") == "Active"
	local level = progression.SprintLevel
	humanoid.WalkSpeed = sprinting and getSprintSpeed(level) or ProgressionConfig.BaseWalkSpeed
	player:SetAttribute("Sprinting", sprinting)
	return true
end

function ProgressionService.ResetSprint()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = ProgressionConfig.BaseWalkSpeed
		end
		player:SetAttribute("Sprinting", false)
	end
end

function ProgressionService.Start(updatedRemote, currencyService)
	assert(updatedRemote and updatedRemote:IsA("RemoteEvent"), "ProgressionUpdated must be a RemoteEvent")
	CurrencyService = currencyService
	progressionUpdated = updatedRemote

	Players.PlayerAdded:Connect(function(player)
		setupPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		saveProgression(player)
		progressions[player] = nil
		loaded[player] = nil
		saveAllowed[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			saveProgression(player)
		end
	end)
end

return ProgressionService