--!nocheck
---@diagnostic disable: undefined-global

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

while Workspace:GetAttribute("ServicesReady") ~= true do
	task.wait()
end

local guardFolder = Workspace:WaitForChild("Guards")
local waypointFolder = Workspace:WaitForChild("GuardWaypoints")
local controllers = {}

local MAX_VISION_DISTANCE = 35
local FRONT_VISION_ANGLE = 120
local LOST_SIGHT_GRACE = 5
local UPDATE_INTERVAL = 0.25
local PATROL_SPEED = 7
local CHASE_SPEED = 18
local ALERT_SOUND_ID = "rbxassetid://9118823101"

local function getRootAndHumanoid(guard)
	local root = guard:FindFirstChild("HumanoidRootPart")
	local humanoid = guard:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return nil, nil
	end
	return root, humanoid
end

local function getWaypoints()
	local waypoints = {}
	for _, waypoint in waypointFolder:GetChildren() do
		if waypoint:IsA("BasePart") then
			table.insert(waypoints, waypoint)
		end
	end
	table.sort(waypoints, function(left, right)
		return left.Name < right.Name
	end)
	return waypoints
end

local function canSeePlayer(guard, player)
	local guardRoot = guard:FindFirstChild("HumanoidRootPart")
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not guardRoot or not playerRoot or not humanoid or humanoid.Health <= 0 then
		return false, nil
	end

	local offset = playerRoot.Position - guardRoot.Position
	if offset.Magnitude > MAX_VISION_DISTANCE then
		return false, playerRoot
	end
	local direction = offset.Unit
	if guardRoot.CFrame.LookVector:Dot(direction) < math.cos(math.rad(FRONT_VISION_ANGLE / 2)) then
		return false, playerRoot
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { guard }
	raycastParams.IgnoreWater = true
	local result = Workspace:Raycast(guardRoot.Position, offset, raycastParams)
	local visible = not result or result.Instance:IsDescendantOf(character)
	return visible, playerRoot
end

local function findVisiblePlayer(guard)
	local closestPlayer
	local closestDistance = MAX_VISION_DISTANCE
	for _, player in Players:GetPlayers() do
		if not player:GetAttribute("Escaped") and not player:GetAttribute("Hidden") and not player:GetAttribute("InLobby") then
			local visible, playerRoot = canSeePlayer(guard, player)
			if visible and playerRoot then
				local distance = (playerRoot.Position - guard.HumanoidRootPart.Position).Magnitude
				if distance < closestDistance then
					closestPlayer = player
					closestDistance = distance
				end
			end
		end
	end
	return closestPlayer
end

local function getNextPathPosition(startPosition, targetPosition)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
	})
	local computed = pcall(function()
		path:ComputeAsync(startPosition, targetPosition)
	end)
	if not computed or path.Status ~= Enum.PathStatus.Success then
		return targetPosition, nil
	end

	local waypoints = path:GetWaypoints()
	local nextWaypoint = waypoints[2] or waypoints[1]
	return nextWaypoint and nextWaypoint.Position or targetPosition, nextWaypoint
end

local function moveToward(humanoid, root, targetPosition)
	local nextPosition, nextWaypoint = getNextPathPosition(root.Position, targetPosition)
	if nextWaypoint and nextWaypoint.Action == Enum.PathWaypointAction.Jump then
		humanoid.Jump = true
	end
	humanoid:MoveTo(nextPosition)
end

local function getAlertSound(guard, root)
	local sound = root:FindFirstChild("AlertSound")
	if sound and sound:IsA("Sound") then
		return sound
	end

	sound = Instance.new("Sound")
	sound.Name = "AlertSound"
	sound.SoundId = guard:GetAttribute("AlertSoundId") or ALERT_SOUND_ID
	sound.Volume = 0.8
	sound.RollOffMaxDistance = 80
	sound.Parent = root
	return sound
end

local function getAlarmPosition()
	local position = Workspace:GetAttribute("GuardAlarmPosition")
	local expires = Workspace:GetAttribute("GuardAlarmExpires")
	if typeof(position) == "Vector3" and typeof(expires) == "number" and expires > os.clock() then
		return position
	end
	return nil
end

local function startController(guard)
	if controllers[guard] or not guard:IsA("Model") or not guard:GetAttribute("PathfindingControlled") then
		return
	end

	local root, humanoid = getRootAndHumanoid(guard)
	if not root or not humanoid then
		warn(string.format("Guard %s needs a HumanoidRootPart and Humanoid", guard:GetFullName()))
		return
	end
	controllers[guard] = true
	humanoid.WalkSpeed = PATROL_SPEED
	local alertSound = getAlertSound(guard, root)
	for _, descendant in guard:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetNetworkOwner(nil)
		end
	end

	task.spawn(function()
		local waypoints = getWaypoints()
		local waypointIndex = 1
		local lastSeenAt = 0
		local lastTargetPosition
		local targetPlayer
		local alerting = false
		while guard.Parent == guardFolder and humanoid.Health > 0 do
			if Workspace:GetAttribute("RoundPhase") ~= "Active" then
				humanoid.WalkSpeed = PATROL_SPEED
				humanoid:MoveTo(root.Position)
				alerting = false
			else
				local alarmPosition = getAlarmPosition()
				if alarmPosition then
					targetPlayer = nil
					lastSeenAt = os.clock()
					lastTargetPosition = alarmPosition
				else
					local target = findVisiblePlayer(guard)
					if target then
						if not alerting then
							alertSound:Play()
							alerting = true
						end
						targetPlayer = target
						lastSeenAt = os.clock()
						local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
						lastTargetPosition = targetRoot and targetRoot.Position or nil
					elseif os.clock() - lastSeenAt > LOST_SIGHT_GRACE then
						targetPlayer = nil
						lastTargetPosition = nil
						alerting = false
					end
				end

				if lastTargetPosition then
					humanoid.WalkSpeed = CHASE_SPEED
					local targetRoot = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
					if targetRoot and targetRoot.Parent then
						lastTargetPosition = targetRoot.Position
					end
					humanoid:MoveTo(lastTargetPosition)
				elseif #waypoints > 0 then
					humanoid.WalkSpeed = PATROL_SPEED
					local waypoint = waypoints[waypointIndex]
					if (root.Position - waypoint.Position).Magnitude <= 4 then
						waypointIndex = waypointIndex % #waypoints + 1
						waypoint = waypoints[waypointIndex]
					end
					moveToward(humanoid, root, waypoint.Position)
				else
					humanoid.WalkSpeed = PATROL_SPEED
					humanoid:MoveTo(root.Position)
				end
			end
			task.wait(UPDATE_INTERVAL)
		end
		controllers[guard] = nil
	end)
end

for _, guard in guardFolder:GetChildren() do
	startController(guard)
end
guardFolder.ChildAdded:Connect(startController)