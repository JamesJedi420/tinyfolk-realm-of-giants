--!nocheck
local ProfilePersistenceLifecycle = require("../src/ServerScriptService/Services/ProfilePersistenceLifecycle")
local globalEnv: any = getfenv()

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function makePlayer(userId: number): any
	return {
		UserId = userId,
		Name = "Player" .. tostring(userId),
	}
end

local function makeSignal()
	local callbacks: { (any) -> () } = {}
	return {
		callbacks = callbacks,
		Connect = function(_self: any, callback: (any) -> ())
			table.insert(callbacks, callback)
			return {
				Disconnect = function() end,
			}
		end,
		Fire = function(_self: any, payload: any)
			for _, callback in ipairs(callbacks) do
				callback(payload)
			end
		end,
	}
end

local function makePlayers(initialPlayers: { any })
	local players = {
		players = initialPlayers,
		PlayerAdded = makeSignal(),
		PlayerRemoving = makeSignal(),
	}

	function players:GetPlayers(): { any }
		return self.players
	end

	return players
end

local function makeRuntimeGame()
	local bindToCloseCallbacks: { () -> () } = {}
	local runtimeGame = {
		bindToCloseCallbacks = bindToCloseCallbacks,
	}

	function runtimeGame:BindToClose(callback: () -> ())
		table.insert(bindToCloseCallbacks, callback)
	end

	return runtimeGame
end

local function makeGateway(overrides: any?): any
	local gateway = {
		calls = {},
		configuredOwnerLayer = nil,
	}

	function gateway.ConfigureOwnerLayer(ownerLayer: any)
		gateway.configuredOwnerLayer = ownerLayer
		table.insert(gateway.calls, {
			method = "ConfigureOwnerLayer",
			ownerLayer = ownerLayer,
		})
	end

	local function resultFor(methodName: string, player: any): any
		if overrides ~= nil and type(overrides[methodName]) == "function" then
			return overrides[methodName](player)
		end
		return {
			ok = true,
			operation = methodName,
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	function gateway.LoadPlayerProfile(player: any): any
		table.insert(gateway.calls, {
			method = "LoadPlayerProfile",
			player = player,
		})
		return resultFor("LoadPlayerProfile", player)
	end

	function gateway.SavePlayerProfile(player: any): any
		table.insert(gateway.calls, {
			method = "SavePlayerProfile",
			player = player,
		})
		return resultFor("SavePlayerProfile", player)
	end

	function gateway.ReleasePlayerProfile(player: any): any
		table.insert(gateway.calls, {
			method = "ReleasePlayerProfile",
			player = player,
		})
		return resultFor("ReleasePlayerProfile", player)
	end

	function gateway.SaveGiantRealmProfile(ownerUserId: number): any
		table.insert(gateway.calls, {
			method = "SaveGiantRealmProfile",
			ownerUserId = ownerUserId,
		})
		if overrides ~= nil and type(overrides.SaveGiantRealmProfile) == "function" then
			return overrides.SaveGiantRealmProfile(ownerUserId)
		end

		return {
			ok = true,
			operation = "SaveGiantRealmProfile",
			profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
		}
	end

	return gateway
end

local function makeAutosaveScheduler()
	local queue: { any } = {}
	local cancelCount = 0
	local scheduler = {
		queue = queue,
		cancelCount = function()
			return cancelCount
		end,
	}

	function scheduler.schedule(delaySeconds: number, callback: () -> ()): any
		local token = {
			delaySeconds = delaySeconds,
			callback = callback,
			cancelled = false,
		}
		table.insert(queue, token)
		return token
	end

	function scheduler.cancel(token: any)
		if token ~= nil then
			token.cancelled = true
			cancelCount += 1
		end
	end

	function scheduler.runNext(): boolean
		for index, token in ipairs(queue) do
			table.remove(queue, index)
			if token.cancelled ~= true then
				token.callback()
				return true
			end
		end

		return false
	end

	function scheduler.runNextByDelay(delaySeconds: number): boolean
		for index, token in ipairs(queue) do
			if token.delaySeconds == delaySeconds then
				table.remove(queue, index)
				if token.cancelled ~= true then
					token.callback()
					return true
				end
			end
		end

		return false
	end

	return scheduler
end

local function countQueuedTokensByDelay(scheduler: any, delaySeconds: number): number
	local count = 0
	for _, token in ipairs(scheduler.queue) do
		if token.cancelled ~= true and token.delaySeconds == delaySeconds then
			count += 1
		end
	end

	return count
end

local function makeLogger()
	local lines: { string } = {}
	return {
		lines = lines,
		warn = function(message: string)
			table.insert(lines, message)
		end,
	}
end

local function countCalls(gateway: any, methodName: string): number
	local count = 0
	for _, call in ipairs(gateway.calls) do
		if call.method == methodName then
			count += 1
		end
	end
	return count
end

local ownerLayer = {}

ProfilePersistenceLifecycle.ResetForTests()
assertEqual(ProfilePersistenceLifecycle.Start(nil).ok, false, "missing config fails")
assertEqual(
	ProfilePersistenceLifecycle.Start({ ownerLayer = ownerLayer, players = makePlayers({}) }).reason,
	"gateway_missing",
	"missing gateway"
)
assertEqual(
	ProfilePersistenceLifecycle.Start({ gateway = makeGateway(), players = makePlayers({}) }).reason,
	"owner_layer_missing",
	"missing owner"
)
assertEqual(
	ProfilePersistenceLifecycle.Start({ gateway = makeGateway(), ownerLayer = ownerLayer }).reason,
	"players_service_missing",
	"missing players"
)

ProfilePersistenceLifecycle.ResetForTests()
local playerA = makePlayer(101)
local playerB = makePlayer(202)
local players = makePlayers({ playerA, playerB })
local runtimeGame = makeRuntimeGame()
local gateway = makeGateway()
local logger = makeLogger()

local startResult = ProfilePersistenceLifecycle.Start({
	gateway = gateway,
	ownerLayer = ownerLayer,
	players = players,
	game = runtimeGame,
	logger = logger,
	autosaveEnabled = false,
})

assertEqual(startResult.ok, true, "start ok")
assertEqual(gateway.configuredOwnerLayer, ownerLayer, "owner layer configured")
assertEqual(countCalls(gateway, "ConfigureOwnerLayer"), 1, "configured once")
assertEqual(countCalls(gateway, "LoadPlayerProfile"), 2, "existing players loaded once")
assertEqual(#runtimeGame.bindToCloseCallbacks, 1, "bind to close")

local lifecycleQueryApi: any = globalEnv._ProfilePersistenceLifecycle_QueryAPI
assertTrue(type(lifecycleQueryApi) == "table", "lifecycle query API exposed")
assertTrue(type(lifecycleQueryApi.IsPlayerOwnershipReady) == "function", "lifecycle ownership readiness query exposed")
assertEqual(lifecycleQueryApi.IsPlayerOwnershipReady(101), true, "initial ownership ready for tracked player")

local ownershipCallbackReady = false
local ownershipCallbackReason: string? = nil
local registeredOwnershipCallback = lifecycleQueryApi.RegisterOwnershipReadyCallback(
	303,
	function(ready: boolean, reason: string?)
		ownershipCallbackReady = ready
		ownershipCallbackReason = reason
	end
)
assertEqual(registeredOwnershipCallback, true, "register ownership callback")

local duplicateStart = ProfilePersistenceLifecycle.Start({
	gateway = gateway,
	ownerLayer = ownerLayer,
	players = players,
	game = runtimeGame,
	logger = logger,
})
assertEqual(duplicateStart.ok, true, "duplicate start ok")
assertEqual(duplicateStart.reason, "already_started", "duplicate start reason")
assertEqual(countCalls(gateway, "ConfigureOwnerLayer"), 1, "duplicate start does not reconfigure")

players.PlayerAdded:Fire(playerA)
assertEqual(countCalls(gateway, "LoadPlayerProfile"), 2, "duplicate join does not double-load")
assertTrue(
	string.find(logger.lines[#logger.lines], "player_already_tracked", 1, true) ~= nil,
	"duplicate join logs warning"
)

local playerC = makePlayer(303)
table.insert(players.players, playerC)
players.PlayerAdded:Fire(playerC)
assertEqual(countCalls(gateway, "LoadPlayerProfile"), 3, "new join loads")
assertEqual(ownershipCallbackReady, true, "ownership callback fired for loaded player")
assertEqual(ownershipCallbackReason, nil, "ownership callback clears failure reason on success")

players.PlayerRemoving:Fire(playerC)
assertEqual(countCalls(gateway, "SavePlayerProfile"), 1, "removing saves")
assertEqual(countCalls(gateway, "ReleasePlayerProfile"), 1, "removing releases")
assertEqual(lifecycleQueryApi.IsPlayerOwnershipReady(303), false, "removed player ownership marked not ready")
assertEqual(
	lifecycleQueryApi.GetOwnershipFailureReason(303),
	"released_or_unloaded",
	"removed player ownership reason set"
)

runtimeGame.bindToCloseCallbacks[1]()
assertEqual(countCalls(gateway, "SavePlayerProfile"), 3, "shutdown saves remaining players only")
assertEqual(countCalls(gateway, "ReleasePlayerProfile"), 3, "shutdown releases remaining players only")

ProfilePersistenceLifecycle.ResetForTests()
local failureLogger = makeLogger()
local failurePlayers = makePlayers({})
local failureGateway = makeGateway({
	LoadPlayerProfile = function(_player: any): any
		return {
			ok = false,
			operation = "LoadPlayerProfile",
			reason = "profile_session_start_failed",
			retryable = true,
			profileKey = "PlayerProfile:404",
		}
	end,
	SavePlayerProfile = function(player: any): any
		return {
			ok = false,
			operation = "SavePlayerProfile",
			reason = "save_failed_for_test",
			retryable = true,
			profileKey = if type(player) == "table" then "PlayerProfile:" .. tostring(player.UserId) else nil,
		}
	end,
	ReleasePlayerProfile = function(player: any): any
		return {
			ok = true,
			operation = "ReleasePlayerProfile",
			profileKey = if type(player) == "table" then "PlayerProfile:" .. tostring(player.UserId) else nil,
		}
	end,
})

ProfilePersistenceLifecycle.Start({
	gateway = failureGateway,
	ownerLayer = ownerLayer,
	players = failurePlayers,
	game = makeRuntimeGame(),
	logger = failureLogger,
	autosaveEnabled = false,
})

local playerD = makePlayer(404)
failurePlayers.PlayerAdded:Fire(playerD)
assertEqual(countCalls(failureGateway, "LoadPlayerProfile"), 1, "failed load attempted")
assertTrue(string.find(failureLogger.lines[1], "phase=load", 1, true) ~= nil, "load failure logs phase")
assertTrue(
	string.find(failureLogger.lines[1], "profile_session_start_failed", 1, true) ~= nil,
	"load failure logs reason"
)
local failureLifecycleQueryApi: any = globalEnv._ProfilePersistenceLifecycle_QueryAPI
assertEqual(failureLifecycleQueryApi.IsPlayerOwnershipReady(404), false, "failed load ownership not ready")
assertEqual(
	failureLifecycleQueryApi.GetOwnershipFailureReason(404),
	"profile_session_start_failed",
	"failed load ownership reason set"
)

failurePlayers.PlayerRemoving:Fire(playerD)
assertEqual(countCalls(failureGateway, "SavePlayerProfile"), 1, "removing after failed load saves")
assertEqual(countCalls(failureGateway, "ReleasePlayerProfile"), 1, "release still runs after save failure")
assertTrue(string.find(failureLogger.lines[2], "phase=save", 1, true) ~= nil, "save failure logs phase")

local invalidPlayer: any = {}
failurePlayers.PlayerAdded:Fire(invalidPlayer)
assertEqual(countCalls(failureGateway, "LoadPlayerProfile"), 2, "invalid player passed to gateway")

ProfilePersistenceLifecycle.ResetForTests()
local autosaveLogger = makeLogger()
local autosavePlayers = makePlayers({ makePlayer(501), makePlayer(502) })
local autosaveGame = makeRuntimeGame()
local autosavePlayerAttemptsByUserId: { [number]: number } = {}
local autosaveGateway = makeGateway({
	SavePlayerProfile = function(player: any): any
		autosavePlayerAttemptsByUserId[player.UserId] = (autosavePlayerAttemptsByUserId[player.UserId] or 0) + 1

		if player.UserId == 502 then
			if autosavePlayerAttemptsByUserId[player.UserId] >= 2 then
				return {
					ok = true,
					operation = "SavePlayerProfile",
					profileKey = "PlayerProfile:502",
				}
			end

			return {
				ok = false,
				operation = "SavePlayerProfile",
				reason = "autosave_player_failure",
				retryable = true,
				profileKey = "PlayerProfile:502",
			}
		end

		return {
			ok = true,
			operation = "SavePlayerProfile",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end,
	SaveGiantRealmProfile = function(ownerUserId: number): any
		if ownerUserId == 9001 then
			return {
				ok = false,
				operation = "SaveGiantRealmProfile",
				reason = "autosave_realm_failure",
				retryable = true,
				profileKey = "GiantRealmProfile:9001",
			}
		end

		return {
			ok = true,
			operation = "SaveGiantRealmProfile",
			profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
		}
	end,
})
local autosaveScheduler = makeAutosaveScheduler()

globalEnv._RoleService_QueryAPI = {
	GetActiveGiantRealmOwnerUserId = function(): number?
		return 9001
	end,
}

local autosaveStartResult = ProfilePersistenceLifecycle.Start({
	gateway = autosaveGateway,
	ownerLayer = ownerLayer,
	players = autosavePlayers,
	game = autosaveGame,
	logger = autosaveLogger,
	autosaveEnabled = true,
	autosaveScheduler = autosaveScheduler,
	autosaveIntervalSeconds = 10,
	autosaveRetryInitialDelaySeconds = 3,
	autosaveRetryMaxDelaySeconds = 6,
	autosaveRetryMaxAttempts = 2,
})

assertEqual(autosaveStartResult.ok, true, "autosave start ok")
assertEqual(#autosaveScheduler.queue, 1, "autosave schedules first cycle")
assertEqual(autosaveScheduler.queue[1].delaySeconds, 10, "autosave interval propagated")
assertEqual(countCalls(autosaveGateway, "SavePlayerProfile"), 0, "autosave does not fire immediately")

autosaveScheduler.runNext()
assertEqual(countCalls(autosaveGateway, "SavePlayerProfile"), 2, "autosave cycle saves tracked players")
assertEqual(countCalls(autosaveGateway, "SaveGiantRealmProfile"), 1, "autosave cycle saves giant realm")
assertEqual(#autosaveScheduler.queue, 3, "autosave queues retries and next cycle")
assertEqual(countQueuedTokensByDelay(autosaveScheduler, 3), 2, "autosave queues two initial retries")
assertEqual(countQueuedTokensByDelay(autosaveScheduler, 10), 1, "autosave reschedules next cycle")
assertTrue(
	string.find(autosaveLogger.lines[1], "phase=autosave_player", 1, true) ~= nil,
	"autosave player failure logged"
)
assertTrue(
	string.find(autosaveLogger.lines[2], "phase=autosave_giant_realm", 1, true) ~= nil,
	"autosave giant failure logged"
)

assertEqual(autosaveScheduler.runNextByDelay(3), true, "player retry runs")
assertEqual(countCalls(autosaveGateway, "SavePlayerProfile"), 3, "player retry save succeeds")
assertEqual(countQueuedTokensByDelay(autosaveScheduler, 3), 1, "player retry clears after success")

assertEqual(autosaveScheduler.runNextByDelay(3), true, "giant retry first attempt runs")
assertEqual(countCalls(autosaveGateway, "SaveGiantRealmProfile"), 2, "giant retry first attempt saved")
assertEqual(countQueuedTokensByDelay(autosaveScheduler, 6), 1, "giant retry backoff delay applied")

assertEqual(autosaveScheduler.runNextByDelay(6), true, "giant retry second attempt runs")
assertEqual(countCalls(autosaveGateway, "SaveGiantRealmProfile"), 3, "giant retry second attempt saved")
assertEqual(countQueuedTokensByDelay(autosaveScheduler, 6), 0, "giant retry does not exceed max attempts")
assertTrue(
	string.find(autosaveLogger.lines[#autosaveLogger.lines], "phase=autosave_giant_realm_retry_exhausted", 1, true)
		~= nil,
	"giant retry exhaustion logged"
)

autosaveGame.bindToCloseCallbacks[1]()
assertEqual(autosaveScheduler.cancelCount(), 1, "shutdown cancels pending autosave callback")
assertEqual(countCalls(autosaveGateway, "SavePlayerProfile"), 5, "shutdown still saves tracked players")
assertEqual(countCalls(autosaveGateway, "ReleasePlayerProfile"), 2, "shutdown still releases tracked players")

ProfilePersistenceLifecycle.ResetForTests()
local cleanupLogger = makeLogger()
local cleanupPlayers = makePlayers({ makePlayer(701) })
local cleanupGame = makeRuntimeGame()
local cleanupScheduler = makeAutosaveScheduler()
local cleanupGiantOwnerUserId = 9101
local cleanupGateway = makeGateway({
	SavePlayerProfile = function(player: any): any
		if player.UserId == 701 then
			return {
				ok = false,
				operation = "SavePlayerProfile",
				reason = "cleanup_player_retryable_failure",
				retryable = true,
				profileKey = "PlayerProfile:701",
			}
		end

		return {
			ok = true,
			operation = "SavePlayerProfile",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end,
	SaveGiantRealmProfile = function(ownerUserId: number): any
		if ownerUserId == 9101 then
			return {
				ok = false,
				operation = "SaveGiantRealmProfile",
				reason = "cleanup_giant_retryable_failure",
				retryable = true,
				profileKey = "GiantRealmProfile:9101",
			}
		end

		return {
			ok = true,
			operation = "SaveGiantRealmProfile",
			profileKey = "GiantRealmProfile:" .. tostring(ownerUserId),
		}
	end,
})

globalEnv._RoleService_QueryAPI = {
	GetActiveGiantRealmOwnerUserId = function(): number?
		return cleanupGiantOwnerUserId
	end,
}

local cleanupStartResult = ProfilePersistenceLifecycle.Start({
	gateway = cleanupGateway,
	ownerLayer = ownerLayer,
	players = cleanupPlayers,
	game = cleanupGame,
	logger = cleanupLogger,
	autosaveEnabled = true,
	autosaveScheduler = cleanupScheduler,
	autosaveIntervalSeconds = 10,
	autosaveRetryInitialDelaySeconds = 3,
	autosaveRetryMaxDelaySeconds = 6,
	autosaveRetryMaxAttempts = 2,
})

assertEqual(cleanupStartResult.ok, true, "cleanup start ok")
cleanupScheduler.runNext()
assertEqual(countQueuedTokensByDelay(cleanupScheduler, 3), 2, "cleanup cycle queues player and giant retries")

cleanupPlayers.PlayerRemoving:Fire(cleanupPlayers.players[1])
assertEqual(countQueuedTokensByDelay(cleanupScheduler, 3), 1, "player removal clears pending player retry")

cleanupGiantOwnerUserId = 9102
assertEqual(cleanupScheduler.runNextByDelay(10), true, "next autosave cycle runs")
assertEqual(countQueuedTokensByDelay(cleanupScheduler, 3), 0, "owner switch clears stale giant retry")

globalEnv._RoleService_QueryAPI = nil

print("profile_persistence_lifecycle: all checks passed")
