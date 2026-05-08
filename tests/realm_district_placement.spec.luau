--!strict

local RealmChunkAssemblySchema = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema")
local RealmAssemblyPrototypeFixture =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture")
local RealmDistrictPlacementValidator =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmDistrictPlacementValidator")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value, label)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertFalse(value, label)
	if value then
		error("assertFalse failed [" .. label .. "]")
	end
end

local function assertHasRejectCode(
	result: RealmDistrictPlacementValidator.DistrictPlacementResult,
	code: string,
	label: string
)
	for _, reason in result.rejectReasons do
		if reason.code == code then
			return
		end
	end
	error("assertHasRejectCode failed [" .. label .. "]: code '" .. code .. "' not found in rejectReasons")
end

-- Prototype assembly output — shared across all blocks.
local protoOutput =
	RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())

-- Prototype occupied space reference (from Slice 4 fixture):
--   P_Start box: worldCenter=(30,0,0), halfExtents=(60,4,40), isLandmarkAnchor=true
--   P_Exit  box: worldCenter=(90,0,0), halfExtents=(60,4,40), isLandmarkAnchor=false

local function run()
	-- BLOCK 1: Prototype assembly output is consumed directly; integrity passes.
	do
		assertTrue(protoOutput.integrity.passed, "block1 proto integrity passed")
		assertEqual(#protoOutput.resolvedOccupiedSpace, 2, "block1 two assembled boxes")
		assertEqual(#protoOutput.resolvedMetadata, 2, "block1 two metadata entries")
	end

	-- BLOCK 2: Disjoint placement passes (far away from all assembled boxes).
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_Disjoint",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 500 },
					halfExtents = { x = 20, y = 10, z = 20 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertTrue(result.accepted, "block2 disjoint accepted")
		assertEqual(#result.rejectReasons, 0, "block2 no reject reasons")
		assertEqual(result.districtId, "D_Disjoint", "block2 districtId echoed")
	end

	-- BLOCK 3: Overlap with generic (non-landmark) assembled occupied space is rejected.
	-- P_Exit box: center=(90,0,0), half=(60,4,40), x range [30,150].
	-- P_Start box: center=(30,0,0), half=(60,4,40), x range [-30,90].
	-- Use district at x=120 to land inside P_Exit only (dx from P_Start = 90, halfSum = 65, no overlap).
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_OverlapGeneric",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 120, y = 0, z = 0 },
					halfExtents = { x = 5, y = 2, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertFalse(result.accepted, "block3 overlap rejected")
		assertTrue(#result.rejectReasons >= 1, "block3 has reject reason")
		assertHasRejectCode(result, "occupied_space_overlap", "block3 code")
		-- Confirm it is NOT flagged as landmark conflict (P_Exit is not a landmark).
		-- P_Start is at dx=90 from x=120, halfSum=65, no overlap; only P_Exit fires.
		local reason = result.rejectReasons[1]
		assertFalse(reason.isLandmarkConflict, "block3 not landmark conflict")
		assertEqual(reason.conflictingPlacementId, "P_Exit", "block3 conflicting placement")
	end

	-- BLOCK 4: Overlap with landmark-anchored occupied space is rejected with landmark code.
	-- P_Start box center=(30,0,0), half=(60,4,40). District centered at (30,0,0).
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_OverlapLandmark",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 30, y = 0, z = 0 },
					halfExtents = { x = 5, y = 2, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertFalse(result.accepted, "block4 landmark overlap rejected")
		assertHasRejectCode(result, "landmark_anchor_exclusion", "block4 code")
		local reason = result.rejectReasons[1]
		assertTrue(reason.isLandmarkConflict, "block4 isLandmarkConflict")
		assertEqual(reason.conflictingPlacementId, "P_Start", "block4 conflicting placement")
	end

	-- BLOCK 5: Boundary touch (exact boundary) does NOT count as overlap (strict less-than rule).
	-- Use z-axis to find clean boundary: P_Start z range [-40,40], P_Exit z range [-40,40].
	-- District at center=(0,0,80) half=(20,4,40): dz from P_Start = 80, halfSumZ = 80 → 80<80 false.
	-- dx from P_Exit = 90, halfSumX = 80 → 90<80 false. Both axes fail → no overlap.
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_BoundaryTouch",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 0, y = 0, z = 80 },
					halfExtents = { x = 20, y = 4, z = 40 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertTrue(result.accepted, "block5 boundary touch passes")
		assertEqual(#result.rejectReasons, 0, "block5 no reject reasons")
	end

	-- BLOCK 6: Overlap by one unit past z-boundary is rejected.
	-- center=(0,0,79) half=(20,4,40): dz=79, halfSumZ=80 → 79<80 true → overlap with P_Start.
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_BoundaryOverlap",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 0, y = 0, z = 79 },
					halfExtents = { x = 20, y = 4, z = 40 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertFalse(result.accepted, "block6 just-past-boundary rejected")
		assertTrue(#result.rejectReasons >= 1, "block6 has reject reason")
	end

	-- BLOCK 7: Multiple proposed boxes — one disjoint, one overlapping — produces rejection.
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_MixedBoxes",
			proposedOccupiedSpace = {
				{
					tag = "safe",
					worldCenter = { x = 0, y = 0, z = 500 },
					halfExtents = { x = 10, y = 5, z = 10 },
				},
				{
					tag = "bad",
					worldCenter = { x = 90, y = 0, z = 0 },
					halfExtents = { x = 5, y = 2, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertFalse(result.accepted, "block7 mixed boxes rejected")
		assertHasRejectCode(result, "occupied_space_overlap", "block7 code")
	end

	-- BLOCK 8: Empty proposed occupied space always passes (vacuous).
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_Empty",
			proposedOccupiedSpace = {},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertTrue(result.accepted, "block8 empty proposedOccupiedSpace passes")
		assertEqual(#result.rejectReasons, 0, "block8 no reject reasons")
	end

	-- BLOCK 9: Repeated runs produce identical reject ordering and reason count.
	do
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
			districtId = "D_Stability",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 60, y = 0, z = 0 },
					halfExtents = { x = 10, y = 4, z = 10 },
				},
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(
			request,
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(
			request,
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		)
		assertEqual(outA.accepted, outB.accepted, "block9 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block9 reason count stable")
		for index, reasonA in ipairs(outA.rejectReasons) do
			local reasonB = outB.rejectReasons[index]
			assertEqual(reasonA.code, reasonB.code, "block9 code stable " .. tostring(index))
			assertEqual(
				reasonA.conflictingPlacementId,
				reasonB.conflictingPlacementId,
				"block9 placementId stable " .. tostring(index)
			)
			assertEqual(
				reasonA.isLandmarkConflict,
				reasonB.isLandmarkConflict,
				"block9 landmark stable " .. tostring(index)
			)
		end
	end

	print("realm_district_placement: all checks passed")
end

run()
