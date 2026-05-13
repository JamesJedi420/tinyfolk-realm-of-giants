--!strict

local ProfilePersistenceLifecycle = require("../src/ServerScriptService/Services/ProfilePersistenceLifecycle")

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
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

	return gateway
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
assertEqual(ProfilePersistenceLifecycle.Start({ ownerLayer = ownerLayer, players = makePlayers({}) }).reason, "gateway_missing", "missing gateway")
assertEqual(ProfilePersistenceLifecycle.Start({ gateway = makeGateway(), players = makePlayers({}) }).reason, "owner_layer_missing", "missing owner")
assertEqual(ProfilePersistenceLifecycle.Start({ gateway = makeGateway(), ownerLayer = ownerLayer }).reason, "players_service_missing", "missing players")

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
})

assertEqual(startResult.ok, true, "start ok")
assertEqual(gateway.configuredOwnerLayer, ownerLayer, "owner layer configured")
assertEqual(countCalls(gateway, "ConfigureOwnerLayer"), 1, "configured once")
assertEqual(countCalls(gateway, "LoadPlayerProfile"), 2, "existing players loaded once")
assertEqual(#runtimeGame.bindToCloseCallbacks, 1, "bind to close")

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
assertTrue(string.find(logger.lines[#logger.lines], "player_already_tracked", 1, true) ~= nil, "duplicate join logs warning")

local playerC = makePlayer(303)
table.insert(players.players, playerC)
players.PlayerAdded:Fire(playerC)
assertEqual(countCalls(gateway, "LoadPlayerProfile"), 3, "new join loads")

players.PlayerRemoving:Fire(playerC)
assertEqual(countCalls(gateway, "SavePlayerProfile"), 1, "removing saves")
assertEqual(countCalls(gateway, "ReleasePlayerProfile"), 1, "removing releases")

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
})

local playerD = makePlayer(404)
failurePlayers.PlayerAdded:Fire(playerD)
assertEqual(countCalls(failureGateway, "LoadPlayerProfile"), 1, "failed load attempted")
assertTrue(string.find(failureLogger.lines[1], "phase=load", 1, true) ~= nil, "load failure logs phase")
assertTrue(string.find(failureLogger.lines[1], "profile_session_start_failed", 1, true) ~= nil, "load failure logs reason")

failurePlayers.PlayerRemoving:Fire(playerD)
assertEqual(countCalls(failureGateway, "SavePlayerProfile"), 1, "removing after failed load saves")
assertEqual(countCalls(failureGateway, "ReleasePlayerProfile"), 1, "release still runs after save failure")
assertTrue(string.find(failureLogger.lines[2], "phase=save", 1, true) ~= nil, "save failure logs phase")

local invalidPlayer: any = {}
failurePlayers.PlayerAdded:Fire(invalidPlayer)
assertEqual(countCalls(failureGateway, "LoadPlayerProfile"), 2, "invalid player passed to gateway")

print("profile_persistence_lifecycle: all checks passed")
