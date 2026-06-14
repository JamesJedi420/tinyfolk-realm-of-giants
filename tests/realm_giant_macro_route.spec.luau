--!nocheck

local GiantMacroRouteAccess = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantMacroRouteAccess")
local RealmGiantMacroRouteValidator =
	require("../src/ReplicatedStorage/Shared/RealmTopology/RealmGiantMacroRouteValidator")
local RealmCaptureZoneValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmCaptureZoneValidator")

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

-- ── Map layout: GiantRoads ↔ GiantRoutes coverage, width, validation cameras ──

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local EscapeConfig = require("../src/ReplicatedStorage/Shared/Config/EscapeConfig")

local GIANT_ROADS_LAYOUT = "src/Workspace/Map/GiantRoads/Layout.model.json"
local GIANT_ROUTES_LAYOUT = "src/Workspace/Map/GiantRoutes/Layout.model.json"
local VALIDATION_CAMERAS_LAYOUT = "src/Workspace/Map/ValidationCameras/Layout.model.json"

local REQUIRED_VALIDATION_CAMERAS = {
	"Shot_Overhead_Map",
	"Shot_Giant_PlazaRoads",
	"Shot_Tinyfolk_RouteRead",
}

local function readJson(path: string): any
	if not fs.isFile(path) then
		error("missing layout file " .. path)
	end
	return serde.decode("json", fs.readFile(path))
end

local function collectPartNodes(root: any): { any }
	local parts: { any } = {}
	local function walk(node: any)
		if type(node) ~= "table" then
			return
		end
		if node.className == "Part" then
			table.insert(parts, node)
		end
		local children = node.children
		if type(children) == "table" then
			for _, child in children do
				walk(child)
			end
		end
	end
	walk(root)
	return parts
end

local function findPartByName(root: any, partName: string): any?
	for _, part in collectPartNodes(root) do
		if part.name == partName then
			return part
		end
	end
	return nil
end

local function visualRoadToGameplayName(visualName: string): string?
	local roadGiantPrefix = "Road_Giant_"
	local giantRoadPrefix = "GiantRoad_"
	if string.sub(visualName, 1, #roadGiantPrefix) == roadGiantPrefix then
		return "GiantRoute_" .. string.sub(visualName, #roadGiantPrefix + 1)
	end
	if string.sub(visualName, 1, #giantRoadPrefix) == giantRoadPrefix then
		return "GiantRoute_" .. string.sub(visualName, #giantRoadPrefix + 1)
	end
	return nil
end

local function vec3FromProperties(properties: any): { x: number, y: number, z: number }?
	if type(properties) ~= "table" or type(properties.Position) ~= "table" then
		return nil
	end
	local position = properties.Position
	return { x = position[1], y = position[2], z = position[3] }
end

local function positionsClose(
	a: { x: number, y: number, z: number },
	b: { x: number, y: number, z: number },
	epsilon: number
): boolean
	return math.abs(a.x - b.x) <= epsilon and math.abs(a.y - b.y) <= epsilon and math.abs(a.z - b.z) <= epsilon
end

local function isTrackedVisualRoad(part: any): boolean
	local attributes = part.attributes
	if type(attributes) ~= "table" then
		return false
	end
	local roadKind = attributes.RoadKind
	return roadKind == "GiantMacro" or roadKind == "GiantApproach"
end

do
	local giantRoadsRoot = readJson(GIANT_ROADS_LAYOUT)
	local giantRoutesRoot = readJson(GIANT_ROUTES_LAYOUT)
	local visualRoads = collectPartNodes(giantRoadsRoot)
	local gameplayRoutes = collectPartNodes(giantRoutesRoot)

	local gameplayByName: { [string]: any } = {}
	for _, route in gameplayRoutes do
		gameplayByName[route.name] = route
	end

	local expectedGameplayNames: { [string]: boolean } = {}
	local trackedVisualCount = 0
	for _, visualRoad in visualRoads do
		if not isTrackedVisualRoad(visualRoad) then
			continue
		end
		trackedVisualCount += 1
		local gameplayName = visualRoadToGameplayName(visualRoad.name)
		if type(gameplayName) ~= "string" then
			error(string.format("visual road %s has no gameplay name mapping", tostring(visualRoad.name)))
		end
		expectedGameplayNames[gameplayName] = true

		local gameplayRoute = gameplayByName[gameplayName]
		if gameplayRoute == nil then
			error(string.format("missing gameplay route for visual road %s -> %s", visualRoad.name, gameplayName))
		end

		local visualPosition = vec3FromProperties(visualRoad.properties)
		local gameplayPosition = vec3FromProperties(gameplayRoute.properties)
		if visualPosition == nil or gameplayPosition == nil then
			error(string.format("missing position metadata for route pair %s", gameplayName))
		end
		if not positionsClose(visualPosition, gameplayPosition, 0.01) then
			error(
				string.format(
					"gameplay route %s position drift from visual road (visual=%s,%s,%s gameplay=%s,%s,%s)",
					gameplayName,
					tostring(visualPosition.x),
					tostring(visualPosition.y),
					tostring(visualPosition.z),
					tostring(gameplayPosition.x),
					tostring(gameplayPosition.y),
					tostring(gameplayPosition.z)
				)
			)
		end
	end

	assertEqual(trackedVisualCount, 12, "tracked visual macro/approach roads count")
	assertEqual(#gameplayRoutes, trackedVisualCount, "gameplay routes mirror all visual roads")

	local giantRoutesFromLayout = {}
	for _, route in gameplayRoutes do
		local attributes = route.attributes
		local properties = route.properties
		local position = vec3FromProperties(properties)
		local widthStuds = if type(attributes) == "table" then attributes.WidthStuds else nil
		table.insert(giantRoutesFromLayout, {
			name = route.name,
			position = position,
			widthStuds = widthStuds,
			attributes = attributes,
		})
	end

	local layoutValidation =
		RealmGiantMacroRouteValidator.ValidateGiantMacroRoutes(makeDescriptor(giantRoutesFromLayout), STANDARD_CONFIG)
	assertEqual(layoutValidation.passed, true, "authored giant routes pass width/metadata validation")
	assertCheckPassed(
		requireResult(layoutValidation.results, "giant_route_metadata", "layout"),
		"layout giant route metadata"
	)
	assertCheckPassed(
		requireResult(layoutValidation.results, "giant_route_width_bounds", "layout"),
		"layout giant route width bounds"
	)

	for _, route in gameplayRoutes do
		local properties = route.properties
		if type(properties) ~= "table" or type(properties.Size) ~= "table" then
			error(string.format("route %s missing Size metadata", tostring(route.name)))
		end
		local routeWidth = properties.Size[1]
		assertEqual(
			routeWidth >= EscapeConfig.MinimumGiantMacroRouteWidthStuds,
			true,
			string.format("route %s gameplay width >= minimum", tostring(route.name))
		)
	end
end

do
	local validationCamerasRoot = readJson(VALIDATION_CAMERAS_LAYOUT)
	for _, cameraName in REQUIRED_VALIDATION_CAMERAS do
		local cameraPart = findPartByName(validationCamerasRoot, cameraName)
		if cameraPart == nil then
			error(string.format("missing validation camera anchor %s", cameraName))
		end
		local attributes = cameraPart.attributes
		if type(attributes) ~= "table" or type(attributes.SuggestedFov) ~= "number" then
			error(string.format("validation camera %s missing SuggestedFov", cameraName))
		end
		if
			type(attributes.LookAtX) ~= "number"
			or type(attributes.LookAtY) ~= "number"
			or type(attributes.LookAtZ) ~= "number"
		then
			error(string.format("validation camera %s missing LookAt metadata", cameraName))
		end
		local properties = cameraPart.properties
		if type(properties) ~= "table" or properties.Transparency ~= 1 then
			error(string.format("validation camera %s should remain invisible for screenshots", cameraName))
		end
	end

	local tinyfolkCamera = findPartByName(validationCamerasRoot, "Shot_Tinyfolk_RouteRead")
	if tinyfolkCamera == nil then
		error("missing validation camera anchor Shot_Tinyfolk_RouteRead")
	end
	local tinyfolkPosition = vec3FromProperties(tinyfolkCamera.properties)
	local tinyfolkAttributes = tinyfolkCamera.attributes
	if tinyfolkPosition == nil or type(tinyfolkAttributes) ~= "table" then
		error("Shot_Tinyfolk_RouteRead missing placement metadata")
	end
	assertEqual(tinyfolkPosition.z <= 8, true, "tinyfolk validation camera stays south of labor bench band")
	assertEqual(tinyfolkAttributes.LookAtZ, 8, "tinyfolk validation camera look-at stays on spawn route")
end

do
	local captureZonesRoot = readJson("src/Workspace/Map/CaptureZones/Layout.model.json")
	local giantRoutesRoot = readJson(GIANT_ROUTES_LAYOUT)

	local captureZones = {}
	for _, part in collectPartNodes(captureZonesRoot) do
		local properties = part.properties
		if type(properties) ~= "table" or type(properties.Position) ~= "table" then
			continue
		end
		local position = properties.Position
		local size = properties.Size
		local radius = if type(size) == "table" then math.max(size[1] * 0.5, size[3] * 0.5) else 0
		table.insert(captureZones, {
			name = part.name,
			position = { x = position[1], y = position[2], z = position[3] },
			radius = radius,
			tag = "GiantCapture",
		})
	end

	local giantRoutes = {}
	for _, part in collectPartNodes(giantRoutesRoot) do
		local attributes = part.attributes
		local properties = part.properties
		if type(properties) ~= "table" or type(properties.Position) ~= "table" then
			continue
		end
		local position = properties.Position
		table.insert(giantRoutes, {
			name = part.name,
			position = { x = position[1], y = position[2], z = position[3] },
			widthStuds = if type(attributes) == "table" then attributes.WidthStuds else nil,
		})
	end

	local captureConfig = {
		minimumGiantRouteSeparationStuds = 5,
	}
	local descriptor = {
		captureZones = captureZones,
		giantRoutes = giantRoutes,
	}
	local separation = RealmCaptureZoneValidator.captureZoneGiantRouteSeparation(descriptor, captureConfig)
	assertCheckPassed(separation, "authored capture zones clear of giant macro routes")
end

print("realm_giant_macro_route: all checks passed")
