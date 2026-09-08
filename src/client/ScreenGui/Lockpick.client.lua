--!nocheck
---@diagnostic disable: undefined-global

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LockpickRemote")
local screenGui = script.Parent
local frame = Instance.new("Frame")
frame.Name = "LockpickFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromOffset(420, 130)
frame.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
frame.Visible = false
frame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 30)
title.Position = UDim2.fromOffset(10, 8)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 20
title.Text = "LOCKPICK  |  Press SPACE in the green zone"
title.Parent = frame

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -40, 0, 30)
track.Position = UDim2.fromOffset(20, 52)
track.BackgroundColor3 = Color3.fromRGB(65, 65, 70)
track.Parent = frame

local target = Instance.new("Frame")
target.BackgroundColor3 = Color3.fromRGB(70, 210, 110)
target.Size = UDim2.fromScale(0.2, 1)
target.Parent = track

local indicator = Instance.new("Frame")
indicator.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
indicator.Size = UDim2.fromOffset(6, 38)
indicator.AnchorPoint = Vector2.new(0.5, 0.5)
indicator.Position = UDim2.fromScale(0, 0.5)
indicator.Parent = track

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 28)
status.Position = UDim2.fromOffset(10, 92)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(235, 235, 235)
status.TextSize = 16
status.Parent = frame

local session
local renderConnection

local function close(message)
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	session = nil
	frame.Visible = false
	status.Text = message or ""
end

local function updateIndicator()
	if not session then
		return
	end
	local elapsed = workspace:GetServerTimeNow() - session.StartedAt
	if elapsed > session.Duration then
		if not session.Expired then
			session.Expired = true
			remote:FireServer("Attempt")
		end
		return
	end
	local phase = (elapsed % session.Cycle) / session.Cycle
	indicator.Position = UDim2.fromScale(phase, 0.5)
end

remote.OnClientEvent:Connect(function(action, data)
	if action == "Start" then
		session = data
		target.Position = UDim2.fromScale(data.TargetStart, 0)
		target.Size = UDim2.fromScale(data.TargetWidth, 1)
		status.Text = ""
		frame.Visible = true
		if renderConnection then
			renderConnection:Disconnect()
		end
		renderConnection = RunService.RenderStepped:Connect(updateIndicator)
	elseif action == "Close" then
		close(data)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not session or input.KeyCode ~= Enum.KeyCode.Space then
		return
	end
	remote:FireServer("Attempt")
end)