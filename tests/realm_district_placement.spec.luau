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
	result: DistrictPlacementResult,
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
		local separated = RealmDistrictPlacementValidator.ValidatePlacement(request, protoOutput, hardConfig, softConfig)
		assertEqual(separated.accepted, legacy.accepted, "block58 accepted equivalent")
		assertEqual(#separated.rejectReasons, #legacy.rejectReasons, "block58 reject count equivalent")
		for i, reason in ipairs(separated.rejectReasons) do
			assertEqual(reason.code, legacy.rejectReasons[i].code, "block58 reject code " .. tostring(i))
		end
		assertEqual(separated.devaluation.totalPenalty, legacy.devaluation.totalPenalty, "block58 total penalty")
		assertEqual(#separated.devaluation.penalties, #legacy.devaluation.penalties, "block58 penalty count")
		for i, category in ipairs(separated.devaluation.categoryTotals) do
			assertEqual(category.category, legacy.devaluation.categoryTotals[i].category, "block58 category " .. tostring(i))
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
			assertEqual(category.category, legacy.devaluation.categoryTotals[i].category, "block68 category " .. tostring(i))
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
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, makeRoutePressureOutput(), nil, softConfig)
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
				{ tag = "near_escape", worldCenter = { x = 100, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block70 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block70 spawn-only penalty score")
		assertEqual(#result.devaluation.penalties, 1, "block70 one spawn penalty")
		assertEqual(result.devaluation.penalties[1].nearCriticalPointCategory, "tinyfolk_spawn", "block70 spawn category")
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
				{ tag = "near_escape", worldCenter = { x = 100, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local result =
			RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		assertTrue(result.accepted, "block71 accepted")
		assertEqual(result.devaluation.totalPenalty, 1, "block71 escape-only penalty score")
		assertEqual(#result.devaluation.penalties, 1, "block71 one escape penalty")
		assertEqual(result.devaluation.penalties[1].nearCriticalPointCategory, "escape_route", "block71 escape category")
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
				{ tag = "near_escape", worldCenter = { x = 100, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
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
				{ tag = "near_escape", worldCenter = { x = 100, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
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
				{ tag = "near_escape", worldCenter = { x = 100, y = 0, z = -60 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, makeCriticalCategoryOutput(), nil, softConfig)
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
				{ tag = "moderate_touch", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
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
				{ tag = "moderate_touch", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
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
				{ tag = "moderate_touch", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
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
				{ tag = "moderate_touch", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
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
				{ tag = "moderate_touch", worldCenter = { x = 0, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
				{ tag = "dense_touch", worldCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 1, y = 1, z = 1 } },
			},
		}
		local outA = RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
		local outB = RealmDistrictPlacementValidator.ValidatePlacement(request, makeDensityCategoryOutput(), nil, softConfig)
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
			assertTrue(type(penalty.sortKey) == "string" and #penalty.sortKey > 0, "block87 sort key exists " .. tostring(i))
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
			assertEqual(summary.totalScore, result.devaluation.categoryTotals[i].totalScore, "block89 totals match " .. tostring(i))
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
			assertEqual(tostring(summaryA.firstSortKey), tostring(summaryB.firstSortKey), "block90 first key stable " .. tostring(i))
			assertEqual(tostring(summaryA.lastSortKey), tostring(summaryB.lastSortKey), "block90 last key stable " .. tostring(i))
		end
	end

	print("realm_district_placement: all checks passed")
end

run()
