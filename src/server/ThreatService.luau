local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RiskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RiskConfig"))

local ThreatService = {}
local guardFolder
local cameraFolder
local guardStates = {}
local running = false
local detectionSources = {}
local roundActive = false
local riskUntil = {}
local riskLevels = {}
local InventoryService
local safeSpawn
local captureInvulnerability = {}

local function getNumberAttribute(instance, name, default, minimum, maximum)
	local value = instance:GetAttribute(name)
	if typeof(value) ~= "number" or value < minimum or value > maximum then
		return default
	end
	return value
end

local function getCharacterRoot(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local function isVisible(origin, targetPosition, ignoredInstance, targetInstance)
	local direction = targetPosition - origin
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { ignoredInstance }
	raycastParams.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction, raycastParams)
	return not result or result.Instance == targetInstance or result.Instance:IsDescendantOf(targetInstance.Parent)
end

local function canSee(origin, lookVector, targetPosition, range, angle, ignoredInstance, targetInstance)
	local offset = targetPosition - origin
	if offset.Magnitude > range or offset.Magnitude < 0.01 then
		return false
	end

	local direction = offset.Unit
	if lookVector:Dot(direction) < math.cos(math.rad(angle / 2)) then
		return false
	end

	return isVisible(origin, targetPosition, ignoredInstance, targetInstance)
end

local function createDefaultGuard()
	local guard = Instance.new("Model")
	guard.Name = "Guard"
	guard:SetAttribute("VisionRange", 45)
	guard:SetAttribute("VisionAngle", 100)
	guard:SetAttribute("PatrolRadius", 12)
	guard:SetAttribute("Speed", 7)
	guard:SetAttribute("AttackDistance", 4)
	guard:SetAttribute("Damage", 20)
	guard:SetAttribute("AttackCooldown", 1.5)
	guard:SetAttribute("PathfindingControlled", true)

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 7
	humanoid.Parent = guard

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = false
	root.CanCollide = false
	root.Size = Vector3.new(2, 4, 2)
	root.Color = Color3.fromRGB(190, 55, 55)
	root.Position = Vector3.new(22, 2, 18)
	root.Parent = guard

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = false
	head.CanCollide = false
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(2, 2, 2)
	head.Color = Color3.fromRGB(240, 190, 150)
	head.Position = root.Position + Vector3.new(0, 3, 0)
	head.Parent = guard

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = head
	weld.Parent = root

	guard.PrimaryPart = root
	guard.Parent = guardFolder
	return guard
end

local function createDefaultCamera()
	local camera = Instance.new("Part")
	camera.Name = "SecurityCamera"
	camera.Anchored = true
	camera.CanCollide = false
	camera.Size = Vector3.new(1, 1, 2)
	camera.Color = Color3.fromRGB(210, 55, 55)
	camera.Material = Enum.Material.Neon
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 8, -8), Vector3.new(0, 2, 0))
	camera:SetAttribute("VisionRange", 38)
	camera:SetAttribute("VisionAngle", 80)
	camera.Parent = cameraFolder
	return camera
end

local function getGuardRoot(guard)
	if guard:IsA("Model") and guard.PrimaryPart and guard.PrimaryPart:IsA("BasePart") then
		return guard.PrimaryPart
	end
	local root = guard:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function setDetection(player, source)
	detectionSources[player] = detectionSources[player] or {}
	detectionSources[player][source] = true
end

local function getRiskName(level)
	return RiskConfig.GetName(level)
end

local function isRiskActive(player)
	return (riskUntil[player] or 0) > os.clock()
end

local function updateDetectionAttributes()
	for _, player in Players:GetPlayers() do
		local sources = detectionSources[player]
		local detected = sources and next(sources) ~= nil or false
		local riskLevel = isRiskActive(player) and (riskLevels[player] or 0) or 0
		if riskLevel >= 2 then
			detected = true
		end
		player:SetAttribute("Detected", detected)
		player:SetAttribute("ThreatLevel", detected and "High" or (riskLevel == 1 and "Medium" or "Safe"))
		player:SetAttribute("LootRisk", getRiskName(riskLevel))
		detectionSources[player] = nil
		if not isRiskActive(player) then
			riskUntil[player] = nil
			riskLevels[player] = nil
		end
	end
end

local function scanCameras()
	for _, camera in cameraFolder:GetChildren() do
		if camera:IsA("BasePart") then
			local range = getNumberAttribute(camera, "VisionRange", 38, 5, 200)
			local angle = getNumberAttribute(camera, "VisionAngle", 80, 10, 180)
			for _, player in Players:GetPlayers() do
				local root = getCharacterRoot(player)
				local riskMultiplier = RiskConfig.GetVisionMultiplier(riskLevels[player] or 0)
				if root and player:GetAttribute("PersistentDataReady") == true and not player:GetAttribute("Escaped") and not player:GetAttribute("Hidden") and not player:GetAttribute("InLobby") and canSee(camera.Position, camera.CFrame.LookVector, root.Position, range * riskMultiplier, angle, camera, root) then
					setDetection(player, camera)
				end
			end
		end
	end
end

local function attackPlayer(state, player, distance)
	local now = os.clock()
	if distance > state.AttackDistance or now - state.LastAttack < state.AttackCooldown or now < (captureInvulnerability[player] or 0) then
		return
	end

	local root = getCharacterRoot(player)
	local humanoid = root and root.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid then
		state.LastAttack = now
		humanoid.Health = math.max(1, humanoid.Health - state.Damage)
		local caughtCount = (player:GetAttribute("CaughtCount") or 0) + 1
		player:SetAttribute("CaughtCount", caughtCount)
		player:SetAttribute("Caught", true)
		captureInvulnerability[player] = now + 5
		if caughtCount == 1 then
			humanoid.Health = humanoid.MaxHealth
			if safeSpawn and player.Character then
				player.Character:PivotTo(safeSpawn.CFrame + Vector3.new(0, 3, 0))
			end
			player:SetAttribute("CaptureStatus", "CAUGHT! You have one more chance. Your loot is safe for now.")
		else
			InventoryService.ClearItems(player)
			player:SetAttribute("ItemsLost", true)
			player:SetAttribute("CaptureStatus", "CAUGHT AGAIN! All loot from this round was lost.")
			humanoid.Health = humanoid.MaxHealth
			if safeSpawn and player.Character then
				player.Character:PivotTo(safeSpawn.CFrame + Vector3.new(0, 3, 0))
			end
		end
	end
end

local function updateGuard(guard, state, deltaTime)
	local root = getGuardRoot(guard)
	if not root or not root:IsDescendantOf(guardFolder) then
		guardStates[guard] = nil
		return
	end

	local targetPlayer
	local targetDistance = math.huge
	for _, player in Players:GetPlayers() do
		local playerRoot = getCharacterRoot(player)
		if playerRoot and player:GetAttribute("PersistentDataReady") == true and not player:GetAttribute("Escaped") and not player:GetAttribute("Hidden") and not player:GetAttribute("InLobby") then
			local riskMultiplier = RiskConfig.GetVisionMultiplier(riskLevels[player] or 0)
			local distance = (playerRoot.Position - root.Position).Magnitude
			if distance < targetDistance and canSee(root.Position, root.CFrame.LookVector, playerRoot.Position, state.VisionRange * riskMultiplier, state.VisionAngle, guard, playerRoot) then
				targetPlayer = player
				targetDistance = distance
			end
		end
	end

	if targetPlayer then
		local targetRoot = getCharacterRoot(targetPlayer)
		setDetection(targetPlayer, guard)
		if targetRoot then
			local direction = targetRoot.Position - root.Position
			if direction.Magnitude > state.AttackDistance and not guard:GetAttribute("PathfindingControlled") then
				local step = math.min(state.Speed * deltaTime, direction.Magnitude - state.AttackDistance)
				local nextPosition = root.Position + direction.Unit * step
				guard:PivotTo(CFrame.lookAt(nextPosition, targetRoot.Position))
			end
			attackPlayer(state, targetPlayer, targetDistance)
		end
		if guard:GetAttribute("PathfindingControlled") then
			return
		end
		return
	end
	if guard:GetAttribute("PathfindingControlled") then
		return
	end

	state.PatrolTime += deltaTime
	local angle = state.PatrolTime * state.Speed / math.max(state.PatrolRadius, 1)
	local patrolPosition = state.Origin + Vector3.new(math.cos(angle) * state.PatrolRadius, 0, math.sin(angle) * state.PatrolRadius)
	guard:PivotTo(CFrame.lookAt(patrolPosition, state.Origin))
end

local function initializePlayer(player)
	player:SetAttribute("Detected", false)
	player:SetAttribute("ThreatLevel", "Safe")
	player:SetAttribute("TimeExpired", not Workspace:GetAttribute("RoundActive"))
	player:SetAttribute("Caught", false)
	player:SetAttribute("Hidden", false)
	player:SetAttribute("Hideout", "")
	player:SetAttribute("HideoutWasSprinting", false)
	player:SetAttribute("LootRisk", "Low")
	player:SetAttribute("EscapeStatus", "Collect loot and reach the escape zone")
	player:SetAttribute("CaughtCount", 0)
	player:SetAttribute("ItemsLost", false)
	player:SetAttribute("CaptureStatus", "")
end

function ThreatService.Start(guards, cameras, inventoryService, spawnPart)
	assert(guards and guards:IsA("Folder"), "Guards must be a Folder")
	assert(cameras and cameras:IsA("Folder"), "SecurityCameras must be a Folder")
	guardFolder = guards
	cameraFolder = cameras
	InventoryService = inventoryService
	safeSpawn = spawnPart

	if #guardFolder:GetChildren() == 0 then
		createDefaultGuard()
	end
	if #cameraFolder:GetChildren() == 0 then
		createDefaultCamera()
	end

	for _, guard in guardFolder:GetChildren() do
		local root = getGuardRoot(guard)
		if root then
			guardStates[guard] = {
				Origin = root.Position,
				PatrolRadius = getNumberAttribute(guard, "PatrolRadius", 12, 0, 100),
				VisionRange = getNumberAttribute(guard, "VisionRange", 45, 5, 200),
				VisionAngle = getNumberAttribute(guard, "VisionAngle", 100, 10, 180),
				Speed = getNumberAttribute(guard, "Speed", 7, 0, 50),
				AttackDistance = getNumberAttribute(guard, "AttackDistance", 4, 1, 15),
				Damage = getNumberAttribute(guard, "Damage", 20, 1, 100),
				AttackCooldown = getNumberAttribute(guard, "AttackCooldown", 1.5, 0.25, 10),
				LastAttack = 0,
				PatrolTime = 0,
			}
		end
	end

	function ThreatService.SetRoundActive(isActive)
		roundActive = isActive == true
		if not roundActive then
			for _, player in Players:GetPlayers() do
				player:SetAttribute("Detected", false)
				player:SetAttribute("ThreatLevel", "Safe")
				player:SetAttribute("LootRisk", "Low")
				player:SetAttribute("CaughtCount", 0)
				player:SetAttribute("ItemsLost", false)
				player:SetAttribute("CaptureStatus", "")
			end
			detectionSources = {}
			riskUntil = {}
			riskLevels = {}
			captureInvulnerability = {}
		end
	end

	function ThreatService.ResetRound(duration)
		for guard, state in pairs(guardStates) do
			local root = getGuardRoot(guard)
			if root then
				if not guard:GetAttribute("PathfindingControlled") then
					guard:PivotTo(CFrame.lookAt(state.Origin, state.Origin + Vector3.new(0, 0, -1)))
				end
				state.LastAttack = 0
				state.PatrolTime = 0
			end
		end
		Workspace:SetAttribute("RoundTimeLeft", duration)
		Workspace:SetAttribute("RoundActive", true)
		Workspace:SetAttribute("RoundPhase", "Active")
	end

	Workspace:SetAttribute("RoundTimeLeft", 0)
	Workspace:SetAttribute("RoundActive", false)
	Players.PlayerAdded:Connect(initializePlayer)
	for _, player in Players:GetPlayers() do
		initializePlayer(player)
	end

	if running then
		return
	end
	running = true
	RunService.Heartbeat:Connect(function(deltaTime)
		if Workspace:GetAttribute("RoundActive") then
			for guard, state in pairs(guardStates) do
				updateGuard(guard, state, math.min(deltaTime, 0.1))
			end
			scanCameras()
		end
		updateDetectionAttributes()
	end)
end

function ThreatService.MarkRisk(player, level, duration)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not roundActive then
		return false
	end
	if not RiskConfig.IsValid(level, duration) then
		return false
	end
	riskLevels[player] = math.max(riskLevels[player] or 0, level)
	riskUntil[player] = math.max(riskUntil[player] or 0, os.clock() + duration)
	player:SetAttribute("LootRisk", getRiskName(riskLevels[player]))
	return true
end

return ThreatService