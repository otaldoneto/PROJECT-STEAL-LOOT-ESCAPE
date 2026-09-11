local InventoryConfig = {
	MaxSlots = 20,
	MaxWeight = 50,
	-- Max carry weight (kg) by BackpackLevel, indexed 1-5 like ProgressionConfig's
	-- SprintSpeeds/SprintCosts. BackpackLevel 0 (the default - there is no purchase
	-- flow for it yet) falls back to index 1, same pattern as
	-- ProgressionConfig.getSprintSpeed falling back to BaseWalkSpeed for level 0.
	BackpackCapacities = { 20, 30, 40, 50, 60 },
	Items = {
		Bandage = {
			DisplayName = "Bandage",
			Weight = 0.5,
			MaxStack = 5,
			EscapeValue = 10,
			RiskLevel = 0,
			RiskDuration = 0,
		},
		Keycard = {
			DisplayName = "Keycard",
			Weight = 0.2,
			MaxStack = 1,
			EscapeValue = 50,
			RiskLevel = 1,
			RiskDuration = 12,
		},
		GoldBar = {
			DisplayName = "Gold Bar",
			Weight = 10,
			MaxStack = 3,
			EscapeValue = 500,
			RiskLevel = 2,
			RiskDuration = 25,
		},
	},
}

return InventoryConfig