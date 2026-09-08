local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
local inventorySnapshot = remotes:WaitForChild("InventorySnapshot")
local progressionUpdated = remotes:WaitForChild("ProgressionUpdated")
local progressionRequest = remotes:WaitForChild("ProgressionRequest")
local sprintRequest = remotes:WaitForChild("SprintRequest")
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

local shopPanel = Instance.new("Frame")
shopPanel.Name = "ShopPanel"
shopPanel.AnchorPoint = Vector2.new(0.5, 0.5)
shopPanel.Position = UDim2.fromScale(0.5, 0.5)
shopPanel.Size = UDim2.fromOffset(360, 220)
shopPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
shopPanel.Visible = false
shopPanel.Parent = screenGui

local shopTitle = Instance.new("TextLabel")
shopTitle.Name = "Title"
shopTitle.Size = UDim2.new(1, -24, 0, 40)
shopTitle.Position = UDim2.fromOffset(12, 8)
shopTitle.BackgroundTransparency = 1
shopTitle.TextColor3 = Color3.new(1, 1, 1)
shopTitle.TextSize = 22
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.Text = "Shop"
shopTitle.Parent = shopPanel

local sprintInfo = Instance.new("TextLabel")
sprintInfo.Name = "SprintInfo"
sprintInfo.Size = UDim2.new(1, -24, 0, 70)
sprintInfo.Position = UDim2.fromOffset(12, 58)
sprintInfo.BackgroundTransparency = 1
sprintInfo.TextColor3 = Color3.fromRGB(220, 220, 225)
sprintInfo.TextSize = 18
sprintInfo.TextWrapped = true
sprintInfo.TextXAlignment = Enum.TextXAlignment.Left
sprintInfo.TextYAlignment = Enum.TextYAlignment.Top
sprintInfo.Parent = shopPanel

local buySprint = Instance.new("TextButton")
buySprint.Name = "BuySprint"
buySprint.Size = UDim2.new(1, -24, 0, 44)
buySprint.Position = UDim2.fromOffset(12, 145)
buySprint.BackgroundColor3 = Color3.fromRGB(70, 150, 100)
buySprint.TextColor3 = Color3.new(1, 1, 1)
buySprint.TextSize = 18
buySprint.Text = "Upgrade Sprint"
buySprint.Parent = shopPanel

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

local function renderProgression(data)
	local level = data and data.SprintLevel or player:GetAttribute("SprintLevel") or 0
	local speed = data and data.SprintSpeed or player:GetAttribute("SprintSpeed") or 16
	local cost = data and data.SprintUpgradeCost or player:GetAttribute("SprintUpgradeCost") or 0
	local maxLevel = data and data.MaxSprintLevel or player:GetAttribute("MaxSprintLevel") or 0
	local message = data and data.Message or ""
	sprintInfo.Text = string.format("Sprint  |  Level %d/%d  |  Speed %d", level, maxLevel, speed)
	if cost > 0 then
		buySprint.Text = string.format("Upgrade Sprint  |  $%d", cost)
		buySprint.Active = true
		buySprint.AutoButtonColor = true
	else
		buySprint.Text = "Sprint fully upgraded"
		buySprint.Active = false
		buySprint.AutoButtonColor = false
	end
	if message ~= "" then
		sprintInfo.Text ..= "\n" .. message
	end
end

progressionUpdated.OnClientEvent:Connect(renderProgression)
buySprint.Activated:Connect(function()
	progressionRequest:FireServer("BuySprint")
end)

local function renderThreatStatus()
	local timeLeft = workspace:GetAttribute("RoundTimeLeft") or 0
	local minutes = math.floor(timeLeft / 60)
	local seconds = timeLeft % 60
	local phase = workspace:GetAttribute("RoundPhase") or "Loading"
	local threatLevel = player:GetAttribute("ThreatLevel") or "Safe"
	local lootRisk = player:GetAttribute("LootRisk") or "Low"
	if player:GetAttribute("Hidden") then
		threatLevel = "HIDDEN"
	elseif phase == "Results" then
		threatLevel = "RESULTS"
	elseif phase == "Intermission" then
		threatLevel = "PREPARE"
	elseif workspace:GetAttribute("RoundActive") == false then
		threatLevel = "TIME EXPIRED"
	end
	local warning = workspace:GetAttribute("TimerWarning") and "  |  HURRY" or ""
	threatStatus.Text = string.format("%s  |  %02d:%02d%s  |  ALERT: %s  |  RISK: %s", string.upper(phase), minutes, seconds, warning, string.upper(threatLevel), string.upper(lootRisk))
	threatStatus.TextColor3 = threatLevel == "High" and Color3.fromRGB(255, 110, 100) or threatLevel == "HIDDEN" and Color3.fromRGB(130, 220, 170) or workspace:GetAttribute("TimerWarning") and Color3.fromRGB(255, 210, 100) or Color3.fromRGB(235, 235, 235)
end

workspace:GetAttributeChangedSignal("RoundTimeLeft"):Connect(renderThreatStatus)
workspace:GetAttributeChangedSignal("RoundActive"):Connect(renderThreatStatus)
workspace:GetAttributeChangedSignal("RoundPhase"):Connect(renderThreatStatus)
workspace:GetAttributeChangedSignal("TimerWarning"):Connect(renderThreatStatus)
player:GetAttributeChangedSignal("ThreatLevel"):Connect(renderThreatStatus)
player:GetAttributeChangedSignal("Hidden"):Connect(renderThreatStatus)
player:GetAttributeChangedSignal("LootRisk"):Connect(renderThreatStatus)
renderThreatStatus()
player:GetAttributeChangedSignal("SprintLevel"):Connect(renderProgression)
player:GetAttributeChangedSignal("SprintSpeed"):Connect(renderProgression)
player:GetAttributeChangedSignal("SprintUpgradeCost"):Connect(renderProgression)
renderProgression()

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
	elseif input.KeyCode == Enum.KeyCode.M then
		shopPanel.Visible = not shopPanel.Visible
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprintRequest:FireServer(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprintRequest:FireServer(false)
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	sprintRequest:FireServer(false)
end)

player:GetAttributeChangedSignal("InventoryWeight"):Connect(function()
	local weight = player:GetAttribute("InventoryWeight") or 0
	local slots = player:GetAttribute("InventorySlots") or 0
	title.Text = string.format("Backpack  %.1f / %.1f kg  (%d / %d)", weight, inventoryConfig.MaxWeight, slots, inventoryConfig.MaxSlots)
end)
