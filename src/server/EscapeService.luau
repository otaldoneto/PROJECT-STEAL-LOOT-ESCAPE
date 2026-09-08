local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local EscapeService = {}
local InventoryService
local CurrencyService
local escapeZone
local escapedPlayers = {}

local function canUseZone(player, zone)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - zone.Position).Magnitude <= 12
end

local function setupPrompt()
	assert(escapeZone and escapeZone:IsA("BasePart"), "EscapeZone must be a BasePart")

	local rewardType = escapeZone:GetAttribute("RewardType") or "Money"
	assert(rewardType == "Money" or rewardType == "Points", "EscapeZone RewardType must be Money or Points")

	local prompt = escapeZone:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Escape"
	prompt.ObjectText = "Escape Zone"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = true
	prompt.Parent = escapeZone

	prompt.Triggered:Connect(function(player)
		if escapedPlayers[player] or player.Parent ~= Players or not canUseZone(player, escapeZone) then
			return
		end

		local reward = InventoryService.GetDepositValue(player)
		if Workspace:GetAttribute("RoundPhase") ~= "Active" or reward < 1 or not CurrencyService.CanAdd(player, rewardType, reward) then
			return
		end

		if not CurrencyService.Add(player, rewardType, reward) then
			return
		end
		if not InventoryService.ClearItems(player) then
			return
		end

		escapedPlayers[player] = true
		player:SetAttribute("Escaped", true)
		player:SetAttribute("EscapeReward", reward)
	end)
end

function EscapeService.Start(inventoryService, currencyService, zone)
	InventoryService = inventoryService
	CurrencyService = currencyService
	escapeZone = zone
	setupPrompt()

	Players.PlayerRemoving:Connect(function(player)
		escapedPlayers[player] = nil
	end)
end

function EscapeService.ResetRound()
	escapedPlayers = {}
	if escapeZone then
		local prompt = escapeZone:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = true
		end
	end
end

return EscapeService