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
		local cfg: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 50,
			stationExclusionRadius = 50,
			constructionSiteExclusionRadius = 50,
			captureZoneExclusionRadius = 50,
			controlZoneExclusionRadius = 50,
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local cfgFires: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local cfgSafe: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 40,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local cfg: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local cfgStation: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 50,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local cfgSite: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 50,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local reqSite: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local cfg: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local cfg: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 0,
			escapeRouteExclusionRadius = 0,
			returnPointExclusionRadius = 0,
			stationExclusionRadius = 0,
			constructionSiteExclusionRadius = 0,
			captureZoneExclusionRadius = 0,
			controlZoneExclusionRadius = 0,
		}
		-- Same box from block17 that would fire with radius=50.
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local cfg: RealmDistrictPlacementValidator.DistrictCriticalExclusionConfig = {
			tinyfolkSpawnExclusionRadius = 50,
			escapeRouteExclusionRadius = 50,
			returnPointExclusionRadius = 50,
			stationExclusionRadius = 50,
			constructionSiteExclusionRadius = 50,
			captureZoneExclusionRadius = 50,
			controlZoneExclusionRadius = 50,
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "outdoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = { "moderate" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "indoor" },
			allowedTraversalDensityClasses = { "sparse" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = { "outdoor" },
			allowedTraversalDensityClasses = {},
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = {},
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "entry_hub" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "exit_chamber" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "spawn_chamber" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "entry_hub" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "spawn_chamber", "exit_chamber" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "spawn_chamber", "entry_hub", "exit_chamber" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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
		local policyConfig: RealmDistrictPlacementValidator.DistrictPlacementPolicyConfig = {
			allowedEnvironmentClasses = {},
			allowedTraversalDensityClasses = {},
			disallowedRecurringStructureTags = { "exit_chamber" },
		}
		local request: RealmDistrictPlacementValidator.DistrictPlacementRequest = {
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

	print("realm_district_placement: all checks passed")
end

run()
