--!nocheck
---@diagnostic disable: undefined-global

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local screenGui = script.Parent
local leaderstats = player:WaitForChild("leaderstats")

local function getOrCreateLabel(name, position)
	local label = screenGui:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		return label
	end

	label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromOffset(260, 34)
	label.Position = position
	label.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = screenGui
	return label
end

local timeLabel = getOrCreateLabel("MatchTime", UDim2.fromOffset(20, 20))
local backpackLabel = getOrCreateLabel("BackpackStatus", UDim2.fromOffset(20, 62))

local function renderTime()
	local timeLeft = Workspace:GetAttribute("RoundTimeLeft")
	if typeof(timeLeft) ~= "number" then
		timeLabel.Text = "Tempo: --:--"
		return
	end

	timeLeft = math.max(0, math.floor(timeLeft))
	timeLabel.Text = string.format("Tempo: %02d:%02d", math.floor(timeLeft / 60), timeLeft % 60)
end

local function renderBackpack()
	local mochila = leaderstats:FindFirstChild("Mochila")
	local current = mochila and mochila.Value or 0
	local maximum = player:GetAttribute("InventorySlotsMax") or 20
	backpackLabel.Text = string.format("Mochila: %d/%d", current, maximum)
end

Workspace:GetAttributeChangedSignal("RoundTimeLeft"):Connect(renderTime)
leaderstats.ChildAdded:Connect(function(child)
	if child.Name == "Mochila" then
		child:GetPropertyChangedSignal("Value"):Connect(renderBackpack)
		renderBackpack()
	end
end)

local mochila = leaderstats:FindFirstChild("Mochila")
if mochila then
	mochila:GetPropertyChangedSignal("Value"):Connect(renderBackpack)
end
player:GetAttributeChangedSignal("InventorySlotsMax"):Connect(renderBackpack)

renderTime()
renderBackpack()