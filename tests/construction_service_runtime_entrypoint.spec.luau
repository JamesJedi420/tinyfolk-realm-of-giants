--!strict

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

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
local stationsFolder = makeNode("Stations", "Folder", "Workspace.Map.Stations")
addChild(mapFolder, "Stations", stationsFolder)
local constructionSitePart = makeBasePart("ConstructionSite_A", 10, 0, 10)
addChild(mapFolder, "ConstructionSite_A", constructionSitePart)
addChild(workspaceService, "Map", mapFolder)

local playerRemovingConnections: { (any) -> () } = {}
local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerRemoving = {
		Connect = function(_signal: any, callback: (any) -> ())
			table.insert(playerRemovingConnections, callback)
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

local scriptParent = makeNode("Services", "Folder", "ServerScriptService.Services")
-- String path stored directly to avoid child.Parent = parent on a string value
scriptParent._Children["ResourceFlowState"] = "../../ServerScriptService/Services/ResourceFlowState"
script = {
	Parent = scriptParent,
} :: any

local function makeAlivePlayer(userId: number, position: Vector3)
	local root = makeBasePart("HumanoidRootPart", position.X, position.Y, position.Z)
	local humanoid = {
		Health = 100,
	}
	local character = {
		FindFirstChild = function(self: any, childName: string): any
			if childName == "HumanoidRootPart" then
				return root
			end
			return nil
		end,
		FindFirstChildOfClass = function(self: any, className: string): any
			if className == "Humanoid" then
				return humanoid
			end
			return nil
		end,
	}
	return {
		UserId = userId,
		Character = character,
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

assertEqual(queryApiCallCount.getAll, 1, "query API GetAllPlacedDistricts called exactly once at startup")
assertEqual(queryApiCallCount.getPlaced, 0, "query API GetPlacedDistrict not called")
assertEqual(queryApiCallCount.getByPlayer, 0, "query API GetPlacedDistrictsByPlayer not called")
assertEqual(queryApiCallCount.isPlaced, 0, "query API IsDistrictPlaced not called")

local siteStateById = _G._ConstructionService_SiteState
assertTrue(type(siteStateById) == "table", "site state table exported")
assertTrue(siteStateById["ConstructionSite_A"] ~= nil, "existing site-backed state still registered")

local builder = makeAlivePlayer(9301, Vector3.new(12, 0, 12))
buildRemote:FireServer(builder, "ConstructionSite_A")

local siteState = siteStateById["ConstructionSite_A"]
assertTrue(siteState.isBuilt, "existing site-backed build mutation still works")
assertEqual(siteState.buildCount, 1, "existing site-backed build count increments")
assertEqual(siteState.lastBuiltByUserId, 9301, "existing site-backed build tracks builder")

-- Use a separate player to avoid triggering the request cooldown gate before site_not_found.
local districtProbePlayer = makeAlivePlayer(9302, Vector3.new(12, 0, 12))
local warnCountBefore = #warns
buildRemote:FireServer(districtProbePlayer, "District_Startup_A")

-- The reject warn only includes reason (not siteId), so check for site_not_found in any new warn line.
local sawDistrictSiteNotFound = false
for i = warnCountBefore + 1, #warns do
	if string.find(warns[i], "site_not_found", 1, true) then
		sawDistrictSiteNotFound = true
		break
	end
end
assertTrue(sawDistrictSiteNotFound, "district ids are not routed into site-backed build mutation path in this slice")
-- Verify district build-state entry is also untouched by the rejected request.
assertEqual(districtBuildState["District_Startup_A"].isBuilt, false, "district build state not mutated by rejected build request")

assertEqual(queryApiCallCount.getAll, 1, "query API startup discovery remains one-time after build requests")

print("construction_service_runtime_entrypoint: startup district build-state slice checks passed")
