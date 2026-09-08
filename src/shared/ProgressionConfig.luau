local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local ProgressionConfig = {
	BaseWalkSpeed = GameConfig.Movement.BaseWalkSpeed,
	SprintSpeeds = { 24, 26, 28, 30, 32 },
	SprintCosts = { 250, 500, 1000, 2000, 4000 },
}

ProgressionConfig.MaxSprintLevel = #ProgressionConfig.SprintSpeeds

return ProgressionConfig