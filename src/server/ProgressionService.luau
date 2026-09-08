local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionConfig"))

local ProgressionService = {}
local DataStoreManager
local progressionUpdated

local function getSprintSpeed(level)
	return level > 0 and ProgressionConfig.SprintSpeeds[level] or ProgressionConfig.BaseWalkSpeed
end

local function getNextCost(level)
	return ProgressionConfig.SprintCosts[level + 1] or 0
end

local function publish(player, message)
	local level = DataStoreManager.Get(player, "SprintLevel") or 0
	player:SetAttribute("ProgressionReady", DataStoreManager.IsReady(player))
	player:SetAttribute("SprintLevel", level)
	player:SetAttribute("SprintSpeed", getSprintSpeed(level))
	player:SetAttribute("SprintUpgradeCost", getNextCost(level))
	player:SetAttribute("MaxSprintLevel", ProgressionConfig.MaxSprintLevel)
	if progressionUpdated then
		progressionUpdated:FireClient(player, {
			SprintLevel = level,
			SprintSpeed = getSprintSpeed(level),
			SprintUpgradeCost = getNextCost(level),
			MaxSprintLevel = ProgressionConfig.MaxSprintLevel,
			Message = message or "",
		})
	end
end

function ProgressionService.BuySprint(player)
	if not DataStoreManager.IsReady(player) then
		publish(player, "Progression is not ready")
		return false, "Progression is not ready"
	end
	local currentLevel = DataStoreManager.Get(player, "SprintLevel") or 0
	if currentLevel >= ProgressionConfig.MaxSprintLevel then
		publish(player, "Sprint is fully upgraded")
		return false, "Sprint is fully upgraded"
	end
	local cost = getNextCost(currentLevel)
	if not DataStoreManager.Spend(player, "Money", cost) then
		publish(player, "Not enough Money")
		return false, "Not enough Money"
	end
	DataStoreManager.Set(player, "SprintLevel", currentLevel + 1)
	publish(player, "Sprint upgraded")
	return true
end

function ProgressionService.SetSprinting(player, isSprinting)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not DataStoreManager.IsReady(player) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or player:GetAttribute("Hidden") or player:GetAttribute("Escaped") then
		return false
	end
	local sprinting = isSprinting == true and Workspace:GetAttribute("RoundPhase") == "Active"
	local level = DataStoreManager.Get(player, "SprintLevel") or 0
	humanoid.WalkSpeed = sprinting and getSprintSpeed(level) or ProgressionConfig.BaseWalkSpeed
	player:SetAttribute("Sprinting", sprinting)
	return true
end

function ProgressionService.ResetSprint()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.WalkSpeed = ProgressionConfig.BaseWalkSpeed end
		player:SetAttribute("Sprinting", false)
	end
end

function ProgressionService.Start(updatedRemote, dataStoreManager)
	assert(updatedRemote and updatedRemote:IsA("RemoteEvent"), "ProgressionUpdated must be a RemoteEvent")
	DataStoreManager = dataStoreManager
	progressionUpdated = updatedRemote
	assert(DataStoreManager, "DataStoreManager is required")
end

return ProgressionService
