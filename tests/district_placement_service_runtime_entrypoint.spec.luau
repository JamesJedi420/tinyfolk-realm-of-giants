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

local logs: { string } = {}
local warns: { string } = {}

local originalPrint = print
local originalWarn = warn

print = function(...: any)
	local parts: any = table.pack(...)
	local out: { string } = {}
	for i = 1, (parts.n :: number) do
		table.insert(out, tostring(parts[i]))
	end
	local line = table.concat(out, " ")
	table.insert(logs, line)
	originalPrint(...)
end

warn = function(...: any)
	local parts: any = table.pack(...)
	local out: { string } = {}
	for i = 1, (parts.n :: number) do
		table.insert(out, tostring(parts[i]))
	end
	local line = table.concat(out, " ")
	table.insert(warns, line)
	originalWarn(...)
end

local function makeNode(name: string, className: string?, fullName: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_FullName = fullName or name,
		_Children = {},
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

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local districtRemote: any = {
	Name = "DistrictPlacementRequest",
	ClassName = "RemoteEvent",
	_Handler = nil,
}

function districtRemote.IsA(self: any, expectedClass: string): boolean
	return self.ClassName == expectedClass
end

districtRemote.OnServerEvent = {
	Connect = function(_signal: any, handler: (any, any) -> ())
		districtRemote._Handler = handler
	end,
}

function districtRemote.FireServer(self: any, player: any, payload: any)
	if self._Handler == nil then
		error("district remote handler not connected")
	end
	self._Handler(player, payload)
end

local constructionRemote: any = {
	Name = "ConstructionBuildRequest",
	ClassName = "RemoteEvent",
	_Handler = nil,
}

function constructionRemote.IsA(self: any, expectedClass: string): boolean
	return self.ClassName == expectedClass
end

constructionRemote.OnServerEvent = {
	Connect = function(_signal: any, handler: (any, any) -> ())
		constructionRemote._Handler = handler
	end,
}

local remotesFolder = makeNode("Remotes", "Folder", "ReplicatedStorage.Remotes")
addChild(remotesFolder, "DistrictPlacementRequest", districtRemote)
addChild(remotesFolder, "ConstructionBuildRequest", constructionRemote)

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
addChild(configFolder, "DistrictPlacementConfig", "../../ReplicatedStorage/Shared/Config/DistrictPlacementConfig")

local realmAssemblyFolder = makeNode("RealmAssembly", "Folder", "ReplicatedStorage.Shared.RealmAssembly")
addChild(realmAssemblyFolder, "RealmChunkAssemblySchema", "../../ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema")
addChild(
	realmAssemblyFolder,
	"RealmAssemblyPrototypeFixture",
	"../../ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture"
)
addChild(
	realmAssemblyFolder,
	"RealmDistrictPlacementValidator",
	"../../ReplicatedStorage/Shared/RealmAssembly/RealmDistrictPlacementValidator"
)

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "RealmAssembly", realmAssemblyFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local playersService = {
	Name = "Players",
	ClassName = "Players",
}

local fakeGame = {}

function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local function makeAlivePlayer(userId: number): any
	local humanoid = {
		Health = 100,
	}

	local character = {}

	function character:FindFirstChildOfClass(className: string): any
		if className == "Humanoid" then
			return humanoid
		end
		return nil
	end

	return {
		UserId = userId,
		Character = character,
	}
end

local function makeAcceptedRequest(): any
	return {
		districtId = "District_RuntimeEntrypoint_Accepted",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 0, y = 0, z = 500 },
				halfExtents = { x = 20, y = 10, z = 20 },
			},
		},
	}
end

local function makeRejectedRequest(): any
	return {
		districtId = "District_RuntimeEntrypoint_Rejected",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 30, y = 0, z = 0 },
				halfExtents = { x = 10, y = 4, z = 10 },
			},
		},
	}
end

require("../src/ServerScriptService/Services/DistrictPlacementService.server")

assertTrue(districtRemote._Handler ~= nil, "service binds DistrictPlacementRequest OnServerEvent")
assertTrue(constructionRemote._Handler == nil, "service does not bind ConstructionBuildRequest OnServerEvent")

local acceptedPlayer = makeAlivePlayer(7101)
local rejectedPlayer = makeAlivePlayer(7102)

districtRemote:FireServer(acceptedPlayer, makeAcceptedRequest())
districtRemote:FireServer(rejectedPlayer, makeRejectedRequest())

local sawAccepted = false
for _, line in ipairs(logs) do
	if string.find(line, "Accepted DistrictPlacementRequest", 1, true) then
		sawAccepted = true
		break
	end
end
assertTrue(sawAccepted, "accepted request flows through DistrictPlacementRequest entrypoint")

local sawRejected = false
for _, line in ipairs(warns) do
	if string.find(line, "placement_rejected_by_validator", 1, true) then
		sawRejected = true
		break
	end
end
assertTrue(sawRejected, "rejected request flows through DistrictPlacementRequest entrypoint")

assertEqual(districtRemote.Name, "DistrictPlacementRequest", "runtime entrypoint remote name remains DistrictPlacementRequest")
assertEqual(constructionRemote.Name, "ConstructionBuildRequest", "construction remote remains separate")

print("district_placement_service_runtime_entrypoint: all checks passed")
