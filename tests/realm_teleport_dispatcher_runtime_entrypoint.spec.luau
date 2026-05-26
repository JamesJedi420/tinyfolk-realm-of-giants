--!nocheck

local RealmTeleportDispatcher = require("../src/ServerScriptService/Services/RealmTeleportDispatcher")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local handoffCalls = {}
local reserveCalls = 0
local teleportCalls = 0
local fakePlayersByUserId = {
	[101] = { UserId = 101, Name = "Player101" },
	[102] = { UserId = 102, Name = "Player102" },
}

local dispatcher = RealmTeleportDispatcher.Create({
	partyResolver = function(partyId: string): { number }
		if partyId == "party-good" then
			return { 101, 102 }
		end
		return {}
	end,
	playersService = {
		GetPlayerByUserId = function(_self: any, userId: number): any
			return fakePlayersByUserId[userId]
		end,
	},
	handoffApi = {
		BeginCrossServerHandoff = function(player: any, _context: any): any
			table.insert(handoffCalls, player.UserId)
			if player.UserId == 102 then
				return {
					ok = true,
					handoffToken = "token-102",
				}
			end
			return {
				ok = true,
				handoffToken = "token-101",
			}
		end,
	},
	teleportService = {
		ReserveServer = function(_self: any, placeId: number): string
			reserveCalls += 1
			assertEqual(placeId, 12345, "reserve place id")
			return "reserved-access-code"
		end,
		TeleportToPrivateServer = function(
			_self: any,
			placeId: number,
			accessCode: string,
			players: { any },
			_spawnName: any,
			teleportData: any
		)
			teleportCalls += 1
			assertEqual(placeId, 12345, "teleport place id")
			assertEqual(accessCode, "reserved-access-code", "teleport access code")
			assertEqual(#players, 2, "teleport player count")
			assertEqual(teleportData.partyId, "party-good", "teleport data party id")
		end,
	},
	destinationResolver = function(_entry: any): any
		return {
			placeId = 12345,
		}
	end,
})

local accepted = dispatcher.Dispatch({
	operationId = "op-accept",
	partyId = "party-good",
	targetRealmId = "realm-100",
})
assertEqual(accepted.ok, true, "accepted dispatch ok")
assertEqual(accepted.retryable, false, "accepted dispatch retryable false")
assertEqual(accepted.reason, "accepted", "accepted dispatch reason")
assertEqual(reserveCalls, 1, "reserve called once")
assertEqual(teleportCalls, 1, "teleport called once")
assertEqual(#handoffCalls, 2, "handoff called per player")

local missingParty = dispatcher.Dispatch({
	operationId = "op-missing-party",
	partyId = "party-missing",
	targetRealmId = "realm-100",
})
assertEqual(missingParty.ok, false, "missing party dispatch rejected")
assertEqual(missingParty.retryable, true, "missing party dispatch retryable")
assertEqual(missingParty.reason, "party_members_unavailable", "missing party dispatch reason")

local missingOperation = dispatcher.Dispatch({
	operationId = "",
	partyId = "party-good",
	targetRealmId = "realm-100",
})
assertEqual(missingOperation.ok, false, "missing operation rejected")
assertEqual(missingOperation.retryable, false, "missing operation non-retryable")
assertEqual(missingOperation.reason, "operation_id_invalid", "missing operation reason")

local noHandoffDispatcher = RealmTeleportDispatcher.Create({
	partyResolver = function(_partyId: string): { number }
		return { 101 }
	end,
	playersService = {
		GetPlayerByUserId = function(_self: any, userId: number): any
			return fakePlayersByUserId[userId]
		end,
	},
	teleportService = {
		ReserveServer = function(_self: any, _placeId: number): string
			return "code"
		end,
		TeleportToPrivateServer = function(
			_self: any,
			_placeId: number,
			_accessCode: string,
			_players: { any },
			_spawnName: any,
			_teleportData: any
		)
			return
		end,
	},
	destinationResolver = function(_entry: any): any
		return {
			placeId = 12345,
		}
	end,
})

local noHandoff = noHandoffDispatcher.Dispatch({
	operationId = "op-no-handoff",
	partyId = "party-good",
	targetRealmId = "realm-100",
})
assertEqual(noHandoff.ok, false, "missing handoff api rejected")
assertEqual(noHandoff.retryable, true, "missing handoff api retryable")
assertEqual(noHandoff.reason, "handoff_api_unavailable", "missing handoff api reason")

local globalEnv: any = getfenv()
globalEnv._RealmAdmissionPartyResolver_QueryAPI = {
	ResolvePartyMemberUserIds = function(partyId: string, _entry: any): { number }
		if partyId == "party-global" then
			return { 101 }
		end
		return {}
	end,
}

local globalResolverReserveCalls = 0
local globalResolverTeleportCalls = 0

local globalResolverDispatcher = RealmTeleportDispatcher.Create({
	playersService = {
		GetPlayerByUserId = function(_self: any, userId: number): any
			return fakePlayersByUserId[userId]
		end,
	},
	handoffApi = {
		BeginCrossServerHandoff = function(_player: any, _context: any): any
			return {
				ok = true,
				handoffToken = "token-global",
			}
		end,
	},
	teleportService = {
		ReserveServer = function(_self: any, _placeId: number): string
			globalResolverReserveCalls += 1
			return "code-global"
		end,
		TeleportToPrivateServer = function(
			_self: any,
			_placeId: number,
			_accessCode: string,
			_players: { any },
			_spawnName: any,
			_teleportData: any
		)
			globalResolverTeleportCalls += 1
			return
		end,
	},
	destinationResolver = function(_entry: any): any
		return {
			placeId = 12345,
		}
	end,
})

local globalResolverResult = globalResolverDispatcher.Dispatch({
	operationId = "op-global",
	partyId = "party-global",
	targetRealmId = "realm-100",
})
assertEqual(globalResolverResult.ok, true, "global resolver dispatch accepted")
assertEqual(globalResolverReserveCalls, 1, "global resolver reserve called")
assertEqual(globalResolverTeleportCalls, 1, "global resolver teleport called")

print("realm_teleport_dispatcher_runtime_entrypoint: all checks passed")
