--!strict

local DistrictPlacementConfig =
	require("../src/ReplicatedStorage/Shared/Config/DistrictPlacementConfig")
local RealmChunkAssemblySchema =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema")
local RealmAssemblyPrototypeFixture =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture")
local RealmDistrictPlacementValidator =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmDistrictPlacementValidator")

-- ConstructionBuildRequest name captured as a local constant for boundary assertions.
-- This must never equal DistrictPlacementConfig.PlacementRemoteName.
local CONSTRUCTION_BUILD_REMOTE_NAME = "ConstructionBuildRequest"

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

local function assertNotEqual(actual: any, notExpected: any, label: string)
	if actual == notExpected then
		error(string.format("FAIL [%s]: expected value to differ from %q", label, tostring(notExpected)))
	end
	print(string.format("PASS [%s]", label))
end

-- Prototype assembly output built once for the run.
-- Prototype occupied space (from Slice 4 fixture):
--   P_Start box: worldCenter=(30,0,0), halfExtents=(60,4,40), isLandmarkAnchor=true
--   P_Exit  box: worldCenter=(90,0,0), halfExtents=(60,4,40), isLandmarkAnchor=false
local protoOutput: any =
	RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())

-- Non-conflicting district: placed far from all prototype boxes.
local function makeAcceptedRequest(): any
	return {
		districtId = "District_EntrypointTest_Accepted",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 0, y = 0, z = 500 },
				halfExtents = { x = 20, y = 10, z = 20 },
			},
		},
	}
end

-- Conflicting district: directly overlaps the P_Start prototype box.
local function makeRejectedRequest(): any
	return {
		districtId = "District_EntrypointTest_Rejected",
		proposedOccupiedSpace = {
			{
				tag = "body",
				worldCenter = { x = 30, y = 0, z = 0 },
				halfExtents = { x = 10, y = 4, z = 10 },
			},
		},
	}
end

local function run()
	-- BLOCK 1: Config contract — PlacementRemoteName is a non-empty string;
	--          RequestCooldownSeconds is a positive number.
	do
		local function runBlock(label: string)
			assertTrue(type(DistrictPlacementConfig.PlacementRemoteName) == "string",
				label .. " PlacementRemoteName is string")
			assertTrue(DistrictPlacementConfig.PlacementRemoteName ~= "",
				label .. " PlacementRemoteName is non-empty")
			assertTrue(type(DistrictPlacementConfig.RequestCooldownSeconds) == "number",
				label .. " RequestCooldownSeconds is number")
			assertTrue(DistrictPlacementConfig.RequestCooldownSeconds > 0,
				label .. " RequestCooldownSeconds is positive")
		end
		runBlock("block1 A")
		runBlock("block1 B")
	end

	-- BLOCK 2: Boundary separation — DistrictPlacementRequest remote name is distinct
	--          from ConstructionBuildRequest. The two systems must not share a remote.
	do
		local function runBlock(label: string)
			assertNotEqual(DistrictPlacementConfig.PlacementRemoteName, CONSTRUCTION_BUILD_REMOTE_NAME,
				label .. " PlacementRemoteName != ConstructionBuildRequest")
			assertEqual(DistrictPlacementConfig.PlacementRemoteName, "DistrictPlacementRequest",
				label .. " PlacementRemoteName == DistrictPlacementRequest")
		end
		runBlock("block2 A")
		runBlock("block2 B")
	end

	-- BLOCK 3: DistrictPlacementRequest shape — districtId is a non-empty string;
	--          proposedOccupiedSpace is a non-empty table of boxes with worldCenter
	--          and halfExtents each carrying x, y, z number fields.
	do
		local function runBlock(label: string)
			local request: any = makeAcceptedRequest()
			assertTrue(type(request.districtId) == "string",
				label .. " districtId is string")
			assertTrue(request.districtId ~= "",
				label .. " districtId is non-empty")
			assertTrue(type(request.proposedOccupiedSpace) == "table",
				label .. " proposedOccupiedSpace is table")
			assertTrue(#request.proposedOccupiedSpace >= 1,
				label .. " proposedOccupiedSpace has at least one box")
			local box: any = request.proposedOccupiedSpace[1]
			assertTrue(type(box) == "table",
				label .. " box is table")
			assertTrue(type(box.worldCenter) == "table",
				label .. " box.worldCenter is table")
			assertTrue(type(box.worldCenter.x) == "number",
				label .. " box.worldCenter.x is number")
			assertTrue(type(box.worldCenter.y) == "number",
				label .. " box.worldCenter.y is number")
			assertTrue(type(box.worldCenter.z) == "number",
				label .. " box.worldCenter.z is number")
			assertTrue(type(box.halfExtents) == "table",
				label .. " box.halfExtents is table")
			assertTrue(type(box.halfExtents.x) == "number",
				label .. " box.halfExtents.x is number")
			assertTrue(type(box.halfExtents.y) == "number",
				label .. " box.halfExtents.y is number")
			assertTrue(type(box.halfExtents.z) == "number",
				label .. " box.halfExtents.z is number")
		end
		runBlock("block3 A")
		runBlock("block3 B")
	end

	-- BLOCK 4: ValidatePlacement accepted path — a non-conflicting district placement
	--          against the prototype assembly output is accepted with zero reject reasons.
	do
		local function runBlock(label: string)
			local request: any = makeAcceptedRequest()
			local result: any = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
			assertTrue(type(result) == "table",
				label .. " result is table")
			assertTrue(type(result.accepted) == "boolean",
				label .. " result.accepted is boolean")
			assertTrue(result.accepted == true,
				label .. " result.accepted is true")
			assertTrue(type(result.rejectReasons) == "table",
				label .. " result.rejectReasons is table")
			assertEqual(#result.rejectReasons, 0,
				label .. " rejectReasons is empty")
			assertEqual(result.districtId, request.districtId,
				label .. " result.districtId matches request")
		end
		runBlock("block4 A")
		runBlock("block4 B")
	end

	-- BLOCK 5: ValidatePlacement rejected path — a district that overlaps the prototype
	--          P_Start occupied box is rejected with at least one reason carrying a code.
	do
		local function runBlock(label: string)
			local request: any = makeRejectedRequest()
			local result: any = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
			assertTrue(type(result) == "table",
				label .. " result is table")
			assertTrue(result.accepted == false,
				label .. " result.accepted is false")
			assertTrue(type(result.rejectReasons) == "table",
				label .. " result.rejectReasons is table")
			assertTrue(#result.rejectReasons >= 1,
				label .. " rejectReasons is non-empty")
			local reason: any = result.rejectReasons[1]
			assertTrue(type(reason.code) == "string",
				label .. " reason.code is string")
			assertTrue(reason.code ~= "",
				label .. " reason.code is non-empty")
		end
		runBlock("block5 A")
		runBlock("block5 B")
	end

	-- BLOCK 6: Result type contract — district placement result uses accepted/rejectReasons/districtId
	--          vocabulary, not ConstructionBuildRequest/ConstructionService terminology.
	--          Confirms the two systems are not blended at the result boundary.
	do
		local function runBlock(label: string)
			local result: any = RealmDistrictPlacementValidator.ValidatePlacement(
				makeAcceptedRequest(), protoOutput)
			-- District placement result fields must be present.
			assertTrue(result.accepted ~= nil,
				label .. " result has accepted field")
			assertTrue(result.rejectReasons ~= nil,
				label .. " result has rejectReasons field")
			assertTrue(result.districtId ~= nil,
				label .. " result has districtId field")
			-- Construction-site terminology must not appear in district placement results.
			assertTrue(result.isBuilt == nil,
				label .. " result has no isBuilt field (construction-site vocabulary)")
			assertTrue(result.siteId == nil,
				label .. " result has no siteId field (construction-site vocabulary)")
			assertTrue(result.buildCount == nil,
				label .. " result has no buildCount field (construction-site vocabulary)")
		end
		runBlock("block6 A")
		runBlock("block6 B")
	end

	print("district_placement_runtime_entrypoint: all blocks passed")
end

run()
