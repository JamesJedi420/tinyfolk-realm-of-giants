--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected %q got %q", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local warns: { string } = {}
local originalWarn = warn
warn = function(...: any)
	local packed: any = table.pack(...)
	local parts: { string } = {}
	for i = 1, packed.n :: number do
		table.insert(parts, tostring(packed[i]))
	end
	local line = table.concat(parts, " ")
	table.insert(warns, line)
	originalWarn(...)
end

if Color3 == nil then
	Color3 = {
		fromRGB = function(r: number, g: number, b: number)
			return { R = r, G = g, B = b }
		end,
	} :: any
end

if Enum == nil then
	Enum = {
		Material = {
			Grass = "Grass",
		},
	} :: any
end

if Vector3 == nil then
	local vector3Mt: any = {}
	vector3Mt.__index = function(self: any, key: string)
		if key == "Magnitude" then
			return math.sqrt((self.X * self.X) + (self.Y * self.Y) + (self.Z * self.Z))
		end
		return nil
	end
	vector3Mt.__sub = function(a: any, b: any)
		return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector3Mt)
	end

	Vector3 = {
		new = function(x: number, y: number, z: number)
			return setmetatable({ X = x, Y = y, Z = z }, vector3Mt)
		end,
	} :: any
end

local function makeNode(name: string, className: string?, fullName: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_FullName = fullName or name,
		_Children = {},
		_Attributes = {},
		Parent = nil,
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.GetFullName(self: any): string
		return self._FullName
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	function node.GetChildren(self: any): { any }
		local children: { any } = {}
		for _, child in pairs(self._Children) do
			table.insert(children, child)
		end
		return children
	end

	function node.GetDescendants(self: any): { any }
		local descendants: { any } = {}
		local walk: (current: any) -> ()
		walk = function(current: any)
			for _, child in pairs(current._Children) do
				table.insert(descendants, child)
				if type(child._Children) == "table" then
					walk(child)
				end
			end
		end
		walk(self)
		return descendants
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	child.Parent = parent
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
		_ClientPayload = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireServer(self: any, player: any, payload: any)
		if self._Handler == nil then
			error(string.format("remote %s handler not connected", self.Name))
		end
		self._Handler(player, payload)
	end

	function remote.FireClient(self: any, _player: any, payload: any)
		self._ClientPayload = payload
	end

	return remote
end

local function makeBasePart(name: string, x: number, y: number, z: number)
	local part = makeNode(name, "BasePart", "Workspace.Map." .. name)
	part.Position = Vector3.new(x, y, z)
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Material = Enum.Material.Grass
	return part
end

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
local buildRemote = makeRemoteEvent("ConstructionBuildRequest")
local debugRequestRemote = makeRemoteEvent("ConstructionDebugStateRequest")
local debugResponseRemote = makeRemoteEvent("ConstructionDebugStateResponse")
addChild(remotesFolder, "ConstructionBuildRequest", buildRemote)
addChild(remotesFolder, "ConstructionDebugStateRequest", debugRequestRemote)
addChild(remotesFolder, "ConstructionDebugStateResponse", debugResponseRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
-- String paths stored directly to avoid child.Parent = parent on a string value
configFolder._Children["ConstructionConfig"] = "../../ReplicatedStorage/Shared/Config/ConstructionConfig"
configFolder._Children["StationConfig"] = "../../ReplicatedStorage/Shared/Config/StationConfig"

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)

local sharedConstructionFolder = makeNode("Construction", "Folder", "ReplicatedStorage.Shared.Construction")
sharedConstructionFolder._Children["ContextualTaskProgressLogic"] =
	"../../ReplicatedStorage/Shared/Construction/ContextualTaskProgressLogic"
sharedConstructionFolder._Children["TaskQteTimingLogic"] =
	"../../ReplicatedStorage/Shared/Construction/TaskQteTimingLogic"

local giantRealmFolder = makeNode("GiantRealm", "Folder", "ReplicatedStorage.Shared.GiantRealm")
giantRealmFolder._Children["RealmObjectiveSiteIdResolver"] =
	"../../ReplicatedStorage/Shared/GiantRealm/RealmObjectiveSiteIdResolver"
giantRealmFolder._Children["PostRescueProtectionState"] =
	"../../ReplicatedStorage/Shared/GiantRealm/PostRescueProtectionState"
addChild(sharedFolder, "GiantRealm", giantRealmFolder)
addChild(sharedFolder, "Construction", sharedConstructionFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local stationsFolder = makeNode("Stations", "Folder", "Workspace.Map.Stations")
addChild(mapFolder, "Stations", stationsFolder)
local constructionSitePart = makeBasePart("ConstructionSite_A", 10, 0, 10)
addChild(mapFolder, "ConstructionSite_A", constructionSitePart)
local constructionSitePartB = makeBasePart("ConstructionSite_B", 15, 0, 10)
addChild(mapFolder, "ConstructionSite_B", constructionSitePartB)
addChild(workspaceService, "Map", mapFolder)

local _playerRemovingConnections: { (any) -> () } = {}
local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerRemoving = {
		Connect = function(_signal: any, callback: (any) -> ())
			table.insert(_playerRemovingConnections, callback)
		end,
	},
}

local fakeGame = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local queryApiCallCount = {
	getAll = 0,
	getPlaced = 0,
	getByPlayer = 0,
	isPlaced = 0,
}

_G._DistrictPlacementService_QueryAPI = {
	GetAllPlacedDistricts = function()
		queryApiCallCount.getAll += 1
		return {
			District_Startup_A = {
				districtId = "District_Startup_A",
				placedByUserId = 9201,
				placedAt = 101.5,
			},
			District_Startup_B = {
				districtId = "District_Startup_B",
				placedByUserId = 9202,
				placedAt = 202.75,
			},
		}
	end,
	GetPlacedDistrict = function(_districtId: string)
		queryApiCallCount.getPlaced += 1
		return nil
	end,
	GetPlacedDistrictsByPlayer = function(_userId: number)
		queryApiCallCount.getByPlayer += 1
		return {}
	end,
	IsDistrictPlaced = function(_districtId: string)
		queryApiCallCount.isPlaced += 1
		return false
	end,
}

local objectiveCompletionCalls: { any } = {}
_G._RealmObjectiveService_QueryAPI = {
	RecordObjectiveCompletion = function(siteId: string, completedByUserId: number?, at: number?): any
		table.insert(objectiveCompletionCalls, {
			siteId = siteId,
			completedByUserId = completedByUserId,
			at = at,
		})
		return { accepted = true, reason = "accepted" }
	end,
}

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
-- String path stored directly to avoid child.Parent = parent on a string value
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
scriptParent._Children["ObjectiveSkillXpProducer"] = "../../ServerScriptService/Services/ObjectiveSkillXpProducer"
scriptParent._Children["RealmObjectiveCompletionCaller"] =
	"../../ServerScriptService/Services/RealmObjectiveCompletionCaller"
scriptParent._Children["PostRescueProtectionCancellationCaller"] =
	"../../ServerScriptService/Services/PostRescueProtectionCancellationCaller"

local postRescueProtectionCancelCalls: { any } = {}
_G._RescueContractService_QueryAPI = {
	CancelPostRescueProtection = function(userId: number, breakingAction: string?, at: number?): boolean
		table.insert(postRescueProtectionCancelCalls, {
			userId = userId,
			breakingAction = breakingAction,
			at = at,
		})
		return true
	end,
}
script = {
	Parent = scriptParent,
} :: any

local function makeAlivePlayer(userId: number, position: Vector3)
	local root = makeBasePart("HumanoidRootPart", position.X, position.Y, position.Z)
	local humanoid = {
		Health = 100,
	}
	local character = {
		FindFirstChild = function(_self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return root
			end
			return nil
		end,
		FindFirstChildOfClass = function(_self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}
	return {
		UserId = userId,
		Character = character,
		_Attributes = {},
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
	}
end

local serviceLoaded, serviceError = pcall(function()
	require("../src/ServerScriptService/Services/ConstructionService.server")
end)
if not serviceLoaded then
	error(string.format("FAIL [construction service loads]: %s", tostring(serviceError)))
end

assertTrue(buildRemote._Handler ~= nil, "construction service binds ConstructionBuildRequest OnServerEvent")

local districtBuildState = _G._ConstructionService_DistrictBuildState
assertTrue(type(districtBuildState) == "table", "district build-state table exported")

assertTrue(districtBuildState["District_Startup_A"] ~= nil, "startup discovery initializes district A build-state")
assertTrue(districtBuildState["District_Startup_B"] ~= nil, "startup discovery initializes district B build-state")

local districtA = districtBuildState["District_Startup_A"]
assertEqual(districtA.districtId, "District_Startup_A", "district A id initialized")
assertEqual(districtA.placedByUserId, 9201, "district A ownership matches district placer")
assertEqual(districtA.placedAt, 101.5, "district A placedAt copied from placement snapshot")
assertEqual(districtA.isBuilt, false, "district A initialized as not built")
assertEqual(districtA.buildCount, 0, "district A buildCount initialized to zero")
assertTrue(districtA.lastBuiltByUserId == nil, "district A lastBuiltByUserId initialized nil")

-- TIN-195: cost fields initialized at startup from ConstructionConfig.DistrictDefaultCost
local ConstructionConfig = require("../src/ReplicatedStorage/Shared/Config/ConstructionConfig")
assertEqual(
	districtA.woodCost,
	ConstructionConfig.DistrictDefaultCost.wood,
	"district A woodCost initialized from DistrictDefaultCost"
)
assertEqual(
	districtA.stoneCost,
	ConstructionConfig.DistrictDefaultCost.stone,
	"district A stoneCost initialized from DistrictDefaultCost"
)
local districtB = districtBuildState["District_Startup_B"]
assertEqual(
	districtB.woodCost,
	ConstructionConfig.DistrictDefaultCost.wood,
	"district B woodCost initialized from DistrictDefaultCost"
)
assertEqual(
	districtB.stoneCost,
	ConstructionConfig.DistrictDefaultCost.stone,
	"district B stoneCost initialized from DistrictDefaultCost"
)

assertEqual(queryApiCallCount.getAll, 1, "query API GetAllPlacedDistricts called exactly once at startup")
assertEqual(queryApiCallCount.getPlaced, 0, "query API GetPlacedDistrict not called")
assertEqual(queryApiCallCount.getByPlayer, 0, "query API GetPlacedDistrictsByPlayer not called")
assertEqual(queryApiCallCount.isPlaced, 0, "query API IsDistrictPlaced not called")

local siteStateById = _G._ConstructionService_SiteState
assertTrue(type(siteStateById) == "table", "site state table exported")
assertTrue(siteStateById["ConstructionSite_A"] ~= nil, "existing site-backed state still registered")

local ResourceFlowState = require("../src/ServerScriptService/Services/ResourceFlowState")
ResourceFlowState.AddStoredAtomic(
	0,
	0,
	"construction_test_seed_food",
	ConstructionConfig.CostBySiteId.ConstructionSite_A.food
)

local builder = makeAlivePlayer(9301, Vector3.new(12, 0, 12))
buildRemote:FireServer(builder, "ConstructionSite_A")

local siteState = siteStateById["ConstructionSite_A"]
assertTrue(siteState.isBuilt, "existing site-backed build mutation still works")
assertEqual(siteState.buildCount, 1, "existing site-backed build count increments")
assertEqual(siteState.lastBuiltByUserId, 9301, "existing site-backed build tracks builder")
assertEqual(
	constructionSitePart:GetAttribute("ConstructionCostFood"),
	ConstructionConfig.CostBySiteId.ConstructionSite_A.food,
	"construction site exposes food cost attribute"
)
assertEqual(ResourceFlowState.GetMaterialSnapshot("Food").stored, 0, "construction build spends stored food")

-- TIN-197: district build mutation-path assertions.
-- Use a separate player to avoid cooldown collision with the site builder above.
local districtBuilder = makeAlivePlayer(9302, Vector3.new(12, 0, 12))
buildRemote:FireServer(districtBuilder, "District_Startup_A")

assertTrue(districtBuildState["District_Startup_A"].isBuilt, "district build request accepted: isBuilt flipped")
assertEqual(
	districtBuildState["District_Startup_A"].buildCount,
	1,
	"district build request accepted: buildCount incremented"
)
assertEqual(
	districtBuildState["District_Startup_A"].lastBuiltByUserId,
	9302,
	"district build request accepted: lastBuiltByUserId set"
)

-- Second request for the same district must be rejected as already_built.
local districtBuilder2 = makeAlivePlayer(9303, Vector3.new(12, 0, 12))
local warnsBefore = #warns
buildRemote:FireServer(districtBuilder2, "District_Startup_A")
local sawAlreadyBuilt = false
for i = warnsBefore + 1, #warns do
	if string.find(warns[i], "already_built", 1, true) then
		sawAlreadyBuilt = true
		break
	end
end
assertTrue(sawAlreadyBuilt, "district already_built rejection fires on second build request")
assertEqual(
	districtBuildState["District_Startup_A"].buildCount,
	1,
	"district buildCount unchanged after already_built rejection"
)

-- Completely unknown ID must still produce site_not_found.
local unknownPlayer = makeAlivePlayer(9304, Vector3.new(12, 0, 12))
local warnsBeforeUnknown = #warns
buildRemote:FireServer(unknownPlayer, "Unknown_District_XYZ")
local sawSiteNotFound = false
for i = warnsBeforeUnknown + 1, #warns do
	if string.find(warns[i], "site_not_found", 1, true) then
		sawSiteNotFound = true
		break
	end
end
assertTrue(sawSiteNotFound, "unknown id still produces site_not_found after district routing")

-- District_Startup_B must still be unbuilt.
assertEqual(
	districtBuildState["District_Startup_B"].isBuilt,
	false,
	"District_Startup_B unaffected by District_Startup_A build"
)

assertEqual(queryApiCallCount.getAll, 1, "query API startup discovery remains one-time after build requests")

print("construction_service_runtime_entrypoint: district mutation-path slice checks passed")

-- TIN-199: ConstructionDebugStateRequest district debug surface assertions.
-- Targeted lookup: district ID returns district build-state in debug response.
-- District_Startup_B is unbuilt (was never built above), so use it for clean state.
local debugPlayer = makeAlivePlayer(9305, Vector3.new(12, 0, 12))
debugRequestRemote:FireServer(debugPlayer, "District_Startup_B")
local debugResponse = debugResponseRemote._ClientPayload
assertTrue(debugResponse ~= nil, "targeted district debug: response payload populated")
assertEqual(debugResponse.districtId, "District_Startup_B", "targeted district debug: districtId field present")
assertEqual(debugResponse.isBuilt, false, "targeted district debug: isBuilt field correct")
assertEqual(debugResponse.buildCount, 0, "targeted district debug: buildCount field correct")
assertTrue(
	debugResponse.lastBuiltByUserId == nil,
	"targeted district debug: lastBuiltByUserId nil for unbuilt district"
)
assertEqual(
	debugResponse.woodCost,
	ConstructionConfig.DistrictDefaultCost.wood,
	"targeted district debug: woodCost field matches config"
)
assertEqual(
	debugResponse.stoneCost,
	ConstructionConfig.DistrictDefaultCost.stone,
	"targeted district debug: stoneCost field matches config"
)
assertTrue(debugResponse.woodStored ~= nil, "targeted district debug: woodStored flow snapshot field present")
assertTrue(debugResponse.stoneStored ~= nil, "targeted district debug: stoneStored flow snapshot field present")

-- Targeted lookup: unknown ID still produces site_not_found warn.
local debugUnknownPlayer = makeAlivePlayer(9306, Vector3.new(12, 0, 12))
local warnsBeforeDebugUnknown = #warns
debugRequestRemote:FireServer(debugUnknownPlayer, "Unknown_District_Debug_XYZ")
local sawDebugSiteNotFound = false
for i = warnsBeforeDebugUnknown + 1, #warns do
	if string.find(warns[i], "site_not_found", 1, true) then
		sawDebugSiteNotFound = true
		break
	end
end
assertTrue(sawDebugSiteNotFound, "targeted district debug: unknown id produces site_not_found warn")

-- Snapshot-all (nil payload): response must include both site and district entries.
local debugSnapshotPlayer = makeAlivePlayer(9307, Vector3.new(12, 0, 12))
debugRequestRemote:FireServer(debugSnapshotPlayer, nil)
local snapshotPayload = debugResponseRemote._ClientPayload
assertTrue(type(snapshotPayload) == "table", "snapshot-all debug: response is a table")
local sawDistrictEntry = false
local sawSiteEntry = false
for _, entry in ipairs(snapshotPayload) do
	if entry.districtId ~= nil then
		sawDistrictEntry = true
	end
	if entry.siteId ~= nil then
		sawSiteEntry = true
	end
end
assertTrue(sawDistrictEntry, "snapshot-all debug: at least one district entry present")
assertTrue(sawSiteEntry, "snapshot-all debug: site entry still present in snapshot")

print("construction_service_runtime_entrypoint: district debug-surface slice checks passed")

-- TIN-153 phase 1: construction contextual task begin/cancel/complete slice.
local objectiveCompletionCallsBeforeTask = #objectiveCompletionCalls
local taskBuilder = makeAlivePlayer(9401, Vector3.new(16, 0, 10))
buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_B",
	mode = "begin",
	now = 200,
})

assertEqual(
	taskBuilder:GetAttribute("ConstructionTaskActiveSiteId"),
	"ConstructionSite_B",
	"task begin sets active site id attribute"
)
assertEqual(taskBuilder:GetAttribute("ConstructionTaskLastReason"), "began", "task begin sets began reason")
assertEqual(
	taskBuilder:GetAttribute("ConstructionTaskObjectiveState"),
	"progressing",
	"task begin sets progressing objective state"
)

local siteBState = siteStateById["ConstructionSite_B"]
assertTrue(siteBState ~= nil, "site B state present")
assertEqual(siteBState.isBuilt, false, "task begin does not instantly build")

local warnsBeforeNotReady = #warns
buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_B",
	mode = "complete",
	now = 200.4,
})
local sawNotReady = false
for i = warnsBeforeNotReady + 1, #warns do
	if string.find(warns[i], "task_not_ready", 1, true) then
		sawNotReady = true
		break
	end
end
assertTrue(sawNotReady, "task complete before timer ends is rejected")
assertEqual(siteBState.isBuilt, false, "task not_ready rejection keeps site unbuilt")

buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_B",
	mode = "cancel",
	now = 201,
})
assertTrue(taskBuilder:GetAttribute("ConstructionTaskActiveSiteId") == nil, "task cancel clears active site id")
assertEqual(taskBuilder:GetAttribute("ConstructionTaskLastReason"), "canceled", "task cancel sets canceled reason")
assertEqual(taskBuilder:GetAttribute("ConstructionTaskObjectiveState"), "idle", "task cancel sets idle objective state")

ResourceFlowState.AddStoredAtomic(
	0,
	0,
	"construction_test_seed_food_b",
	ConstructionConfig.CostBySiteId.ConstructionSite_B.food
)

buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_B",
	mode = "begin",
	now = 202,
})
buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_B",
	mode = "complete",
	now = 204,
})

assertEqual(siteBState.isBuilt, true, "task complete after timer builds site")
assertEqual(siteBState.buildCount, 1, "task complete increments build count")
assertEqual(siteBState.lastBuiltByUserId, 9401, "task complete tracks builder user id")
assertTrue(taskBuilder:GetAttribute("ConstructionTaskActiveSiteId") == nil, "task complete clears active site")
assertEqual(taskBuilder:GetAttribute("ConstructionTaskLastReason"), "completed", "task complete sets completed reason")
assertEqual(
	taskBuilder:GetAttribute("ConstructionTaskObjectiveState"),
	"completed",
	"task complete sets completed objective state"
)
assertEqual(
	#objectiveCompletionCalls,
	objectiveCompletionCallsBeforeTask + 1,
	"contextual task completion records realm objective once"
)
assertEqual(
	objectiveCompletionCalls[#objectiveCompletionCalls].siteId,
	"ConstructionSite_B",
	"contextual task completion maps construction site id"
)
assertEqual(
	objectiveCompletionCalls[#objectiveCompletionCalls].completedByUserId,
	9401,
	"contextual task completion forwards completer user id"
)
assertEqual(
	objectiveCompletionCalls[#objectiveCompletionCalls].at,
	204,
	"contextual task completion forwards completion timestamp"
)
assertEqual(#postRescueProtectionCancelCalls, 1, "contextual task completion cancels post-rescue protection once")
assertEqual(
	postRescueProtectionCancelCalls[1].userId,
	9401,
	"contextual task completion forwards protection cancel user id"
)
assertEqual(
	postRescueProtectionCancelCalls[1].breakingAction,
	"objective_task_complete",
	"contextual task completion uses objective breaking action"
)

-- TIN-154-prep: disruption and blocked state transitions through service task modes.
buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 206,
})
buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_A",
	mode = "disrupt",
	now = 206.5,
})
assertEqual(
	taskBuilder:GetAttribute("ConstructionTaskObjectiveState"),
	"regressing",
	"task disrupt sets regressing objective state"
)
assertEqual(taskBuilder:GetAttribute("ConstructionTaskLastReason"), "disrupted", "task disrupt sets disrupted reason")
assertTrue(taskBuilder:GetAttribute("ConstructionTaskProgressSeconds") ~= nil, "task disrupt exposes progress seconds")
assertTrue(taskBuilder:GetAttribute("ConstructionTaskRegressionCount") ~= nil, "task disrupt exposes regression count")

buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_A",
	mode = "block",
	now = 207.0,
})
assertEqual(
	taskBuilder:GetAttribute("ConstructionTaskObjectiveState"),
	"blocked",
	"task block sets blocked objective state"
)

local warnsBeforeBlockedBegin = #warns
buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 207.5,
})
local sawTaskBlocked = false
for i = warnsBeforeBlockedBegin + 1, #warns do
	if string.find(warns[i], "task_blocked", 1, true) then
		sawTaskBlocked = true
		break
	end
end
assertTrue(sawTaskBlocked, "task begin while blocked is rejected")

buildRemote:FireServer(taskBuilder, {
	siteId = "ConstructionSite_A",
	mode = "unblock",
	now = 208,
})
assertEqual(
	taskBuilder:GetAttribute("ConstructionTaskObjectiveState"),
	"idle",
	"task unblock returns objective state to idle"
)

-- Shared objective state (site-scoped): begin from one user should block begin from another.
local taskBuilderA = makeAlivePlayer(9501, Vector3.new(16, 0, 10))
local taskBuilderB = makeAlivePlayer(9502, Vector3.new(16, 0, 10))
buildRemote:FireServer(taskBuilderA, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 300,
})

local warnsBeforeSharedBegin = #warns
buildRemote:FireServer(taskBuilderB, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 300.3,
})
local sawAlreadyActive = false
for i = warnsBeforeSharedBegin + 1, #warns do
	if string.find(warns[i], "task_already_active", 1, true) then
		sawAlreadyActive = true
		break
	end
end
assertTrue(sawAlreadyActive, "shared site task begin from second user is rejected while active")

-- Cancel should bypass request cooldown so quick key release can cancel an active begin.
buildRemote:FireServer(taskBuilderA, {
	siteId = "ConstructionSite_A",
	mode = "cancel",
	now = 300.35,
})
assertEqual(taskBuilderA:GetAttribute("ConstructionTaskLastReason"), "canceled", "cancel bypass cooldown succeeds")

buildRemote:FireServer(taskBuilderB, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 301,
})
assertEqual(
	taskBuilderB:GetAttribute("ConstructionTaskLastReason"),
	"resumed",
	"second user can begin after shared task is canceled"
)

-- Regression-cap check: third major regression on same site should reject at configured cap.
buildRemote:FireServer(taskBuilderB, {
	siteId = "ConstructionSite_A",
	mode = "disrupt",
	now = 301.6,
})

buildRemote:FireServer(taskBuilderB, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 302.2,
})

local warnsBeforeRegressionCap = #warns
buildRemote:FireServer(taskBuilderB, {
	siteId = "ConstructionSite_A",
	mode = "disrupt",
	now = 302.8,
})
local sawRegressionCap = false
for i = warnsBeforeRegressionCap + 1, #warns do
	if string.find(warns[i], "task_regression_cap_reached", 1, true) then
		sawRegressionCap = true
		break
	end
end
assertTrue(sawRegressionCap, "third major regression is rejected at configured cap")

buildRemote:FireServer(taskBuilderB, {
	siteId = "ConstructionSite_A",
	mode = "cancel",
	now = 303.1,
})

-- TIN-154 QTE slice: optional complete-time window can award early completion or apply disruption penalty.
ConstructionConfig.TaskQteEnabled = true
ConstructionConfig.TaskQteWindowSeconds = 5.0
ConstructionConfig.TaskQteBonusSeconds = 0.35
ConstructionConfig.TaskQteFailureDisrupts = true

local qteBuilder = makeAlivePlayer(9601, Vector3.new(16, 0, 10))
buildRemote:FireServer(qteBuilder, {
	siteId = "ConstructionSite_A",
	mode = "begin",
	now = 400,
})
buildRemote:FireServer(qteBuilder, {
	siteId = "ConstructionSite_A",
	mode = "complete",
	now = 401.35,
	qteTapAt = 401.35,
})

assertEqual(
	qteBuilder:GetAttribute("ConstructionTaskQteResult"),
	"success",
	"QTE success marks construction task qte attribute"
)
assertEqual(qteBuilder:GetAttribute("ConstructionTaskLastReason"), "completed", "QTE success allows completed reason")

ConstructionConfig.TaskQteWindowSeconds = 0.2
buildRemote:FireServer(qteBuilder, {
	siteId = "ConstructionSite_B",
	mode = "begin",
	now = 420,
})
local warnsBeforeQteFail = #warns
buildRemote:FireServer(qteBuilder, {
	siteId = "ConstructionSite_B",
	mode = "complete",
	now = 423.0,
	qteTapAt = 423.0,
})

local sawQteFailed = false
for i = warnsBeforeQteFail + 1, #warns do
	if string.find(warns[i], "task_qte_failed", 1, true) ~= nil then
		sawQteFailed = true
		break
	end
end
assertTrue(sawQteFailed, "QTE miss rejects completion with task_qte_failed")
assertEqual(
	qteBuilder:GetAttribute("ConstructionTaskQteResult"),
	"failed",
	"QTE failure marks construction task qte attribute"
)
assertEqual(
	qteBuilder:GetAttribute("ConstructionTaskObjectiveState"),
	"regressing",
	"QTE failure applies disruption regression penalty"
)

print("construction_service_runtime_entrypoint: contextual task progress slice checks passed")
