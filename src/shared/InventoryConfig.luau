local InventoryConfig = {
	MaxSlots = 20,
	MaxWeight = 50,
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