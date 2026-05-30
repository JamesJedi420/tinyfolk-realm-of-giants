--!strict

local PlayerCreatedRouteState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerCreatedRouteState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

do
	local validation = PlayerCreatedRouteState.ValidateRouteRecord({
		routeId = "EscapeRoute_Player_A",
		createdByUserId = 1001,
		createdAt = 50,
		enabled = true,
		expiresAt = 75,
	})
	assertTrue(validation.valid, "valid player-created route record passes validation")
end

do
	local missingRouteId = PlayerCreatedRouteState.ValidateRouteRecord({
		routeId = "",
		createdByUserId = 1001,
		createdAt = 50,
		enabled = true,
	})
	assertFalse(missingRouteId.valid, "empty route id fails validation")
	assertEqual(missingRouteId.reason, "route_id_invalid", "empty route id failure reason")

	local invalidCreator = PlayerCreatedRouteState.ValidateRouteRecord({
		routeId = "EscapeRoute_Player_A",
		createdByUserId = 0,
		createdAt = 50,
		enabled = true,
	})
	assertFalse(invalidCreator.valid, "non-positive creator user id fails validation")
	assertEqual(invalidCreator.reason, "created_by_user_id_invalid", "invalid creator failure reason")

	local invalidCreatedAt = PlayerCreatedRouteState.ValidateRouteRecord({
		routeId = "EscapeRoute_Player_A",
		createdByUserId = 1001,
		createdAt = -1,
		enabled = true,
	})
	assertFalse(invalidCreatedAt.valid, "negative createdAt fails validation")
	assertEqual(invalidCreatedAt.reason, "created_at_invalid", "invalid createdAt failure reason")
end

do
	local active = PlayerCreatedRouteState.QueryActivePlayerRoutes({
		EscapeRoute_Player_A = {
			routeId = "EscapeRoute_Player_A",
			createdByUserId = 1001,
			createdAt = 40,
			enabled = true,
			expiresAt = 80,
		},
		EscapeRoute_Player_B = {
			routeId = "EscapeRoute_Player_B",
			createdByUserId = 1002,
			createdAt = 60,
			enabled = false,
		},
		EscapeRoute_Player_C = {
			routeId = "EscapeRoute_Player_C",
			createdByUserId = 1003,
			createdAt = 90,
			enabled = true,
		},
		EscapeRoute_Player_D = {
			routeId = "EscapeRoute_Player_D",
			createdByUserId = 1004,
			createdAt = 30,
			enabled = true,
			expiresAt = 50,
		},
	}, 60)

	assertTrue(active.EscapeRoute_Player_A ~= nil, "query includes enabled non-expired current route")
	assertTrue(active.EscapeRoute_Player_B == nil, "query excludes disabled route")
	assertTrue(active.EscapeRoute_Player_C == nil, "query excludes future-created route")
	assertTrue(active.EscapeRoute_Player_D == nil, "query excludes expired route")
end

do
	local upserted = PlayerCreatedRouteState.UpsertRouteRecord(nil, {
		routeId = "EscapeRoute_Player_A",
		requesterUserId = 2001,
		createdAt = 20,
		expiresAt = 50,
	})
	assertTrue(upserted.accepted, "upsert accepts valid create request")
	assertEqual(upserted.reason, "accepted", "upsert accepted reason")
	assertEqual(upserted.record.createdByUserId, 2001, "upsert sets owner from requester")

	local ownerMismatch = PlayerCreatedRouteState.UpsertRouteRecord(upserted.record, {
		routeId = "EscapeRoute_Player_A",
		requesterUserId = 2002,
		createdAt = 21,
	})
	assertFalse(ownerMismatch.accepted, "upsert rejects non-owner requester")
	assertEqual(ownerMismatch.reason, "player_route_owner_mismatch", "upsert owner mismatch reason")

	local invalidCreatedAt = PlayerCreatedRouteState.UpsertRouteRecord(nil, {
		routeId = "EscapeRoute_Player_A",
		requesterUserId = 2001,
		createdAt = -10,
	})
	assertFalse(invalidCreatedAt.accepted, "upsert rejects invalid createdAt")
	assertEqual(invalidCreatedAt.reason, "created_at_invalid", "upsert invalid createdAt reason")

	local invalidExpiresAt = PlayerCreatedRouteState.UpsertRouteRecord(nil, {
		routeId = "EscapeRoute_Player_A",
		requesterUserId = 2001,
		createdAt = 10,
		expiresAt = -1,
	})
	assertFalse(invalidExpiresAt.accepted, "upsert rejects invalid expiresAt")
	assertEqual(invalidExpiresAt.reason, "expires_at_invalid", "upsert invalid expiresAt reason")

	local expiresBeforeCreated = PlayerCreatedRouteState.UpsertRouteRecord(nil, {
		routeId = "EscapeRoute_Player_A",
		requesterUserId = 2001,
		createdAt = 10,
		expiresAt = 9,
	})
	assertFalse(expiresBeforeCreated.accepted, "upsert rejects expiresAt before createdAt")
	assertEqual(expiresBeforeCreated.reason, "expires_before_created", "upsert expires-before-created reason")
end

do
	local existing = {
		routeId = "EscapeRoute_Player_A",
		createdByUserId = 3001,
		createdAt = 15,
		enabled = true,
		expiresAt = 45,
	}

	local disabled = PlayerCreatedRouteState.DisableRouteRecord(existing, 3001)
	assertTrue(disabled.accepted, "disable accepts owner requester")
	assertEqual(disabled.reason, "accepted", "disable accepted reason")
	assertFalse(disabled.record.enabled, "disable projects enabled=false")

	local mismatch = PlayerCreatedRouteState.DisableRouteRecord(existing, 3002)
	assertFalse(mismatch.accepted, "disable rejects non-owner requester")
	assertEqual(mismatch.reason, "player_route_owner_mismatch", "disable owner mismatch reason")

	local missing = PlayerCreatedRouteState.DisableRouteRecord(nil, 3001)
	assertFalse(missing.accepted, "disable rejects missing owner record")
	assertEqual(missing.reason, "player_route_owner_mismatch", "disable missing record mismatch reason")

	local invalidRequester = PlayerCreatedRouteState.DisableRouteRecord(existing, 0)
	assertFalse(invalidRequester.accepted, "disable rejects invalid requester id")
	assertEqual(invalidRequester.reason, "requester_user_id_invalid", "disable invalid requester reason")
end

print("player_created_route_state: all checks passed")
