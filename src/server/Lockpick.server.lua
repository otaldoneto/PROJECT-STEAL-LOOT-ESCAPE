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
local sessions = {}
local vaultStates = {}
local vaultFolders = {}
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
	state = { Unlocked = false, Rewarded = {} }
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
	-- Eligibility is per-player: Rewarded[player] is the only thing that
	-- blocks a session here. Unlocked is informational/visual only (set on
	-- any success, for the vault's appearance) and must never gate who can
	-- attempt the vault, so a second player can still loot it after a first
	-- player already succeeded.
	if sessions[player] or state.Rewarded[player] or not isActiveRound(player) or not isNear(player, vault) then
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

-- Workspace currently has two separate "Vaults" folders (one Rojo-tracked,
-- one Studio-only leftover), each with its own Vault Part.
-- Workspace:WaitForChild("Vaults") only ever resolves one of them, so every
-- "Vaults"-named Folder in Workspace is set up here instead of relying on a
-- single resolved reference - this is what previously left the second
-- Vault without a ProximityPrompt/AlarmSound.
local function setupVaultFolder(folder)
	if vaultFolders[folder] then
		return
	end
	vaultFolders[folder] = true
	for _, vault in folder:GetChildren() do
		setupVault(vault)
	end
	folder.ChildAdded:Connect(setupVault)
end

Workspace:WaitForChild("Vaults")
for _, child in Workspace:GetChildren() do
	if child.Name == "Vaults" and child:IsA("Folder") then
		setupVaultFolder(child)
	end
end
Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Vaults" and child:IsA("Folder") then
		setupVaultFolder(child)
	end
end)

remote.OnServerEvent:Connect(function(player, action)
	local session = sessions[player]
	if not session or action ~= "Attempt" then
		return
	end
	local vault = session.Vault
	if not vault:IsDescendantOf(Workspace) or not isNear(player, vault) or not isActiveRound(player) then
		closeSession(player, "Lockpick cancelled")
		return
	end

	if not isSuccessfulTiming(session) then
		alarm(vault)
		closeSession(player, "Missed! The alarm attracted the guard.")
		return
	end

	local state = getVaultState(vault)
	if state.Rewarded[player] then
		closeSession(player, "Vault already looted")
		return
	end
	if not InventoryService.AddItem(player, "GoldBar", 1) then
		closeSession(player, "Inventory full")
		return
	end
	state.Rewarded[player] = true
	-- Unlocked is now purely a visual/informational marker (this vault has
	-- been opened by someone this round) - it must stay enabled so other,
	-- still-eligible players can keep attempting it. Do not disable the
	-- prompt here: Rewarded[player] is what gates eligibility now, not the
	-- prompt itself.
	state.Unlocked = true
	vault.Transparency = 1
	vault.CanCollide = false
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
			table.clear(state.Rewarded)
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