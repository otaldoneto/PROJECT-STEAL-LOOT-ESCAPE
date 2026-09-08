--!nocheck
---@diagnostic disable: undefined-global

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local screenGui = script.Parent
local matchTime = ReplicatedStorage:WaitForChild("MatchTime")
local leaderstats = player:WaitForChild("leaderstats")
local mochila = leaderstats:WaitForChild("Mochila")

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

local timerLabel = getOrCreateLabel("TimerLabel", UDim2.fromOffset(20, 20))
local lootLabel = getOrCreateLabel("LootLabel", UDim2.fromOffset(20, 62))

local function formatTime(value)
	if typeof(value) == "number" then
		local seconds = math.max(0, math.floor(value))
		return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
	end

	local minutes, seconds = tostring(value):match("(%d+):(%d%d)")
	if minutes and seconds then
		return string.format("%02d:%02d", tonumber(minutes), tonumber(seconds))
	end
	return "00:00"
end

local function updateTimer()
	timerLabel.Text = formatTime(matchTime.Value)
end

local function updateLoot()
	local maximum = player:GetAttribute("InventorySlotsMax") or 20
	lootLabel.Text = string.format("Loot: %d/%d", mochila.Value, maximum)
end

matchTime:GetPropertyChangedSignal("Value"):Connect(updateTimer)
mochila:GetPropertyChangedSignal("Value"):Connect(updateLoot)
player:GetAttributeChangedSignal("InventorySlotsMax"):Connect(updateLoot)

updateTimer()
updateLoot()