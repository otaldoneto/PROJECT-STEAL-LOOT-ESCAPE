--!nocheck
---@diagnostic disable: undefined-global

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

while Workspace:GetAttribute("ServicesReady") ~= true do
	task.wait()
end

local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LockpickRemote")
local vaultFolder = Workspace:WaitForChild("Vaults")
local sessions = {}
local vaultStates = {}
local playerConnections = {}

local SESSION_DURATION = 12
local TARGET_WIDTH = 0.2
local CYCLE_DURATION = 1.8
local ALARM_DURATION = 15
local MAX_DISTANCE = 12
local TIMEOUT_CHECK_INTERVAL = 0.25

local function isNear(player, vault)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root and humanoid and humanoid.Health > 0 and (root.Position - vault.Position).Magnitude <= MAX_DISTANCE
end

local function isActiveRound(player)
	return Workspace:GetAttribute("RoundPhase") == "Active" and not player:GetAttribute("InLobby") and not player:GetAttribute("Caught") and not player:GetAttribute("Hidden") and player:GetAttribute("PersistentDataReady") == true
end

local function getVaultState(vault)
	local state = vaultStates[vault]
	if state then
		return state
	end
	state = { Unlocked = false }
	vaultStates[vault] = state
	return state
end

local function closeSession(player, message)
	sessions[player] = nil
	if player.Parent == Players then
		remote:FireClient(player, "Close", message or "")
	end
end

task.spawn(function()
	while true do
		task.wait(TIMEOUT_CHECK_INTERVAL)
		local now = workspace:GetServerTimeNow()
		for player, session in pairs(sessions) do
			if player.Parent ~= Players then
				sessions[player] = nil
			elseif now >= session.ExpiresAt then
				closeSession(player, "Lockpick timed out")
			end
		end
	end
end)

local function alarm(vault)
	local sound = vault:FindFirstChild("AlarmSound")
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
	Workspace:SetAttribute("GuardAlarmPosition", vault.Position)
	Workspace:SetAttribute("GuardAlarmExpires", os.clock() + ALARM_DURATION)
end

local function isSuccessfulTiming(session)
	local elapsed = workspace:GetServerTimeNow() - session.StartedAt
	if elapsed < 0 or elapsed > SESSION_DURATION then
		return false
	end
	local phase = (elapsed % CYCLE_DURATION) / CYCLE_DURATION
	return phase >= session.TargetStart and phase <= session.TargetStart + TARGET_WIDTH
end

local function startSession(player, vault)
	local state = getVaultState(vault)
	if sessions[player] or state.Unlocked or not isActiveRound(player) or not isNear(player, vault) then
		return
	end

	local startedAt = workspace:GetServerTimeNow()
	sessions[player] = {
		Vault = vault,
		StartedAt = startedAt,
		ExpiresAt = startedAt + SESSION_DURATION,
		TargetStart = 0.35,
	}
	remote:FireClient(player, "Start", {
		Vault = vault,
		StartedAt = sessions[player].StartedAt,
		Duration = SESSION_DURATION,
		Cycle = CYCLE_DURATION,
		TargetStart = sessions[player].TargetStart,
		TargetWidth = TARGET_WIDTH,
	})
end

local function setupVault(vault)
	if not vault:IsA("BasePart") or vaultStates[vault] then
		return
	end
	getVaultState(vault)
	local alarmSound = vault:FindFirstChild("AlarmSound") or Instance.new("Sound")
	alarmSound.Name = "AlarmSound"
	alarmSound.SoundId = vault:GetAttribute("AlarmSoundId") or "rbxassetid://9118823101"
	alarmSound.Volume = 1
	alarmSound.RollOffMaxDistance = 100
	alarmSound.Parent = vault
	local prompt = vault:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Lockpick"
	prompt.ObjectText = "Vault"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = vault
	prompt.Triggered:Connect(function(player)
		startSession(player, vault)
	end)
end

for _, vault in vaultFolder:GetChildren() do
	setupVault(vault)
end
vaultFolder.ChildAdded:Connect(setupVault)

remote.OnServerEvent:Connect(function(player, action)
	local session = sessions[player]
	if not session or action ~= "Attempt" then
		return
	end
	local vault = session.Vault
	if not vault:IsDescendantOf(vaultFolder) or not isNear(player, vault) or not isActiveRound(player) then
		closeSession(player, "Lockpick cancelled")
		return
	end

	if not isSuccessfulTiming(session) then
		alarm(vault)
		closeSession(player, "Missed! The alarm attracted the guard.")
		return
	end

	local state = getVaultState(vault)
	if state.Unlocked or not InventoryService.AddItem(player, "GoldBar", 1) then
		closeSession(player, "Inventory full")
		return
	end
	state.Unlocked = true
	vault.Transparency = 1
	vault.CanCollide = false
	local prompt = vault:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end
	closeSession(player, "Success! Gold Bar added to your inventory.")
end)

local function setupPlayer(player)
	playerConnections[player] = {
		player:GetAttributeChangedSignal("Caught"):Connect(function()
			if player:GetAttribute("Caught") == true and sessions[player] then
				closeSession(player, "Captured")
			end
		end),
	}
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	local connections = playerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end
end)

Workspace:GetAttributeChangedSignal("RoundPhase"):Connect(function()
	if Workspace:GetAttribute("RoundPhase") ~= "Active" then
		for player in pairs(sessions) do
			closeSession(player, "Round ended")
		end
		for vault, state in pairs(vaultStates) do
			state.Unlocked = false
			vault.Transparency = 0
			vault.CanCollide = true
			local prompt = vault:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = true
			end
		end
		Workspace:SetAttribute("GuardAlarmPosition", nil)
		Workspace:SetAttribute("GuardAlarmExpires", nil)
	end
end)