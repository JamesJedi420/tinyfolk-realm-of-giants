--!strict

local RealmChunkAssemblySchema = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema")
local RealmAssemblyPrototypeFixture =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture")
local RealmDistrictPlacementValidator =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmDistrictPlacementValidator")

type DistrictPlacementRequest = any
type DistrictPlacementResult = any
type DistrictCriticalExclusionConfig = any
type DistrictPlacementPolicyConfig = any
type DistrictPlacementHardConfig = any
type DistrictPlacementSoftConfig = any

local EXPECTED_RESULT_SECTION_ORDER = {
	"districtId",
	"accepted",
	"rejectReasons",
	"devaluation",
	"configSnapshot",
	"validationSnapshot",
}

local EXPECTED_DEVALUATION_SECTION_ORDER = {
	"penalties",
	"totalPenalty",
	"categoryTotals",
	"groupSummaries",
	"factorSummaries",
	"subjectSummaries",
	"configSnapshot",
}

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

local function assertHasRejectCode(result: DistrictPlacementResult, code: string, label: string)
	for _, reason in result.rejectReasons do
		if reason.code == code then
			return
		end
	end
	error("assertHasRejectCode failed [" .. label .. "]: code '" .. code .. "' not found in rejectReasons")
end

-- Prototype assembly output — shared across all blocks.
local function assertValidationResultShape(result: any, label: string)
	for i, sectionName in ipairs(EXPECTED_RESULT_SECTION_ORDER) do
		assertTrue(result[sectionName] ~= nil, label .. " result section " .. tostring(i))
	end
	for i, sectionName in ipairs(EXPECTED_DEVALUATION_SECTION_ORDER) do
		assertTrue(result.devaluation[sectionName] ~= nil, label .. " devaluation section " .. tostring(i))
	end
	assertTrue(type(result.accepted) == "boolean", label .. " accepted")
	assertTrue(type(result.rejectReasons) == "table", label .. " reject reasons")
	assertTrue(type(result.devaluation) == "table", label .. " devaluation")
	assertTrue(type(result.devaluation.penalties) == "table", label .. " penalties")
	assertTrue(type(result.devaluation.categoryTotals) == "table", label .. " category totals")
	assertTrue(type(result.devaluation.groupSummaries) == "table", label .. " group summaries")
	assertTrue(type(result.devaluation.factorSummaries) == "table", label .. " factor summaries")
	assertTrue(type(result.devaluation.subjectSummaries) == "table", label .. " subject summaries")
	assertTrue(type(result.devaluation.configSnapshot) == "table", label .. " soft config snapshot")
	assertTrue(type(result.configSnapshot) == "table", label .. " hard config snapshot")
	assertTrue(type(result.validationSnapshot) == "table", label .. " validation snapshot")
	assertTrue(type(result.validationSnapshot.hardConfig) == "table", label .. " validation hard snapshot")
	assertTrue(type(result.validationSnapshot.softConfig) == "table", label .. " validation soft snapshot")
end

local function assertCompatibilitySnapshotPaths(result: any, label: string)
	assertTrue(result.configSnapshot == result.validationSnapshot.hardConfig, label .. " hard snapshot reference")
	assertTrue(
		result.devaluation.configSnapshot == result.validationSnapshot.softConfig,
		label .. " soft snapshot reference"
	)
	assertEqual(
		result.configSnapshot.criticalExclusionRadii.tinyfolk_spawn,
		result.validationSnapshot.hardConfig.criticalExclusionRadii.tinyfolk_spawn,
		label .. " hard critical"
	)
	assertEqual(
		#result.configSnapshot.policy.allowedEnvironmentClasses,
		#result.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses,
		label .. " hard environment count"
	)
	assertEqual(
		result.devaluation.configSnapshot.criticalPointSoftRadii.tinyfolk_spawn,
		result.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
		label .. " soft critical"
	)
	assertEqual(
		result.devaluation.configSnapshot.routeEdgeSoftRadius,
		result.validationSnapshot.softConfig.routeEdgeSoftRadius,
		label .. " soft route"
	)
	assertEqual(
		result.devaluation.configSnapshot.densityPressurePenaltyScores.dense,
		result.validationSnapshot.softConfig.densityPressurePenaltyScores.dense,
		label .. " soft density"
	)
end

local function assertSnapshotMatrix(result: any, label: string)
	assertTrue(type(result.validationSnapshot) == "table", label .. " validation snapshot")
	assertTrue(type(result.validationSnapshot.hardConfig) == "table", label .. " unified hard snapshot")
	assertTrue(type(result.validationSnapshot.softConfig) == "table", label .. " unified soft snapshot")
	assertCompatibilitySnapshotPaths(result, label .. " compatibility")
end

local function assertSummaryMatrix(result: any, expectPenalties: boolean, label: string)
	assertTrue(type(result.devaluation.categoryTotals) == "table", label .. " category totals")
	assertTrue(type(result.devaluation.groupSummaries) == "table", label .. " group summaries")
	assertTrue(type(result.devaluation.factorSummaries) == "table", label .. " factor summaries")
	assertTrue(type(result.devaluation.subjectSummaries) == "table", label .. " subject summaries")
	assertTrue(#result.devaluation.categoryTotals > 0, label .. " category totals present")
	assertTrue(#result.devaluation.groupSummaries > 0, label .. " group summaries present")
	assertEqual(
		#result.devaluation.groupSummaries,
		#result.devaluation.categoryTotals,
		label .. " category/group summary count"
	)
	for i, categoryTotal in ipairs(result.devaluation.categoryTotals) do
		local groupSummary = result.devaluation.groupSummaries[i]
		assertEqual(groupSummary.category, categoryTotal.category, label .. " summary category " .. tostring(i))
		assertEqual(groupSummary.totalScore, categoryTotal.totalScore, label .. " summary score " .. tostring(i))
	end
	assertEqual(#result.devaluation.factorSummaries > 0, expectPenalties, label .. " factor summary mode")
	assertEqual(#result.devaluation.subjectSummaries > 0, expectPenalties, label .. " subject summary mode")
end

local function assertReasonMatrix(result: any, expectRejects: boolean, expectPenalties: boolean, label: string)
	assertTrue(type(result.rejectReasons) == "table", label .. " reject reasons")
	assertEqual(#result.rejectReasons > 0, expectRejects, label .. " reject count mode")
	for i, reason in ipairs(result.rejectReasons) do
		assertTrue(type(reason.code) == "string", label .. " reason code " .. tostring(i))
		assertTrue(type(reason.message) == "string", label .. " reason message " .. tostring(i))
		assertTrue(type(reason.isLandmarkConflict) == "boolean", label .. " reason landmark flag " .. tostring(i))
	end
	if expectRejects and expectPenalties then
		assertTrue(result.devaluation.totalPenalty > 0, label .. " reject/devalue total coexistence")
		assertTrue(#result.devaluation.penalties > 0, label .. " reject/devalue penalty coexistence")
	end
end

local function assertValidationResultContract(
	result: any,
	expectedAccepted: boolean,
	expectRejects: boolean,
	expectPenalties: boolean,
	label: string
)
	assertValidationResultShape(result, label .. " shape")
	assertEqual(result.accepted, expectedAccepted, label .. " accepted")
	assertReasonMatrix(result, expectRejects, expectPenalties, label .. " reasons")
	assertEqual(result.devaluation.totalPenalty > 0, expectPenalties, label .. " penalty score mode")
	assertEqual(#result.devaluation.penalties > 0, expectPenalties, label .. " penalty count mode")
	assertSnapshotMatrix(result, label .. " snapshot")
	assertSummaryMatrix(result, expectPenalties, label .. " summaries")
end

local function assertMinimalConsumerReadPaths(result: any, label: string)
	assertTrue(type(result.accepted) == "boolean", label .. " accepted readable")
	assertTrue(type(result.rejectReasons) == "table", label .. " reject reasons readable")
	assertTrue(type(result.devaluation.totalPenalty) == "number", label .. " total penalty readable")
	assertTrue(type(result.devaluation.categoryTotals) == "table", label .. " category totals readable")
	assertTrue(type(result.validationSnapshot.hardConfig) == "table", label .. " hard snapshot readable")
	assertTrue(type(result.validationSnapshot.softConfig) == "table", label .. " soft snapshot readable")
	assertSnapshotMatrix(result, label .. " snapshot")
end

local function assertResultModeMatrix(
	result: any,
	expectedAccepted: boolean,
	expectRejects: boolean,
	expectPenalties: boolean,
	label: string
)
	assertValidationResultContract(result, expectedAccepted, expectRejects, expectPenalties, label)
end

local protoOutput =
	RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())

local function makeRoutePressureOutput(): any
	return {
		descriptor = {
			spawns = {
				{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
			},
			escapeRoutes = {
				{ name = "EscapeRoute_A", position = { x = 100, y = 0, z = 0 } },
			},
			returnPoints = {},
			stations = {},
			constructionSites = {},
			upgradeBoards = {},
			controlZones = {},
			captureZones = {},
			props = {},
			routeGraph = {
				nodes = {
					{ name = "SpawnNode", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn" },
					{ name = "EscapeNode", position = { x = 100, y = 0, z = 0 }, nodeType = "escape" },
				},
				edges = {
					{ from = "SpawnNode", to = "EscapeNode", distance = 100 },
				},
			},
		},
		resolvedOccupiedSpace = {},
		resolvedMetadata = {},
		resolvedMetadataByPlacement = {},
	}
end

local function makeCriticalCategoryOutput(): any
	return {
		descriptor = {
			spawns = {
				{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
			},
			escapeRoutes = {
				{ name = "EscapeRoute_A", position = { x = 100, y = 0, z = 0 } },
			},
			returnPoints = {
				{ name = "ReturnPoint_A", position = { x = 200, y = 0, z = 0 } },
			},
			stations = {
				{ name = "Station_A", position = { x = 300, y = 0, z = 0 } },
			},
			constructionSites = {
				{ name = "ConstructionSite_A", position = { x = 400, y = 0, z = 0 } },
			},
			upgradeBoards = {},
			controlZones = {
				{ name = "ControlZone_A", position = { x = 500, y = 0, z = 0 } },
			},
			captureZones = {
				{ name = "CaptureZone_A", position = { x = 600, y = 0, z = 0 } },
			},
			props = {},
			routeGraph = {
				nodes = {},
				edges = {},
			},
		},
		resolvedOccupiedSpace = {},
		resolvedMetadata = {},
		resolvedMetadataByPlacement = {},
	}
end

local function makeDensityCategoryOutput(): any
	return {
		descriptor = {
			spawns = {},
			escapeRoutes = {},
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
		},
		resolvedOccupiedSpace = {
			{
				placementId = "P_Moderate",
				chunkId = "Chunk_Moderate",
				tag = "moderate_body",
				worldCenter = { x = 0, y = 0, z = 0 },
				halfExtents = { x = 5, y = 5, z = 5 },
				isLandmarkAnchor = false,
			},
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 30, y = 0, z = 0 },
				halfExtents = { x = 5, y = 5, z = 5 },
				isLandmarkAnchor = false,
			},
		},
		resolvedMetadata = {
			{
				placementId = "P_Moderate",
				chunkId = "Chunk_Moderate",
				traversalDensityClass = "moderate",
			},
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		},
		resolvedMetadataByPlacement = {
			P_Moderate = {
				placementId = "P_Moderate",
				chunkId = "Chunk_Moderate",
				traversalDensityClass = "moderate",
			},
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		},
	}
end

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
		local request: DistrictPlacementRequest = {
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
		local request: DistrictPlacementRequest = {
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
		local request: DistrictPlacementRequest = {
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
		local request: DistrictPlacementRequest = {
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
		local request: DistrictPlacementRequest = {
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
		local request: DistrictPlacementRequest = {
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
		local request: DistrictPlacementRequest = {
			districtId = "D_Empty",
			proposedOccupiedSpace = {},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertTrue(result.accepted, "block8 empty proposedOccupiedSpace passes")
		assertEqual(#result.rejectReasons, 0, "block8 no reject reasons")
	end

	-- BLOCK 9: Repeated runs produce identical reject ordering and reason count.
	do
		local request: DistrictPlacementRequest = {
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

	-- Slice 3: critical-point proximity gate
	-- Prototype world-space critical points:
	--   P_Start::TinyfolkSpawn      at (0,   0, 0)
	--   P_Start::TinyfolkReturnPoint at (-20, 0, 0)
	--   P_Start::WorkStation_A       at (25,  0, 0)
	--   P_Start::ConstructionSite_A  at (15,  0, 10)
	--   P_Start::GiantCaptureZone_A  at (40,  0, 20)
	--   P_Exit::EscapeRoute_A        at (120, 0, 0)
	-- All z=0 for P_Start content; P_Start occupiedBox z range is [-40, +40].
	-- A box centered at (x, 0, 50) halfExtents (5,5,5) is:
	--   - outside the P_Start occupied box (z: 50 < 40+5=45? false → no Slice 1 overlap)
	--   - at surface distance 45 from any point at the same (x,0,0)

	-- BLOCK 16: Disjoint placement far from all critical points passes Slice 3 with a
	-- non-zero critical config (no spatial proximity violation).
	do
		local cfg: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 50,
			stationExclusionRadius = 50,
			constructionSiteExclusionRadius = 50,
			captureZoneExclusionRadius = 50,
			controlZoneExclusionRadius = 50,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_CritDisjoint",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 500 },
					halfExtents = { x = 20, y = 10, z = 20 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, cfg)
		assertTrue(result.accepted, "block16 critical-disjoint passes")
		assertEqual(#result.rejectReasons, 0, "block16 no reject reasons")
	end

	-- BLOCK 17: Box at surface distance 45 from TinyfolkSpawn.
	-- exclusionRadius 50 → 45 < 50 → fires. exclusionRadius 40 → 45 < 40 → does not fire.
	-- Box center (0,0,50) halfExtents (5,5,5):
	--   distPointToAABB({0,0,0}, {0,0,50}, {5,5,5}) = dz = max(0, 50-5) = 45.
	do
		local cfgFires: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local cfgSafe: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 40,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_TinyfolkSpawnProx",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 0, y = 0, z = 50 },
					halfExtents = { x = 5, y = 5, z = 5 },
				},
			},
		}
		local resultFires = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, cfgFires)
		assertFalse(resultFires.accepted, "block17 spawn proximity rejected")
		assertHasRejectCode(resultFires, "tinyfolk_spawn_exclusion", "block17 code")
		local r = resultFires.rejectReasons[#resultFires.rejectReasons]
		assertEqual(r.criticalCategory, "tinyfolk_spawn", "block17 category")
		assertTrue(
			r.conflictingCriticalPointName ~= nil
				and string.find(r.conflictingCriticalPointName, "TinyfolkSpawn", 1, true) ~= nil,
			"block17 conflicting name contains TinyfolkSpawn"
		)
		local resultSafe = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, cfgSafe)
		assertTrue(resultSafe.accepted, "block17 below radius passes")
	end

	-- BLOCK 18: Box at surface distance 45 from EscapeRoute_A (world 120,0,0).
	-- Box center (120,0,50) halfExtents (5,5,5).
	-- P_Exit occupied box z range [-40,40]: |50-0|=50 < 45? false → no Slice 1 overlap.
	do
		local cfg: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_EscapeRouteProx",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 120, y = 0, z = 50 },
					halfExtents = { x = 5, y = 5, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, cfg)
		assertFalse(result.accepted, "block18 escape route proximity rejected")
		assertHasRejectCode(result, "escape_route_exclusion", "block18 code")
		local r = result.rejectReasons[#result.rejectReasons]
		assertEqual(r.criticalCategory, "escape_route", "block18 category")
	end

	-- BLOCK 19: Box at surface distance 45 from WorkStation_A (world 25,0,0).
	-- Box center (25,0,50) halfExtents (5,5,5).
	-- P_Start occupied box z range [-40,40]: |50-0|=50 < 45? false → no Slice 1 overlap.
	do
		local cfgStation: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 50,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_StationProx",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 25, y = 0, z = 50 },
					halfExtents = { x = 5, y = 5, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, cfgStation)
		assertFalse(result.accepted, "block19 station proximity rejected")
		assertHasRejectCode(result, "station_exclusion", "block19 station code")

		-- Also confirm construction site exclusion fires for ConstructionSite_A at (15,0,10).
		-- Box center (15,0,60) halfExtents (5,5,5).
		-- dz = max(0, |10-60|-5) = max(0,45) = 45 < constructionSiteExclusionRadius=50 → fires.
		local cfgSite: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 50,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local reqSite: DistrictPlacementRequest = {
			districtId = "D_SiteProx",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 15, y = 0, z = 60 },
					halfExtents = { x = 5, y = 5, z = 5 },
				},
			},
		}
		local resultSite = RealmDistrictPlacementValidator.ValidatePlacement(reqSite, protoOutput, cfgSite)
		assertFalse(resultSite.accepted, "block19 construction site proximity rejected")
		assertHasRejectCode(resultSite, "construction_site_exclusion", "block19 site code")
		local rSite = resultSite.rejectReasons[#resultSite.rejectReasons]
		assertEqual(rSite.criticalCategory, "construction_site", "block19 site category")
	end

	-- BLOCK 20: Multiple critical violations coexist in one result.
	-- Two proposed boxes: one close to TinyfolkSpawn, one close to EscapeRoute_A.
	-- Both categories enabled → two reject reasons, one per violated critical point.
	do
		local cfg: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_MultiCritical",
			proposedOccupiedSpace = {
				-- Near TinyfolkSpawn (0,0,0): surface dist = 45
				{ tag = "box_a", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
				-- Near EscapeRoute_A (120,0,0): surface dist = 45
				{ tag = "box_b", worldCenter = { x = 120, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, cfg)
		assertFalse(result.accepted, "block20 multi-critical rejected")
		assertHasRejectCode(result, "tinyfolk_spawn_exclusion", "block20 spawn code")
		assertHasRejectCode(result, "escape_route_exclusion", "block20 escape code")
		-- Both violations must be present.
		local spawnCount, escapeCount = 0, 0
		for _, reason in result.rejectReasons do
			if reason.code == "tinyfolk_spawn_exclusion" then
				spawnCount += 1
			elseif reason.code == "escape_route_exclusion" then
				escapeCount += 1
			end
		end
		assertEqual(spawnCount, 1, "block20 one spawn violation")
		assertEqual(escapeCount, 1, "block20 one escape violation")
	end

	-- BLOCK 21: All exclusion radii = 0 disables Slice 3 check entirely; placement passes.
	do
		local cfg: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		-- Same box from block17 that would fire with radius=50.
		local request: DistrictPlacementRequest = {
			districtId = "D_ZeroRadius",
			proposedOccupiedSpace = {
				{ tag = "core", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, cfg)
		assertTrue(result.accepted, "block21 zero-radius config passes")
		assertEqual(#result.rejectReasons, 0, "block21 no reject reasons")
	end

	-- BLOCK 22: Nil criticalConfig leaves Slice 1/2 active but skips Slice 3.
	-- Block17's box (near TinyfolkSpawn) has no occupied-space overlap → Slices 1 and 2 pass.
	-- Without criticalConfig, Slice 3 does not fire.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_NilConfig",
			proposedOccupiedSpace = {
				{ tag = "core", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertTrue(result.accepted, "block22 nil config skips slice3")
	end

	-- BLOCK 23: Stability — repeated Slice 3 runs with same input produce identical output.
	do
		local cfg: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 50,
			stationExclusionRadius = 50,
			constructionSiteExclusionRadius = 50,
			captureZoneExclusionRadius = 50,
			controlZoneExclusionRadius = 50,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_Stability3",
			proposedOccupiedSpace = {
				{ tag = "core", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local function build()
			return RealmDistrictPlacementValidator.ValidatePlacement(
				request,
				RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()),
				cfg
			)
		end
		local outA = build()
		local outB = build()
		assertEqual(outA.accepted, outB.accepted, "block23 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block23 count stable")
		for i, rA in ipairs(outA.rejectReasons) do
			local rB = outB.rejectReasons[i]
			assertEqual(rA.code, rB.code, "block23 code stable " .. i)
			assertEqual(rA.criticalCategory, rB.criticalCategory, "block23 category stable " .. i)
			assertEqual(
				rA.conflictingCriticalPointName,
				rB.conflictingCriticalPointName,
				"block23 point name stable " .. i
			)
		end
	end

	-- Slice 2: route/escape preservation gate
	-- Prototype escape routes (world-space):
	--   P_Exit::EscapeRoute_A at (120, 0, 0)  [from Chunk_Exit local (0,0,0) + P_Exit at (120,0,0)]

	-- BLOCK 10: Disjoint placement that does not overlap any escape route position passes.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_RouteDisjoint",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 500 },
					halfExtents = { x = 30, y = 10, z = 30 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertTrue(result.accepted, "block10 route-disjoint passes")
		assertEqual(#result.rejectReasons, 0, "block10 no reject reasons")
	end

	-- BLOCK 11: Placement whose box strictly contains the only escape route position fails.
	-- EscapeRoute_A is at world (120,0,0). Box centered at (120,0,0) with halfExtents (5,5,5)
	-- strictly contains that point.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_BlocksEscape",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 120, y = 0, z = 0 },
					halfExtents = { x = 5, y = 5, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertFalse(result.accepted, "block11 escape blocked rejected")
		assertHasRejectCode(result, "route_escape_preservation_failure", "block11 code")
		local reason = result.rejectReasons[#result.rejectReasons]
		assertFalse(reason.isLandmarkConflict, "block11 not landmark conflict")
	end

	-- BLOCK 12: Escape route position exactly on box boundary is NOT blocked (boundary convention).
	-- EscapeRoute_A at (120,0,0). Box at (115,0,0) halfExtents (5,5,5):
	-- |120-115| = 5, halfExtents.x = 5 → 5 < 5 is false → not inside.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_EscapeBoundary",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 115, y = 0, z = 0 },
					halfExtents = { x = 5, y = 5, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		-- Occupied-space overlap with P_Exit box will fire (P_Exit center=90, half=60 → range [30,150]).
		-- But route escape check should NOT fire (escape point at boundary, not inside).
		local hasEscapeFailure = false
		for _, reason in result.rejectReasons do
			if reason.code == "route_escape_preservation_failure" then
				hasEscapeFailure = true
			end
		end
		assertFalse(hasEscapeFailure, "block12 escape boundary not blocked")
	end

	-- BLOCK 13: Placement that is one unit inside boundary DOES block the escape route.
	-- Box at (114,0,0) halfExtents (5,5,5): |120-114|=6 < 5? No... adjust.
	-- Use box at (116,0,0) halfExtents (5,5,5): |120-116|=4 < 5 → inside → blocked.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_EscapeInsideBoundary",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 116, y = 0, z = 0 },
					halfExtents = { x = 5, y = 5, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertFalse(result.accepted, "block13 just-inside boundary blocks escape")
		assertHasRejectCode(result, "route_escape_preservation_failure", "block13 code")
	end

	-- BLOCK 14: Slice 1 and Slice 2 rejections can coexist in the same result.
	-- Use a box that both overlaps assembled occupied space AND blocks the escape route.
	-- Box at (120,0,0) halfExtents (50,5,5):
	--   Overlaps P_Exit box (center=90, half=60): dx=|120-90|=30 < 50+60=110 → yes.
	--   Contains EscapeRoute_A at (120,0,0): |0|<50, |0|<5, |0|<5 → yes.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_BothFailures",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 120, y = 0, z = 0 },
					halfExtents = { x = 50, y = 5, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertFalse(result.accepted, "block14 both failures rejected")
		assertHasRejectCode(result, "occupied_space_overlap", "block14 slice1 code present")
		assertHasRejectCode(result, "route_escape_preservation_failure", "block14 slice2 code present")
	end

	-- BLOCK 15: Repeated runs on route-blocking placement produce identical reject ordering.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_RouteStability",
			proposedOccupiedSpace = {
				{
					tag = "core",
					worldCenter = { x = 120, y = 0, z = 0 },
					halfExtents = { x = 5, y = 5, z = 5 },
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
		assertEqual(outA.accepted, outB.accepted, "block15 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block15 reason count stable")
		for index, reasonA in ipairs(outA.rejectReasons) do
			local reasonB = outB.rejectReasons[index]
			assertEqual(reasonA.code, reasonB.code, "block15 code stable " .. tostring(index))
			assertEqual(
				reasonA.isLandmarkConflict,
				reasonB.isLandmarkConflict,
				"block15 landmark stable " .. tostring(index)
			)
		end
	end

	-- ── Slice 5: indoor/outdoor and traversal-density policy gate ─────────────

	-- Fixture reference:
	--   P_Start box: worldCenter=(30,0,0) halfExtents=(60,4,40)  env=outdoor  density=moderate
	--   P_Exit  box: worldCenter=(90,0,0) halfExtents=(60,4,40)  env=indoor   density=sparse
	--
	-- Positions that isolate exactly one chunk:
	--   x=0,  half=1 → overlaps P_Start only  (|0-30|=30 < 61; |0-90|=90 ≥ 61)
	--   x=120, half=1 → overlaps P_Exit only  (|120-90|=30 < 61; |120-30|=90 ≥ 61)
	--   x=60,  half=1 → overlaps BOTH          (|60-30|=30 < 61; |60-90|=30 < 61)

	-- BLOCK 24: Disjoint district + restrictive policy → no overlaps → passes vacuously.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_PolicyDisjoint",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 500 },
					halfExtents = { x = 10, y = 10, z = 10 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertTrue(result.accepted, "block24 disjoint accepted")
		assertEqual(#result.rejectReasons, 0, "block24 no reject reasons")
	end

	-- BLOCK 25: Box overlapping P_Start (outdoor); allowedEnvironmentClasses={"outdoor"} → passes.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "outdoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_OutdoorAllowed",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		local hasEnvReject = false
		for _, reason in result.rejectReasons do
			if reason.code == "environment_class_exclusion" then
				hasEnvReject = true
			end
		end
		assertFalse(hasEnvReject, "block25 no env rejection when outdoor allowed")
	end

	-- BLOCK 26: Box overlapping P_Start (outdoor); allowedEnvironmentClasses={"indoor"} → rejects.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_IndoorOnly",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block26 env violation rejected")
		assertHasRejectCode(result, "environment_class_exclusion", "block26 code present")
		local envReason = nil
		for _, reason in result.rejectReasons do
			if reason.code == "environment_class_exclusion" then
				envReason = reason
			end
		end
		assertTrue(envReason ~= nil, "block26 envReason found")
		if envReason ~= nil then
			assertEqual(envReason.conflictingEnvironmentClass, "outdoor", "block26 conflictingEnvironmentClass")
			assertEqual(envReason.conflictingPlacementId, "P_Start", "block26 conflictingPlacementId")
			assertFalse(envReason.isLandmarkConflict, "block26 not landmark conflict")
		end
	end

	-- BLOCK 27: Box overlapping P_Exit (indoor); allowedEnvironmentClasses={"indoor"} → passes.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_ExitIndoorAllowed",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 120, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		local hasEnvReject = false
		for _, reason in result.rejectReasons do
			if reason.code == "environment_class_exclusion" then
				hasEnvReject = true
			end
		end
		assertFalse(hasEnvReject, "block27 no env rejection when indoor allowed and chunk is indoor")
	end

	-- BLOCK 28: Box overlapping P_Start (moderate density); allowedTraversalDensityClasses={"sparse"} → rejects.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_DensityViolation",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block28 density violation rejected")
		assertHasRejectCode(result, "traversal_density_exclusion", "block28 code present")
		local densityReason = nil
		for _, reason in result.rejectReasons do
			if reason.code == "traversal_density_exclusion" then
				densityReason = reason
			end
		end
		assertTrue(densityReason ~= nil, "block28 densityReason found")
		if densityReason ~= nil then
			assertEqual(densityReason.conflictingTraversalDensityClass, "moderate", "block28 conflictingDensity")
			assertEqual(densityReason.conflictingPlacementId, "P_Start", "block28 density placementId")
		end
	end

	-- BLOCK 29: Box overlapping P_Start (moderate); allowedTraversalDensityClasses={"moderate"} → passes density.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = { "moderate" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_DensityAllowed",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		local hasDensityReject = false
		for _, reason in result.rejectReasons do
			if reason.code == "traversal_density_exclusion" then
				hasDensityReject = true
			end
		end
		assertFalse(hasDensityReject, "block29 no density rejection when moderate allowed")
	end

	-- BLOCK 30: nil policyConfig → Slice 5 is skipped entirely; Slices 1-4 still active.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_NoPolicyConfig",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		-- No criticalConfig, no policyConfig — any rejects come from Slices 1-4 only.
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		local hasEnvReject = false
		local hasDensityReject = false
		for _, reason in result.rejectReasons do
			if reason.code == "environment_class_exclusion" then
				hasEnvReject = true
			end
			if reason.code == "traversal_density_exclusion" then
				hasDensityReject = true
			end
		end
		assertFalse(hasEnvReject, "block30 no env reject without policyConfig")
		assertFalse(hasDensityReject, "block30 no density reject without policyConfig")
	end

	-- BLOCK 31: Both env and density violated in one overlapping run → multi-reason output.
	-- Box at x=0 overlaps P_Start (outdoor, moderate).
	-- Policy: only indoor + only sparse → two separate violations from the same box-pair.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_BothViolations",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block31 both violations rejected")
		assertHasRejectCode(result, "environment_class_exclusion", "block31 env code")
		assertHasRejectCode(result, "traversal_density_exclusion", "block31 density code")
		local envCount = 0
		local densityCount = 0
		for _, reason in result.rejectReasons do
			if reason.code == "environment_class_exclusion" then
				envCount += 1
			end
			if reason.code == "traversal_density_exclusion" then
				densityCount += 1
			end
		end
		assertEqual(envCount, 1, "block31 exactly one env violation")
		assertEqual(densityCount, 1, "block31 exactly one density violation")
	end

	-- BLOCK 32: Stability — repeated Slice 5 runs with same input produce identical output.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_PolicyStability",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertEqual(outA.accepted, outB.accepted, "block32 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block32 count stable")
		for i, reasonA in ipairs(outA.rejectReasons) do
			local reasonB = outB.rejectReasons[i]
			assertEqual(reasonA.code, reasonB.code, "block32 code stable " .. tostring(i))
		end
	end

	-- BLOCK 33: Slice 5 env violation coexists with Slice 1 occupied_space_overlap.
	-- x=120 overlaps P_Exit (occupied space → Slice 1 reject) and is indoor.
	-- Policy: only outdoor allowed → Slice 5 also fires.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "outdoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_Slice1And5Coexist",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 120, y = 0, z = 0 },
					halfExtents = { x = 5, y = 2, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block33 rejected")
		assertHasRejectCode(result, "occupied_space_overlap", "block33 slice1 code present")
		assertHasRejectCode(result, "environment_class_exclusion", "block33 slice5 code present")
	end

	-- ── Slice 6: recurring-structure policy gate ──────────────────────────────

	-- Fixture reference (recurringStructureTags):
	--   P_Start: { "spawn_chamber", "entry_hub" }   box: center=(30,0,0) half=(60,4,40)
	--   P_Exit:  { "exit_chamber" }                 box: center=(90,0,0) half=(60,4,40)
	--
	-- Overlap positions (x, half=1, y=0, z=0):
	--   x=0   → P_Start only
	--   x=120 → P_Exit only
	--   x=60  → both

	-- BLOCK 34: nil disallowedRecurringStructureTags (empty list) → no Slice 6 rejection.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = {},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_EmptyPolicy",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		local hasRS = false
		for _, reason in result.rejectReasons do
			if reason.code == "recurring_structure_tag_exclusion" then
				hasRS = true
			end
		end
		assertFalse(hasRS, "block34 no RS rejection when disallowed list empty")
	end

	-- BLOCK 35: Overlapping P_Start; disallow "entry_hub" (present) → rejects.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "entry_hub" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_EntryHubDisallowed",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block35 rejected")
		assertHasRejectCode(result, "recurring_structure_tag_exclusion", "block35 code present")
		local rsReason = nil
		for _, reason in result.rejectReasons do
			if reason.code == "recurring_structure_tag_exclusion" then
				rsReason = reason
			end
		end
		assertTrue(rsReason ~= nil, "block35 rsReason found")
		if rsReason ~= nil then
			assertEqual(rsReason.conflictingRecurringStructureTag, "entry_hub", "block35 conflicting tag")
			assertEqual(rsReason.conflictingPlacementId, "P_Start", "block35 conflicting placement")
		end
	end

	-- BLOCK 36: Overlapping P_Start; disallow "exit_chamber" (not present on P_Start) → passes Slice 6.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "exit_chamber" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_ExitChamberNotOnStart",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		local hasRS = false
		for _, reason in result.rejectReasons do
			if reason.code == "recurring_structure_tag_exclusion" then
				hasRS = true
			end
		end
		assertFalse(hasRS, "block36 no RS rejection when disallowed tag absent from overlapping chunk")
	end

	-- BLOCK 37: Chunk with multiple tags → fails when any disallowed tag is present.
	-- P_Start has both "spawn_chamber" and "entry_hub"; disallow only "spawn_chamber".
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "spawn_chamber" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_SpawnChamberDisallowed",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block37 rejected on one disallowed tag in multi-tag chunk")
		assertHasRejectCode(result, "recurring_structure_tag_exclusion", "block37 code present")
	end

	-- BLOCK 38: Box at x=60 overlaps both P_Start and P_Exit; disallow "entry_hub".
	-- P_Start carries "entry_hub" → 1 reason; P_Exit does not → no extra reason for P_Exit.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "entry_hub" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_BothOverlap",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 60, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block38 rejected")
		local rsCount = 0
		for _, reason in result.rejectReasons do
			if reason.code == "recurring_structure_tag_exclusion" then
				rsCount += 1
			end
		end
		-- Only P_Start carries "entry_hub" → exactly one RS reason.
		assertEqual(rsCount, 1, "block38 exactly one RS reason (only P_Start has entry_hub)")
	end

	-- BLOCK 39: Both "spawn_chamber" and "exit_chamber" disallowed; box at x=60 overlaps both.
	-- P_Start fires for "spawn_chamber"; P_Exit fires for "exit_chamber" → 2 reasons total.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "spawn_chamber", "exit_chamber" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_MultiReason",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 60, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block39 rejected")
		local rsCount = 0
		for _, reason in result.rejectReasons do
			if reason.code == "recurring_structure_tag_exclusion" then
				rsCount += 1
			end
		end
		assertEqual(rsCount, 2, "block39 two RS reasons (one per chunk)")
	end

	-- BLOCK 40: Stability — repeated runs produce identical RS reason ordering.
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "spawn_chamber", "entry_hub", "exit_chamber" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_Stability",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 60, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertEqual(outA.accepted, outB.accepted, "block40 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block40 count stable")
		for i, reasonA in ipairs(outA.rejectReasons) do
			local reasonB = outB.rejectReasons[i]
			assertEqual(reasonA.code, reasonB.code, "block40 code stable " .. tostring(i))
			assertEqual(
				reasonA.conflictingRecurringStructureTag,
				reasonB.conflictingRecurringStructureTag,
				"block40 tag stable " .. tostring(i)
			)
		end
	end

	-- BLOCK 41: Slice 6 coexists with Slice 1 occupied_space_overlap.
	-- x=120 overlaps P_Exit (Slice 1 fires) and P_Exit carries "exit_chamber" (Slice 6 fires).
	do
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "exit_chamber" },
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_RS_Slice1And6Coexist",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 120, y = 0, z = 0 },
					halfExtents = { x = 5, y = 2, z = 5 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, policyConfig)
		assertFalse(result.accepted, "block41 rejected")
		assertHasRejectCode(result, "occupied_space_overlap", "block41 slice1 code present")
		assertHasRejectCode(result, "recurring_structure_tag_exclusion", "block41 slice6 code present")
	end

	-- ── Slice 7: soft devaluation / scoring track ─────────────────────────────

	-- Fixture critical-point world positions (P_Start placed at origin):
	--   TinyfolkSpawn        (0,  0, 0)
	--   TinyfolkReturnPoint  (-20, 0, 0)
	--   WorkStation_A        (25,  0, 0)
	--   ConstructionSite_A   (15,  0, 10)
	--   GiantCaptureZone_A   (40,  0, 20)
	--   EscapeRoute_A        (120, 0, 0)  -- P_Exit
	--
	-- Test box at (0,0,-60) half=(1,1,1):
	--   TinyfolkSpawn dist = 59.0  (sqrt(59^2))
	--   TinyfolkReturnPoint dist = sqrt(19^2+59^2) ≈ 61.99
	--   → softRadius=60 catches only TinyfolkSpawn (dist=59 < 60); score = floor(60-59) = 1

	-- BLOCK 42: nil softConfig → devaluation always present, totalPenalty=0, penalties empty.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_NoSoftConfig",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 500 },
					halfExtents = { x = 10, y = 10, z = 10 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		assertTrue(result.devaluation ~= nil, "block42 devaluation present")
		assertEqual(result.devaluation.totalPenalty, 0, "block42 totalPenalty zero")
		assertEqual(#result.devaluation.penalties, 0, "block42 penalties empty")
		assertTrue(result.accepted, "block42 accepted")
	end

	-- BLOCK 43: softConfig provided but placement far from all critical points → 0 penalties.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 60,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_FarFromEverything",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = 500 },
					halfExtents = { x = 10, y = 10, z = 10 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertTrue(result.accepted, "block43 accepted")
		assertEqual(result.devaluation.totalPenalty, 0, "block43 no penalty when far")
		assertEqual(#result.devaluation.penalties, 0, "block43 penalty list empty")
	end

	-- BLOCK 44: Placement near TinyfolkSpawn only → exactly 1 near_critical_point penalty.
	-- Box at (0,0,-60) half=(1,1,1): TinyfolkSpawn dist=59 < 60 → score=1.
	-- TinyfolkReturnPoint dist≈61.99 > 60 → no penalty for it.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_NearSpawnOnly",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = -60 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertTrue(result.accepted, "block44 accepted (no hard reject)")
		assertEqual(#result.devaluation.penalties, 1, "block44 exactly one penalty")
		assertEqual(result.devaluation.totalPenalty, 1, "block44 total penalty = 1")
		local p1 = result.devaluation.penalties[1]
		assertEqual(p1.factor, "near_critical_point", "block44 factor")
		assertTrue(
			p1.nearCriticalPointName ~= nil and string.find(p1.nearCriticalPointName, "TinyfolkSpawn", 1, true) ~= nil,
			"block44 point name"
		)
		assertEqual(tostring(p1.nearCriticalPointCategory), "tinyfolk_spawn", "block44 category")
		assertEqual(p1.score, 1, "block44 score")
	end

	-- BLOCK 45: Placement near multiple critical points → multiple penalties.
	-- Box at (0,0,-50) half=(1,1,1) softRadius=80:
	-- TinyfolkSpawn dist=49 < 80 → penalty; several other close points also trigger.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 80,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_NearMultiple",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = -50 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertTrue(result.accepted, "block45 accepted")
		assertTrue(#result.devaluation.penalties >= 2, "block45 multiple penalties")
		assertTrue(result.devaluation.totalPenalty >= 2, "block45 total penalty >= 2")
		local hasCritPenalty = false
		for _, p in result.devaluation.penalties do
			if p.factor == "near_critical_point" then
				hasCritPenalty = true
			end
		end
		assertTrue(hasCritPenalty, "block45 near_critical_point factor present")
	end

	-- BLOCK 46: Hard-rejected placement (Slice 1 overlap) also accumulates soft penalties.
	-- Box at (30,0,0) half=(1,1,1) overlaps P_Start → Slice 1 rejects.
	-- TinyfolkSpawn (0,0,0): dist = |30-0|-1 = 29 studs < 40 → soft penalty, score=11.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 40,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_HardRejectWithPenalty",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 30, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertFalse(result.accepted, "block46 hard rejected")
		assertHasRejectCode(result, "occupied_space_overlap", "block46 hard reject present")
		assertTrue(result.devaluation.totalPenalty > 0, "block46 soft penalty still accumulated")
		local hasSpawnPenalty = false
		for _, p in result.devaluation.penalties do
			if
				p.factor == "near_critical_point"
				and p.nearCriticalPointName ~= nil
				and string.find(p.nearCriticalPointName, "TinyfolkSpawn", 1, true) ~= nil
			then
				hasSpawnPenalty = true
			end
		end
		assertTrue(hasSpawnPenalty, "block46 TinyfolkSpawn soft penalty on rejected placement")
	end

	-- BLOCK 47: Near-route-edge factor — prototype fixture has no protected edges
	--           (disconnected route graph) → 0 near_route_edge penalties (vacuous).
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 0,
			nearRouteEdgeSoftRadius = 200,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_NearEdgeVacuous",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 30, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		local hasEdgePenalty = false
		for _, p in result.devaluation.penalties do
			if p.factor == "near_route_edge" then
				hasEdgePenalty = true
			end
		end
		assertFalse(hasEdgePenalty, "block47 no route-edge penalty (no protected edges in prototype)")
	end

	-- BLOCK 48: Stability — repeated runs produce identical devaluation output.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 80,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_SoftStability",
			proposedOccupiedSpace = {
				{
					tag = "body",
					worldCenter = { x = 0, y = 0, z = -50 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block48 totalPenalty stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block48 count stable")
		for i, pA in ipairs(outA.devaluation.penalties) do
			local pB = outB.devaluation.penalties[i]
			assertEqual(pA.factor, pB.factor, "block48 factor stable " .. tostring(i))
			assertEqual(pA.score, pB.score, "block48 score stable " .. tostring(i))
			assertEqual(
				tostring(pA.nearCriticalPointName),
				tostring(pB.nearCriticalPointName),
				"block48 name stable " .. tostring(i)
			)
		end
	end

	-- BLOCK 49: Slice 8 - penalty entry carries category field.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S8Block49",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertTrue(#result.devaluation.penalties >= 1, "block49 has penalties")
		local p = result.devaluation.penalties[1]
		assertTrue(p.category ~= nil, "block49 penalty has category field")
		assertEqual(p.category, "proximity", "block49 near_critical_point is proximity category")
	end

	-- BLOCK 50: Slice 8 - proximity category total is correct.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S8Block50",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertTrue(#result.devaluation.categoryTotals > 0, "block50 has category totals")
		local proximityTotal = nil
		for _, cat in ipairs(result.devaluation.categoryTotals) do
			if cat.category == "proximity" then
				proximityTotal = cat.totalScore
				break
			end
		end
		assertTrue(proximityTotal ~= nil, "block50 proximity category present in totals")
		assertEqual(proximityTotal, result.devaluation.totalPenalty, "block50 proximity total matches single penalty")
	end

	-- BLOCK 51: Slice 8 - multiple penalty categories with stable ordering.
	do
		-- Create a scenario that might trigger both proximity and route_pressure (though
		-- prototype fixture is disconnected, so route_pressure will be 0, but test ordering anyway).
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 80,
			nearRouteEdgeSoftRadius = 200,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S8Block51",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = -50 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertTrue(#result.devaluation.categoryTotals >= 1, "block51 has category totals")
		-- Verify ordering: proximity should come before route_pressure.
		for i = 1, #result.devaluation.categoryTotals - 1 do
			local cat1 = result.devaluation.categoryTotals[i].category
			local cat2 = result.devaluation.categoryTotals[i + 1].category
			local order1 = (cat1 == "proximity" and 0)
				or (cat1 == "route_pressure" and 1)
				or (cat1 == "density_pressure" and 2)
				or 999
			local order2 = (cat2 == "proximity" and 0)
				or (cat2 == "route_pressure" and 1)
				or (cat2 == "density_pressure" and 2)
				or 999
			assertTrue(order1 < order2, "block51 categories ordered deterministically at index " .. tostring(i))
		end
	end

	-- BLOCK 52: Slice 8 - hard-rejected placement still works with categories.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 40,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S8Block52",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertFalse(result.accepted, "block52 hard rejected (Slice 1 overlap)")
		assertTrue(#result.rejectReasons > 0, "block52 has reject reasons")
		-- Devaluation should still be computed and categorized.
		assertTrue(result.devaluation.totalPenalty > 0, "block52 devaluation still accumulated")
		assertTrue(#result.devaluation.categoryTotals > 0, "block52 category totals present")
		local hasProximity = false
		for _, cat in ipairs(result.devaluation.categoryTotals) do
			if cat.category == "proximity" and cat.totalScore > 0 then
				hasProximity = true
				break
			end
		end
		assertTrue(hasProximity, "block52 proximity category has score on rejected placement")
	end

	-- BLOCK 53: Slice 8 - category totals are deterministic (repeated runs identical).
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 80,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S8Block53",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = -50 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertEqual(#outA.devaluation.categoryTotals, #outB.devaluation.categoryTotals, "block53 category count stable")
		for i, catA in ipairs(outA.devaluation.categoryTotals) do
			local catB = outB.devaluation.categoryTotals[i]
			assertEqual(catA.category, catB.category, "block53 category name stable " .. tostring(i))
			assertEqual(catA.totalScore, catB.totalScore, "block53 category score stable " .. tostring(i))
		end
	end

	-- BLOCK 54: Slice 8 - category totals always present and ordered, even with no penalties.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 60,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S8Block54",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 500 }, halfExtents = { x = 10, y = 10, z = 10 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, nil, softConfig)
		assertEqual(result.devaluation.totalPenalty, 0, "block54 no penalties far away")
		assertEqual(#result.devaluation.penalties, 0, "block54 penalty list empty")
		-- Even with no penalties, category structure should be present and ordered.
		assertTrue(#result.devaluation.categoryTotals > 0, "block54 category totals present even with no penalties")
		local expectedOrder = { "proximity", "route_pressure", "density_pressure" }
		for i, expectedCat in ipairs(expectedOrder) do
			if i <= #result.devaluation.categoryTotals then
				assertEqual(
					result.devaluation.categoryTotals[i].category,
					expectedCat,
					"block54 category order " .. tostring(i)
				)
			end
		end
	end

	-- BLOCK 55: Slice 9 - hard config alone can reject while soft config is nil.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 0,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S9HardOnly",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig)
		assertFalse(result.accepted, "block55 hard config rejects")
		assertHasRejectCode(result, "tinyfolk_spawn_exclusion", "block55 hard reject code")
		assertEqual(result.devaluation.totalPenalty, 0, "block55 no soft penalty")
	end

	-- BLOCK 56: Slice 9 - soft config alone can devalue while hard config is nil.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S9SoftOnly",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertTrue(result.accepted, "block56 soft-only accepted")
		assertEqual(#result.rejectReasons, 0, "block56 no reject reasons")
		assertEqual(result.devaluation.totalPenalty, 1, "block56 soft penalty applied")
		assertEqual(result.devaluation.categoryTotals[1].category, "proximity", "block56 proximity first")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block56 proximity total")
	end

	-- BLOCK 57: Slice 9 - hard and soft configs together produce combined behavior.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 0,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S9HardAndSoft",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertFalse(result.accepted, "block57 hard config rejects")
		assertHasRejectCode(result, "tinyfolk_spawn_exclusion", "block57 hard reject code")
		assertEqual(result.devaluation.totalPenalty, 15, "block57 soft penalty also applied")
	end

	-- BLOCK 58: Slice 9 - equivalent legacy and separated config paths match.
	do
		local criticalConfig: DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local policyConfig: DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = {},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 0,
		}
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = criticalConfig,
			policy = policyConfig,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S9Compat",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local legacy = RealmDistrictPlacementValidator.ValidatePlacement(
			request,
			protoOutput,
			criticalConfig,
			policyConfig,
			softConfig
		)
		local separated =
			RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertEqual(separated.accepted, legacy.accepted, "block58 accepted equivalent")
		assertEqual(#separated.rejectReasons, #legacy.rejectReasons, "block58 reject count equivalent")
		for i, reason in ipairs(separated.rejectReasons) do
			assertEqual(reason.code, legacy.rejectReasons[i].code, "block58 reject code " .. tostring(i))
		end
		assertEqual(separated.devaluation.totalPenalty, legacy.devaluation.totalPenalty, "block58 total penalty")
		assertEqual(#separated.devaluation.penalties, #legacy.devaluation.penalties, "block58 penalty count")
		for i, category in ipairs(separated.devaluation.categoryTotals) do
			assertEqual(
				category.category,
				legacy.devaluation.categoryTotals[i].category,
				"block58 category " .. tostring(i)
			)
			assertEqual(
				category.totalScore,
				legacy.devaluation.categoryTotals[i].totalScore,
				"block58 category score " .. tostring(i)
			)
		end
	end

	-- BLOCK 59: Slice 9 - repeated separated-config runs remain stable.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 50,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S9Stable",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
				{ tag = "overlap", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertEqual(outA.accepted, outB.accepted, "block59 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block59 reject count stable")
		for i, reasonA in ipairs(outA.rejectReasons) do
			local reasonB = outB.rejectReasons[i]
			assertEqual(reasonA.code, reasonB.code, "block59 reject code stable " .. tostring(i))
			assertEqual(
				tostring(reasonA.conflictingPlacementId),
				tostring(reasonB.conflictingPlacementId),
				"block59 placement stable " .. tostring(i)
			)
		end
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block59 penalty stable")
		assertEqual(#outA.devaluation.categoryTotals, #outB.devaluation.categoryTotals, "block59 category count stable")
		for i, categoryA in ipairs(outA.devaluation.categoryTotals) do
			local categoryB = outB.devaluation.categoryTotals[i]
			assertEqual(categoryA.category, categoryB.category, "block59 category stable " .. tostring(i))
			assertEqual(categoryA.totalScore, categoryB.totalScore, "block59 category total stable " .. tostring(i))
		end
	end

	-- BLOCK 60: Slice 10 - sparse/allowed density overlap yields no density_pressure penalty.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 0,
			nearRouteEdgeSoftRadius = 0,
			penalizedTraversalDensityClasses = { "moderate" },
			densityPressurePenaltyScore = 7,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S10SparseAllowed",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 120, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertFalse(result.accepted, "block60 still hard rejected by occupied overlap")
		local densityTotal = result.devaluation.categoryTotals[3]
		assertEqual(densityTotal.category, "density_pressure", "block60 density category")
		assertEqual(densityTotal.totalScore, 0, "block60 no density pressure for sparse")
		for _, penalty in ipairs(result.devaluation.penalties) do
			assertFalse(penalty.factor == "density_pressure", "block60 no density_pressure penalty")
		end
	end

	-- BLOCK 61: Slice 10 - configured moderate density overlap yields density_pressure penalty.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 0,
			nearRouteEdgeSoftRadius = 0,
			penalizedTraversalDensityClasses = { "moderate" },
			densityPressurePenaltyScore = 7,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S10ModeratePenalty",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertFalse(result.accepted, "block61 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 7, "block61 density pressure score")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 7, "block61 density category total")
		assertEqual(#result.devaluation.penalties, 1, "block61 one density penalty")
		local penalty = result.devaluation.penalties[1]
		assertEqual(penalty.factor, "density_pressure", "block61 factor")
		assertEqual(penalty.category, "density_pressure", "block61 category")
		assertEqual(penalty.densityPressurePlacementId, "P_Start", "block61 placement")
		assertEqual(penalty.densityPressureChunkId, "Chunk_Start", "block61 chunk")
		assertEqual(penalty.densityPressureClass, "moderate", "block61 density class")
	end

	-- BLOCK 62: Slice 10 - proximity and density_pressure accumulate with stable category totals.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 40,
			nearRouteEdgeSoftRadius = 0,
			penalizedTraversalDensityClasses = { "moderate" },
			densityPressurePenaltyScore = 7,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S10ProximityAndDensity",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertFalse(result.accepted, "block62 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 18, "block62 combined soft score")
		assertEqual(result.devaluation.categoryTotals[1].category, "proximity", "block62 proximity category")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 11, "block62 proximity total")
		assertEqual(result.devaluation.categoryTotals[2].category, "route_pressure", "block62 route category")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 0, "block62 route total")
		assertEqual(result.devaluation.categoryTotals[3].category, "density_pressure", "block62 density category")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 7, "block62 density total")
	end

	-- BLOCK 63: Slice 10 - hard reject behavior is unchanged when density pressure is active.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 0,
			nearRouteEdgeSoftRadius = 0,
			penalizedTraversalDensityClasses = { "moderate" },
			densityPressurePenaltyScore = 7,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S10HardRejectUnchanged",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local noSoft = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		local withDensity = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertEqual(withDensity.accepted, noSoft.accepted, "block63 accepted unchanged")
		assertEqual(#withDensity.rejectReasons, #noSoft.rejectReasons, "block63 reject count unchanged")
		for i, reason in ipairs(withDensity.rejectReasons) do
			assertEqual(reason.code, noSoft.rejectReasons[i].code, "block63 reject code " .. tostring(i))
		end
		assertEqual(withDensity.devaluation.categoryTotals[3].totalScore, 7, "block63 density still scored")
	end

	-- BLOCK 64: Slice 10 - repeated density-pressure runs preserve ordering and totals.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 40,
			nearRouteEdgeSoftRadius = 0,
			penalizedTraversalDensityClasses = { "moderate", "sparse" },
			densityPressurePenaltyScore = 7,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S10DensityStable",
			proposedOccupiedSpace = {
				{ tag = "start", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
				{ tag = "exit", worldCenter = { x = 120, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block64 total stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block64 penalty count stable")
		for i, penaltyA in ipairs(outA.devaluation.penalties) do
			local penaltyB = outB.devaluation.penalties[i]
			assertEqual(penaltyA.factor, penaltyB.factor, "block64 factor stable " .. tostring(i))
			assertEqual(penaltyA.score, penaltyB.score, "block64 score stable " .. tostring(i))
			assertEqual(
				tostring(penaltyA.densityPressurePlacementId),
				tostring(penaltyB.densityPressurePlacementId),
				"block64 density placement stable " .. tostring(i)
			)
		end
		for i, categoryA in ipairs(outA.devaluation.categoryTotals) do
			local categoryB = outB.devaluation.categoryTotals[i]
			assertEqual(categoryA.category, categoryB.category, "block64 category stable " .. tostring(i))
			assertEqual(categoryA.totalScore, categoryB.totalScore, "block64 category score stable " .. tostring(i))
		end
	end

	-- BLOCK 65: Slice 11 - route pressure can be enabled while proximity is disabled.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 20,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S11RouteOnly",
			proposedOccupiedSpace = {
				{ tag = "near_edge", worldCenter = { x = 50, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, softConfig)
		assertTrue(result.accepted, "block65 accepted")
		assertEqual(result.devaluation.totalPenalty, 11, "block65 route penalty score")
		assertEqual(#result.devaluation.penalties, 1, "block65 one route penalty")
		assertEqual(result.devaluation.penalties[1].factor, "near_route_edge", "block65 route factor")
		assertEqual(result.devaluation.penalties[1].category, "route_pressure", "block65 route category")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 0, "block65 proximity disabled")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 11, "block65 route total")
	end

	-- BLOCK 66: Slice 11 - proximity can be enabled while route pressure is disabled.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S11ProximityOnly",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertTrue(result.accepted, "block66 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block66 proximity penalty score")
		assertEqual(#result.devaluation.penalties, 1, "block66 one proximity penalty")
		assertEqual(result.devaluation.penalties[1].factor, "near_critical_point", "block66 proximity factor")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block66 proximity total")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 0, "block66 route disabled")
	end

	-- BLOCK 67: Slice 11 - route and proximity split fields accumulate together.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 20,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S11BothSplit",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, softConfig)
		assertTrue(result.accepted, "block67 accepted")
		assertEqual(result.devaluation.totalPenalty, 12, "block67 combined penalty")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block67 proximity total")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 11, "block67 route total")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 0, "block67 density total")
	end

	-- BLOCK 68: Slice 11 - legacy and split soft config paths are equivalent.
	do
		local legacySoftConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 60,
			nearRouteEdgeSoftRadius = 20,
		}
		local splitSoftConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 20,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S11Compat",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local legacy =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, legacySoftConfig)
		local split =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, splitSoftConfig)
		assertEqual(split.devaluation.totalPenalty, legacy.devaluation.totalPenalty, "block68 total equivalent")
		assertEqual(#split.devaluation.penalties, #legacy.devaluation.penalties, "block68 penalty count equivalent")
		for i, penalty in ipairs(split.devaluation.penalties) do
			assertEqual(penalty.factor, legacy.devaluation.penalties[i].factor, "block68 factor " .. tostring(i))
			assertEqual(penalty.score, legacy.devaluation.penalties[i].score, "block68 score " .. tostring(i))
		end
		for i, category in ipairs(split.devaluation.categoryTotals) do
			assertEqual(
				category.category,
				legacy.devaluation.categoryTotals[i].category,
				"block68 category " .. tostring(i)
			)
			assertEqual(
				category.totalScore,
				legacy.devaluation.categoryTotals[i].totalScore,
				"block68 category score " .. tostring(i)
			)
		end
	end

	-- BLOCK 69: Slice 11 - repeated split-config runs remain stable.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 20,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S11Stable",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, softConfig)
		local outB =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block69 total stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block69 penalty count stable")
		for i, penaltyA in ipairs(outA.devaluation.penalties) do
			local penaltyB = outB.devaluation.penalties[i]
			assertEqual(penaltyA.factor, penaltyB.factor, "block69 factor stable " .. tostring(i))
			assertEqual(penaltyA.score, penaltyB.score, "block69 score stable " .. tostring(i))
		end
		for i, categoryA in ipairs(outA.devaluation.categoryTotals) do
			local categoryB = outB.devaluation.categoryTotals[i]
			assertEqual(categoryA.category, categoryB.category, "block69 category stable " .. tostring(i))
			assertEqual(categoryA.totalScore, categoryB.totalScore, "block69 category score stable " .. tostring(i))
		end
	end

	-- BLOCK 70: Slice 12 - spawn proximity can be tuned independently of escape proximity.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S12SpawnOnly",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
				{
					tag = "near_escape",
					worldCenter = { x = 100, y = 0, z = -60 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block70 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block70 spawn-only penalty score")
		assertEqual(#result.devaluation.penalties, 1, "block70 one spawn penalty")
		assertEqual(
			result.devaluation.penalties[1].nearCriticalPointCategory,
			"tinyfolk_spawn",
			"block70 spawn category"
		)
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block70 proximity total")
	end

	-- BLOCK 71: Slice 12 - escape proximity can be tuned independently of spawn proximity.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 0,
			escapeRouteSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S12EscapeOnly",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
				{
					tag = "near_escape",
					worldCenter = { x = 100, y = 0, z = -60 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block71 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block71 escape-only penalty score")
		assertEqual(#result.devaluation.penalties, 1, "block71 one escape penalty")
		assertEqual(
			result.devaluation.penalties[1].nearCriticalPointCategory,
			"escape_route",
			"block71 escape category"
		)
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block71 proximity total")
	end

	-- BLOCK 72: Slice 12 - shared critical-point fallback still applies by category order.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S12SharedFallback",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
				{
					tag = "near_escape",
					worldCenter = { x = 100, y = 0, z = -60 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block72 accepted")
		assertEqual(result.devaluation.totalPenalty, 2, "block72 shared fallback total")
		assertEqual(#result.devaluation.penalties, 2, "block72 two proximity penalties")
		assertEqual(result.devaluation.penalties[1].nearCriticalPointCategory, "tinyfolk_spawn", "block72 spawn first")
		assertEqual(result.devaluation.penalties[2].nearCriticalPointCategory, "escape_route", "block72 escape second")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 2, "block72 proximity total")
	end

	-- BLOCK 73: Slice 12 - category-specific radius overrides shared critical-point fallback.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			tinyfolkSpawnSoftRadius = 0,
			escapeRouteSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S12Override",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
				{
					tag = "near_escape",
					worldCenter = { x = 100, y = 0, z = -60 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block73 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block73 override total")
		assertEqual(#result.devaluation.penalties, 1, "block73 one override penalty")
		assertEqual(result.devaluation.penalties[1].nearCriticalPointCategory, "escape_route", "block73 escape only")
	end

	-- BLOCK 74: Slice 12 - repeated category-specific runs remain stable.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			tinyfolkSpawnSoftRadius = 0,
			escapeRouteSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S12Stable",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
				{
					tag = "near_escape",
					worldCenter = { x = 100, y = 0, z = -60 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local outA =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		local outB =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block74 total stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block74 penalty count stable")
		for i, penaltyA in ipairs(outA.devaluation.penalties) do
			local penaltyB = outB.devaluation.penalties[i]
			assertEqual(penaltyA.factor, penaltyB.factor, "block74 factor stable " .. tostring(i))
			assertEqual(
				penaltyA.nearCriticalPointCategory,
				penaltyB.nearCriticalPointCategory,
				"block74 category stable " .. tostring(i)
			)
			assertEqual(penaltyA.score, penaltyB.score, "block74 score stable " .. tostring(i))
		end
		for i, categoryA in ipairs(outA.devaluation.categoryTotals) do
			local categoryB = outB.devaluation.categoryTotals[i]
			assertEqual(categoryA.category, categoryB.category, "block74 category total stable " .. tostring(i))
			assertEqual(categoryA.totalScore, categoryB.totalScore, "block74 category score stable " .. tostring(i))
		end
	end

	-- BLOCK 75: Slice 13 - dense density can be penalized independently of moderate.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 0,
			moderateDensityPressurePenaltyScore = 0,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S13DenseOnly",
			proposedOccupiedSpace = {
				{
					tag = "moderate_touch",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
				{ tag = "dense_touch", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		assertFalse(result.accepted, "block75 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 9, "block75 dense-only total")
		assertEqual(#result.devaluation.penalties, 1, "block75 one density penalty")
		assertEqual(result.devaluation.penalties[1].densityPressureClass, "dense", "block75 dense class")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 9, "block75 density total")
	end

	-- BLOCK 76: Slice 13 - moderate density can be penalized independently of dense.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 0,
			moderateDensityPressurePenaltyScore = 5,
			denseDensityPressurePenaltyScore = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S13ModerateOnly",
			proposedOccupiedSpace = {
				{
					tag = "moderate_touch",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
				{ tag = "dense_touch", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		assertFalse(result.accepted, "block76 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 5, "block76 moderate-only total")
		assertEqual(#result.devaluation.penalties, 1, "block76 one density penalty")
		assertEqual(result.devaluation.penalties[1].densityPressureClass, "moderate", "block76 moderate class")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 5, "block76 density total")
	end

	-- BLOCK 77: Slice 13 - shared density-pressure fallback still works.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 0,
			penalizedTraversalDensityClasses = { "moderate", "dense" },
			densityPressurePenaltyScore = 6,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S13SharedFallback",
			proposedOccupiedSpace = {
				{
					tag = "moderate_touch",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
				{ tag = "dense_touch", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		assertFalse(result.accepted, "block77 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 12, "block77 shared fallback total")
		assertEqual(#result.devaluation.penalties, 2, "block77 two density penalties")
		assertEqual(result.devaluation.penalties[1].densityPressureClass, "moderate", "block77 moderate first")
		assertEqual(result.devaluation.penalties[2].densityPressureClass, "dense", "block77 dense second")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 12, "block77 density total")
	end

	-- BLOCK 78: Slice 13 - class-specific score overrides shared density-pressure fallback.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 0,
			penalizedTraversalDensityClasses = { "moderate", "dense" },
			densityPressurePenaltyScore = 6,
			moderateDensityPressurePenaltyScore = 0,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S13Override",
			proposedOccupiedSpace = {
				{
					tag = "moderate_touch",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
				{ tag = "dense_touch", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		assertFalse(result.accepted, "block78 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 9, "block78 override total")
		assertEqual(#result.devaluation.penalties, 1, "block78 one override penalty")
		assertEqual(result.devaluation.penalties[1].densityPressureClass, "dense", "block78 dense override")
	end

	-- BLOCK 79: Slice 13 - repeated class-specific density runs remain stable.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 0,
			moderateDensityPressurePenaltyScore = 5,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S13Stable",
			proposedOccupiedSpace = {
				{
					tag = "moderate_touch",
					worldCenter = { x = 0, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
				{ tag = "dense_touch", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		local outB =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block79 total stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block79 penalty count stable")
		for i, penaltyA in ipairs(outA.devaluation.penalties) do
			local penaltyB = outB.devaluation.penalties[i]
			assertEqual(penaltyA.factor, penaltyB.factor, "block79 factor stable " .. tostring(i))
			assertEqual(penaltyA.score, penaltyB.score, "block79 score stable " .. tostring(i))
			assertEqual(
				penaltyA.densityPressureClass,
				penaltyB.densityPressureClass,
				"block79 density class stable " .. tostring(i)
			)
		end
		for i, categoryA in ipairs(outA.devaluation.categoryTotals) do
			local categoryB = outB.devaluation.categoryTotals[i]
			assertEqual(categoryA.category, categoryB.category, "block79 category stable " .. tostring(i))
			assertEqual(categoryA.totalScore, categoryB.totalScore, "block79 category score stable " .. tostring(i))
		end
	end

	-- BLOCK 80: Slice 14 - proximity penalties expose normalized core fields and retained details.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S14ProximityCore",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block80 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block80 total unchanged")
		local penalty = result.devaluation.penalties[1]
		assertEqual(penalty.factor, "near_critical_point", "block80 factor")
		assertEqual(penalty.category, "proximity", "block80 category")
		assertEqual(penalty.score, 1, "block80 score")
		assertTrue(type(penalty.message) == "string" and #penalty.message > 0, "block80 message")
		assertEqual(
			penalty.message,
			"Soft penalty: near_critical_point subject=TinyfolkSpawn reason=within_soft_radius",
			"block80 normalized message"
		)
		assertEqual(penalty.subjectType, "critical_point", "block80 subject type")
		assertEqual(penalty.subjectName, "TinyfolkSpawn", "block80 subject name")
		assertEqual(
			penalty.sortKey,
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"block80 sort key"
		)
		assertEqual(penalty.nearCriticalPointName, "TinyfolkSpawn", "block80 retained point name")
		assertEqual(penalty.nearCriticalPointCategory, "tinyfolk_spawn", "block80 retained point category")
	end

	-- BLOCK 81: Slice 14 - route-pressure penalties expose normalized core fields and retained details.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 20,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S14RouteCore",
			proposedOccupiedSpace = {
				{ tag = "near_edge", worldCenter = { x = 50, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, softConfig)
		assertTrue(result.accepted, "block81 accepted")
		assertEqual(result.devaluation.totalPenalty, 11, "block81 total unchanged")
		local penalty = result.devaluation.penalties[1]
		assertEqual(penalty.factor, "near_route_edge", "block81 factor")
		assertEqual(penalty.category, "route_pressure", "block81 category")
		assertEqual(penalty.score, 11, "block81 score")
		assertTrue(type(penalty.message) == "string" and #penalty.message > 0, "block81 message")
		assertEqual(
			penalty.message,
			"Soft penalty: near_route_edge subject=SpawnNode->EscapeNode reason=within_soft_radius",
			"block81 normalized message"
		)
		assertEqual(penalty.subjectType, "route_edge", "block81 subject type")
		assertEqual(penalty.subjectName, "SpawnNode->EscapeNode", "block81 subject name")
		assertEqual(
			penalty.sortKey,
			"02:route_pressure|near_route_edge|route_edge|SpawnNode->EscapeNode",
			"block81 sort key"
		)
		assertEqual(penalty.nearRouteEdgeFrom, "SpawnNode", "block81 retained edge from")
		assertEqual(penalty.nearRouteEdgeTo, "EscapeNode", "block81 retained edge to")
	end

	-- BLOCK 82: Slice 14 - density-pressure penalties expose normalized core fields and retained details.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 0,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S14DensityCore",
			proposedOccupiedSpace = {
				{ tag = "dense_touch", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		assertFalse(result.accepted, "block82 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 9, "block82 total unchanged")
		local penalty = result.devaluation.penalties[1]
		assertEqual(penalty.factor, "density_pressure", "block82 factor")
		assertEqual(penalty.category, "density_pressure", "block82 category")
		assertEqual(penalty.score, 9, "block82 score")
		assertTrue(type(penalty.message) == "string" and #penalty.message > 0, "block82 message")
		assertEqual(
			penalty.message,
			"Soft penalty: density_pressure subject=P_Dense/Chunk_Dense reason=penalized_density_class",
			"block82 normalized message"
		)
		assertEqual(penalty.subjectType, "chunk_density", "block82 subject type")
		assertEqual(penalty.subjectName, "P_Dense/Chunk_Dense", "block82 subject name")
		assertEqual(
			penalty.sortKey,
			"03:density_pressure|density_pressure|chunk_density|P_Dense/Chunk_Dense",
			"block82 sort key"
		)
		assertEqual(penalty.densityPressurePlacementId, "P_Dense", "block82 retained placement")
		assertEqual(penalty.densityPressureChunkId, "Chunk_Dense", "block82 retained chunk")
		assertEqual(penalty.densityPressureClass, "dense", "block82 retained class")
	end

	-- BLOCK 83: Slice 14 - normalized payload keeps category totals and total score unchanged.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S14Totals",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertFalse(result.accepted, "block83 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 21, "block83 total unchanged")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block83 proximity total")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 11, "block83 route total")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 9, "block83 density total")
	end

	-- BLOCK 84: Slice 14 - repeated runs preserve normalized payload ordering.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S14Stable",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block84 total stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block84 penalty count stable")
		for i, penaltyA in ipairs(outA.devaluation.penalties) do
			local penaltyB = outB.devaluation.penalties[i]
			assertEqual(penaltyA.factor, penaltyB.factor, "block84 factor stable " .. tostring(i))
			assertEqual(penaltyA.category, penaltyB.category, "block84 category stable " .. tostring(i))
			assertEqual(penaltyA.score, penaltyB.score, "block84 score stable " .. tostring(i))
			assertEqual(penaltyA.message, penaltyB.message, "block84 message stable " .. tostring(i))
			assertEqual(penaltyA.subjectType, penaltyB.subjectType, "block84 subject type stable " .. tostring(i))
			assertEqual(penaltyA.subjectName, penaltyB.subjectName, "block84 subject name stable " .. tostring(i))
			assertEqual(penaltyA.sortKey, penaltyB.sortKey, "block84 sort key stable " .. tostring(i))
		end
		for i, categoryA in ipairs(outA.devaluation.categoryTotals) do
			local categoryB = outB.devaluation.categoryTotals[i]
			assertEqual(categoryA.category, categoryB.category, "block84 category total stable " .. tostring(i))
			assertEqual(categoryA.totalScore, categoryB.totalScore, "block84 category score stable " .. tostring(i))
		end
	end

	-- BLOCK 85: Slice 15 - subject types use the finite taxonomy and deterministic names.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S15SubjectTaxonomy",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertFalse(result.accepted, "block85 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 21, "block85 total unchanged")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block85 proximity total")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 11, "block85 route total")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 9, "block85 density total")
		assertEqual(#result.devaluation.penalties, 3, "block85 three soft penalties")

		local expectedSubjects = {
			{ subjectType = "critical_point", subjectName = "TinyfolkSpawn" },
			{ subjectType = "route_edge", subjectName = "SpawnNode->EscapeNode" },
			{ subjectType = "chunk_density", subjectName = "P_Dense/Chunk_Dense" },
		}
		local allowedSubjectTypes = {
			critical_point = true,
			route_edge = true,
			chunk_density = true,
		}
		for i, penalty in ipairs(result.devaluation.penalties) do
			assertTrue(allowedSubjectTypes[penalty.subjectType] == true, "block85 allowed subject type " .. tostring(i))
			assertEqual(penalty.subjectType, expectedSubjects[i].subjectType, "block85 subject type " .. tostring(i))
			assertEqual(penalty.subjectName, expectedSubjects[i].subjectName, "block85 subject name " .. tostring(i))
		end
	end

	-- BLOCK 86: Slice 16 - normalized messages remain stable across all current soft factors.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S16MessageStable",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local expectedMessages = {
			"Soft penalty: near_critical_point subject=TinyfolkSpawn reason=within_soft_radius",
			"Soft penalty: near_route_edge subject=SpawnNode->EscapeNode reason=within_soft_radius",
			"Soft penalty: density_pressure subject=P_Dense/Chunk_Dense reason=penalized_density_class",
		}
		local expectedSortKeys = {
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"02:route_pressure|near_route_edge|route_edge|SpawnNode->EscapeNode",
			"03:density_pressure|density_pressure|chunk_density|P_Dense/Chunk_Dense",
		}
		assertEqual(outA.devaluation.totalPenalty, 21, "block86 total unchanged")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block86 total stable")
		assertEqual(#outA.devaluation.penalties, 3, "block86 three penalties")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block86 penalty count stable")
		for i, expectedMessage in ipairs(expectedMessages) do
			assertEqual(outA.devaluation.penalties[i].message, expectedMessage, "block86 message " .. tostring(i))
			assertEqual(outA.devaluation.penalties[i].sortKey, expectedSortKeys[i], "block86 sort key " .. tostring(i))
			assertEqual(
				outA.devaluation.penalties[i].message,
				outB.devaluation.penalties[i].message,
				"block86 message stable " .. tostring(i)
			)
			assertEqual(
				outA.devaluation.penalties[i].sortKey,
				outB.devaluation.penalties[i].sortKey,
				"block86 sort key stable " .. tostring(i)
			)
		end
		assertEqual(outA.devaluation.categoryTotals[1].totalScore, 1, "block86 proximity total")
		assertEqual(outA.devaluation.categoryTotals[2].totalScore, 11, "block86 route total")
		assertEqual(outA.devaluation.categoryTotals[3].totalScore, 9, "block86 density total")
	end

	-- BLOCK 87: Slice 17 - mixed penalties expose explicit deterministic sort-key ordering contract.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S17SortKey",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertFalse(result.accepted, "block87 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 21, "block87 total unchanged")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block87 proximity total")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 11, "block87 route total")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 9, "block87 density total")
		assertEqual(#result.devaluation.penalties, 3, "block87 three soft penalties")
		local previousKey = ""
		for i, penalty in ipairs(result.devaluation.penalties) do
			assertTrue(
				type(penalty.sortKey) == "string" and #penalty.sortKey > 0,
				"block87 sort key exists " .. tostring(i)
			)
			assertTrue(previousKey < penalty.sortKey, "block87 sort key order " .. tostring(i))
			previousKey = penalty.sortKey
		end
	end

	-- BLOCK 88: Slice 18 - grouped summary reflects a single soft penalty.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S18SingleSummary",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block88 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block88 total unchanged")
		assertEqual(#result.devaluation.penalties, 1, "block88 raw penalty preserved")
		assertEqual(#result.devaluation.groupSummaries, 3, "block88 three summaries")
		assertEqual(result.devaluation.groupSummaries[1].category, "proximity", "block88 proximity category")
		assertEqual(result.devaluation.groupSummaries[1].penaltyCount, 1, "block88 proximity count")
		assertEqual(result.devaluation.groupSummaries[1].totalScore, 1, "block88 proximity score")
		assertEqual(
			result.devaluation.groupSummaries[1].firstSortKey,
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"block88 first sort key"
		)
		assertEqual(
			result.devaluation.groupSummaries[1].lastSortKey,
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"block88 last sort key"
		)
		assertEqual(result.devaluation.groupSummaries[2].penaltyCount, 0, "block88 route count")
		assertEqual(result.devaluation.groupSummaries[2].totalScore, 0, "block88 route score")
		assertEqual(result.devaluation.groupSummaries[3].penaltyCount, 0, "block88 density count")
		assertEqual(result.devaluation.groupSummaries[3].totalScore, 0, "block88 density score")
	end

	-- BLOCK 89: Slice 18 - grouped summary reflects multiple penalties across categories.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S18MixedSummary",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertFalse(result.accepted, "block89 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 21, "block89 total unchanged")
		assertEqual(#result.devaluation.penalties, 3, "block89 raw penalties preserved")
		local expectedCategories = { "proximity", "route_pressure", "density_pressure" }
		local expectedScores = { 1, 11, 9 }
		local expectedKeys = {
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"02:route_pressure|near_route_edge|route_edge|SpawnNode->EscapeNode",
			"03:density_pressure|density_pressure|chunk_density|P_Dense/Chunk_Dense",
		}
		for i, expectedCategory in ipairs(expectedCategories) do
			local summary = result.devaluation.groupSummaries[i]
			assertEqual(summary.category, expectedCategory, "block89 summary category " .. tostring(i))
			assertEqual(summary.penaltyCount, 1, "block89 summary count " .. tostring(i))
			assertEqual(summary.totalScore, expectedScores[i], "block89 summary score " .. tostring(i))
			assertEqual(summary.firstSortKey, expectedKeys[i], "block89 summary first key " .. tostring(i))
			assertEqual(summary.lastSortKey, expectedKeys[i], "block89 summary last key " .. tostring(i))
			assertEqual(
				summary.totalScore,
				result.devaluation.categoryTotals[i].totalScore,
				"block89 totals match " .. tostring(i)
			)
		end
	end

	-- BLOCK 90: Slice 18 - grouped summary ordering remains stable across repeated runs.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S18StableSummary",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block90 total stable")
		assertEqual(#outA.devaluation.groupSummaries, #outB.devaluation.groupSummaries, "block90 summary count stable")
		for i, summaryA in ipairs(outA.devaluation.groupSummaries) do
			local summaryB = outB.devaluation.groupSummaries[i]
			assertEqual(summaryA.category, summaryB.category, "block90 category stable " .. tostring(i))
			assertEqual(summaryA.penaltyCount, summaryB.penaltyCount, "block90 count stable " .. tostring(i))
			assertEqual(summaryA.totalScore, summaryB.totalScore, "block90 score stable " .. tostring(i))
			assertEqual(
				tostring(summaryA.firstSortKey),
				tostring(summaryB.firstSortKey),
				"block90 first key stable " .. tostring(i)
			)
			assertEqual(
				tostring(summaryA.lastSortKey),
				tostring(summaryB.lastSortKey),
				"block90 last key stable " .. tostring(i)
			)
		end
	end

	-- BLOCK 91: Slice 19 - factor summary reflects a single-factor penalty.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S19SingleFactorSummary",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block91 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block91 total unchanged")
		assertEqual(#result.devaluation.penalties, 1, "block91 raw penalty preserved")
		assertEqual(#result.devaluation.groupSummaries, 3, "block91 category summaries preserved")
		assertEqual(#result.devaluation.factorSummaries, 1, "block91 one factor summary")
		local summary = result.devaluation.factorSummaries[1]
		assertEqual(summary.factor, "near_critical_point", "block91 factor")
		assertEqual(summary.penaltyCount, 1, "block91 count")
		assertEqual(summary.totalScore, 1, "block91 score")
		assertEqual(
			summary.firstSortKey,
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"block91 first key"
		)
		assertEqual(
			summary.lastSortKey,
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"block91 last key"
		)
	end

	-- BLOCK 92: Slice 19 - factor summary reflects multiple factors deterministically.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S19MixedFactorSummary",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertFalse(result.accepted, "block92 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 21, "block92 total unchanged")
		assertEqual(#result.devaluation.penalties, 3, "block92 raw penalties preserved")
		assertEqual(#result.devaluation.groupSummaries, 3, "block92 category summaries preserved")
		assertEqual(#result.devaluation.factorSummaries, 3, "block92 three factor summaries")
		local expectedFactors = { "near_critical_point", "near_route_edge", "density_pressure" }
		local expectedScores = { 1, 11, 9 }
		local expectedKeys = {
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"02:route_pressure|near_route_edge|route_edge|SpawnNode->EscapeNode",
			"03:density_pressure|density_pressure|chunk_density|P_Dense/Chunk_Dense",
		}
		for i, expectedFactor in ipairs(expectedFactors) do
			local summary = result.devaluation.factorSummaries[i]
			assertEqual(summary.factor, expectedFactor, "block92 factor " .. tostring(i))
			assertEqual(summary.penaltyCount, 1, "block92 count " .. tostring(i))
			assertEqual(summary.totalScore, expectedScores[i], "block92 score " .. tostring(i))
			assertEqual(summary.firstSortKey, expectedKeys[i], "block92 first key " .. tostring(i))
			assertEqual(summary.lastSortKey, expectedKeys[i], "block92 last key " .. tostring(i))
		end
	end

	-- BLOCK 93: Slice 19 - factor summaries remain stable across repeated runs.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S19StableFactorSummary",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block93 total stable")
		assertEqual(
			#outA.devaluation.factorSummaries,
			#outB.devaluation.factorSummaries,
			"block93 summary count stable"
		)
		for i, summaryA in ipairs(outA.devaluation.factorSummaries) do
			local summaryB = outB.devaluation.factorSummaries[i]
			assertEqual(summaryA.factor, summaryB.factor, "block93 factor stable " .. tostring(i))
			assertEqual(summaryA.penaltyCount, summaryB.penaltyCount, "block93 count stable " .. tostring(i))
			assertEqual(summaryA.totalScore, summaryB.totalScore, "block93 score stable " .. tostring(i))
			assertEqual(summaryA.firstSortKey, summaryB.firstSortKey, "block93 first key stable " .. tostring(i))
			assertEqual(summaryA.lastSortKey, summaryB.lastSortKey, "block93 last key stable " .. tostring(i))
		end
		for i, summaryA in ipairs(outA.devaluation.groupSummaries) do
			local summaryB = outB.devaluation.groupSummaries[i]
			assertEqual(summaryA.category, summaryB.category, "block93 category summary stable " .. tostring(i))
			assertEqual(summaryA.totalScore, summaryB.totalScore, "block93 category score stable " .. tostring(i))
		end
	end

	-- BLOCK 94: Slice 20 - subject summary reflects a single penalty.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S20SingleSubjectSummary",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block94 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block94 total unchanged")
		assertEqual(#result.devaluation.penalties, 1, "block94 raw penalty preserved")
		assertEqual(#result.devaluation.groupSummaries, 3, "block94 category summaries preserved")
		assertEqual(#result.devaluation.factorSummaries, 1, "block94 factor summaries preserved")
		assertEqual(#result.devaluation.subjectSummaries, 1, "block94 one subject summary")
		local summary = result.devaluation.subjectSummaries[1]
		assertEqual(summary.subjectType, "critical_point", "block94 subject type")
		assertEqual(summary.subjectName, "TinyfolkSpawn", "block94 subject name")
		assertEqual(summary.penaltyCount, 1, "block94 count")
		assertEqual(summary.totalScore, 1, "block94 score")
		assertEqual(
			summary.firstSortKey,
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"block94 first key"
		)
		assertEqual(
			summary.lastSortKey,
			"01:proximity|near_critical_point|critical_point|TinyfolkSpawn",
			"block94 last key"
		)
	end

	-- BLOCK 95: Slice 20 - subject summary aggregates multiple penalties on the same subject.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			routeEdgeSoftRadius = 0,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S20AggregatedSubjectSummary",
			proposedOccupiedSpace = {
				{
					tag = "dense_touch_a",
					worldCenter = { x = 30, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
				{
					tag = "dense_touch_b",
					worldCenter = { x = 31, y = 0, z = 0 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		assertFalse(result.accepted, "block95 hard rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 18, "block95 total unchanged")
		assertEqual(#result.devaluation.penalties, 2, "block95 raw penalties preserved")
		assertEqual(#result.devaluation.subjectSummaries, 1, "block95 one subject summary")
		local summary = result.devaluation.subjectSummaries[1]
		assertEqual(summary.subjectType, "chunk_density", "block95 subject type")
		assertEqual(summary.subjectName, "P_Dense/Chunk_Dense", "block95 subject name")
		assertEqual(summary.penaltyCount, 2, "block95 count")
		assertEqual(summary.totalScore, 18, "block95 score")
		assertEqual(
			summary.firstSortKey,
			"03:density_pressure|density_pressure|chunk_density|P_Dense/Chunk_Dense",
			"block95 first key"
		)
		assertEqual(
			summary.lastSortKey,
			"03:density_pressure|density_pressure|chunk_density|P_Dense/Chunk_Dense",
			"block95 last key"
		)
		assertEqual(result.devaluation.groupSummaries[3].penaltyCount, 2, "block95 category count preserved")
		assertEqual(result.devaluation.factorSummaries[1].penaltyCount, 2, "block95 factor count preserved")
	end

	-- BLOCK 96: Slice 20 - subject summaries are deterministic across subjects and runs.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S20StableSubjectSummary",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, 21, "block96 total unchanged")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block96 total stable")
		assertEqual(#outA.devaluation.subjectSummaries, 3, "block96 three subject summaries")
		assertEqual(
			#outA.devaluation.subjectSummaries,
			#outB.devaluation.subjectSummaries,
			"block96 subject count stable"
		)
		local expectedSubjects = {
			{ subjectType = "critical_point", subjectName = "TinyfolkSpawn", totalScore = 1 },
			{ subjectType = "route_edge", subjectName = "SpawnNode->EscapeNode", totalScore = 11 },
			{ subjectType = "chunk_density", subjectName = "P_Dense/Chunk_Dense", totalScore = 9 },
		}
		for i, expected in ipairs(expectedSubjects) do
			local summaryA = outA.devaluation.subjectSummaries[i]
			local summaryB = outB.devaluation.subjectSummaries[i]
			assertEqual(summaryA.subjectType, expected.subjectType, "block96 subject type " .. tostring(i))
			assertEqual(summaryA.subjectName, expected.subjectName, "block96 subject name " .. tostring(i))
			assertEqual(summaryA.penaltyCount, 1, "block96 count " .. tostring(i))
			assertEqual(summaryA.totalScore, expected.totalScore, "block96 score " .. tostring(i))
			assertEqual(summaryA.subjectType, summaryB.subjectType, "block96 subject type stable " .. tostring(i))
			assertEqual(summaryA.subjectName, summaryB.subjectName, "block96 subject name stable " .. tostring(i))
			assertEqual(summaryA.penaltyCount, summaryB.penaltyCount, "block96 count stable " .. tostring(i))
			assertEqual(summaryA.totalScore, summaryB.totalScore, "block96 score stable " .. tostring(i))
			assertEqual(summaryA.firstSortKey, summaryB.firstSortKey, "block96 first key stable " .. tostring(i))
			assertEqual(summaryA.lastSortKey, summaryB.lastSortKey, "block96 last key stable " .. tostring(i))
		end
	end

	-- BLOCK 97: Slice 21 - summary invariants pass for a single-penalty result.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S21SingleInvariant",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		local invariant = RealmDistrictPlacementValidator.ValidateDevaluationSummaryConsistency(result.devaluation)
		assertTrue(invariant.passed, "block97 invariant passed")
		assertEqual(#invariant.errors, 0, "block97 no invariant errors")
		assertEqual(result.devaluation.totalPenalty, 1, "block97 total unchanged")
	end

	-- BLOCK 98: Slice 21 - summary invariants pass for multi-penalty, multi-category output.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S21MixedInvariant",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local invariant = RealmDistrictPlacementValidator.ValidateDevaluationSummaryConsistency(result.devaluation)
		assertTrue(invariant.passed, "block98 invariant passed")
		assertEqual(#invariant.errors, 0, "block98 no invariant errors")
		assertEqual(result.devaluation.totalPenalty, 21, "block98 total unchanged")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block98 category proximity")
		assertEqual(result.devaluation.factorSummaries[2].totalScore, 11, "block98 factor route")
		assertEqual(result.devaluation.subjectSummaries[3].totalScore, 9, "block98 subject density")
	end

	-- BLOCK 99: Slice 21 - invariant results are stable across repeated runs.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S21StableInvariant",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local invariantA = RealmDistrictPlacementValidator.ValidateDevaluationSummaryConsistency(outA.devaluation)
		local invariantB = RealmDistrictPlacementValidator.ValidateDevaluationSummaryConsistency(outB.devaluation)
		assertTrue(invariantA.passed, "block99 invariant A passed")
		assertTrue(invariantB.passed, "block99 invariant B passed")
		assertEqual(#invariantA.errors, #invariantB.errors, "block99 error count stable")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block99 total stable")
		assertEqual(
			#outA.devaluation.subjectSummaries,
			#outB.devaluation.subjectSummaries,
			"block99 subject summary count stable"
		)
	end

	-- BLOCK 100: Slice 21 - invariant helper detects a deliberate summary mismatch.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 60,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S21MismatchInvariant",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		local mismatchedFactorSummaries = {
			{
				factor = result.devaluation.factorSummaries[1].factor,
				penaltyCount = result.devaluation.factorSummaries[1].penaltyCount,
				totalScore = result.devaluation.factorSummaries[1].totalScore + 1,
				firstSortKey = result.devaluation.factorSummaries[1].firstSortKey,
				lastSortKey = result.devaluation.factorSummaries[1].lastSortKey,
			},
		}
		local mismatched = {
			totalPenalty = result.devaluation.totalPenalty,
			penalties = result.devaluation.penalties,
			categoryTotals = result.devaluation.categoryTotals,
			groupSummaries = result.devaluation.groupSummaries,
			factorSummaries = mismatchedFactorSummaries,
			subjectSummaries = result.devaluation.subjectSummaries,
		}
		local invariant = RealmDistrictPlacementValidator.ValidateDevaluationSummaryConsistency(mismatched)
		assertFalse(invariant.passed, "block100 invariant failed")
		assertTrue(#invariant.errors > 0, "block100 invariant errors reported")
	end

	-- BLOCK 101: Slice 22 - config snapshot reflects basic split soft config values.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S22BasicSnapshot",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local snapshot = result.devaluation.configSnapshot
		assertEqual(result.devaluation.totalPenalty, 21, "block101 total unchanged")
		assertEqual(snapshot.criticalPointSoftRadii.tinyfolk_spawn, 60, "block101 tinyfolk radius")
		assertEqual(snapshot.criticalPointSoftRadii.escape_route, 0, "block101 escape radius")
		assertEqual(snapshot.routeEdgeSoftRadius, 20, "block101 route radius")
		assertEqual(snapshot.densityPressurePenaltyScores.dense, 9, "block101 dense penalty")
		assertEqual(snapshot.densityPressurePenaltyScores.moderate, 0, "block101 moderate penalty")
	end

	-- BLOCK 102: Slice 22 - config snapshot reflects shared critical-point fallback.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			nearCriticalPointSoftRadius = 40,
			nearRouteEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S22SharedFallbackSnapshot",
			proposedOccupiedSpace = {
				{ tag = "near_spawn", worldCenter = { x = 0, y = 0, z = -40 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		local snapshot = result.devaluation.configSnapshot
		assertEqual(result.devaluation.totalPenalty, 1, "block102 total unchanged")
		assertEqual(snapshot.criticalPointSoftRadii.tinyfolk_spawn, 40, "block102 tinyfolk fallback")
		assertEqual(snapshot.criticalPointSoftRadii.escape_route, 40, "block102 escape fallback")
		assertEqual(snapshot.criticalPointSoftRadii.return_point, 40, "block102 return fallback")
		assertEqual(snapshot.criticalPointSoftRadii.station, 40, "block102 station fallback")
		assertEqual(snapshot.criticalPointSoftRadii.construction_site, 40, "block102 construction fallback")
		assertEqual(snapshot.criticalPointSoftRadii.capture_zone, 40, "block102 capture fallback")
		assertEqual(snapshot.criticalPointSoftRadii.control_zone, 40, "block102 control fallback")
		assertEqual(snapshot.routeEdgeSoftRadius, 0, "block102 route fallback")
	end

	-- BLOCK 103: Slice 22 - config snapshot reflects category and density class overrides.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 50,
			tinyfolkSpawnSoftRadius = 0,
			escapeRouteSoftRadius = 70,
			routeEdgeSoftRadius = 15,
			penalizedTraversalDensityClasses = { "moderate", "dense" },
			densityPressurePenaltyScore = 6,
			moderateDensityPressurePenaltyScore = 0,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S22OverrideSnapshot",
			proposedOccupiedSpace = {
				{
					tag = "near_escape",
					worldCenter = { x = 100, y = 0, z = -70 },
					halfExtents = { x = 1, y = 1, z = 1 },
				},
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		local snapshot = result.devaluation.configSnapshot
		assertEqual(result.devaluation.totalPenalty, 1, "block103 total unchanged")
		assertEqual(snapshot.criticalPointSoftRadii.tinyfolk_spawn, 0, "block103 tinyfolk override")
		assertEqual(snapshot.criticalPointSoftRadii.escape_route, 70, "block103 escape override")
		assertEqual(snapshot.criticalPointSoftRadii.return_point, 50, "block103 return shared")
		assertEqual(snapshot.routeEdgeSoftRadius, 15, "block103 route split")
		assertEqual(snapshot.densityPressurePenaltyScores.open, 0, "block103 open penalty")
		assertEqual(snapshot.densityPressurePenaltyScores.sparse, 0, "block103 sparse penalty")
		assertEqual(snapshot.densityPressurePenaltyScores.moderate, 0, "block103 moderate override")
		assertEqual(snapshot.densityPressurePenaltyScores.dense, 9, "block103 dense override")
	end

	-- BLOCK 104: Slice 22 - config snapshot remains stable across repeated runs.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S22StableSnapshot",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block104 total stable")
		assertEqual(
			outA.devaluation.configSnapshot.criticalPointSoftRadii.tinyfolk_spawn,
			outB.devaluation.configSnapshot.criticalPointSoftRadii.tinyfolk_spawn,
			"block104 tinyfolk stable"
		)
		assertEqual(
			outA.devaluation.configSnapshot.routeEdgeSoftRadius,
			outB.devaluation.configSnapshot.routeEdgeSoftRadius,
			"block104 route stable"
		)
		assertEqual(
			outA.devaluation.configSnapshot.densityPressurePenaltyScores.dense,
			outB.devaluation.configSnapshot.densityPressurePenaltyScores.dense,
			"block104 dense stable"
		)
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block104 penalties stable")
		assertEqual(
			#outA.devaluation.groupSummaries,
			#outB.devaluation.groupSummaries,
			"block104 group summaries stable"
		)
		assertEqual(
			#outA.devaluation.factorSummaries,
			#outB.devaluation.factorSummaries,
			"block104 factor summaries stable"
		)
		assertEqual(
			#outA.devaluation.subjectSummaries,
			#outB.devaluation.subjectSummaries,
			"block104 subject summaries stable"
		)
	end

	-- BLOCK 105: Slice 23 - hard config snapshot reflects critical exclusion radii.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 40,
				returnPointExclusionRadius = 30,
				stationExclusionRadius = 20,
				constructionSiteExclusionRadius = 10,
				captureZoneExclusionRadius = 8,
				controlZoneExclusionRadius = 6,
			},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S23CriticalSnapshot",
			proposedOccupiedSpace = {
				{ tag = "safe", worldCenter = { x = 0, y = 0, z = 80 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig)
		local snapshot = result.configSnapshot
		assertTrue(result.accepted, "block105 accepted")
		assertEqual(snapshot.criticalExclusionRadii.tinyfolk_spawn, 50, "block105 tinyfolk radius")
		assertEqual(snapshot.criticalExclusionRadii.escape_route, 40, "block105 escape radius")
		assertEqual(snapshot.criticalExclusionRadii.return_point, 30, "block105 return radius")
		assertEqual(snapshot.criticalExclusionRadii.station, 20, "block105 station radius")
		assertEqual(snapshot.criticalExclusionRadii.construction_site, 10, "block105 construction radius")
		assertEqual(snapshot.criticalExclusionRadii.capture_zone, 8, "block105 capture radius")
		assertEqual(snapshot.criticalExclusionRadii.control_zone, 6, "block105 control radius")
		assertEqual(#snapshot.policy.allowedEnvironmentClasses, 0, "block105 no environment policy")
		assertEqual(result.devaluation.totalPenalty, 0, "block105 devaluation unchanged")
	end

	-- BLOCK 106: Slice 23 - hard config snapshot reflects policy lists.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor", "outdoor" },
				allowedTraversalDensityClasses = { "sparse", "moderate" },
				disallowedRecurringStructureTags = { "entry_hub", "exit_chamber" },
			},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S23PolicySnapshot",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig)
		local snapshot = result.configSnapshot
		assertFalse(result.accepted, "block106 hard rejected by occupied/recurring policy")
		assertEqual(snapshot.policy.allowedEnvironmentClasses[1], "indoor", "block106 env 1")
		assertEqual(snapshot.policy.allowedEnvironmentClasses[2], "outdoor", "block106 env 2")
		assertEqual(snapshot.policy.allowedTraversalDensityClasses[1], "sparse", "block106 density 1")
		assertEqual(snapshot.policy.allowedTraversalDensityClasses[2], "moderate", "block106 density 2")
		assertEqual(snapshot.policy.disallowedRecurringStructureTags[1], "entry_hub", "block106 tag 1")
		assertEqual(snapshot.policy.disallowedRecurringStructureTags[2], "exit_chamber", "block106 tag 2")
		assertEqual(snapshot.criticalExclusionRadii.tinyfolk_spawn, 0, "block106 no critical policy")
		assertEqual(result.devaluation.totalPenalty, 0, "block106 devaluation unchanged")
	end

	-- BLOCK 107: Slice 23 - hard config snapshot reflects nil/disabled config paths.
	do
		local request: DistrictPlacementRequest = {
			districtId = "D_S23DisabledSnapshot",
			proposedOccupiedSpace = {
				{ tag = "safe", worldCenter = { x = 0, y = 0, z = 80 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		local snapshot = result.configSnapshot
		assertTrue(result.accepted, "block107 accepted")
		assertEqual(snapshot.criticalExclusionRadii.tinyfolk_spawn, 0, "block107 tinyfolk disabled")
		assertEqual(snapshot.criticalExclusionRadii.escape_route, 0, "block107 escape disabled")
		assertEqual(snapshot.criticalExclusionRadii.return_point, 0, "block107 return disabled")
		assertEqual(snapshot.criticalExclusionRadii.station, 0, "block107 station disabled")
		assertEqual(snapshot.criticalExclusionRadii.construction_site, 0, "block107 construction disabled")
		assertEqual(snapshot.criticalExclusionRadii.capture_zone, 0, "block107 capture disabled")
		assertEqual(snapshot.criticalExclusionRadii.control_zone, 0, "block107 control disabled")
		assertEqual(#snapshot.policy.allowedEnvironmentClasses, 0, "block107 environment disabled")
		assertEqual(#snapshot.policy.allowedTraversalDensityClasses, 0, "block107 density disabled")
		assertEqual(#snapshot.policy.disallowedRecurringStructureTags, 0, "block107 recurring disabled")
	end

	-- BLOCK 108: Slice 23 - hard config snapshot remains stable across repeated runs.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 0,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S23StableSnapshot",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig)
		assertEqual(outA.accepted, outB.accepted, "block108 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block108 reject count stable")
		assertEqual(
			outA.configSnapshot.criticalExclusionRadii.tinyfolk_spawn,
			outB.configSnapshot.criticalExclusionRadii.tinyfolk_spawn,
			"block108 tinyfolk stable"
		)
		assertEqual(
			outA.configSnapshot.policy.allowedEnvironmentClasses[1],
			outB.configSnapshot.policy.allowedEnvironmentClasses[1],
			"block108 environment stable"
		)
		assertEqual(
			outA.configSnapshot.policy.allowedTraversalDensityClasses[1],
			outB.configSnapshot.policy.allowedTraversalDensityClasses[1],
			"block108 density stable"
		)
		assertEqual(
			outA.configSnapshot.policy.disallowedRecurringStructureTags[1],
			outB.configSnapshot.policy.disallowedRecurringStructureTags[1],
			"block108 recurring stable"
		)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block108 devaluation stable")
	end

	-- BLOCK 109: Slice 24 - unified validation snapshot contains hard and soft snapshot content.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 0,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S24UnifiedSnapshot",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertFalse(result.accepted, "block109 hard rejected")
		assertEqual(
			result.validationSnapshot.hardConfig.criticalExclusionRadii.tinyfolk_spawn,
			50,
			"block109 hard critical"
		)
		assertEqual(
			result.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"indoor",
			"block109 hard env"
		)
		assertEqual(
			result.validationSnapshot.hardConfig.policy.allowedTraversalDensityClasses[1],
			"sparse",
			"block109 hard density"
		)
		assertEqual(
			result.validationSnapshot.hardConfig.policy.disallowedRecurringStructureTags[1],
			"entry_hub",
			"block109 hard recurring"
		)
		assertEqual(
			result.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			60,
			"block109 soft critical"
		)
		assertEqual(result.validationSnapshot.softConfig.routeEdgeSoftRadius, 20, "block109 soft route")
		assertEqual(result.validationSnapshot.softConfig.densityPressurePenaltyScores.dense, 9, "block109 soft density")
		assertEqual(result.devaluation.totalPenalty, 15, "block109 devaluation unchanged")
	end

	-- BLOCK 110: Slice 24 - unified snapshot preserves old separate access paths.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S24SnapshotCompatibility",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertEqual(
			result.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			result.configSnapshot.policy.allowedEnvironmentClasses[1],
			"block110 hard path equivalent"
		)
		assertEqual(
			result.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			result.devaluation.configSnapshot.criticalPointSoftRadii.tinyfolk_spawn,
			"block110 soft path equivalent"
		)
		assertEqual(result.devaluation.totalPenalty, 11, "block110 devaluation unchanged")
	end

	-- BLOCK 111: Slice 24 - unified validation snapshot remains stable across repeated runs.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 0,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S24StableUnifiedSnapshot",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 0, y = 0, z = 50 }, halfExtents = { x = 5, y = 5, z = 5 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertEqual(outA.accepted, outB.accepted, "block111 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block111 reject count stable")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block111 devaluation stable")
		assertEqual(
			outA.validationSnapshot.hardConfig.criticalExclusionRadii.tinyfolk_spawn,
			outB.validationSnapshot.hardConfig.criticalExclusionRadii.tinyfolk_spawn,
			"block111 hard critical stable"
		)
		assertEqual(
			outA.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			outB.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"block111 hard policy stable"
		)
		assertEqual(
			outA.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			outB.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			"block111 soft critical stable"
		)
		assertEqual(
			outA.validationSnapshot.softConfig.densityPressurePenaltyScores.dense,
			outB.validationSnapshot.softConfig.densityPressurePenaltyScores.dense,
			"block111 soft density stable"
		)
	end

	-- BLOCK 112: Slice 25 - validation result exposes the documented top-level contract.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S25ResultShape",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertValidationResultShape(result, "block112 shape")
		assertEqual(result.devaluation.totalPenalty, 11, "block112 devaluation unchanged")
		assertEqual(
			result.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"indoor",
			"block112 hard snapshot"
		)
		assertEqual(
			result.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			40,
			"block112 soft snapshot"
		)
	end

	-- BLOCK 113: Slice 25 - contracted devaluation summary sections are present.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S25DevaluationShape",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertValidationResultShape(result, "block113 shape")
		assertEqual(#result.devaluation.penalties, 3, "block113 penalties present")
		assertEqual(#result.devaluation.categoryTotals, 3, "block113 category totals present")
		assertEqual(#result.devaluation.groupSummaries, 3, "block113 group summaries present")
		assertEqual(#result.devaluation.factorSummaries, 3, "block113 factor summaries present")
		assertEqual(#result.devaluation.subjectSummaries, 3, "block113 subject summaries present")
		assertEqual(result.devaluation.totalPenalty, 21, "block113 total unchanged")
	end

	-- BLOCK 114: Slice 25 - result shape and output stay stable across repeated runs.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S25StableShape",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertValidationResultShape(outA, "block114 shape A")
		assertValidationResultShape(outB, "block114 shape B")
		assertEqual(outA.accepted, outB.accepted, "block114 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block114 reject count stable")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block114 total stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block114 penalties stable")
		assertEqual(
			#outA.devaluation.groupSummaries,
			#outB.devaluation.groupSummaries,
			"block114 group summaries stable"
		)
		assertEqual(
			#outA.devaluation.factorSummaries,
			#outB.devaluation.factorSummaries,
			"block114 factor summaries stable"
		)
		assertEqual(
			#outA.devaluation.subjectSummaries,
			#outB.devaluation.subjectSummaries,
			"block114 subject summaries stable"
		)
		assertEqual(
			outA.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			outB.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"block114 hard snapshot stable"
		)
		assertEqual(
			outA.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			outB.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			"block114 soft snapshot stable"
		)
	end

	-- BLOCK 115: Slice 26 - documented result and devaluation section order is stable.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S26SectionOrder",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertValidationResultShape(outA, "block115 shape A")
		assertValidationResultShape(outB, "block115 shape B")
		for i, sectionName in ipairs(EXPECTED_RESULT_SECTION_ORDER) do
			assertTrue(outA[sectionName] ~= nil and outB[sectionName] ~= nil, "block115 result order " .. tostring(i))
		end
		for i, sectionName in ipairs(EXPECTED_DEVALUATION_SECTION_ORDER) do
			assertTrue(
				outA.devaluation[sectionName] ~= nil and outB.devaluation[sectionName] ~= nil,
				"block115 devaluation order " .. tostring(i)
			)
		end
		assertEqual(outA.accepted, outB.accepted, "block115 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block115 reject count stable")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block115 total stable")
		assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, "block115 penalties stable")
		assertEqual(#outA.devaluation.groupSummaries, #outB.devaluation.groupSummaries, "block115 summaries stable")
		assertEqual(
			outA.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			outB.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			"block115 snapshot stable"
		)
	end

	-- BLOCK 116: Slice 27 - preserved hard snapshot path matches unified hard snapshot.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 50,
				escapeRouteExclusionRadius = 0,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S27HardCompatibility",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertValidationResultShape(result, "block116 shape")
		assertCompatibilitySnapshotPaths(result, "block116 compatibility")
		assertEqual(result.configSnapshot.policy.allowedEnvironmentClasses[1], "indoor", "block116 legacy hard env")
		assertEqual(
			result.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"indoor",
			"block116 unified hard env"
		)
		assertEqual(result.devaluation.totalPenalty, 11, "block116 output unchanged")
	end

	-- BLOCK 117: Slice 27 - preserved soft snapshot path matches unified soft snapshot.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S27SoftCompatibility",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result = RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, nil, softConfig)
		assertValidationResultShape(result, "block117 shape")
		assertCompatibilitySnapshotPaths(result, "block117 compatibility")
		assertEqual(result.devaluation.configSnapshot.routeEdgeSoftRadius, 20, "block117 legacy soft route")
		assertEqual(result.validationSnapshot.softConfig.routeEdgeSoftRadius, 20, "block117 unified soft route")
		assertEqual(result.devaluation.totalPenalty, 21, "block117 output unchanged")
	end

	-- BLOCK 118: Slice 27 - compatibility-visible outputs remain stable across repeated runs.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S27StableCompatibility",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertCompatibilitySnapshotPaths(outA, "block118 compatibility A")
		assertCompatibilitySnapshotPaths(outB, "block118 compatibility B")
		assertEqual(outA.accepted, outB.accepted, "block118 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block118 reject count stable")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block118 total stable")
		assertEqual(
			outA.configSnapshot.policy.allowedEnvironmentClasses[1],
			outB.configSnapshot.policy.allowedEnvironmentClasses[1],
			"block118 legacy hard stable"
		)
		assertEqual(
			outA.devaluation.configSnapshot.criticalPointSoftRadii.tinyfolk_spawn,
			outB.devaluation.configSnapshot.criticalPointSoftRadii.tinyfolk_spawn,
			"block118 legacy soft stable"
		)
		assertEqual(
			outA.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			outB.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"block118 unified hard stable"
		)
		assertEqual(
			outA.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			outB.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			"block118 unified soft stable"
		)
	end

	-- BLOCK 119: Slice 28 - minimal consumer can read accepted and rejectReasons.
	do
		local acceptedRequest: DistrictPlacementRequest = {
			districtId = "D_S28AcceptedConsumer",
			proposedOccupiedSpace = {
				{ tag = "safe", worldCenter = { x = 0, y = 0, z = 80 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local rejectedRequest: DistrictPlacementRequest = {
			districtId = "D_S28RejectedConsumer",
			proposedOccupiedSpace = {
				{ tag = "overlap", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local accepted = RealmDistrictPlacementValidator.ValidatePlacement(acceptedRequest, protoOutput)
		local rejected = RealmDistrictPlacementValidator.ValidatePlacement(rejectedRequest, protoOutput)
		assertMinimalConsumerReadPaths(accepted, "block119 accepted")
		assertMinimalConsumerReadPaths(rejected, "block119 rejected")
		assertTrue(accepted.accepted, "block119 accepted result")
		assertEqual(#accepted.rejectReasons, 0, "block119 accepted reject count")
		assertFalse(rejected.accepted, "block119 rejected result")
		assertTrue(#rejected.rejectReasons > 0, "block119 rejected reject count")
	end

	-- BLOCK 120: Slice 28 - minimal consumer can read penalty totals, summaries, and unified snapshots.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 0,
			tinyfolkSpawnSoftRadius = 60,
			escapeRouteSoftRadius = 0,
			routeEdgeSoftRadius = 20,
			denseDensityPressurePenaltyScore = 9,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S28PenaltyConsumer",
			proposedOccupiedSpace = {
				{ tag = "near_both", worldCenter = { x = 59, y = 0, z = 10 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local assemblyOutput = makeRoutePressureOutput()
		assemblyOutput.resolvedOccupiedSpace = {
			{
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				tag = "dense_body",
				worldCenter = { x = 59, y = 0, z = 10 },
				halfExtents = { x = 1, y = 1, z = 1 },
				isLandmarkAnchor = false,
			},
		}
		assemblyOutput.resolvedMetadataByPlacement = {
			P_Dense = {
				placementId = "P_Dense",
				chunkId = "Chunk_Dense",
				traversalDensityClass = "dense",
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, assemblyOutput, hardConfig, softConfig)
		assertMinimalConsumerReadPaths(result, "block120 consumer")
		assertFalse(result.accepted, "block120 rejected by occupied overlap")
		assertEqual(result.devaluation.totalPenalty, 21, "block120 total penalty")
		assertEqual(result.devaluation.categoryTotals[1].totalScore, 1, "block120 proximity total")
		assertEqual(result.devaluation.categoryTotals[2].totalScore, 11, "block120 route total")
		assertEqual(result.devaluation.categoryTotals[3].totalScore, 9, "block120 density total")
		assertEqual(
			result.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"indoor",
			"block120 hard snapshot"
		)
		assertEqual(result.validationSnapshot.softConfig.routeEdgeSoftRadius, 20, "block120 soft route snapshot")
		assertEqual(
			result.validationSnapshot.softConfig.densityPressurePenaltyScores.dense,
			9,
			"block120 soft density snapshot"
		)
	end

	-- BLOCK 121: Slice 28 - consumer-visible outputs remain stable across repeated runs.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S28StableConsumer",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertMinimalConsumerReadPaths(outA, "block121 consumer A")
		assertMinimalConsumerReadPaths(outB, "block121 consumer B")
		assertEqual(outA.accepted, outB.accepted, "block121 accepted stable")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block121 reject count stable")
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block121 total stable")
		assertEqual(
			outA.devaluation.categoryTotals[1].totalScore,
			outB.devaluation.categoryTotals[1].totalScore,
			"block121 category total stable"
		)
		assertEqual(
			outA.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			outB.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"block121 hard snapshot stable"
		)
		assertEqual(
			outA.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			outB.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			"block121 soft snapshot stable"
		)
	end

	local validationResultExampleRegistry: { [string]: any } = {
		accepted_no_penalty = function()
			local request: DistrictPlacementRequest = {
				districtId = "D_S36AcceptedNoPenalty",
				proposedOccupiedSpace = {
					{ tag = "safe", worldCenter = { x = 0, y = 0, z = 80 }, halfExtents = { x = 1, y = 1, z = 1 } },
				},
			}
			return RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		end,
		accepted_with_penalty = function()
			local softConfig: DistrictPlacementSoftConfig = {
				criticalPointSoftRadius = 60,
				routeEdgeSoftRadius = 0,
			}
			local request: DistrictPlacementRequest = {
				districtId = "D_S36AcceptedPenalty",
				proposedOccupiedSpace = {
					{
						tag = "near_spawn",
						worldCenter = { x = 0, y = 0, z = -60 },
						halfExtents = { x = 1, y = 1, z = 1 },
					},
				},
			}
			return RealmDistrictPlacementValidator.ValidatePlacement(
				request,
				makeCriticalCategoryOutput(),
				nil,
				softConfig
			)
		end,
		rejected_with_penalty = function()
			local softConfig: DistrictPlacementSoftConfig = {
				criticalPointSoftRadius = 40,
				routeEdgeSoftRadius = 0,
			}
			local request: DistrictPlacementRequest = {
				districtId = "D_S36RejectedPenalty",
				proposedOccupiedSpace = {
					{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
				},
			}
			return RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		end,
		rejected_no_penalty = function()
			local request: DistrictPlacementRequest = {
				districtId = "D_S36RejectedNoPenalty",
				proposedOccupiedSpace = {
					{ tag = "overlap", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
				},
			}
			return RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput)
		end,
	}

	local validationResultExampleAliases: { [string]: string } = {
		a0 = "accepted_no_penalty",
		a1 = "accepted_with_penalty",
		r1 = "rejected_with_penalty",
		r0 = "rejected_no_penalty",
	}

	local VALIDATION_RESULT_CANONICAL_CASE_ORDER = {
		"accepted_no_penalty",
		"accepted_with_penalty",
		"rejected_with_penalty",
		"rejected_no_penalty",
	}

	local VALIDATION_RESULT_ALIAS_CASE_ORDER = { "a0", "a1", "r1", "r0" }

	local validationResultCaseMetadata: { [string]: any } = {
		accepted_no_penalty = {
			keys = {
				canonical = "accepted_no_penalty",
				aliases = { "a0" },
			},
			mode = {
				expectedAccepted = true,
				expectRejects = false,
				expectPenalties = false,
			},
			devaluation = {
				expectedTotalPenalty = 0,
				expectedFirstCategoryTotal = 0,
			},
		},
		accepted_with_penalty = {
			keys = {
				canonical = "accepted_with_penalty",
				aliases = { "a1" },
			},
			mode = {
				expectedAccepted = true,
				expectRejects = false,
				expectPenalties = true,
			},
			devaluation = {
				expectedTotalPenalty = 1,
				expectedFirstCategoryTotal = 1,
			},
		},
		rejected_with_penalty = {
			keys = {
				canonical = "rejected_with_penalty",
				aliases = { "r1" },
			},
			mode = {
				expectedAccepted = false,
				expectRejects = true,
				expectPenalties = true,
			},
			devaluation = {
				expectedTotalPenalty = 11,
				expectedFirstCategoryTotal = 11,
			},
		},
		rejected_no_penalty = {
			keys = {
				canonical = "rejected_no_penalty",
				aliases = { "r0" },
			},
			mode = {
				expectedAccepted = false,
				expectRejects = true,
				expectPenalties = false,
			},
			devaluation = {
				expectedTotalPenalty = 0,
				expectedFirstCategoryTotal = 0,
			},
		},
	}

	local function resolveValidationResultCaseKey(caseKey: string): string
		return validationResultExampleAliases[caseKey] or caseKey
	end

	local function getValidationResultCaseMetadata(caseKey: string): any
		local canonicalKey = resolveValidationResultCaseKey(caseKey)
		local metadata = validationResultCaseMetadata[canonicalKey]
		assertTrue(type(metadata) == "table", "case metadata " .. canonicalKey)
		return metadata
	end

	local function getValidationResultCaseBuilder(caseKey: string): any
		local canonicalKey = resolveValidationResultCaseKey(caseKey)
		local makeResult = validationResultExampleRegistry[canonicalKey]
		assertTrue(type(makeResult) == "function", "example registry entry " .. canonicalKey)
		return makeResult
	end

	local function makeValidationResultExample(caseKey: string)
		return getValidationResultCaseBuilder(caseKey)()
	end

	local function enumerateValidationResultCanonicalCaseKeys(): { string }
		local keys = {}
		for _, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			table.insert(keys, canonicalKey)
		end
		return keys
	end

	local function enumerateValidationResultAliasCaseKeys(): { string }
		local keys = {}
		for _, aliasKey in ipairs(VALIDATION_RESULT_ALIAS_CASE_ORDER) do
			table.insert(keys, aliasKey)
		end
		return keys
	end

	local function enumerateValidationResultCanonicalCaseEntries(): { any }
		local entries = {}
		for _, canonicalKey in ipairs(enumerateValidationResultCanonicalCaseKeys()) do
			table.insert(entries, {
				key = canonicalKey,
				metadata = getValidationResultCaseMetadata(canonicalKey),
				builder = getValidationResultCaseBuilder(canonicalKey),
			})
		end
		return entries
	end

	local function enumerateValidationResultAliasCaseEntries(): { any }
		return {
			{ aliasKey = "a0", canonicalKey = "accepted_no_penalty" },
			{ aliasKey = "a1", canonicalKey = "accepted_with_penalty" },
			{ aliasKey = "r1", canonicalKey = "rejected_with_penalty" },
			{ aliasKey = "r0", canonicalKey = "rejected_no_penalty" },
		}
	end

	local function captureValidationResultCaseRoundtrip(caseKey: string): any
		local canonicalKey = resolveValidationResultCaseKey(caseKey)
		local metadata = getValidationResultCaseMetadata(caseKey)
		local builder = getValidationResultCaseBuilder(caseKey)
		local result = builder()
		return {
			inputKey = caseKey,
			canonicalKey = canonicalKey,
			metadata = metadata,
			builder = builder,
			result = result,
		}
	end

	local function assertValidationResultCaseRoundtrip(caseKey: string, label: string)
		local roundtrip = captureValidationResultCaseRoundtrip(caseKey)
		local canonicalKey = roundtrip.canonicalKey
		local canonicalMetadata = getValidationResultCaseMetadata(canonicalKey)
		local canonicalBuilder = getValidationResultCaseBuilder(canonicalKey)
		local canonicalResult = canonicalBuilder()

		assertEqual(
			resolveValidationResultCaseKey(canonicalKey),
			canonicalKey,
			label .. " canonical resolves to itself"
		)
		assertEqual(roundtrip.metadata.keys.canonical, canonicalKey, label .. " metadata canonical key")
		assertEqual(
			roundtrip.metadata.keys.canonical,
			canonicalMetadata.keys.canonical,
			label .. " metadata equivalent"
		)
		assertEqual(
			roundtrip.metadata.mode.expectedAccepted,
			canonicalMetadata.mode.expectedAccepted,
			label .. " metadata accepted equivalent"
		)
		assertEqual(
			roundtrip.metadata.mode.expectRejects,
			canonicalMetadata.mode.expectRejects,
			label .. " metadata rejects equivalent"
		)
		assertEqual(
			roundtrip.metadata.mode.expectPenalties,
			canonicalMetadata.mode.expectPenalties,
			label .. " metadata penalties equivalent"
		)
		assertTrue(type(roundtrip.builder) == "function", label .. " builder type")
		assertEqual(roundtrip.builder, canonicalBuilder, label .. " builder equivalent")
		assertValidationResultContract(
			roundtrip.result,
			canonicalMetadata.mode.expectedAccepted,
			canonicalMetadata.mode.expectRejects,
			canonicalMetadata.mode.expectPenalties,
			label .. " contract"
		)
		assertEqual(roundtrip.result.accepted, canonicalResult.accepted, label .. " result accepted equivalent")
		assertEqual(
			#roundtrip.result.rejectReasons,
			#canonicalResult.rejectReasons,
			label .. " result rejects equivalent"
		)
		assertEqual(
			roundtrip.result.devaluation.totalPenalty,
			canonicalResult.devaluation.totalPenalty,
			label .. " result total equivalent"
		)
		assertEqual(
			#roundtrip.result.devaluation.penalties,
			#canonicalResult.devaluation.penalties,
			label .. " result penalties equivalent"
		)
	end

	local function captureValidationResultCaseMissingKeyFailure(caseKey: string): any
		local resolvedKey = resolveValidationResultCaseKey(caseKey)
		local metadataOk, metadataResult = pcall(function()
			return getValidationResultCaseMetadata(caseKey)
		end)
		local builderOk, builderResult = pcall(function()
			return getValidationResultCaseBuilder(caseKey)
		end)
		return {
			inputKey = caseKey,
			resolvedKey = resolvedKey,
			metadataOk = metadataOk,
			metadataResult = metadataResult,
			builderOk = builderOk,
			builderResult = builderResult,
		}
	end

	local function assertValidationResultCaseMissingKeyFailure(caseKey: string, label: string)
		local failure = captureValidationResultCaseMissingKeyFailure(caseKey)
		assertEqual(failure.resolvedKey, caseKey, label .. " resolved key echoes input")
		assertFalse(failure.metadataOk, label .. " metadata should fail")
		assertFalse(failure.builderOk, label .. " builder should fail")
		assertTrue(
			type(failure.metadataResult) == "string"
				and string.find(failure.metadataResult, "assertTrue failed [case metadata ", 1, true) ~= nil,
			label .. " metadata error contract"
		)
		assertTrue(
			type(failure.builderResult) == "string"
				and string.find(failure.builderResult, "assertTrue failed [example registry entry ", 1, true) ~= nil,
			label .. " builder error contract"
		)
	end

	local function assertValidationResultCaseRegistryUniqueness(label: string)
		local canonicalKeys = enumerateValidationResultCanonicalCaseKeys()
		local aliasKeys = enumerateValidationResultAliasCaseKeys()
		local canonicalKeySet: { [string]: boolean } = {}
		local aliasKeySet: { [string]: boolean } = {}

		for _, canonicalKey in ipairs(canonicalKeys) do
			assertFalse(canonicalKeySet[canonicalKey] == true, label .. " duplicate canonical key " .. canonicalKey)
			canonicalKeySet[canonicalKey] = true
		end

		for _, aliasKey in ipairs(aliasKeys) do
			assertFalse(aliasKeySet[aliasKey] == true, label .. " duplicate alias key " .. aliasKey)
			assertFalse(canonicalKeySet[aliasKey] == true, label .. " alias collides with canonical key " .. aliasKey)
			aliasKeySet[aliasKey] = true
		end

		assertEqual(#canonicalKeys, 4, label .. " canonical key count")
		assertEqual(#aliasKeys, 4, label .. " alias key count")
		assertEqual(table.find(canonicalKeys, "a0") == nil, true, label .. " alias absent from canonical order")
		assertEqual(table.find(canonicalKeys, "r0") == nil, true, label .. " alias absent from canonical order")
		assertEqual(
			table.find(aliasKeys, "accepted_no_penalty") == nil,
			true,
			label .. " canonical absent from alias order"
		)
		assertEqual(
			table.find(aliasKeys, "rejected_no_penalty") == nil,
			true,
			label .. " canonical absent from alias order"
		)
	end

	local resultContractRegressionGrid: { any }

	local function assertValidationResultCaseBuilderCoverage(label: string)
		local canonicalKeys = enumerateValidationResultCanonicalCaseKeys()
		local coveredCanonicalByGrid: { [string]: boolean } = {}
		local coveredCanonicalCount = 0

		for _, canonicalKey in ipairs(canonicalKeys) do
			local metadata = getValidationResultCaseMetadata(canonicalKey)
			local builder = getValidationResultCaseBuilder(canonicalKey)
			assertEqual(metadata.keys.canonical, canonicalKey, label .. " canonical metadata " .. canonicalKey)
			assertTrue(type(builder) == "function", label .. " canonical builder " .. canonicalKey)
		end

		for _, gridCase in ipairs(resultContractRegressionGrid) do
			local resolvedCanonicalKey = resolveValidationResultCaseKey(gridCase.key)
			assertTrue(
				type(validationResultCaseMetadata[resolvedCanonicalKey]) == "table",
				label .. " grid metadata " .. gridCase.key
			)
			assertTrue(
				type(validationResultExampleRegistry[resolvedCanonicalKey]) == "function",
				label .. " grid builder " .. gridCase.key
			)
			if coveredCanonicalByGrid[resolvedCanonicalKey] ~= true then
				coveredCanonicalByGrid[resolvedCanonicalKey] = true
				coveredCanonicalCount += 1
			end
		end

		for _, canonicalKey in ipairs(canonicalKeys) do
			assertTrue(coveredCanonicalByGrid[canonicalKey] == true, label .. " grid coverage " .. canonicalKey)
		end

		assertEqual(coveredCanonicalCount, #canonicalKeys, label .. " grid canonical coverage count")
	end

	local function assertValidationResultCaseMetadataRequiredFields(canonicalKey: string, label: string)
		local rawMetadata = validationResultCaseMetadata[canonicalKey]
		assertTrue(type(rawMetadata) == "table", label .. " raw metadata " .. canonicalKey)
		assertTrue(rawMetadata.keys ~= nil, label .. " required keys " .. canonicalKey)
		assertTrue(rawMetadata.keys.canonical ~= nil, label .. " required keys.canonical " .. canonicalKey)
		assertTrue(rawMetadata.keys.aliases ~= nil, label .. " required keys.aliases " .. canonicalKey)
		assertTrue(rawMetadata.mode ~= nil, label .. " required mode " .. canonicalKey)
		assertTrue(
			rawMetadata.mode.expectedAccepted ~= nil,
			label .. " required mode.expectedAccepted " .. canonicalKey
		)
		assertTrue(rawMetadata.mode.expectRejects ~= nil, label .. " required mode.expectRejects " .. canonicalKey)
		assertTrue(
			rawMetadata.mode.expectPenalties ~= nil,
			label .. " required mode.expectPenalties " .. canonicalKey
		)
		assertTrue(rawMetadata.devaluation ~= nil, label .. " required devaluation " .. canonicalKey)
		assertTrue(
			rawMetadata.devaluation.expectedTotalPenalty ~= nil,
			label .. " required devaluation.expectedTotalPenalty " .. canonicalKey
		)
		assertTrue(
			rawMetadata.devaluation.expectedFirstCategoryTotal ~= nil,
			label .. " required devaluation.expectedFirstCategoryTotal " .. canonicalKey
		)

		local resolvedMetadata = getValidationResultCaseMetadata(canonicalKey)
		assertTrue(
			resolvedMetadata == rawMetadata,
			label .. " all required fields are explicit (no metadata defaults) " .. canonicalKey
		)
	end

	local function assertValidationResultCaseMetadataShape(canonicalKey: string, label: string)
		local metadata = getValidationResultCaseMetadata(canonicalKey)
		assertValidationResultCaseMetadataRequiredFields(canonicalKey, label)
		assertTrue(type(metadata.keys) == "table", label .. " keys " .. canonicalKey)
		assertEqual(metadata.keys.canonical, canonicalKey, label .. " keys canonical " .. canonicalKey)
		assertTrue(type(metadata.keys.aliases) == "table", label .. " keys aliases " .. canonicalKey)
		assertTrue(type(metadata.mode) == "table", label .. " mode " .. canonicalKey)
		assertTrue(
			type(metadata.mode.expectedAccepted) == "boolean",
			label .. " mode expectedAccepted " .. canonicalKey
		)
		assertTrue(type(metadata.mode.expectRejects) == "boolean", label .. " mode expectRejects " .. canonicalKey)
		assertTrue(type(metadata.mode.expectPenalties) == "boolean", label .. " mode expectPenalties " .. canonicalKey)
		assertTrue(type(metadata.devaluation) == "table", label .. " devaluation " .. canonicalKey)
		assertTrue(
			type(metadata.devaluation.expectedTotalPenalty) == "number",
			label .. " devaluation expectedTotalPenalty " .. canonicalKey
		)
		assertTrue(
			type(metadata.devaluation.expectedFirstCategoryTotal) == "number",
			label .. " devaluation expectedFirstCategoryTotal " .. canonicalKey
		)
	end

	local function assertValidationResultCaseRegistryRequiredFieldDefaultsContract(label: string)
		for _, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			assertValidationResultCaseMetadataRequiredFields(canonicalKey, label)
		end
	end

	local function assertValidationResultCaseRegistryShapeContract(label: string)
		for _, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			assertValidationResultCaseMetadataShape(canonicalKey, label)
		end

		local canonicalEntries = enumerateValidationResultCanonicalCaseEntries()
		assertEqual(#canonicalEntries, #VALIDATION_RESULT_CANONICAL_CASE_ORDER, label .. " entry count")
		for index, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			local entry = canonicalEntries[index]
			assertEqual(entry.key, canonicalKey, label .. " entry key " .. tostring(index))
			assertTrue(type(entry.metadata) == "table", label .. " entry metadata " .. canonicalKey)
			assertTrue(type(entry.builder) == "function", label .. " entry builder " .. canonicalKey)
			assertEqual(
				entry.metadata.keys.canonical,
				canonicalKey,
				label .. " entry metadata canonical " .. canonicalKey
			)
		end
	end

	local function assertValidationResultCaseSingleSourceContract(label: string)
		local canonicalKeys = enumerateValidationResultCanonicalCaseKeys()
		local aliasKeys = enumerateValidationResultAliasCaseKeys()
		local coveredAliasKeys: { [string]: boolean } = {}
		local coveredCanonicalByGrid: { [string]: boolean } = {}

		assertEqual(#canonicalKeys, #VALIDATION_RESULT_CANONICAL_CASE_ORDER, label .. " canonical order count")
		assertEqual(#aliasKeys, #VALIDATION_RESULT_ALIAS_CASE_ORDER, label .. " alias order count")

		for index, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			assertEqual(canonicalKeys[index], canonicalKey, label .. " canonical source order " .. tostring(index))
			local metadata = getValidationResultCaseMetadata(canonicalKey)
			local builder = getValidationResultCaseBuilder(canonicalKey)
			assertEqual(metadata.keys.canonical, canonicalKey, label .. " canonical metadata " .. canonicalKey)
			assertTrue(type(builder) == "function", label .. " canonical builder " .. canonicalKey)
			for _, aliasKey in ipairs(metadata.keys.aliases) do
				assertEqual(
					resolveValidationResultCaseKey(aliasKey),
					canonicalKey,
					label .. " alias source " .. aliasKey
				)
				assertEqual(validationResultExampleAliases[aliasKey], canonicalKey, label .. " alias map " .. aliasKey)
				coveredAliasKeys[aliasKey] = true
			end
		end

		for index, aliasKey in ipairs(VALIDATION_RESULT_ALIAS_CASE_ORDER) do
			assertEqual(aliasKeys[index], aliasKey, label .. " alias source order " .. tostring(index))
			assertTrue(coveredAliasKeys[aliasKey] == true, label .. " alias live " .. aliasKey)
		end

		assertValidationResultCaseBuilderCoverage(label .. " builder coverage")

		for _, gridCase in ipairs(resultContractRegressionGrid) do
			local canonicalKey = resolveValidationResultCaseKey(gridCase.key)
			assertTrue(
				validationResultCaseMetadata[canonicalKey] ~= nil,
				label .. " grid metadata live " .. gridCase.key
			)
			assertTrue(
				validationResultExampleRegistry[canonicalKey] ~= nil,
				label .. " grid builder live " .. gridCase.key
			)
			coveredCanonicalByGrid[canonicalKey] = true
		end

		for _, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			assertTrue(coveredCanonicalByGrid[canonicalKey] == true, label .. " grid coverage " .. canonicalKey)
		end
	end

	local function assertValidationResultCaseRegistryConsistency(label: string)
		for _, entry in ipairs(enumerateValidationResultCanonicalCaseEntries()) do
			assertEqual(entry.metadata.keys.canonical, entry.key, label .. " canonical metadata " .. entry.key)
			assertTrue(type(entry.builder) == "function", label .. " canonical builder " .. entry.key)
		end
		for _, pair in ipairs(enumerateValidationResultAliasCaseEntries()) do
			local aliasKey = pair.aliasKey
			local canonicalKey = pair.canonicalKey
			assertEqual(
				resolveValidationResultCaseKey(aliasKey),
				canonicalKey,
				label .. " alias resolution " .. aliasKey
			)
			local aliasMetadata = getValidationResultCaseMetadata(aliasKey)
			local canonicalMetadata = getValidationResultCaseMetadata(canonicalKey)
			assertEqual(
				aliasMetadata.keys.canonical,
				canonicalMetadata.keys.canonical,
				label .. " metadata canonical " .. aliasKey
			)
			assertEqual(
				aliasMetadata.mode.expectedAccepted,
				canonicalMetadata.mode.expectedAccepted,
				label .. " metadata accepted " .. aliasKey
			)
			assertEqual(
				aliasMetadata.mode.expectRejects,
				canonicalMetadata.mode.expectRejects,
				label .. " metadata rejects " .. aliasKey
			)
			assertEqual(
				aliasMetadata.mode.expectPenalties,
				canonicalMetadata.mode.expectPenalties,
				label .. " metadata penalties " .. aliasKey
			)
			local aliasResult = makeValidationResultExample(aliasKey)
			local canonicalResult = makeValidationResultExample(canonicalKey)
			assertEqual(aliasResult.accepted, canonicalResult.accepted, label .. " result accepted " .. aliasKey)
			assertEqual(
				#aliasResult.rejectReasons,
				#canonicalResult.rejectReasons,
				label .. " result rejects " .. aliasKey
			)
			assertEqual(
				aliasResult.devaluation.totalPenalty,
				canonicalResult.devaluation.totalPenalty,
				label .. " result total " .. aliasKey
			)
			assertEqual(
				#aliasResult.devaluation.penalties,
				#canonicalResult.devaluation.penalties,
				label .. " result penalties " .. aliasKey
			)
		end
	end

	resultContractRegressionGrid = {
		{ key = "a0", label = "accepted/no-penalty" },
		{ key = "a1", label = "accepted/penalty" },
		{ key = "r1", label = "rejected/penalty" },
		{ key = "r0", label = "rejected/no-penalty" },
	}

	-- BLOCK 122: Slice 36 - validation result example registry exposes all major named modes.
	do
		assertTrue(
			type(validationResultExampleRegistry.accepted_no_penalty) == "function",
			"block122 accepted no penalty"
		)
		assertTrue(
			type(validationResultExampleRegistry.accepted_with_penalty) == "function",
			"block122 accepted penalty"
		)
		assertTrue(
			type(validationResultExampleRegistry.rejected_with_penalty) == "function",
			"block122 rejected penalty"
		)
		assertTrue(
			type(validationResultExampleRegistry.rejected_no_penalty) == "function",
			"block122 rejected no penalty"
		)
	end

	-- BLOCK 123: Slice 37 - validation result example aliases resolve to canonical entries.
	do
		assertEqual(validationResultExampleAliases.a0, "accepted_no_penalty", "block123 a0 alias")
		assertEqual(validationResultExampleAliases.a1, "accepted_with_penalty", "block123 a1 alias")
		assertEqual(validationResultExampleAliases.r1, "rejected_with_penalty", "block123 r1 alias")
		assertEqual(validationResultExampleAliases.r0, "rejected_no_penalty", "block123 r0 alias")
	end

	-- BLOCK 124: Slice 38 - validation result case metadata covers all named examples.
	do
		assertEqual(
			validationResultCaseMetadata.accepted_no_penalty.keys.canonical,
			"accepted_no_penalty",
			"block124 accepted no penalty"
		)
		assertEqual(
			validationResultCaseMetadata.accepted_with_penalty.keys.canonical,
			"accepted_with_penalty",
			"block124 accepted penalty"
		)
		assertEqual(
			validationResultCaseMetadata.rejected_with_penalty.keys.canonical,
			"rejected_with_penalty",
			"block124 rejected penalty"
		)
		assertEqual(
			validationResultCaseMetadata.rejected_no_penalty.keys.canonical,
			"rejected_no_penalty",
			"block124 rejected no penalty"
		)
		for _, canonicalKey in ipairs(enumerateValidationResultCanonicalCaseKeys()) do
			assertValidationResultCaseMetadataShape(canonicalKey, "block124")
		end
	end

	-- BLOCK 125: Slice 41 - case registry consistency guard covers metadata and builders.
	do
		assertValidationResultCaseRegistryConsistency("block125")
	end

	-- BLOCK 126: Slice 43 - case registry enumeration helpers honor explicit order contracts.
	do
		local canonicalKeysA = enumerateValidationResultCanonicalCaseKeys()
		local canonicalKeysB = enumerateValidationResultCanonicalCaseKeys()
		assertEqual(#canonicalKeysA, #VALIDATION_RESULT_CANONICAL_CASE_ORDER, "block126 canonical count")
		assertEqual(#canonicalKeysB, #VALIDATION_RESULT_CANONICAL_CASE_ORDER, "block126 canonical repeat count")
		for i, expectedKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			assertEqual(canonicalKeysA[i], expectedKey, "block126 canonical order A " .. tostring(i))
			assertEqual(canonicalKeysB[i], expectedKey, "block126 canonical order B " .. tostring(i))
		end
		local aliasKeysA = enumerateValidationResultAliasCaseKeys()
		local aliasKeysB = enumerateValidationResultAliasCaseKeys()
		assertEqual(#aliasKeysA, #VALIDATION_RESULT_ALIAS_CASE_ORDER, "block126 alias count")
		assertEqual(#aliasKeysB, #VALIDATION_RESULT_ALIAS_CASE_ORDER, "block126 alias repeat count")
		for i, expectedKey in ipairs(VALIDATION_RESULT_ALIAS_CASE_ORDER) do
			assertEqual(aliasKeysA[i], expectedKey, "block126 alias order A " .. tostring(i))
			assertEqual(aliasKeysB[i], expectedKey, "block126 alias order B " .. tostring(i))
		end
		local canonicalEntries = enumerateValidationResultCanonicalCaseEntries()
		assertEqual(#canonicalEntries, #VALIDATION_RESULT_CANONICAL_CASE_ORDER, "block126 entry count")
		for i, expectedKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			assertEqual(canonicalEntries[i].key, expectedKey, "block126 entry order " .. tostring(i))
		end
	end

	-- BLOCK 127: Slice 40 - case registry index resolves canonical and alias keys.
	do
		assertEqual(
			resolveValidationResultCaseKey("accepted_no_penalty"),
			"accepted_no_penalty",
			"block127 canonical accepted"
		)
		assertEqual(resolveValidationResultCaseKey("a0"), "accepted_no_penalty", "block127 alias accepted")
		assertEqual(resolveValidationResultCaseKey("r1"), "rejected_with_penalty", "block127 alias rejected")
		assertEqual(
			getValidationResultCaseMetadata("a0").keys.canonical,
			getValidationResultCaseMetadata("accepted_no_penalty").keys.canonical,
			"block127 accepted metadata equivalent"
		)
		assertEqual(
			getValidationResultCaseMetadata("r1").keys.canonical,
			getValidationResultCaseMetadata("rejected_with_penalty").keys.canonical,
			"block127 rejected metadata equivalent"
		)
		assertTrue(type(getValidationResultCaseBuilder("a0")) == "function", "block127 alias builder")
		assertTrue(
			type(getValidationResultCaseBuilder("accepted_no_penalty")) == "function",
			"block127 canonical builder"
		)
	end

	-- BLOCK 128: Slice 41 - case registry consistency guard remains stable across repeated runs.
	do
		assertValidationResultCaseRegistryConsistency("block128 A")
		assertValidationResultCaseRegistryConsistency("block128 B")
	end

	-- BLOCK 129: Slice 44 - case registry roundtrip helper covers canonical and alias keys.
	do
		for _, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			assertValidationResultCaseRoundtrip(canonicalKey, "block129 canonical " .. canonicalKey)
		end
		for _, aliasKey in ipairs(VALIDATION_RESULT_ALIAS_CASE_ORDER) do
			assertEqual(
				resolveValidationResultCaseKey(aliasKey),
				validationResultExampleAliases[aliasKey],
				"block129 alias canonical mapping " .. aliasKey
			)
			assertValidationResultCaseRoundtrip(aliasKey, "block129 alias " .. aliasKey)
		end
	end

	-- BLOCK 130: Slice 44 - roundtrip capture remains stable across repeated runs.
	do
		for _, canonicalKey in ipairs(VALIDATION_RESULT_CANONICAL_CASE_ORDER) do
			local outA = captureValidationResultCaseRoundtrip(canonicalKey)
			local outB = captureValidationResultCaseRoundtrip(canonicalKey)
			assertEqual(outA.canonicalKey, outB.canonicalKey, "block130 canonical key stable " .. canonicalKey)
			assertEqual(
				outA.metadata.keys.canonical,
				outB.metadata.keys.canonical,
				"block130 canonical metadata stable " .. canonicalKey
			)
			assertEqual(outA.builder, outB.builder, "block130 canonical builder stable " .. canonicalKey)
			assertEqual(
				outA.result.accepted,
				outB.result.accepted,
				"block130 canonical accepted stable " .. canonicalKey
			)
			assertEqual(
				#outA.result.rejectReasons,
				#outB.result.rejectReasons,
				"block130 canonical rejects stable " .. canonicalKey
			)
			assertEqual(
				outA.result.devaluation.totalPenalty,
				outB.result.devaluation.totalPenalty,
				"block130 canonical total stable " .. canonicalKey
			)
		end
		for _, aliasKey in ipairs(VALIDATION_RESULT_ALIAS_CASE_ORDER) do
			local outA = captureValidationResultCaseRoundtrip(aliasKey)
			local outB = captureValidationResultCaseRoundtrip(aliasKey)
			assertEqual(outA.canonicalKey, outB.canonicalKey, "block130 alias canonical stable " .. aliasKey)
			assertEqual(
				outA.metadata.keys.canonical,
				outB.metadata.keys.canonical,
				"block130 alias metadata stable " .. aliasKey
			)
			assertEqual(outA.builder, outB.builder, "block130 alias builder stable " .. aliasKey)
			assertEqual(outA.result.accepted, outB.result.accepted, "block130 alias accepted stable " .. aliasKey)
			assertEqual(
				#outA.result.rejectReasons,
				#outB.result.rejectReasons,
				"block130 alias rejects stable " .. aliasKey
			)
			assertEqual(
				outA.result.devaluation.totalPenalty,
				outB.result.devaluation.totalPenalty,
				"block130 alias total stable " .. aliasKey
			)
		end
	end

	-- BLOCK 131: Slice 45 - missing-key guard covers canonical, alias, and empty-string inputs.
	do
		for _, missingKey in ipairs({
			"missing_canonical_case",
			"z9",
			"",
		}) do
			assertValidationResultCaseMissingKeyFailure(missingKey, "block131 missing key " .. tostring(missingKey))
			assertValidationResultCaseMissingKeyFailure(
				missingKey,
				"block131 repeated missing key " .. tostring(missingKey)
			)
		end
	end

	-- BLOCK 132: Slice 46 - duplicate-key guard covers canonical uniqueness and alias collision assumptions.
	do
		assertValidationResultCaseRegistryUniqueness("block132 A")
		assertValidationResultCaseRegistryUniqueness("block132 B")
	end

	-- BLOCK 133: Slice 48 - single-source contract makes canonical order the explicit traversal driver.
	do
		assertValidationResultCaseSingleSourceContract("block133 A")
		assertValidationResultCaseSingleSourceContract("block133 B")
	end

	-- BLOCK 134: Slice 49 - registry shape contract guards canonical metadata entry structure.
	do
		assertValidationResultCaseRegistryShapeContract("block134 A")
		assertValidationResultCaseRegistryShapeContract("block134 B")
	end

	-- BLOCK 135: Slice 50 - registry required/default-field contract is explicit and stable.
	do
		assertValidationResultCaseRegistryRequiredFieldDefaultsContract("block135 A")
		assertValidationResultCaseRegistryRequiredFieldDefaultsContract("block135 B")
	end

	-- BLOCK 136: Slice 40 - metadata-backed validation result contract grid covers all major modes.
	do
		assertEqual(#resultContractRegressionGrid, 4, "block136 grid mode count")
		for i, gridCase in ipairs(resultContractRegressionGrid) do
			local metadata = getValidationResultCaseMetadata(gridCase.key)
			local result = makeValidationResultExample(gridCase.key)
			local label = "block136 " .. gridCase.label
			assertValidationResultContract(
				result,
				metadata.mode.expectedAccepted,
				metadata.mode.expectRejects,
				metadata.mode.expectPenalties,
				label
			)
			assertEqual(
				result.devaluation.totalPenalty,
				metadata.devaluation.expectedTotalPenalty,
				label .. " total penalty"
			)
			assertEqual(
				result.devaluation.categoryTotals[1].totalScore,
				metadata.devaluation.expectedFirstCategoryTotal,
				label .. " first category total"
			)
			assertEqual(i >= 1 and i <= 4, true, "block136 grid index " .. tostring(i))
		end
	end

	-- BLOCK 137: Slice 40 - metadata-backed validation result contract grid remains stable across repeated runs.
	do
		for _, gridCase in ipairs(resultContractRegressionGrid) do
			local metadata = getValidationResultCaseMetadata(gridCase.key)
			local outA = makeValidationResultExample(gridCase.key)
			local outB = makeValidationResultExample(gridCase.key)
			local label = "block137 " .. gridCase.label
			assertValidationResultContract(
				outA,
				metadata.mode.expectedAccepted,
				metadata.mode.expectRejects,
				metadata.mode.expectPenalties,
				label .. " A"
			)
			assertValidationResultContract(
				outB,
				metadata.mode.expectedAccepted,
				metadata.mode.expectRejects,
				metadata.mode.expectPenalties,
				label .. " B"
			)
			assertEqual(outA.accepted, outB.accepted, label .. " accepted stable")
			assertEqual(#outA.rejectReasons, #outB.rejectReasons, label .. " reject count stable")
			assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, label .. " total stable")
			assertEqual(#outA.devaluation.penalties, #outB.devaluation.penalties, label .. " penalty count stable")
			assertEqual(
				outA.devaluation.categoryTotals[1].totalScore,
				outB.devaluation.categoryTotals[1].totalScore,
				label .. " category stable"
			)
		end
	end

	-- BLOCK 138: Slice 31 - snapshot matrix helper remains stable across repeated runs.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			policy = {
				allowedEnvironmentClasses = { "indoor" },
				allowedTraversalDensityClasses = { "sparse" },
				disallowedRecurringStructureTags = { "entry_hub" },
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S31StableSnapshotMatrix",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertSnapshotMatrix(outA, "block138 snapshot A")
		assertSnapshotMatrix(outB, "block138 snapshot B")
		assertEqual(
			outA.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			outB.validationSnapshot.hardConfig.policy.allowedEnvironmentClasses[1],
			"block138 hard snapshot stable"
		)
		assertEqual(
			outA.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			outB.validationSnapshot.softConfig.criticalPointSoftRadii.tinyfolk_spawn,
			"block138 soft snapshot stable"
		)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block138 total stable")
	end

	-- BLOCK 139: Slice 32 - summary matrix helper remains stable across repeated runs.
	do
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S32StableSummaryMatrix",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, nil, softConfig)
		assertSummaryMatrix(outA, true, "block139 summaries A")
		assertSummaryMatrix(outB, true, "block139 summaries B")
		assertEqual(
			#outA.devaluation.categoryTotals,
			#outB.devaluation.categoryTotals,
			"block139 category count stable"
		)
		assertEqual(#outA.devaluation.groupSummaries, #outB.devaluation.groupSummaries, "block139 group count stable")
		assertEqual(
			#outA.devaluation.factorSummaries,
			#outB.devaluation.factorSummaries,
			"block139 factor count stable"
		)
		assertEqual(
			#outA.devaluation.subjectSummaries,
			#outB.devaluation.subjectSummaries,
			"block139 subject count stable"
		)
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block139 total stable")
	end

	-- BLOCK 140: Slice 33 - reason matrix helper remains stable across repeated runs.
	do
		local hardConfig: DistrictPlacementHardConfig = {
			criticalExclusion = {
				tinyfolkSpawnExclusionRadius = 20,
				escapeRouteExclusionRadius = 0,
				returnPointExclusionRadius = 0,
				stationExclusionRadius = 0,
				constructionSiteExclusionRadius = 0,
				captureZoneExclusionRadius = 0,
				controlZoneExclusionRadius = 0,
			},
		}
		local softConfig: DistrictPlacementSoftConfig = {
			criticalPointSoftRadius = 40,
			routeEdgeSoftRadius = 0,
		}
		local request: DistrictPlacementRequest = {
			districtId = "D_S33StableReasonMatrix",
			proposedOccupiedSpace = {
				{ tag = "body", worldCenter = { x = 5, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertReasonMatrix(outA, true, true, "block140 reasons A")
		assertReasonMatrix(outB, true, true, "block140 reasons B")
		assertEqual(#outA.rejectReasons, #outB.rejectReasons, "block140 reason count stable")
		for i, reasonA in ipairs(outA.rejectReasons) do
			local reasonB = outB.rejectReasons[i]
			assertEqual(reasonA.code, reasonB.code, "block140 reason code stable " .. tostring(i))
			assertEqual(reasonA.message, reasonB.message, "block140 reason message stable " .. tostring(i))
		end
		assertEqual(outA.devaluation.totalPenalty, outB.devaluation.totalPenalty, "block140 devaluation stable")
	end

	print("realm_district_placement: all checks passed")
end

run()
