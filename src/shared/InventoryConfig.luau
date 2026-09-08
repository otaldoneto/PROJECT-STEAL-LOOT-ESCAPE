local InventoryConfig = {
	MaxSlots = 20,
	MaxWeight = 50,
	Items = {
		Bandage = {
			DisplayName = "Bandage",
			Weight = 0.5,
			MaxStack = 5,
			EscapeValue = 10,
		},
		Keycard = {
			DisplayName = "Keycard",
			Weight = 0.2,
			MaxStack = 1,
			EscapeValue = 50,
		},
		GoldBar = {
			DisplayName = "Gold Bar",
			Weight = 10,
			MaxStack = 3,
			EscapeValue = 500,
		},
	},
}

return InventoryConfig