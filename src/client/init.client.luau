local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
local inventorySnapshot = remotes:WaitForChild("InventorySnapshot")
local inventoryConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InventoryConfig"))

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "InventoryPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 300)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
panel.Visible = false
panel.Parent = screenGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -24, 0, 40)
title.Position = UDim2.fromOffset(12, 8)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Backpack"
title.Parent = panel

local contents = Instance.new("TextLabel")
contents.Name = "Contents"
contents.Size = UDim2.new(1, -24, 1, -60)
contents.Position = UDim2.fromOffset(12, 52)
contents.BackgroundTransparency = 1
contents.TextColor3 = Color3.fromRGB(220, 220, 225)
contents.TextSize = 18
contents.TextWrapped = false
contents.TextXAlignment = Enum.TextXAlignment.Left
contents.TextYAlignment = Enum.TextYAlignment.Top
contents.Parent = panel

local threatStatus = Instance.new("TextLabel")
threatStatus.Name = "ThreatStatus"
threatStatus.AnchorPoint = Vector2.new(1, 0)
threatStatus.Position = UDim2.new(1, -20, 0, 20)
threatStatus.Size = UDim2.fromOffset(280, 34)
threatStatus.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
threatStatus.BackgroundTransparency = 0.15
threatStatus.TextColor3 = Color3.fromRGB(235, 235, 235)
threatStatus.TextSize = 18
threatStatus.TextXAlignment = Enum.TextXAlignment.Center
threatStatus.Parent = screenGui

local function render(snapshot)
	local lines = {}
	for _, entry in snapshot do
		table.insert(lines, string.format("%s  x%d", entry.ItemId, entry.Amount))
	end
	contents.Text = #lines > 0 and table.concat(lines, "\n") or "Empty"

	local weight = player:GetAttribute("InventoryWeight") or 0
	local slots = player:GetAttribute("InventorySlots") or 0
	title.Text = string.format("Backpack  %.1f / %.1f kg  (%d / %d)", weight, inventoryConfig.MaxWeight, slots, inventoryConfig.MaxSlots)
end

inventoryUpdated.OnClientEvent:Connect(render)

local function renderThreatStatus()
	local timeLeft = workspace:GetAttribute("RoundTimeLeft") or 0
	local minutes = math.floor(timeLeft / 60)
	local seconds = timeLeft % 60
	local threatLevel = workspace:GetAttribute("RoundActive") == false and "TIME EXPIRED" or (player:GetAttribute("ThreatLevel") or "Safe")
	threatStatus.Text = string.format("TIME %02d:%02d  |  ALERT: %s", minutes, seconds, string.upper(threatLevel))
	threatStatus.TextColor3 = threatLevel == "High" and Color3.fromRGB(255, 110, 100) or Color3.fromRGB(235, 235, 235)
end

workspace:GetAttributeChangedSignal("RoundTimeLeft"):Connect(renderThreatStatus)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(renderThreatStatus)
player:GetAttributeChangedSignal("ThreatLevel"):Connect(renderThreatStatus)
renderThreatStatus()

local initialSnapshot = inventorySnapshot:InvokeServer()
if typeof(initialSnapshot) == "table" then
	render(initialSnapshot)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		panel.Visible = not panel.Visible
	end
end)

player:GetAttributeChangedSignal("InventoryWeight"):Connect(function()
	local weight = player:GetAttribute("InventoryWeight") or 0
	local slots = player:GetAttribute("InventorySlots") or 0
	title.Text = string.format("Backpack  %.1f / %.1f kg  (%d / %d)", weight, inventoryConfig.MaxWeight, slots, inventoryConfig.MaxSlots)
end)
