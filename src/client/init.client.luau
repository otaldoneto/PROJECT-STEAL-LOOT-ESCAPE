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
