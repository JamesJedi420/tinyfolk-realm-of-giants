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
	[101] = { UserId = 101, Name = "Player101", _Attributes = { Role = "Tinyfolk" } },
	[102] = { UserId = 102, Name = "Player102", _Attributes = { Role = "Giant" } },
}

for _, player in pairs(fakePlayersByUserId) do
	function player:GetAttribute(attributeName: string): any
		return self._Attributes[attributeName]
	end
end

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
			assertEqual(type(teleportData.tinyfolkToolLoadoutByUserId), "table", "teleport tinyfolk payload attached")
			assertEqual(
				teleportData.tinyfolkToolLoadoutByUserId[101].tools[1].toolId,
				"grappling_hook",
				"teleport tinyfolk payload includes tool"
			)
			assertEqual(
				teleportData.tinyfolkToolLoadoutByUserId[102],
				nil,
				"teleport payload excludes non-tinyfolk user"
			)
		end,
	},
	tinyfolkToolLoadoutApi = {
		BuildEntryPayload = function(player: any, operationId: string): any
			if player.UserId ~= 101 then
				return {
					accepted = false,
					reason = "tinyfolk_role_required",
					payload = nil,
				}
			end
			return {
				accepted = true,
				reason = "accepted",
				payload = {
					schemaVersion = 1,
					ownerUserId = 101,
					role = "Tinyfolk",
					source = "shared_hub_loadout",
					transferId = "tool_loadout:101:" .. operationId,
					tools = {
						{
							slotId = "tool_1",
							toolId = "grappling_hook",
							displayName = "Grappling Hook",
							categories = { "escape" },
							cooldownSeconds = 30,
							cooldownReadyAt = 0,
						},
					},
					validation = {
						validatedAt = 100,
						catalogVersion = "tinyfolk_tools_v1",
						loadoutStateVersion = 1,
					},
				},
			}
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

do
	local telemetryTeleportCalls = 0
	local dispatcherWithPayloadFailure = RealmTeleportDispatcher.Create({
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
			ReserveServer = function(_self: any, _placeId: number): string
				return "reserved-access-code-telemetry"
			end,
			TeleportToPrivateServer = function(
				_self: any,
				_placeId: number,
				_accessCode: string,
				_players: { any },
				_spawnName: any,
				teleportData: any
			)
				telemetryTeleportCalls += 1
				assertEqual(teleportData.tinyfolkToolLoadoutByUserId, nil, "payload omitted on build failure")
				assertEqual(
					type(teleportData.tinyfolkToolPayloadFailures),
					"table",
					"payload failure diagnostics attached"
				)
				assertEqual(teleportData.tinyfolkToolPayloadFailures[1].userId, 101, "failure diagnostic user id")
				assertEqual(
					teleportData.tinyfolkToolPayloadFailures[1].reason,
					"payload_invalid",
					"failure diagnostic reason"
				)
			end,
		},
		tinyfolkToolLoadoutApi = {
			BuildEntryPayload = function(player: any, _operationId: string): any
				if player.UserId == 101 then
					return {
						accepted = false,
						reason = "tool_cooldown_metadata_missing",
						payload = nil,
					}
				end
				return {
					accepted = false,
					reason = "tinyfolk_role_required",
					payload = nil,
				}
			end,
		},
		destinationResolver = function(_entry: any): any
			return {
				placeId = 12345,
			}
		end,
	})

	local acceptedWithDiagnostics = dispatcherWithPayloadFailure.Dispatch({
		operationId = "op-telemetry",
		partyId = "party-good",
		targetRealmId = "realm-100",
	})
	assertEqual(acceptedWithDiagnostics.ok, true, "dispatch still accepted on payload failure")
	assertEqual(acceptedWithDiagnostics.reason, "accepted", "dispatch reason still accepted")
	assertEqual(telemetryTeleportCalls, 1, "teleport still executes on payload failure")
	assertEqual(
		type(acceptedWithDiagnostics.tinyfolkToolPayloadFailures),
		"table",
		"result surfaces payload failure diagnostics"
	)
	assertEqual(
		acceptedWithDiagnostics.tinyfolkToolPayloadFailures[1].reason,
		"payload_invalid",
		"result payload failure reason surfaced"
	)
end

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

do
	local hubReserveCalls = 0
	local hubTeleportAccessCode: string? = nil
	local hubDispatcher = RealmTeleportDispatcher.Create({
		partyResolver = function(partyId: string): { number }
			if partyId == "party-good" then
				return { 101 }
			end
			return {}
		end,
		playersService = {
			GetPlayerByUserId = function(_self: any, userId: number): any
				return fakePlayersByUserId[userId]
			end,
		},
		handoffApi = {
			BeginCrossServerHandoff = function(_player: any, _context: any): any
				return {
					ok = true,
					handoffToken = "token-101",
				}
			end,
		},
		listLiveRealmAvailability = function(_limit: number?, _at: number?): { any }
			return {
				{
					realmId = "realm-100",
					ownerUserId = 100,
					privateServerId = "registry-access-code",
					accessMode = "private",
					playerCount = 1,
					capacity = 8,
					dangerRating = 0.5,
					lifecycle = "active",
					isAvailable = true,
					updatedAt = 100,
				},
			}
		end,
		teleportService = {
			ReserveServer = function(_self: any, _placeId: number): string
				hubReserveCalls += 1
				return "should-not-be-used"
			end,
			TeleportToPrivateServer = function(
				_self: any,
				_placeId: number,
				accessCode: string,
				_players: { any },
				_spawnName: any,
				_teleportData: any
			)
				hubTeleportAccessCode = accessCode
			end,
		},
		destinationResolver = function(_entry: any): any
			return {
				placeId = 12345,
			}
		end,
	})

	local hubAccepted = hubDispatcher.Dispatch({
		operationId = "op-hub",
		partyId = "party-good",
		targetRealmId = "realm-100",
	})
	assertEqual(hubAccepted.ok, true, "hub resolved dispatch accepted")
	assertEqual(hubAccepted.registryAccessCodeResolved, true, "hub resolved access code flag")
	assertEqual(hubReserveCalls, 0, "hub resolved dispatch skips reserve server")
	assertEqual(hubTeleportAccessCode, "registry-access-code", "hub resolved dispatch uses registry access code")
end

print("realm_teleport_dispatcher_runtime_entrypoint: all checks passed")
