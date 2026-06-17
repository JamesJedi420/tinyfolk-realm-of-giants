--!nocheck

local Players = game:GetService("Players")

local RoleConfig = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RoleConfig")
)
local SafeLocationProfileState = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Shared")
		:WaitForChild("Escape")
		:WaitForChild("SafeLocationProfileState")
)
local RealmSafeReturnState = require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Shared")
		:WaitForChild("GiantRealm")
		:WaitForChild("RealmSafeReturnState")
)

local RealmSafeReturnService = require(script.Parent.RealmSafeReturnService)
local ProfilePersistenceGateway = require(script.Parent.ProfilePersistenceGateway)

local ROLE_ATTRIBUTE = "Role"

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute(ROLE_ATTRIBUTE) == RoleConfig.Roles.Tinyfolk
end

local function resolvePendingReturnForPlayer(player: Player)
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
	local hasSafeLocation = profileResult.ok == true
		and type(profileResult.data) == "table"
		and SafeLocationProfileState.HasPersistedState(profileResult.data)

	RealmSafeReturnService.ResolvePendingReturnOnJoin(player.UserId, {
		hasSafeLocation = hasSafeLocation,
	})
end

local function handlePlayerLogout(player: Player)
	if not isTinyfolk(player) then
		return
	end

	RealmSafeReturnService.ApplyReturnRequest(player.UserId, {
		trigger = RealmSafeReturnState.ReturnTrigger.Logout,
		isOnline = false,
	})
end

local function handleServerShutdown()
	for _, player in Players:GetPlayers() do
		if isTinyfolk(player) then
			RealmSafeReturnService.ApplyReturnRequest(player.UserId, {
				trigger = RealmSafeReturnState.ReturnTrigger.ServerShutdown,
				isOnline = false,
			})
		end
	end
end

local function handleGiantDisconnect(player: Player)
	if player:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Giant then
		return
	end

	local candidateUserIds: { number } = {}
	for _, candidate in Players:GetPlayers() do
		if candidate.UserId ~= player.UserId then
			table.insert(candidateUserIds, candidate.UserId)
		end
	end

	RealmSafeReturnService.HandleGiantDisconnect(player.UserId, {
		candidateUserIds = candidateUserIds,
		isOnline = true,
	})
end

Players.PlayerAdded:Connect(function(player)
	resolvePendingReturnForPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	handlePlayerLogout(player)
	handleGiantDisconnect(player)
end)

if game ~= nil and type((game :: any).BindToClose) == "function" then
	(game :: any):BindToClose(function()
		handleServerShutdown()
	end)
end

for _, player in Players:GetPlayers() do
	resolvePendingReturnForPlayer(player)
end
