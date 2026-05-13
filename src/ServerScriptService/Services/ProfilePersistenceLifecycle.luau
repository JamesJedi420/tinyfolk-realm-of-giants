--!strict

local ProfilePersistenceLifecycle = {}

export type GatewayResult = {
	ok: boolean,
	operation: string,
	reason: string?,
	retryable: boolean?,
	profileKey: string?,
	data: any?,
}

export type StartResult = {
	ok: boolean,
	reason: string?,
}

type Logger = {
	warn: ((string) -> ())?,
}

type Gateway = {
	ConfigureOwnerLayer: (any) -> (),
	LoadPlayerProfile: (any) -> GatewayResult,
	SavePlayerProfile: (any) -> GatewayResult,
	ReleasePlayerProfile: (any) -> GatewayResult,
}

type PlayersService = {
	PlayerAdded: any,
	PlayerRemoving: any,
	GetPlayers: (any) -> { any },
}

type RuntimeGame = {
	GetService: (any, string) -> any,
	BindToClose: (any, () -> ()) -> (),
}

type StartConfig = {
	gateway: Gateway?,
	ownerLayer: any?,
	players: PlayersService?,
	game: RuntimeGame?,
	logger: Logger?,
}

local started = false
local trackedUserIds: { [number]: boolean } = {}
local cleanedUserIds: { [number]: boolean } = {}

local function makeResult(ok: boolean, reason: string?): StartResult
	return {
		ok = ok,
		reason = reason,
	}
end

local function getUserId(player: any): number?
	if type(player) ~= "table" and typeof(player) ~= "Instance" then
		return nil
	end

	local userId = player.UserId
	if type(userId) ~= "number" or userId ~= userId or userId == math.huge or userId == -math.huge or userId <= 0 or userId % 1 ~= 0 then
		return nil
	end

	return userId
end

local function logFailure(logger: Logger?, phase: string, userId: number?, result: GatewayResult)
	local message = string.format(
		"[ProfilePersistenceLifecycle] phase=%s userId=%s operation=%s reason=%s retryable=%s profileKey=%s",
		phase,
		if userId ~= nil then tostring(userId) else "nil",
		tostring(result.operation),
		tostring(result.reason),
		tostring(result.retryable),
		tostring(result.profileKey)
	)

	if logger ~= nil and type(logger.warn) == "function" then
		logger.warn(message)
	else
		warn(message)
	end
end

local function makeLifecycleFailure(operation: string, reason: string): GatewayResult
	return {
		ok = false,
		operation = operation,
		reason = reason,
		retryable = false,
	}
end

local function loadPlayer(gateway: Gateway, logger: Logger?, player: any)
	local userId = getUserId(player)
	if userId == nil then
		local result = gateway.LoadPlayerProfile(player)
		if not result.ok then
			logFailure(logger, "load", nil, result)
		end
		return
	end

	if trackedUserIds[userId] then
		logFailure(logger, "load", userId, makeLifecycleFailure("LoadPlayerProfile", "player_already_tracked"))
		return
	end

	trackedUserIds[userId] = true
	cleanedUserIds[userId] = nil

	local result = gateway.LoadPlayerProfile(player)
	if not result.ok then
		logFailure(logger, "load", userId, result)
	end
end

local function saveAndReleasePlayer(gateway: Gateway, logger: Logger?, player: any)
	local userId = getUserId(player)
	if userId ~= nil and cleanedUserIds[userId] then
		return
	end

	local saveResult = gateway.SavePlayerProfile(player)
	if not saveResult.ok then
		logFailure(logger, "save", userId, saveResult)
	end

	local releaseResult = gateway.ReleasePlayerProfile(player)
	if not releaseResult.ok then
		logFailure(logger, "release", userId, releaseResult)
	end

	if userId ~= nil then
		cleanedUserIds[userId] = true
		trackedUserIds[userId] = nil
	end
end

local function resolvePlayersService(config: StartConfig): PlayersService?
	if config.players ~= nil then
		return config.players
	end

	local runtimeGame = config.game or game
	if runtimeGame == nil or type(runtimeGame.GetService) ~= "function" then
		return nil
	end

	return runtimeGame:GetService("Players")
end

local function bindToClose(config: StartConfig, callback: () -> ())
	local runtimeGame = config.game or game
	if runtimeGame ~= nil and type(runtimeGame.BindToClose) == "function" then
		runtimeGame:BindToClose(callback)
	end
end

function ProfilePersistenceLifecycle.ResetForTests()
	started = false
	trackedUserIds = {}
	cleanedUserIds = {}
end

function ProfilePersistenceLifecycle.Start(config: StartConfig?): StartResult
	if started then
		return makeResult(true, "already_started")
	end

	if type(config) ~= "table" then
		return makeResult(false, "config_missing")
	end

	local gateway = config.gateway
	if type(gateway) ~= "table"
		or type(gateway.ConfigureOwnerLayer) ~= "function"
		or type(gateway.LoadPlayerProfile) ~= "function"
		or type(gateway.SavePlayerProfile) ~= "function"
		or type(gateway.ReleasePlayerProfile) ~= "function"
	then
		return makeResult(false, "gateway_missing")
	end

	if config.ownerLayer == nil then
		return makeResult(false, "owner_layer_missing")
	end

	local players = resolvePlayersService(config)
	if type(players) ~= "table"
		or type(players.GetPlayers) ~= "function"
		or type(players.PlayerAdded) ~= "table"
		or type(players.PlayerAdded.Connect) ~= "function"
		or type(players.PlayerRemoving) ~= "table"
		or type(players.PlayerRemoving.Connect) ~= "function"
	then
		return makeResult(false, "players_service_missing")
	end

	gateway.ConfigureOwnerLayer(config.ownerLayer)
	started = true

	players.PlayerAdded:Connect(function(player: any)
		loadPlayer(gateway, config.logger, player)
	end)

	players.PlayerRemoving:Connect(function(player: any)
		saveAndReleasePlayer(gateway, config.logger, player)
	end)

	for _, player in players:GetPlayers() do
		loadPlayer(gateway, config.logger, player)
	end

	bindToClose(config, function()
		for _, player in players:GetPlayers() do
			saveAndReleasePlayer(gateway, config.logger, player)
		end
	end)

	return makeResult(true, nil)
end

return ProfilePersistenceLifecycle
