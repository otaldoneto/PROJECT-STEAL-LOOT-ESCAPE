local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local LobbyService = {}
local EscapeService
local CurrencyService
local sellCounter
local leaderboardBoard
local sellPrompt
local leaderboardStore = DataStoreService:GetOrderedDataStore("StealLootEscapeLeaderboard_v1")
local actionLocks = {}
local LEADERBOARD_REFRESH_INTERVAL = 60
local LEADERBOARD_RETRIES = 3
local lastLeaderboardAttempt = 0
local leaderboardRefreshInProgress = false
local cachedLeaderboardText

local function canUsePart(player, part)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local position = part.CFrame:PointToObjectSpace(root.Position)
	return math.abs(position.X) <= part.Size.X / 2 + 4
		and math.abs(position.Z) <= part.Size.Z / 2 + 4
		and math.abs(position.Y) <= 8
end

local function getBoardLabel()
	local surface = leaderboardBoard:FindFirstChildOfClass("SurfaceGui") or Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.AlwaysOnTop = true
	surface.Parent = leaderboardBoard
	local label = surface:FindFirstChild("Entries") or Instance.new("TextLabel")
	label.Name = "Entries"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	label.TextColor3 = Color3.fromRGB(245, 220, 120)
	label.TextSize = 22
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Font = Enum.Font.GothamBold
	label.Parent = surface
	return label
end

local function refreshLeaderboard(force)
	local now = os.clock()
	if leaderboardRefreshInProgress or (not force and now - lastLeaderboardAttempt < LEADERBOARD_REFRESH_INTERVAL) then
		return
	end
	lastLeaderboardAttempt = now
	leaderboardRefreshInProgress = true
	local label = getBoardLabel()
	local success, pages
	for attempt = 1, LEADERBOARD_RETRIES do
		success, pages = pcall(function()
			return leaderboardStore:GetSortedAsync(false, 10)
		end)
		if success then
			break
		end
		task.wait(attempt)
	end
	if not success then
		label.Text = cachedLeaderboardText or "TOP THIEVES\nLeaderboard temporarily unavailable"
		leaderboardRefreshInProgress = false
		return
	end

	local entries = { "TOP THIEVES" }
	for rank, entry in ipairs(pages:GetCurrentPage()) do
		local name = "Player " .. tostring(entry.key)
		local nameSuccess, resolvedName = pcall(function()
			return Players:GetNameFromUserIdAsync(tonumber(entry.key))
		end)
		if nameSuccess then
			name = resolvedName
		end
		table.insert(entries, string.format("%d. %s  %d", rank, name, entry.value))
	end
	cachedLeaderboardText = table.concat(entries, "\n")
	label.Text = cachedLeaderboardText
	leaderboardRefreshInProgress = false
end

local function recordSale(player, amount)
	return pcall(function()
		leaderboardStore:UpdateAsync(tostring(player.UserId), function(previous)
			local current = typeof(previous) == "number" and previous or 0
			return current + amount
		end)
	end)
end

local function setupSellPrompt()
	sellPrompt = sellCounter:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	sellPrompt.ActionText = "Sell Loot"
	sellPrompt.ObjectText = "Loot Counter"
	sellPrompt.HoldDuration = 0.75
	sellPrompt.MaxActivationDistance = 12
	sellPrompt.RequiresLineOfSight = false
	sellPrompt.Parent = sellCounter

	sellPrompt.Triggered:Connect(function(player)
		if actionLocks[player] or player.Parent ~= Players or player:GetAttribute("Caught") or not canUsePart(player, sellCounter) then
			return
		end
		actionLocks[player] = true
		local amount, rewardType = EscapeService.GetPendingSale(player)
		if amount < 1 or not CurrencyService.CanAdd(player, rewardType, amount) then
			player:SetAttribute("LobbyStatus", "No loot to sell or currency is full")
			actionLocks[player] = nil
			return
		end
		if not CurrencyService.Add(player, rewardType, amount) then
			player:SetAttribute("LobbyStatus", "Sale failed")
			actionLocks[player] = nil
			return
		end
		EscapeService.ClearPendingSale(player)
		player:SetAttribute("LobbyStatus", string.format("Sold loot: +%d %s", amount, rewardType))
		if not recordSale(player, amount) then
			warn(string.format("Could not update leaderboard for %s", player.Name))
		end
		refreshLeaderboard(false)
		actionLocks[player] = nil
	end)
end

function LobbyService.Start(escapeService, currencyService, counter, board)
	assert(escapeService and currencyService and counter and board, "LobbyService dependencies are required")
	EscapeService = escapeService
	CurrencyService = currencyService
	sellCounter = counter
	leaderboardBoard = board
	setupSellPrompt()
	refreshLeaderboard(true)

	Players.PlayerRemoving:Connect(function(player)
		actionLocks[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(60)
			refreshLeaderboard(false)
		end
	end)
end

return LobbyService