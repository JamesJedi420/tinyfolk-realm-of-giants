--!nocheck

local GiantMacroRouteAccess = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantMacroRouteAccess")
local RealmGiantMacroRouteValidator =
	require("../src/ReplicatedStorage/Shared/RealmTopology/RealmGiantMacroRouteValidator")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertCheckPassed(check, label)
	if not check.passed then
		error(string.format("expected pass [%s id=%s] but got failure: %s", label, check.id, tostring(check.reason)))
	end
end

local function assertCheckFailed(check, label)
	if check.passed then
		error(string.format("expected failure [%s id=%s] but got pass", label, check.id))
	end
end

local function requireResult(results, id, context)
	for _, check in results do
		if check.id == id then
			return check
		end
	end
	error(string.format("check id=%s not present in results [%s]", id, context))
end

local STANDARD_CONFIG = {
	minimumGiantMacroRouteWidthStuds = 18,
	requireGiantOnlyRouteMetadata = true,
}

local function makeDescriptor(giantRoutes)
	return {
		spawns = {},
		escapeRoutes = {},
		giantRoutes = giantRoutes,
		returnPoints = {},
		stations = {},
		constructionSites = {},
		upgradeBoards = {},
		controlZones = {},
		captureZones = {},
		props = {},
		routeGraph = {
			nodes = {},
			edges = {},
		},
	}
end

do
	local giantAccess = GiantMacroRouteAccess.EvaluateGiantMacroRouteAccess({
		role = "Giant",
		giantOnly = true,
		tinyfolkOnly = false,
		isEnabled = true,
	})
	assertEqual(giantAccess.accepted, true, "giant access accepts enabled giant-only route")
	assertEqual(giantAccess.reason, "accepted", "giant access accepted reason")

	local tinyfolkAccess = GiantMacroRouteAccess.EvaluateGiantMacroRouteAccess({
		role = "Tinyfolk",
		giantOnly = true,
		tinyfolkOnly = false,
		isEnabled = true,
	})
	assertEqual(tinyfolkAccess.accepted, false, "tinyfolk rejected on giant-only route")
	assertEqual(tinyfolkAccess.reason, "requester_not_giant", "tinyfolk giant-only rejection reason")

	local conflict = GiantMacroRouteAccess.EvaluateGiantMacroRouteAccess({
		role = "Giant",
		giantOnly = true,
		tinyfolkOnly = true,
		isEnabled = true,
	})
	assertEqual(conflict.accepted, false, "conflicting metadata rejects giant access")
	assertEqual(conflict.reason, "route_role_metadata_conflict", "conflicting metadata reason")
end

do
	local valid = makeDescriptor({
		{
			name = "GiantRoute_PlazaToHearth",
			position = { x = 0, y = 0.38, z = -36 },
			widthStuds = 18,
			attributes = { GiantOnlyRoute = true, RouteEnabled = true },
		},
	})
	local result = RealmGiantMacroRouteValidator.ValidateGiantMacroRoutes(valid, STANDARD_CONFIG)
	assertEqual(result.passed, true, "valid giant route metadata passes")
	assertCheckPassed(requireResult(result.results, "giant_route_metadata", "valid"), "valid metadata")
	assertCheckPassed(requireResult(result.results, "giant_route_width_bounds", "valid"), "valid width")

	local invalid = makeDescriptor({
		{
			name = "GiantRoute_PlazaToHearth",
			position = { x = 0, y = 0.38, z = -36 },
			widthStuds = 10,
			attributes = { GiantOnlyRoute = true, TinyfolkOnlyRoute = true, RouteEnabled = false },
		},
		{
			name = "GiantRoute_PlazaToHearth",
			position = { x = 1, y = 0.38, z = -36 },
			widthStuds = 18,
		},
	})
	local invalidResult = RealmGiantMacroRouteValidator.ValidateGiantMacroRoutes(invalid, STANDARD_CONFIG)
	assertEqual(invalidResult.passed, false, "invalid giant route metadata fails")
	local metadata = requireResult(invalidResult.results, "giant_route_metadata", "invalid")
	assertCheckFailed(metadata, "invalid metadata")
	assertEqual(
		string.find(metadata.reason :: string, "missing GiantOnlyRoute=true", 1, true) ~= nil,
		true,
		"invalid missing metadata reason"
	)
	assertEqual(
		string.find(metadata.reason :: string, "conflicting TinyfolkOnlyRoute=true", 1, true) ~= nil,
		true,
		"invalid conflicting metadata reason"
	)
	assertEqual(string.find(metadata.reason :: string, "is disabled", 1, true) ~= nil, true, "invalid disabled reason")
	assertEqual(
		string.find(metadata.reason :: string, "duplicate route id", 1, true) ~= nil,
		true,
		"invalid duplicate route reason"
	)

	local width = requireResult(invalidResult.results, "giant_route_width_bounds", "invalid width")
	assertCheckFailed(width, "invalid width")
	assertEqual(
		string.find(width.reason :: string, "below minimum", 1, true) ~= nil,
		true,
		"invalid width below minimum reason"
	)
end

print("realm_giant_macro_route: all checks passed")
