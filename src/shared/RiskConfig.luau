local RiskConfig = {
	MaxLevel = 2,
	MaxDuration = 120,
	Names = { "Low", "Medium", "High" },
	VisionMultipliers = { 1, 1.1, 1.25 },
}

function RiskConfig.IsValid(level, duration)
	return typeof(level) == "number"
		and level >= 0
		and level <= RiskConfig.MaxLevel
		and level % 1 == 0
		and typeof(duration) == "number"
		and duration >= 0
		and duration <= RiskConfig.MaxDuration
end

function RiskConfig.GetName(level)
	return RiskConfig.Names[level + 1] or RiskConfig.Names[1]
end

function RiskConfig.GetVisionMultiplier(level)
	return RiskConfig.VisionMultipliers[level + 1] or RiskConfig.VisionMultipliers[1]
end

return RiskConfig