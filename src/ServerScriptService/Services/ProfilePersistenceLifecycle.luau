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
	SaveGiantRealmProfile: (any) -> GatewayResult,
}

type AutosaveScheduler = {
	schedule: (number, () -> ()) -> any,
	cancel: ((any) -> ())?,
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
	autosaveEnabled: boolean?,
	autosaveIntervalSeconds: number?,
	autosaveScheduler: AutosaveScheduler?,
	autosaveRetryInitialDelaySeconds: number?,
	autosaveRetryMaxDelaySeconds: number?,
	autosaveRetryMaxAttempts: number?,
}

type AutosaveRetryPolicy = {
	initialDelaySeconds: number,
	maxDelaySeconds: number,
	maxAttempts: number,
}

type AutosaveRetryState = {
	attempts: number,
	token: any?,
}

local LOAD_FAILURE_SAFE_ROUTE = "safe_fallback"
local DEFAULT_AUTOSAVE_INTERVAL_SECONDS = 60
local DEFAULT_AUTOSAVE_RETRY_INITIAL_DELAY_SECONDS = 2
local DEFAULT_AUTOSAVE_RETRY_MAX_DELAY_SECONDS = 30
local DEFAULT_AUTOSAVE_RETRY_MAX_ATTEMPTS = 3
local globalEnv: any = getfenv()

local started = false
local trackedUserIds: { [number]: boolean } = {}
local cleanedUserIds: { [number]: boolean } = {}
local ownershipReadyByUserId: { [number]: boolean } = {}
local ownershipFailureReasonByUserId: { [number]: string? } = {}
local loadFailureRouteByUserId: { [number]: string? } = {}
local ownershipReadyCallbacksByUserId: { [number]: { (boolean, string?) -> () }? } = {}
local autosaveScheduler: AutosaveScheduler? = nil
local autosaveScheduledToken: any = nil
local autosaveLoopActive = false
local autosaveRetryPolicy: AutosaveRetryPolicy = {
	initialDelaySeconds = DEFAULT_AUTOSAVE_RETRY_INITIAL_DELAY_SECONDS,
	maxDelaySeconds = DEFAULT_AUTOSAVE_RETRY_MAX_DELAY_SECONDS,
	maxAttempts = DEFAULT_AUTOSAVE_RETRY_MAX_ATTEMPTS,
}
local autosaveRetryStatesByKey: { [string]: AutosaveRetryState } = {}

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
	if
		type(userId) ~= "number"
		or userId ~= userId
		or userId == math.huge
		or userId == -math.huge
		or userId <= 0
		or userId % 1 ~= 0
	then
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

local function defaultAutosaveSchedule(delaySeconds: number, callback: () -> ()): any
	if task ~= nil and type(task.delay) == "function" then
		return task.delay(delaySeconds, callback)
	end

	callback()
	return nil
end

local function defaultAutosaveCancel(token: any)
	if token == nil then
		return
	end

	if task ~= nil and type(task.cancel) == "function" then
		pcall(function()
			task.cancel(token)
		end)
	end
end

local function notifyOwnershipCallbacks(userId: number)
	local callbacks = ownershipReadyCallbacksByUserId[userId]
	if callbacks == nil or #callbacks == 0 then
		return
	end

	local ready = ownershipReadyByUserId[userId] == true
	local reason = ownershipFailureReasonByUserId[userId]
	for _, callback in ipairs(callbacks) do
		pcall(callback, ready, reason)
	end
end

local function setOwnershipState(userId: number, ready: boolean, reason: string?)
	ownershipReadyByUserId[userId] = ready
	ownershipFailureReasonByUserId[userId] = reason
	notifyOwnershipCallbacks(userId)
end

local function clearOwnershipCallbacks(userId: number)
	ownershipReadyCallbacksByUserId[userId] = nil
end

local function clearLoadFailureRoute(userId: number)
	loadFailureRouteByUserId[userId] = nil
end

local function setLoadFailureRoute(userId: number)
	loadFailureRouteByUserId[userId] = LOAD_FAILURE_SAFE_ROUTE
end

local function registerOwnershipReadyCallback(userId: number, callback: any): boolean
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
		return false
	end
	if type(callback) ~= "function" then
		return false
	end

	local callbacks = ownershipReadyCallbacksByUserId[userId]
	if callbacks == nil then
		callbacks = {}
		ownershipReadyCallbacksByUserId[userId] = callbacks
	end
	table.insert(callbacks, callback)

	if ownershipReadyByUserId[userId] ~= nil then
		pcall(callback, ownershipReadyByUserId[userId] == true, ownershipFailureReasonByUserId[userId])
	end

	return true
end

globalEnv._ProfilePersistenceLifecycle_QueryAPI = {
	IsPlayerOwnershipReady = function(userId: number): boolean
		return ownershipReadyByUserId[userId] == true
	end,
	GetOwnershipFailureReason = function(userId: number): string?
		return ownershipFailureReasonByUserId[userId]
	end,
	GetLoadFailureRoute = function(userId: number): string?
		return loadFailureRouteByUserId[userId]
	end,
	RegisterOwnershipReadyCallback = function(userId: number, callback: any): boolean
		return registerOwnershipReadyCallback(userId, callback)
	end,
}

local function getAutosaveScheduler(config: StartConfig): AutosaveScheduler
	if config.autosaveScheduler ~= nil then
		return config.autosaveScheduler
	end

	return {
		schedule = defaultAutosaveSchedule,
		cancel = defaultAutosaveCancel,
	}
end

local function stopAutosaveLoop()
	autosaveLoopActive = false
	if autosaveScheduler ~= nil and type(autosaveScheduler.cancel) == "function" and autosaveScheduledToken ~= nil then
		autosaveScheduler.cancel(autosaveScheduledToken)
	end
	autosaveScheduledToken = nil

	if autosaveScheduler ~= nil and type(autosaveScheduler.cancel) == "function" then
		for _, retryState in autosaveRetryStatesByKey do
			if retryState.token ~= nil then
				autosaveScheduler.cancel(retryState.token)
				retryState.token = nil
			end
		end
	end

	autosaveRetryStatesByKey = {}
end

local function getActiveGiantRealmOwnerUserId(): number?
	local globalValue: any = globalEnv
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RoleService_QueryAPI
	if type(queryApi) ~= "table" or type(queryApi.GetActiveGiantRealmOwnerUserId) ~= "function" then
		return nil
	end

	local ok, ownerUserId = pcall(function()
		return queryApi.GetActiveGiantRealmOwnerUserId()
	end)

	if not ok then
		return nil
	end

	if type(ownerUserId) ~= "number" or ownerUserId <= 0 or ownerUserId % 1 ~= 0 then
		return nil
	end

	return ownerUserId
end

local function makeLifecycleFailure(operation: string, reason: string): GatewayResult
	return {
		ok = false,
		operation = operation,
		reason = reason,
		retryable = false,
	}
end

local function makePlayerRetryKey(userId: number): string
	return string.format("player:%d", userId)
end

local function makeGiantRetryKey(ownerUserId: number): string
	return string.format("giant:%d", ownerUserId)
end

local clearRetryState: (retryKey: string) -> ()
local scheduleAutosaveRetry: (
	logger: Logger?,
	retryKey: string,
	phasePrefix: string,
	userId: number,
	saveAttempt: () -> GatewayResult
) -> ()

local function clearStaleGiantRetryStates(activeOwnerUserId: number?)
	local activeRetryKey = if activeOwnerUserId ~= nil then makeGiantRetryKey(activeOwnerUserId) else nil

	for retryKey, _ in autosaveRetryStatesByKey do
		if string.sub(retryKey, 1, 6) == "giant:" and retryKey ~= activeRetryKey then
			clearRetryState(retryKey)
		end
	end
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
		setLoadFailureRoute(userId)
		setOwnershipState(userId, false, tostring(result.reason or "load_failed"))
		logFailure(logger, "load", userId, result)
		return
	end

	clearLoadFailureRoute(userId)
	setOwnershipState(userId, true, nil)
end

local function saveAndReleasePlayer(gateway: Gateway, logger: Logger?, player: any)
	local userId = getUserId(player)
	if userId ~= nil then
		clearRetryState(makePlayerRetryKey(userId))
		clearLoadFailureRoute(userId)
		setOwnershipState(userId, false, "released_or_unloaded")
		clearOwnershipCallbacks(userId)
	end

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

local function saveTrackedProfiles(gateway: Gateway, logger: Logger?, players: PlayersService)
	local playersByUserId: { [number]: any } = {}
	for _, player in players:GetPlayers() do
		local userId = getUserId(player)
		if userId ~= nil then
			playersByUserId[userId] = player
		end
	end

	for userId, isTracked in trackedUserIds do
		if isTracked and not cleanedUserIds[userId] then
			local player = playersByUserId[userId]
			if player ~= nil then
				local retryKey = makePlayerRetryKey(userId)
				local saveResult = gateway.SavePlayerProfile(player)
				if not saveResult.ok then
					logFailure(logger, "autosave_player", userId, saveResult)
					if saveResult.retryable == true then
						scheduleAutosaveRetry(logger, retryKey, "autosave_player", userId, function(): GatewayResult
							return gateway.SavePlayerProfile(player)
						end)
					else
						clearRetryState(retryKey)
					end
				else
					clearRetryState(retryKey)
				end
			end
		end
	end

	local activeGiantOwnerUserId = getActiveGiantRealmOwnerUserId()
	clearStaleGiantRetryStates(activeGiantOwnerUserId)
	if activeGiantOwnerUserId ~= nil then
		local giantRetryKey = makeGiantRetryKey(activeGiantOwnerUserId)
		local giantSaveResult = gateway.SaveGiantRealmProfile(activeGiantOwnerUserId)
		if not giantSaveResult.ok then
			logFailure(logger, "autosave_giant_realm", activeGiantOwnerUserId, giantSaveResult)
			if giantSaveResult.retryable == true then
				scheduleAutosaveRetry(
					logger,
					giantRetryKey,
					"autosave_giant_realm",
					activeGiantOwnerUserId,
					function(): GatewayResult
						return gateway.SaveGiantRealmProfile(activeGiantOwnerUserId)
					end
				)
			else
				clearRetryState(giantRetryKey)
			end
		else
			clearRetryState(giantRetryKey)
		end
	end
end

local function resolveAutosaveIntervalSeconds(config: StartConfig): number
	local configured = config.autosaveIntervalSeconds
	if type(configured) == "number" and configured > 0 and configured == configured and configured < math.huge then
		return configured
	end

	return DEFAULT_AUTOSAVE_INTERVAL_SECONDS
end

local function resolveAutosaveRetryPolicy(config: StartConfig): AutosaveRetryPolicy
	local initialDelaySeconds = DEFAULT_AUTOSAVE_RETRY_INITIAL_DELAY_SECONDS
	if
		type(config.autosaveRetryInitialDelaySeconds) == "number"
		and config.autosaveRetryInitialDelaySeconds > 0
		and config.autosaveRetryInitialDelaySeconds == config.autosaveRetryInitialDelaySeconds
		and config.autosaveRetryInitialDelaySeconds < math.huge
	then
		initialDelaySeconds = config.autosaveRetryInitialDelaySeconds
	end

	local maxDelaySeconds = DEFAULT_AUTOSAVE_RETRY_MAX_DELAY_SECONDS
	if
		type(config.autosaveRetryMaxDelaySeconds) == "number"
		and config.autosaveRetryMaxDelaySeconds > 0
		and config.autosaveRetryMaxDelaySeconds == config.autosaveRetryMaxDelaySeconds
		and config.autosaveRetryMaxDelaySeconds < math.huge
	then
		maxDelaySeconds = config.autosaveRetryMaxDelaySeconds
	end

	if maxDelaySeconds < initialDelaySeconds then
		maxDelaySeconds = initialDelaySeconds
	end

	local maxAttempts = DEFAULT_AUTOSAVE_RETRY_MAX_ATTEMPTS
	if
		type(config.autosaveRetryMaxAttempts) == "number"
		and config.autosaveRetryMaxAttempts > 0
		and config.autosaveRetryMaxAttempts == config.autosaveRetryMaxAttempts
		and config.autosaveRetryMaxAttempts < math.huge
		and config.autosaveRetryMaxAttempts % 1 == 0
	then
		maxAttempts = config.autosaveRetryMaxAttempts
	end

	return {
		initialDelaySeconds = initialDelaySeconds,
		maxDelaySeconds = maxDelaySeconds,
		maxAttempts = maxAttempts,
	}
end

local function computeRetryDelaySeconds(policy: AutosaveRetryPolicy, attempts: number): number
	local rawDelay = policy.initialDelaySeconds * math.pow(2, math.max(attempts - 1, 0))
	if rawDelay > policy.maxDelaySeconds then
		return policy.maxDelaySeconds
	end

	return rawDelay
end

clearRetryState = function(retryKey: string)
	local retryState = autosaveRetryStatesByKey[retryKey]
	if retryState == nil then
		return
	end

	if autosaveScheduler ~= nil and type(autosaveScheduler.cancel) == "function" and retryState.token ~= nil then
		autosaveScheduler.cancel(retryState.token)
	end

	autosaveRetryStatesByKey[retryKey] = nil
end

scheduleAutosaveRetry = function(
	logger: Logger?,
	retryKey: string,
	phasePrefix: string,
	userId: number,
	saveAttempt: () -> GatewayResult
)
	local scheduler = autosaveScheduler
	if scheduler == nil then
		return
	end

	local retryState = autosaveRetryStatesByKey[retryKey]
	if retryState == nil then
		retryState = {
			attempts = 0,
			token = nil,
		}
		autosaveRetryStatesByKey[retryKey] = retryState
	end

	if retryState.token ~= nil then
		return
	end

	if retryState.attempts >= autosaveRetryPolicy.maxAttempts then
		logFailure(logger, phasePrefix .. "_retry_exhausted", userId, {
			ok = false,
			operation = "AutosaveRetry",
			reason = "retry_attempts_exhausted",
			retryable = false,
			profileKey = nil,
			data = nil,
		})
		return
	end

	retryState.attempts += 1
	local nextDelaySeconds = computeRetryDelaySeconds(autosaveRetryPolicy, retryState.attempts)
	retryState.token = scheduler.schedule(nextDelaySeconds, function()
		retryState.token = nil
		if not autosaveLoopActive then
			return
		end

		local retryResult = saveAttempt()
		if retryResult.ok then
			autosaveRetryStatesByKey[retryKey] = nil
			return
		end

		logFailure(logger, phasePrefix .. "_retry", userId, retryResult)
		if retryResult.retryable == true then
			scheduleAutosaveRetry(logger, retryKey, phasePrefix, userId, saveAttempt)
		else
			autosaveRetryStatesByKey[retryKey] = nil
		end
	end)
end

local function startAutosaveLoop(gateway: Gateway, logger: Logger?, players: PlayersService, intervalSeconds: number)
	if autosaveScheduler == nil then
		return
	end

	autosaveLoopActive = true

	local function scheduleNext()
		if not autosaveLoopActive then
			return
		end

		autosaveScheduledToken = autosaveScheduler.schedule(intervalSeconds, function()
			autosaveScheduledToken = nil
			if not autosaveLoopActive then
				return
			end

			saveTrackedProfiles(gateway, logger, players)
			scheduleNext()
		end)
	end

	scheduleNext()
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
	stopAutosaveLoop()
	autosaveScheduler = nil
	autosaveRetryPolicy = {
		initialDelaySeconds = DEFAULT_AUTOSAVE_RETRY_INITIAL_DELAY_SECONDS,
		maxDelaySeconds = DEFAULT_AUTOSAVE_RETRY_MAX_DELAY_SECONDS,
		maxAttempts = DEFAULT_AUTOSAVE_RETRY_MAX_ATTEMPTS,
	}
	started = false
	trackedUserIds = {}
	cleanedUserIds = {}
	ownershipReadyByUserId = {}
	ownershipFailureReasonByUserId = {}
	loadFailureRouteByUserId = {}
	ownershipReadyCallbacksByUserId = {}
end

function ProfilePersistenceLifecycle.Start(config: StartConfig?): StartResult
	if started then
		return makeResult(true, "already_started")
	end

	if type(config) ~= "table" then
		return makeResult(false, "config_missing")
	end

	local gateway = config.gateway
	if
		type(gateway) ~= "table"
		or type(gateway.ConfigureOwnerLayer) ~= "function"
		or type(gateway.LoadPlayerProfile) ~= "function"
		or type(gateway.SavePlayerProfile) ~= "function"
		or type(gateway.ReleasePlayerProfile) ~= "function"
		or type(gateway.SaveGiantRealmProfile) ~= "function"
	then
		return makeResult(false, "gateway_missing")
	end

	if config.ownerLayer == nil then
		return makeResult(false, "owner_layer_missing")
	end

	local players = resolvePlayersService(config)
	if
		type(players) ~= "table"
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
	autosaveScheduler = getAutosaveScheduler(config)
	autosaveRetryPolicy = resolveAutosaveRetryPolicy(config)

	players.PlayerAdded:Connect(function(player: any)
		loadPlayer(gateway, config.logger, player)
	end)

	players.PlayerRemoving:Connect(function(player: any)
		saveAndReleasePlayer(gateway, config.logger, player)
	end)

	for _, player in players:GetPlayers() do
		loadPlayer(gateway, config.logger, player)
	end

	if config.autosaveEnabled ~= false then
		startAutosaveLoop(gateway, config.logger, players, resolveAutosaveIntervalSeconds(config))
	end

	bindToClose(config, function()
		stopAutosaveLoop()
		for _, player in players:GetPlayers() do
			saveAndReleasePlayer(gateway, config.logger, player)
		end
	end)

	return makeResult(true, nil)
end

return ProfilePersistenceLifecycle
