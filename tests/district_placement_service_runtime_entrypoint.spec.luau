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
	for i = 1, parts.n :: number do
		table.insert(out, tostring(parts[i]))
	end
	local line = table.concat(out, " ")
	table.insert(logs, line)
	originalPrint(...)
end

warn = function(...: any)
	local parts: any = table.pack(...)
	local out: { string } = {}
	for i = 1, parts.n :: number do
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
		_Attributes = {},
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
addChild(
	realmAssemblyFolder,
	"RealmChunkAssemblySchema",
	"../../ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema"
)
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

local workspaceService = makeNode("Workspace", "Workspace", "Workspace")
local mapFolder = makeNode("Map", "Folder", "Workspace.Map")
addChild(workspaceService, "Map", mapFolder)

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

assertEqual(
	districtRemote.Name,
	"DistrictPlacementRequest",
	"runtime entrypoint remote name remains DistrictPlacementRequest"
)
assertEqual(constructionRemote.Name, "ConstructionBuildRequest", "construction remote remains separate")

print("district_placement_service_runtime_entrypoint: all checks passed")

-- ============================================================================
-- TIN-175: Validation Gate Integration Tests
-- ============================================================================
-- These tests prove that the validation gate works correctly at runtime:
-- 1. Valid placements pass the validator and record in the registry
-- 2. Invalid placements are rejected before any registry mutation
-- 3. Reject reasons are deterministic and accessible
-- Workspace content creation is deferred; this slice proves the gate only.

local function getPlacedDistrictRegistry(): any
	if _G._DistrictPlacementService_Registry == nil then
		error("validation gate integration test: registry not exposed by service")
	end
	return _G._DistrictPlacementService_Registry
end

local function getDistrictsFolder(): any
	local map = workspaceService:FindFirstChild("Map")
	if map == nil then
		return nil
	end
	return map:FindFirstChild("Districts")
end

local function getDistrictArtifactCount(): number
	local districts = getDistrictsFolder()
	if districts == nil then
		return 0
	end
	return #districts:GetChildren()
end

-- TIN-175 Integration Test: Accepted Placement
-- Validates that a non-conflicting placement passes the validator and records state.
do
	local registry = getPlacedDistrictRegistry()
	local initialCount = 0
	for _ in pairs(registry) do
		initialCount = initialCount + 1
	end

	local acceptedIntegrationRequest = {
		districtId = "District_ValidationGate_Accepted_TIN175",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 100, y = 0, z = 500 },
				halfExtents = { x = 20, y = 10, z = 20 },
			},
		},
	}

	local acceptedIntegrationPlayer = makeAlivePlayer(7201)
	districtRemote:FireServer(acceptedIntegrationPlayer, acceptedIntegrationRequest)

	local entry = registry[acceptedIntegrationRequest.districtId]
	assertTrue(entry ~= nil, "TIN-175 accepted: placement recorded in registry")

	if entry then
		assertEqual(
			entry.districtId,
			acceptedIntegrationRequest.districtId,
			"TIN-175 accepted: registry entry has correct districtId"
		)
		assertEqual(
			entry.placedByUserId,
			acceptedIntegrationPlayer.UserId,
			"TIN-175 accepted: registry entry has correct placedByUserId"
		)
		assertTrue(
			type(entry.placedAt) == "number" and entry.placedAt > 0,
			"TIN-175 accepted: registry entry has valid placedAt timestamp"
		)
		assertTrue(
			type(entry.proposedOccupiedSpace) == "table" and #entry.proposedOccupiedSpace > 0,
			"TIN-175 accepted: registry entry has proposedOccupiedSpace"
		)
	end

	local afterAcceptCount = 0
	for _ in pairs(registry) do
		afterAcceptCount = afterAcceptCount + 1
	end
	assertTrue(afterAcceptCount == initialCount + 1, "TIN-175 accepted: registry size increased by exactly one entry")

	print("PASS [TIN-175 accepted: placement passes validator and records in registry]")
end

-- TIN-175 Integration Test: Rejected Placement
-- Validates that a conflicting placement is rejected before mutation with deterministic reasons.
do
	local registry = getPlacedDistrictRegistry()
	local initialCount = 0
	for _ in pairs(registry) do
		initialCount = initialCount + 1
	end

	-- This placement overlaps the prototype P_Start landmark anchor at (30,0,0)
	-- and will be rejected with "landmark_anchor_exclusion" reason.
	local rejectedIntegrationRequest = {
		districtId = "District_ValidationGate_Rejected_TIN175",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 30, y = 0, z = 0 },
				halfExtents = { x = 10, y = 4, z = 10 },
			},
		},
	}

	local rejectedIntegrationPlayer = makeAlivePlayer(7202)
	districtRemote:FireServer(rejectedIntegrationPlayer, rejectedIntegrationRequest)

	local entry = registry[rejectedIntegrationRequest.districtId]
	assertTrue(entry == nil, "TIN-175 rejected: placement NOT recorded in registry (mutation prevented)")

	local afterRejectCount = 0
	for _ in pairs(registry) do
		afterRejectCount = afterRejectCount + 1
	end
	assertTrue(afterRejectCount == initialCount, "TIN-175 rejected: registry size unchanged (no mutation on reject)")

	-- Verify rejection was logged with deterministic reason
	local sawRejectionWithCode = false
	for _, line in ipairs(logs) do
		if
			type(line) == "string"
			and string.find(line, "PlacementOutcome status=rejected", 1, true)
			and string.find(line, "placement_rejected_by_validator", 1, true)
			and string.find(line, "District_ValidationGate_Rejected_TIN175", 1, true)
		then
			sawRejectionWithCode = true
			break
		end
	end
	assertTrue(sawRejectionWithCode, "TIN-175 rejected: rejection logged with deterministic validation reason")

	print("PASS [TIN-175 rejected: placement blocked before mutation with deterministic reason]")
end

-- TIN-189 Integration Test: Accepted Placement Materializes World State
-- Validates that an accepted placement creates explicit district world-state content.
do
	local registry = getPlacedDistrictRegistry()
	local registryInitialCount = 0
	for _ in pairs(registry) do
		registryInitialCount = registryInitialCount + 1
	end

	local acceptedIntegrationRequest = {
		districtId = "District_WorldState_Accepted_TIN189",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 200, y = 0, z = 500 },
				halfExtents = { x = 20, y = 10, z = 20 },
			},
		},
	}

	local acceptedIntegrationPlayer = makeAlivePlayer(7301)
	districtRemote:FireServer(acceptedIntegrationPlayer, acceptedIntegrationRequest)

	local registryEntry = registry[acceptedIntegrationRequest.districtId]
	assertTrue(registryEntry ~= nil, "TIN-189 accepted: registry still records accepted placement")

	assertTrue(registryEntry.materializedWorldState ~= nil, "TIN-189 accepted: world-state payload created")

	if registryEntry.materializedWorldState then
		local worldStateEntry = registryEntry.materializedWorldState
		assertEqual(
			worldStateEntry.districtId,
			acceptedIntegrationRequest.districtId,
			"TIN-189 accepted: world-state districtId matches"
		)
		assertEqual(
			worldStateEntry.placedByUserId,
			acceptedIntegrationPlayer.UserId,
			"TIN-189 accepted: world-state placedByUserId matches"
		)
		assertTrue(
			type(worldStateEntry.placedAt) == "number" and worldStateEntry.placedAt > 0,
			"TIN-189 accepted: world-state placedAt is valid"
		)
		assertTrue(
			type(worldStateEntry.proposedOccupiedSpace) == "table" and #worldStateEntry.proposedOccupiedSpace > 0,
			"TIN-189 accepted: world-state retains proposedOccupiedSpace"
		)
	end

	local registryAfterCount = 0
	for _ in pairs(registry) do
		registryAfterCount = registryAfterCount + 1
	end
	assertTrue(
		registryAfterCount == registryInitialCount + 1,
		"TIN-189 accepted: registry size increased by exactly one entry"
	)

	print("PASS [TIN-189 accepted: placement materializes explicit world state]")
end

-- TIN-189 Integration Test: Rejected Placement Does Not Materialize World State
-- Validates that rejected placements still create no explicit district world state.
do
	local registry = getPlacedDistrictRegistry()
	local registryInitialCount = 0
	for _ in pairs(registry) do
		registryInitialCount = registryInitialCount + 1
	end

	local rejectedIntegrationRequest = {
		districtId = "District_WorldState_Rejected_TIN189",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 30, y = 0, z = 0 },
				halfExtents = { x = 10, y = 4, z = 10 },
			},
		},
	}

	local rejectedIntegrationPlayer = makeAlivePlayer(7302)
	districtRemote:FireServer(rejectedIntegrationPlayer, rejectedIntegrationRequest)

	assertTrue(
		registry[rejectedIntegrationRequest.districtId] == nil,
		"TIN-189 rejected: registry remains unchanged for rejected placement"
	)

	local registryAfterCount = 0
	for _ in pairs(registry) do
		registryAfterCount = registryAfterCount + 1
	end
	assertTrue(registryAfterCount == registryInitialCount, "TIN-189 rejected: registry size unchanged")

	assertTrue(
		registry[rejectedIntegrationRequest.districtId] == nil
			or registry[rejectedIntegrationRequest.districtId].materializedWorldState == nil,
		"TIN-189 rejected: no world-state payload created"
	)

	local sawRejectionWithCode = false
	for _, line in ipairs(logs) do
		if
			type(line) == "string"
			and string.find(line, "PlacementOutcome status=rejected", 1, true)
			and string.find(line, "placement_rejected_by_validator", 1, true)
			and string.find(line, "District_WorldState_Rejected_TIN189", 1, true)
		then
			sawRejectionWithCode = true
			break
		end
	end
	assertTrue(sawRejectionWithCode, "TIN-189 rejected: rejection logged with deterministic validation reason")

	print("PASS [TIN-189 rejected: placement does not materialize world state]")
end

print("district_placement_validation_gate_integration: all validation gate tests passed")

-- TIN-190 Integration Test: Accepted Placement Materializes One Workspace Artifact
do
	local registry = getPlacedDistrictRegistry()
	local initialArtifactCount = getDistrictArtifactCount()

	local acceptedIntegrationRequest = {
		districtId = "District_WorkspaceArtifact_Accepted_TIN190",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 300, y = 0, z = 500 },
				halfExtents = { x = 20, y = 10, z = 20 },
			},
		},
	}

	local acceptedIntegrationPlayer = makeAlivePlayer(7401)
	districtRemote:FireServer(acceptedIntegrationPlayer, acceptedIntegrationRequest)

	local registryEntry = registry[acceptedIntegrationRequest.districtId]
	assertTrue(registryEntry ~= nil, "TIN-190 accepted: registry still records accepted placement")

	local districtsFolder = getDistrictsFolder()
	assertTrue(districtsFolder ~= nil, "TIN-190 accepted: Workspace.Map.Districts exists")

	if districtsFolder ~= nil then
		local artifact = districtsFolder:FindFirstChild(acceptedIntegrationRequest.districtId)
		assertTrue(artifact ~= nil, "TIN-190 accepted: exactly one district artifact exists by districtId")

		if artifact ~= nil then
			assertEqual(
				artifact:GetAttribute("DistrictId"),
				acceptedIntegrationRequest.districtId,
				"TIN-190 accepted: artifact DistrictId attribute matches"
			)
			assertEqual(
				artifact:GetAttribute("PlacedByUserId"),
				acceptedIntegrationPlayer.UserId,
				"TIN-190 accepted: artifact PlacedByUserId attribute matches"
			)
			assertTrue(
				type(artifact:GetAttribute("PlacedAt")) == "number" and artifact:GetAttribute("PlacedAt") > 0,
				"TIN-190 accepted: artifact PlacedAt attribute is valid"
			)
			assertEqual(
				artifact:GetAttribute("OccupiedBoxCount"),
				#acceptedIntegrationRequest.proposedOccupiedSpace,
				"TIN-190 accepted: artifact OccupiedBoxCount attribute matches"
			)
		end
	end

	local afterArtifactCount = getDistrictArtifactCount()
	assertTrue(
		afterArtifactCount == initialArtifactCount + 1,
		"TIN-190 accepted: district artifact count increased by exactly one"
	)

	print("PASS [TIN-190 accepted: one Workspace artifact materialized]")
end

-- TIN-190 Integration Test: Rejected Placement Materializes No Workspace Artifact
do
	local registry = getPlacedDistrictRegistry()
	local initialArtifactCount = getDistrictArtifactCount()

	local rejectedIntegrationRequest = {
		districtId = "District_WorkspaceArtifact_Rejected_TIN190",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 30, y = 0, z = 0 },
				halfExtents = { x = 10, y = 4, z = 10 },
			},
		},
	}

	local rejectedIntegrationPlayer = makeAlivePlayer(7402)
	districtRemote:FireServer(rejectedIntegrationPlayer, rejectedIntegrationRequest)

	assertTrue(
		registry[rejectedIntegrationRequest.districtId] == nil,
		"TIN-190 rejected: registry remains unchanged for rejected placement"
	)

	local districtsFolder = getDistrictsFolder()
	if districtsFolder ~= nil then
		assertTrue(
			districtsFolder:FindFirstChild(rejectedIntegrationRequest.districtId) == nil,
			"TIN-190 rejected: no district artifact exists for rejected placement"
		)
	end

	local afterArtifactCount = getDistrictArtifactCount()
	assertTrue(afterArtifactCount == initialArtifactCount, "TIN-190 rejected: district artifact count unchanged")

	local sawRejectionWithCode = false
	for _, line in ipairs(logs) do
		if
			type(line) == "string"
			and string.find(line, "PlacementOutcome status=rejected", 1, true)
			and string.find(line, "placement_rejected_by_validator", 1, true)
			and string.find(line, "District_WorkspaceArtifact_Rejected_TIN190", 1, true)
		then
			sawRejectionWithCode = true
			break
		end
	end
	assertTrue(
		sawRejectionWithCode,
		"TIN-190 rejected: validator rejection logged before any Workspace artifact mutation"
	)

	print("PASS [TIN-190 rejected: no Workspace artifact materialized]")
end

-- TIN-191 Contract Proof: Deterministic Artifact Lifecycle Ownership
-- Validates that district artifact ownership is deterministic for repeated accepted placements.
-- Same districtId reacceptance replaces the owned artifact deterministically (not based on instance identity).
-- Artifact count remains one per districtId; metadata updates to latest accepted payload.
do
	local registry = getPlacedDistrictRegistry()
	local initialArtifactCount = getDistrictArtifactCount()

	local lifecycleDistrictId = "District_WorkspaceArtifact_Lifecycle_TIN190"
	local firstAcceptedRequest = {
		districtId = lifecycleDistrictId,
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 340, y = 0, z = 500 },
				halfExtents = { x = 20, y = 10, z = 20 },
			},
		},
	}
	local firstAcceptedPlayer = makeAlivePlayer(7501)
	districtRemote:FireServer(firstAcceptedPlayer, firstAcceptedRequest)

	local secondAcceptedRequest = {
		districtId = lifecycleDistrictId,
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 360, y = 0, z = 520 },
				halfExtents = { x = 24, y = 12, z = 24 },
			},
		},
	}
	local secondAcceptedPlayer = makeAlivePlayer(7502)
	districtRemote:FireServer(secondAcceptedPlayer, secondAcceptedRequest)

	local registryEntry = registry[lifecycleDistrictId]
	assertTrue(registryEntry ~= nil, "TIN-190 lifecycle: registry keeps accepted district state")

	if registryEntry ~= nil then
		assertEqual(
			registryEntry.placedByUserId,
			secondAcceptedPlayer.UserId,
			"TIN-190 lifecycle: registry entry ownership updates to the latest accepted placement"
		)
		assertTrue(
			registryEntry.materializedWorldState ~= nil,
			"TIN-190 lifecycle: world-state payload still exists after replacement"
		)
		if registryEntry.materializedWorldState then
			assertEqual(
				registryEntry.materializedWorldState.placedByUserId,
				secondAcceptedPlayer.UserId,
				"TIN-190 lifecycle: world-state placedByUserId updates to latest accepted placement"
			)
			assertEqual(
				registryEntry.materializedWorldState.proposedOccupiedSpace[1].worldCenter.x,
				secondAcceptedRequest.proposedOccupiedSpace[1].worldCenter.x,
				"TIN-190 lifecycle: world-state proposedOccupiedSpace updates to latest accepted placement"
			)
		end
	end

	local districtsFolder = getDistrictsFolder()
	assertTrue(districtsFolder ~= nil, "TIN-190 lifecycle: Workspace.Map.Districts exists")
	if districtsFolder ~= nil then
		local artifact = districtsFolder:FindFirstChild(lifecycleDistrictId)
		assertTrue(artifact ~= nil, "TIN-190 lifecycle: district artifact remains present after replacement")
		if artifact ~= nil then
			assertEqual(
				artifact:GetAttribute("PlacedByUserId"),
				secondAcceptedPlayer.UserId,
				"TIN-190 lifecycle: artifact ownership updates to latest accepted placement"
			)
			assertEqual(
				artifact:GetAttribute("OccupiedBoxCount"),
				#secondAcceptedRequest.proposedOccupiedSpace,
				"TIN-190 lifecycle: artifact metadata updates to latest accepted placement"
			)
		end
	end

	local afterArtifactCount = getDistrictArtifactCount()
	assertTrue(
		afterArtifactCount == initialArtifactCount + 1,
		"TIN-190 lifecycle: repeated accepted placement keeps exactly one district artifact"
	)

	print("PASS [TIN-191 contract: same districtId replaces owned artifact deterministically, count remains one]")
end

print("district_placement_workspace_artifact_integration: all TIN-190 checks passed")
