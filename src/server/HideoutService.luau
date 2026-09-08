local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HideoutService = {}
local hideoutFolder
local hideouts = {}
local playerHideouts = {}
local playerConnections = {}

local function getCharacter(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character, root, humanoid
end

local function isNear(player, hideout)
	local _, root = getCharacter(player)
	return root ~= nil and (root.Position - hideout.Position).Magnitude <= 12
end

local function setCharacterHidden(player, hidden, hideout)
	local character, root, humanoid = getCharacter(player)
	if not character then
		return false
	end

	if hidden then
		root.CFrame = hideout.CFrame
		root.Anchored = true
		player:SetAttribute("HideoutWasSprinting", player:GetAttribute("Sprinting") == true)
		player:SetAttribute("Sprinting", false)
		humanoid:SetAttribute("HideoutWalkSpeed", humanoid.WalkSpeed)
		humanoid:SetAttribute("HideoutJumpPower", humanoid.JumpPower)
		humanoid:SetAttribute("HideoutAutoRotate", humanoid.AutoRotate)
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant:SetAttribute("HideoutTransparency", descendant.Transparency)
				descendant.Transparency = 1
			end
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		player:SetAttribute("Hidden", true)
		player:SetAttribute("Hideout", hideout.Name)
	else
		root.Anchored = false
		root.CFrame = hideout.CFrame * CFrame.new(0, 0, -(hideout.Size.Z / 2 + 3))
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") then
				local transparency = descendant:GetAttribute("HideoutTransparency")
				if typeof(transparency) == "number" then
					descendant.Transparency = transparency
					descendant:SetAttribute("HideoutTransparency", nil)
				end
			end
		end
		local walkSpeed = humanoid:GetAttribute("HideoutWalkSpeed")
		local jumpPower = humanoid:GetAttribute("HideoutJumpPower")
		local autoRotate = humanoid:GetAttribute("HideoutAutoRotate")
		local wasSprinting = player:GetAttribute("HideoutWasSprinting") == true
		humanoid.WalkSpeed = wasSprinting and 16 or (typeof(walkSpeed) == "number" and walkSpeed or 16)
		humanoid.JumpPower = typeof(jumpPower) == "number" and jumpPower or 50
		humanoid.AutoRotate = typeof(autoRotate) == "boolean" and autoRotate or true
		humanoid:SetAttribute("HideoutWalkSpeed", nil)
		humanoid:SetAttribute("HideoutJumpPower", nil)
		humanoid:SetAttribute("HideoutAutoRotate", nil)
		player:SetAttribute("HideoutWasSprinting", false)
		player:SetAttribute("Hidden", false)
		player:SetAttribute("Hideout", "")
	end
	return true
end

local function releasePlayer(player, restoreCharacter)
	local hideout = playerHideouts[player]
	playerHideouts[player] = nil
	if hideout then
		if hideout.Occupant == player then
			hideout.Occupant = nil
		end
		if hideout.Prompt and hideout.Prompt.Parent then
			hideout.Prompt.ActionText = "Hide"
			hideout.Prompt.ObjectText = hideout.DisplayName
		end
	end
	if restoreCharacter and player.Parent == Players and hideout and hideout.Part then
		setCharacterHidden(player, false, hideout.Part)
	end
	player:SetAttribute("Hidden", false)
	player:SetAttribute("Hideout", "")
	player:SetAttribute("HideoutWasSprinting", false)
end

local function enterHideout(player, state)
	if state.Occupant or playerHideouts[player] or Workspace:GetAttribute("RoundPhase") ~= "Active" or player:GetAttribute("PersistentDataReady") ~= true or player:GetAttribute("InLobby") or player:GetAttribute("Caught") or player:GetAttribute("Escaped") or player:GetAttribute("Hidden") or not isNear(player, state.Part) then
		return
	end
	if not setCharacterHidden(player, true, state.Part) then
		return
	end

	state.Occupant = player
	playerHideouts[player] = state
	state.Prompt.ActionText = "Leave"
	state.Prompt.ObjectText = "Hidden"
end

local function toggleHideout(player, state)
	if state.Occupant == player then
		if isNear(player, state.Part) then
			releasePlayer(player, true)
		end
		return
	end
	enterHideout(player, state)
end

local function setupHideout(part)
	if not part:IsA("BasePart") or hideouts[part] then
		return
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.ActionText = "Hide"
	prompt.ObjectText = part:GetAttribute("DisplayName") or "Hideout"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = true
	prompt.Parent = part

	local state = {
		Part = part,
		Prompt = prompt,
		DisplayName = prompt.ObjectText,
		Occupant = nil,
	}
	hideouts[part] = state
	prompt.Triggered:Connect(function(player)
		if player.Parent == Players then
			toggleHideout(player, state)
		end
	end)
end

function HideoutService.Start(folder)
	assert(folder and folder:IsA("Folder"), "Hideouts must be a Folder")
	hideoutFolder = folder
	for _, descendant in folder:GetDescendants() do
		setupHideout(descendant)
	end
	folder.DescendantAdded:Connect(setupHideout)
	folder.DescendantRemoving:Connect(function(descendant)
		local state = hideouts[descendant]
		if not state then
			return
		end
		if state.Occupant then
			releasePlayer(state.Occupant, true)
		end
		hideouts[descendant] = nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		releasePlayer(player, false)
		local connections = playerConnections[player]
		if connections then
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			playerConnections[player] = nil
		end
	end)

	local function setupPlayer(player)
		playerConnections[player] = {
			player.CharacterAdded:Connect(function()
				releasePlayer(player, false)
			end),
			player.CharacterRemoving:Connect(function()
				releasePlayer(player, false)
			end),
		}
	end

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

function HideoutService.ResetRound()
	local occupants = {}
	for player in pairs(playerHideouts) do
		table.insert(occupants, player)
	end
	for _, player in occupants do
		releasePlayer(player, true)
	end
end

return HideoutService