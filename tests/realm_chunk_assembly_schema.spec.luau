--!nocheck
local RealmChunkAssemblySchema = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema")
local RealmAssemblyPrototypeFixture =
	require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture")
local RealmTopologyValidator = require("../src/ReplicatedStorage/Shared/RealmTopology/RealmTopologyValidator")

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

local function assertVector3Equal(actual, expected, label)
	assertEqual(actual.x, expected.x, label .. " x")
	assertEqual(actual.y, expected.y, label .. " y")
	assertEqual(actual.z, expected.z, label .. " z")
end

local function assertIssueCode(output, expectedCode, label)
	for _, issue in output.integrity.issues do
		if issue.code == expectedCode then
			return
		end
	end
	error("assertIssueCode failed [" .. label .. "]: missing code=" .. expectedCode)
end

local function run()
	local function makeRotationProbeInput(
		yawQuarterTurns: number,
		position: RealmChunkAssemblySchema.Vector3Data
	): RealmChunkAssemblySchema.AssemblyInput
		local chunk: RealmChunkAssemblySchema.AuthoredChunk = {
			chunkId = "Chunk_Rotate",
			chunkKind = "probe",
			authoringVersion = 1,
			tags = {},
			sockets = {
				{
					socketId = "probe_socket",
					localPosition = { x = 2, y = 3, z = 5 },
					localForward = { x = 1, y = 0, z = 0 },
					compatibility = {
						connectionClass = "route_probe",
						socketRole = "male",
					},
				},
			},
			validatorMetadata = {
				validatorProfileId = "probe_chunk_v1",
			},
			content = {
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
		}

		return {
			chunkLibrary = {
				[chunk.chunkId] = chunk,
			},
			placements = {
				{
					placementId = "P_Probe",
					chunkId = chunk.chunkId,
					transform = {
						position = position,
						yawQuarterTurns = yawQuarterTurns,
					},
				},
			},
			declaredConnections = {},
			validatorMetadata = {
				validatorProfileId = "probe_assembly_v1",
			},
		}
	end

	-- BLOCK 1: Chunk descriptors can be constructed deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		assertEqual(#input.placements, 2, "block1 placement count")
		assertTrue(input.chunkLibrary["Chunk_Start"] ~= nil, "block1 start chunk exists")
		assertTrue(input.chunkLibrary["Chunk_Exit"] ~= nil, "block1 exit chunk exists")
		assertEqual(input.chunkLibrary["Chunk_Start"].sockets[1].socketId, "east_path", "block1 socket id")
	end

	-- BLOCK 2: Compatible connection metadata is explicit and testable.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local a = input.chunkLibrary["Chunk_Start"].sockets[1].compatibility
		local b = input.chunkLibrary["Chunk_Exit"].sockets[1].compatibility
		local compatible, reason = RealmChunkAssemblySchema.AreSocketsCompatible(a, b)
		assertEqual(compatible, true, "block2 sockets compatible")
		assertEqual(reason, nil, "block2 compatible has nil reason")
	end

	-- BLOCK 3: Incompatible connection metadata is representable and testable.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local a = input.chunkLibrary["Chunk_Start"].sockets[1].compatibility
		local incompatibleB: RealmChunkAssemblySchema.ChunkSocketCompatibility = {
			connectionClass = "route_side",
			socketRole = "female",
			lane = "main",
			elevationTier = 0,
		}
		local compatible, reason = RealmChunkAssemblySchema.AreSocketsCompatible(a, incompatibleB)
		assertEqual(compatible, false, "block3 sockets incompatible")
		assertEqual(reason, "connectionClass mismatch", "block3 mismatch reason")
	end

	-- BLOCK 4: Assembled output maps into validator-ready realm descriptor shape.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		local descriptor = RealmChunkAssemblySchema.ToRealmDescriptor(output)

		assertEqual(#descriptor.spawns > 0, true, "block4 descriptor has spawns")
		assertEqual(#descriptor.escapeRoutes > 0, true, "block4 descriptor has escape routes")
		assertEqual(#descriptor.routeGraph.nodes > 0, true, "block4 descriptor has route graph nodes")
		assertEqual(#output.resolvedConnections, 1, "block4 resolved connection count")
		assertEqual(output.resolvedConnections[1].compatible, true, "block4 resolved connection compatibility")
	end

	-- BLOCK 5: Fixture path is stable and inspectable (deterministic output).
	do
		local inputA = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local inputB = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local outA = RealmChunkAssemblySchema.BuildAssemblyOutput(inputA)
		local outB = RealmChunkAssemblySchema.BuildAssemblyOutput(inputB)

		assertEqual(#outA.descriptor.spawns, #outB.descriptor.spawns, "block5 spawn count stable")
		assertEqual(#outA.descriptor.escapeRoutes, #outB.descriptor.escapeRoutes, "block5 escape count stable")
		assertEqual(
			outA.resolvedConnections[1].compatible,
			outB.resolvedConnections[1].compatible,
			"block5 connection compatibility stable"
		)
		assertEqual(outA.resolvedConnections[1].reason, outB.resolvedConnections[1].reason, "block5 reason stable")
	end

	-- BLOCK 6: Handoff into existing validation pipeline is usable.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		local descriptor = RealmChunkAssemblySchema.ToRealmDescriptor(output)

		local validationConfig: RealmTopologyValidator.RealmValidationConfig = {
			escapeTriggerRadiusStuds = 10,
			boardInteractionRangeStuds = 20,
			stationActivationRangeStuds = 16,
			constructionInteractionRangeStuds = 16,
			requiredSpecialistStationIds = {},
			constructionSiteIds = {},
		}

		local result = RealmTopologyValidator.ValidateRealm(descriptor, validationConfig)
		assertTrue(type(result.passed) == "boolean", "block6 validator returned result")
		assertTrue(#result.results > 0, "block6 validator produced checks")
	end

	-- BLOCK 7: Valid two-chunk connection stitches into stable graph output.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.integrity.passed, true, "block7 integrity pass")
		assertEqual(#output.stitchedGraph.edges, 1, "block7 stitched edge count")
		assertEqual(#output.stitchedGraph.adjacencyByPlacement["P_Start"], 1, "block7 start adjacency count")
		assertEqual(
			output.stitchedGraph.adjacencyByPlacement["P_Start"][1].neighborPlacementId,
			"P_Exit",
			"block7 adjacency neighbor"
		)
	end

	-- BLOCK 8: Missing chunk reference is reported deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetMissingChunkAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.integrity.passed, false, "block8 integrity fail")
		assertIssueCode(output, "missing_chunk_reference", "block8 missing chunk issue")
		assertIssueCode(output, "unstitchable_connection", "block8 unstitchable issue")
	end

	-- BLOCK 9: Missing socket reference is reported deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetMissingSocketAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.integrity.passed, false, "block9 integrity fail")
		assertIssueCode(output, "missing_socket_reference", "block9 missing socket issue")
		assertIssueCode(output, "unstitchable_connection", "block9 unstitchable issue")
	end

	-- BLOCK 10: Incompatible sockets are reported deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetIncompatibleSocketAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.integrity.passed, false, "block10 integrity fail")
		assertIssueCode(output, "incompatible_socket_connection", "block10 incompatible issue")
		assertIssueCode(output, "unstitchable_connection", "block10 unstitchable issue")
	end

	-- BLOCK 11: Duplicate socket use is reported deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetDuplicateSocketUseAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.integrity.passed, false, "block11 integrity fail")
		assertIssueCode(output, "duplicate_socket_use", "block11 duplicate socket issue")
		assertIssueCode(output, "unstitchable_connection", "block11 unstitchable issue")
	end

	-- BLOCK 12: Self-connection behavior is explicit and testable.
	do
		local disallowed = RealmAssemblyPrototypeFixture.GetSelfConnectionAssemblyInput(false)
		local outputA = RealmChunkAssemblySchema.BuildAssemblyOutput(disallowed)
		assertEqual(outputA.integrity.passed, false, "block12 disallowed self integrity fail")
		assertIssueCode(outputA, "self_connection_not_allowed", "block12 self disallowed issue")

		local allowed = RealmAssemblyPrototypeFixture.GetSelfConnectionAssemblyInput(true)
		local outputB = RealmChunkAssemblySchema.BuildAssemblyOutput(allowed)
		assertEqual(outputB.integrity.passed, true, "block12 allowed self integrity pass")
		assertEqual(#outputB.stitchedGraph.edges, 1, "block12 allowed self stitched edge")
	end

	-- BLOCK 13: Repeated runs produce identical stitched graph and integrity output.
	do
		local inputA = RealmAssemblyPrototypeFixture.GetDuplicateSocketUseAssemblyInput()
		local inputB = RealmAssemblyPrototypeFixture.GetDuplicateSocketUseAssemblyInput()
		local outA = RealmChunkAssemblySchema.BuildAssemblyOutput(inputA)
		local outB = RealmChunkAssemblySchema.BuildAssemblyOutput(inputB)
		assertEqual(#outA.stitchedGraph.edges, #outB.stitchedGraph.edges, "block13 stitched edge count stable")
		assertEqual(#outA.integrity.issues, #outB.integrity.issues, "block13 issue count stable")
		assertEqual(outA.integrity.issues[1].code, outB.integrity.issues[1].code, "block13 first issue code stable")
		assertEqual(
			outA.integrity.issues[1].message,
			outB.integrity.issues[1].message,
			"block13 first issue message stable"
		)
	end

	-- BLOCK 14: Validator handoff still works for a valid assembled output.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.integrity.passed, true, "block14 integrity pass")
		local descriptor = RealmChunkAssemblySchema.ToRealmDescriptor(output)
		local validationConfig: RealmTopologyValidator.RealmValidationConfig = {
			escapeTriggerRadiusStuds = 10,
			boardInteractionRangeStuds = 20,
			stationActivationRangeStuds = 16,
			constructionInteractionRangeStuds = 16,
			requiredSpecialistStationIds = {},
			constructionSiteIds = {},
		}
		local result = RealmTopologyValidator.ValidateRealm(descriptor, validationConfig)
		assertTrue(type(result.passed) == "boolean", "block14 validator returned result")
	end

	-- BLOCK 15: Identity transform resolves socket with translation only.
	do
		local input = makeRotationProbeInput(0, { x = 100, y = 20, z = -40 })
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(#output.resolvedWorldSockets, 1, "block15 resolved socket count")
		local socket = output.resolvedWorldSockets[1]
		assertVector3Equal(socket.worldPosition, { x = 102, y = 23, z = -35 }, "block15 world position")
		assertVector3Equal(socket.worldForward, { x = 1, y = 0, z = 0 }, "block15 world forward")
	end

	-- BLOCK 16: Quarter turn 90 resolves socket position and forward deterministically.
	do
		local input = makeRotationProbeInput(1, { x = 100, y = 20, z = -40 })
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		local socket = output.resolvedWorldSockets[1]
		assertVector3Equal(socket.worldPosition, { x = 95, y = 23, z = -38 }, "block16 world position")
		assertVector3Equal(socket.worldForward, { x = 0, y = 0, z = 1 }, "block16 world forward")
	end

	-- BLOCK 17: Quarter turn 180 resolves socket position and forward deterministically.
	do
		local input = makeRotationProbeInput(2, { x = 100, y = 20, z = -40 })
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		local socket = output.resolvedWorldSockets[1]
		assertVector3Equal(socket.worldPosition, { x = 98, y = 23, z = -45 }, "block17 world position")
		assertVector3Equal(socket.worldForward, { x = -1, y = 0, z = 0 }, "block17 world forward")
	end

	-- BLOCK 18: Quarter turn 270 resolves socket position and forward deterministically.
	do
		local input = makeRotationProbeInput(3, { x = 100, y = 20, z = -40 })
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		local socket = output.resolvedWorldSockets[1]
		assertVector3Equal(socket.worldPosition, { x = 105, y = 23, z = -42 }, "block18 world position")
		assertVector3Equal(socket.worldForward, { x = 0, y = 0, z = -1 }, "block18 world forward")
	end

	-- BLOCK 19: Stitched connection exposes resolved endpoint sockets deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		local connection = output.resolvedConnections[1]
		assertTrue(connection.fromWorldSocket ~= nil, "block19 from endpoint exists")
		assertTrue(connection.toWorldSocket ~= nil, "block19 to endpoint exists")
		assertEqual(connection.fromWorldSocket.socketId, "east_path", "block19 from socket id")
		assertEqual(connection.toWorldSocket.socketId, "west_path", "block19 to socket id")
		assertVector3Equal(connection.fromWorldSocket.worldPosition, { x = 60, y = 0, z = 0 }, "block19 from position")
		assertVector3Equal(connection.toWorldSocket.worldPosition, { x = 60, y = 0, z = 0 }, "block19 to position")
	end

	-- BLOCK 20: Repeated runs keep resolved world socket ordering deterministic.
	do
		local inputA = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local inputB = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local outA = RealmChunkAssemblySchema.BuildAssemblyOutput(inputA)
		local outB = RealmChunkAssemblySchema.BuildAssemblyOutput(inputB)
		assertEqual(#outA.resolvedWorldSockets, #outB.resolvedWorldSockets, "block20 socket count stable")
		for index, socketA in ipairs(outA.resolvedWorldSockets) do
			local socketB = outB.resolvedWorldSockets[index]
			assertEqual(socketA.placementId, socketB.placementId, "block20 placement stable " .. tostring(index))
			assertEqual(socketA.socketId, socketB.socketId, "block20 socket stable " .. tostring(index))
			assertVector3Equal(
				socketA.worldPosition,
				socketB.worldPosition,
				"block20 position stable " .. tostring(index)
			)
			assertVector3Equal(socketA.worldForward, socketB.worldForward, "block20 forward stable " .. tostring(index))
		end
	end

	-- Slice 4: chunk footprint / occupied-space contract
	-- Helper: single-placement input with one box, configurable yaw and position.
	local function makeOccupiedSpaceProbeInput(
		yawQuarterTurns: number,
		position: RealmChunkAssemblySchema.Vector3Data
	): RealmChunkAssemblySchema.AssemblyInput
		return {
			chunkLibrary = {
				Probe = {
					chunkId = "Probe",
					chunkKind = "probe",
					authoringVersion = 1,
					tags = {},
					sockets = {},
					occupiedSpace = {
						{
							tag = "body",
							localCenter = { x = 10, y = 0, z = 5 },
							halfExtents = { x = 8, y = 3, z = 4 },
						},
					},
					validatorMetadata = {
						validatorProfileId = "occupied_probe_chunk_v1",
					},
					content = {
						spawns = {},
						escapeRoutes = {},
						returnPoints = {},
						stations = {},
						constructionSites = {},
						upgradeBoards = {},
						controlZones = {},
						captureZones = {},
						props = {},
						routeGraph = { nodes = {}, edges = {} },
					},
				},
			},
			placements = {
				{
					placementId = "P_Probe",
					chunkId = "Probe",
					transform = { position = position, yawQuarterTurns = yawQuarterTurns },
				},
			},
			declaredConnections = {},
			validatorMetadata = {
				validatorProfileId = "occupied_probe_assembly_v1",
			},
		}
	end

	-- BLOCK 21: Prototype assembly output exposes resolvedOccupiedSpace and resolvedOccupiedSpaceByPlacement.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		assert(out.resolvedOccupiedSpace ~= nil, "block21 resolvedOccupiedSpace present")
		assert(out.resolvedOccupiedSpaceByPlacement ~= nil, "block21 resolvedOccupiedSpaceByPlacement present")
		-- Two placements, each with one box.
		assertEqual(#out.resolvedOccupiedSpace, 2, "block21 total box count")
		assertEqual(#out.resolvedOccupiedSpaceByPlacement["P_Start"], 1, "block21 P_Start box count")
		assertEqual(#out.resolvedOccupiedSpaceByPlacement["P_Exit"], 1, "block21 P_Exit box count")
		assertEqual(out.resolvedOccupiedSpace[1].placementId, "P_Start", "block21 first box from P_Start")
		assertEqual(out.resolvedOccupiedSpace[1].tag, "main", "block21 first box tag")
	end

	-- BLOCK 22: Identity placement (0 turns) resolves center by translation only; halfExtents unchanged.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(makeOccupiedSpaceProbeInput(0, { x = 100, y = 20, z = -40 }))
		local box = out.resolvedOccupiedSpace[1]
		assertVector3Equal(box.worldCenter, { x = 110, y = 20, z = -35 }, "block22 worldCenter")
		assertVector3Equal(box.halfExtents, { x = 8, y = 3, z = 4 }, "block22 halfExtents unchanged")
		assertEqual(box.tag, "body", "block22 tag preserved")
	end

	-- BLOCK 23: 90-degree turn (1) rotates center and swaps x/z half-extents.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(makeOccupiedSpaceProbeInput(1, { x = 100, y = 20, z = -40 }))
		local box = out.resolvedOccupiedSpace[1]
		-- rotate(10,0,5) at 1 turn → (-5,0,10); worldCenter = (95,20,-30)
		assertVector3Equal(box.worldCenter, { x = 95, y = 20, z = -30 }, "block23 worldCenter")
		-- halfExtents x/z swapped: (8,3,4) → (4,3,8)
		assertVector3Equal(box.halfExtents, { x = 4, y = 3, z = 8 }, "block23 halfExtents swapped")
	end

	-- BLOCK 24: 180-degree turn (2) rotates center; halfExtents unchanged (symmetric swap).
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(makeOccupiedSpaceProbeInput(2, { x = 100, y = 20, z = -40 }))
		local box = out.resolvedOccupiedSpace[1]
		-- rotate(10,0,5) at 2 turns → (-10,0,-5); worldCenter = (90,20,-45)
		assertVector3Equal(box.worldCenter, { x = 90, y = 20, z = -45 }, "block24 worldCenter")
		-- halfExtents unchanged at 180°
		assertVector3Equal(box.halfExtents, { x = 8, y = 3, z = 4 }, "block24 halfExtents unchanged")
	end

	-- BLOCK 25: 270-degree turn (3) rotates center and swaps x/z half-extents.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(makeOccupiedSpaceProbeInput(3, { x = 100, y = 20, z = -40 }))
		local box = out.resolvedOccupiedSpace[1]
		-- rotate(10,0,5) at 3 turns → (5,0,-10); worldCenter = (105,20,-50)
		assertVector3Equal(box.worldCenter, { x = 105, y = 20, z = -50 }, "block25 worldCenter")
		-- halfExtents x/z swapped: (8,3,4) → (4,3,8)
		assertVector3Equal(box.halfExtents, { x = 4, y = 3, z = 8 }, "block25 halfExtents swapped")
	end

	-- BLOCK 26: Repeated runs produce identical resolved occupied space ordering.
	do
		local outA =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		local outB =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		assertEqual(#outA.resolvedOccupiedSpace, #outB.resolvedOccupiedSpace, "block26 count stable")
		for index, boxA in ipairs(outA.resolvedOccupiedSpace) do
			local boxB = outB.resolvedOccupiedSpace[index]
			assertEqual(boxA.placementId, boxB.placementId, "block26 placementId stable " .. tostring(index))
			assertEqual(boxA.tag, boxB.tag, "block26 tag stable " .. tostring(index))
			assertVector3Equal(boxA.worldCenter, boxB.worldCenter, "block26 worldCenter stable " .. tostring(index))
			assertVector3Equal(boxA.halfExtents, boxB.halfExtents, "block26 halfExtents stable " .. tostring(index))
		end
	end

	-- BLOCK 27: Assembly with occupied space still hands off to validator via ToRealmDescriptor.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local out = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assert(out.integrity.passed, "block27 integrity passed with occupiedSpace present")
		local descriptor = RealmChunkAssemblySchema.ToRealmDescriptor(out)
		assert(descriptor ~= nil, "block27 descriptor produced")
		assert(descriptor.routeGraph ~= nil, "block27 descriptor routeGraph present")
	end

	-- Slice 5: landmark anchors and structural metadata contract

	-- BLOCK 28: Assembly output exposes resolvedMetadata and resolvedMetadataByPlacement.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		assert(out.resolvedMetadata ~= nil, "block28 resolvedMetadata present")
		assert(out.resolvedMetadataByPlacement ~= nil, "block28 resolvedMetadataByPlacement present")
		assertEqual(#out.resolvedMetadata, 2, "block28 two placement metadata entries")
		assert(out.resolvedMetadataByPlacement["P_Start"] ~= nil, "block28 P_Start metadata present")
		assert(out.resolvedMetadataByPlacement["P_Exit"] ~= nil, "block28 P_Exit metadata present")
	end

	-- BLOCK 29: Landmark anchor metadata is preserved through assembly output.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		local startMeta = out.resolvedMetadataByPlacement["P_Start"]
		assert(startMeta ~= nil, "block29 P_Start metadata present")
		assertEqual(startMeta.placementId, "P_Start", "block29 placementId")
		assertEqual(startMeta.chunkId, "Chunk_Start", "block29 chunkId")
		assertEqual(startMeta.isLandmarkAnchor, true, "block29 isLandmarkAnchor")
		assertEqual(startMeta.landmarkAnchorId, "start_anchor", "block29 landmarkAnchorId")
		local exitMeta = out.resolvedMetadataByPlacement["P_Exit"]
		assert(exitMeta ~= nil, "block29 P_Exit metadata present")
		assertEqual(exitMeta.isLandmarkAnchor, false, "block29 P_Exit not landmark")
		assert(exitMeta.landmarkAnchorId == nil, "block29 P_Exit no anchorId")
	end

	-- BLOCK 30: Tile-size class metadata is preserved through assembly output.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		local startMeta = out.resolvedMetadataByPlacement["P_Start"]
		local exitMeta = out.resolvedMetadataByPlacement["P_Exit"]
		assertEqual(startMeta.tileSizeClass, "large", "block30 P_Start tileSizeClass")
		assertEqual(exitMeta.tileSizeClass, "medium", "block30 P_Exit tileSizeClass")
	end

	-- BLOCK 31: Recurring-structure tags are preserved with stable ordering.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		local startMeta = out.resolvedMetadataByPlacement["P_Start"]
		assert(startMeta.recurringStructureTags ~= nil, "block31 recurringStructureTags present")
		assertEqual(#startMeta.recurringStructureTags, 2, "block31 tag count")
		assertEqual(startMeta.recurringStructureTags[1], "spawn_chamber", "block31 tag[1]")
		assertEqual(startMeta.recurringStructureTags[2], "entry_hub", "block31 tag[2]")
		local exitMeta = out.resolvedMetadataByPlacement["P_Exit"]
		assert(exitMeta.recurringStructureTags ~= nil, "block31 P_Exit recurringStructureTags present")
		assertEqual(exitMeta.recurringStructureTags[1], "exit_chamber", "block31 P_Exit tag[1]")
	end

	-- BLOCK 32: Indoor/outdoor and traversal-density metadata are preserved through assembly output.
	do
		local out =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		local startMeta = out.resolvedMetadataByPlacement["P_Start"]
		local exitMeta = out.resolvedMetadataByPlacement["P_Exit"]
		assertEqual(startMeta.environmentClass, "outdoor", "block32 P_Start environmentClass")
		assertEqual(startMeta.traversalDensityClass, "moderate", "block32 P_Start traversalDensityClass")
		assertEqual(exitMeta.environmentClass, "indoor", "block32 P_Exit environmentClass")
		assertEqual(exitMeta.traversalDensityClass, "sparse", "block32 P_Exit traversalDensityClass")
	end

	-- BLOCK 33: Repeated runs produce identical resolved metadata ordering and values.
	do
		local outA =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		local outB =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		assertEqual(#outA.resolvedMetadata, #outB.resolvedMetadata, "block33 count stable")
		for index, metaA in ipairs(outA.resolvedMetadata) do
			local metaB = outB.resolvedMetadata[index]
			assertEqual(metaA.placementId, metaB.placementId, "block33 placementId stable " .. tostring(index))
			assertEqual(metaA.chunkId, metaB.chunkId, "block33 chunkId stable " .. tostring(index))
			assertEqual(metaA.isLandmarkAnchor, metaB.isLandmarkAnchor, "block33 landmark stable " .. tostring(index))
			assertEqual(metaA.tileSizeClass, metaB.tileSizeClass, "block33 tileSize stable " .. tostring(index))
			assertEqual(metaA.environmentClass, metaB.environmentClass, "block33 env stable " .. tostring(index))
			assertEqual(
				metaA.traversalDensityClass,
				metaB.traversalDensityClass,
				"block33 density stable " .. tostring(index)
			)
		end
	end

	-- BLOCK 34: Assembly input contract accepts canonical prototype fixture input.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, true, "block34 input contract valid")
		assertEqual(reason, nil, "block34 valid reason nil")
	end

	-- BLOCK 35: Assembly input contract rejects duplicate placement ids deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		input.placements[2].placementId = input.placements[1].placementId
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block35 input contract invalid")
		assertEqual(reason, "assembly_input_placement_id_duplicate", "block35 duplicate reason")
	end

	-- BLOCK 36: Assembly input contract rejects missing placement chunk references.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		input.placements[1].chunkId = "MissingChunk"
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block36 input contract invalid")
		assertEqual(reason, "assembly_input_placement_chunk_missing", "block36 missing chunk reason")
	end

	-- BLOCK 37: Assembly input contract rejects non-integer yaw transform values.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		input.placements[1].transform.yawQuarterTurns = 0.5
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block37 input contract invalid")
		assertEqual(reason, "assembly_input_placement_transform_yaw_invalid", "block37 yaw reason")
	end

	-- BLOCK 38: Assembly input contract rejects duplicate socket ids per chunk.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		table.insert(
			input.chunkLibrary["Chunk_Start"].sockets,
			table.clone(input.chunkLibrary["Chunk_Start"].sockets[1])
		)
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block38 input contract invalid")
		assertEqual(reason, "assembly_input_chunk_socket_id_duplicate", "block38 duplicate socket reason")
	end

	-- BLOCK 39: Assembly input contract rejects malformed socket data.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		input.chunkLibrary["Chunk_Start"].sockets[1].localForward = { x = 1, y = 0, z = "bad" }
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block39 input contract invalid")
		assertEqual(reason, "assembly_input_chunk_socket_invalid", "block39 malformed socket reason")
	end

	-- BLOCK 40: Assembly input contract rejects malformed content arrays.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		input.chunkLibrary["Chunk_Start"].content.spawns = { { name = "", position = { x = 0, y = 0, z = 0 } } }
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block40 input contract invalid")
		assertEqual(reason, "assembly_input_chunk_content_arrays_invalid", "block40 malformed content reason")
	end

	-- BLOCK 41: Assembly input contract rejects duplicate local route node names.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		table.insert(input.chunkLibrary["Chunk_Start"].content.routeGraph.nodes, {
			name = "StartNode",
			position = { x = 10, y = 0, z = 10 },
			nodeType = "waypoint",
			tier = "primary",
		})
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block41 input contract invalid")
		assertEqual(reason, "assembly_input_chunk_route_node_name_duplicate", "block41 duplicate route node reason")
	end

	-- BLOCK 42: Assembly input contract rejects route edges that reference missing local nodes.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		input.chunkLibrary["Chunk_Start"].content.routeGraph.edges[1].to = "MissingNode"
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block42 input contract invalid")
		assertEqual(reason, "assembly_input_chunk_route_edge_node_missing", "block42 missing route edge node reason")
	end

	-- BLOCK 43: Assembly input contract rejects malformed occupiedSpace.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		input.chunkLibrary["Chunk_Start"].occupiedSpace[1].halfExtents.x = -1
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block43 input contract invalid")
		assertEqual(reason, "assembly_input_chunk_occupied_space_invalid", "block43 occupied space reason")
	end

	-- BLOCK 44: Assembly input contract rejects missing or invalid validator metadata.
	do
		local missing = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		missing.validatorMetadata = nil
		local missingValid, missingReason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(missing)
		assertEqual(missingValid, false, "block44 missing metadata invalid")
		assertEqual(missingReason, "assembly_input_validator_metadata_invalid", "block44 missing metadata reason")

		local invalid = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		invalid.validatorMetadata.validatorProfileId = ""
		local invalidValid, invalidReason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(invalid)
		assertEqual(invalidValid, false, "block44 invalid metadata invalid")
		assertEqual(invalidReason, "assembly_input_validator_metadata_invalid", "block44 invalid metadata reason")
	end

	-- BLOCK 45: Assembly input contract rejects missing or invalid chunk validator metadata.
	do
		local missing = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		missing.chunkLibrary["Chunk_Start"].validatorMetadata = nil
		local missingValid, missingReason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(missing)
		assertEqual(missingValid, false, "block45 missing chunk metadata invalid")
		assertEqual(
			missingReason,
			"assembly_input_chunk_validator_metadata_invalid",
			"block45 missing chunk metadata reason"
		)

		local invalid = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		invalid.chunkLibrary["Chunk_Start"].validatorMetadata.validatorProfileId = ""
		local invalidValid, invalidReason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(invalid)
		assertEqual(invalidValid, false, "block45 invalid chunk metadata invalid")
		assertEqual(
			invalidReason,
			"assembly_input_chunk_validator_metadata_invalid",
			"block45 invalid chunk metadata reason"
		)
	end

	-- BLOCK 46: Assembly input contract rejects invalid structural metadata enum fields.
	do
		local invalidTile = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		invalidTile.chunkLibrary["Chunk_Start"].structuralMetadata.tileSizeClass = "huge"
		local tileValid, tileReason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(invalidTile)
		assertEqual(tileValid, false, "block46 invalid tile enum invalid")
		assertEqual(tileReason, "assembly_input_chunk_structural_metadata_invalid", "block46 invalid tile enum reason")

		local invalidEnvironment = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		invalidEnvironment.chunkLibrary["Chunk_Start"].structuralMetadata.environmentClass = "cave"
		local environmentValid, environmentReason =
			RealmChunkAssemblySchema.ValidateAssemblyInputContract(invalidEnvironment)
		assertEqual(environmentValid, false, "block46 invalid env enum invalid")
		assertEqual(
			environmentReason,
			"assembly_input_chunk_structural_metadata_invalid",
			"block46 invalid env enum reason"
		)

		local invalidDensity = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		invalidDensity.chunkLibrary["Chunk_Start"].structuralMetadata.traversalDensityClass = "jammed"
		local densityValid, densityReason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(invalidDensity)
		assertEqual(densityValid, false, "block46 invalid density enum invalid")
		assertEqual(
			densityReason,
			"assembly_input_chunk_structural_metadata_invalid",
			"block46 invalid density enum reason"
		)
	end

	-- BLOCK 47: Validator handoff records descriptor readiness and validator profile id.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.validatorHandoff.descriptorReady, true, "block47 descriptor ready")
		assertEqual(
			output.validatorHandoff.validatorProfileId,
			"prototype_realm_topology_v1",
			"block47 validator profile"
		)
		assertEqual(#output.validatorHandoff.blockingAssemblyIssueCodes, 0, "block47 no blocking issues")
	end

	-- BLOCK 48: Validator handoff records blocking assembly issue codes deterministically.
	do
		local input = RealmAssemblyPrototypeFixture.GetDuplicateSocketUseAssemblyInput()
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
		assertEqual(output.validatorHandoff.descriptorReady, false, "block48 descriptor blocked")
		assertEqual(output.validatorHandoff.blockingAssemblyIssueCodes[1], "duplicate_socket_use", "block48 first code")
		assertEqual(
			output.validatorHandoff.blockingAssemblyIssueCodes[2],
			"unstitchable_connection",
			"block48 second code"
		)
	end

	-- BLOCK 49: Prototype fixture exposes explicit assembled descriptor/handoff path.
	do
		local assembled = RealmAssemblyPrototypeFixture.GetPrototypeAssembledRealmDescriptorHandoff()
		assertTrue(assembled.descriptor ~= nil, "block49 descriptor present")
		assertTrue(#assembled.descriptor.routeGraph.nodes > 0, "block49 descriptor route nodes present")
		assertEqual(assembled.handoff.descriptorReady, true, "block49 handoff ready")
		assertEqual(assembled.handoff.validatorProfileId, "prototype_realm_topology_v1", "block49 profile")
	end

	-- BLOCK 50: Misaligned socket positions block descriptor handoff inspectably.
	do
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(
			RealmAssemblyPrototypeFixture.GetMisalignedSocketAssemblyInput()
		)
		assertEqual(output.integrity.passed, false, "block50 integrity failed")
		assertIssueCode(output, "socket_position_mismatch", "block50 position mismatch issue")
		assertIssueCode(output, "unstitchable_connection", "block50 unstitchable issue")
		assertIssueCode(output, "disconnected_placement", "block50 disconnected issue")
		assertEqual(output.validatorHandoff.descriptorReady, false, "block50 descriptor blocked")
		assertEqual(
			output.validatorHandoff.blockingAssemblyIssueCodes[1],
			"socket_position_mismatch",
			"block50 first blocking code"
		)
	end

	-- BLOCK 51: Non-opposing socket forward vectors block descriptor handoff inspectably.
	do
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(
			RealmAssemblyPrototypeFixture.GetMisorientedSocketAssemblyInput()
		)
		assertEqual(output.integrity.passed, false, "block51 integrity failed")
		assertIssueCode(output, "socket_forward_mismatch", "block51 forward mismatch issue")
		assertIssueCode(output, "unstitchable_connection", "block51 unstitchable issue")
		assertEqual(output.validatorHandoff.descriptorReady, false, "block51 descriptor blocked")
		assertEqual(
			output.validatorHandoff.blockingAssemblyIssueCodes[1],
			"socket_forward_mismatch",
			"block51 first blocking code"
		)
	end

	-- BLOCK 52: Disconnected placements block descriptor handoff inspectably.
	do
		local output = RealmChunkAssemblySchema.BuildAssemblyOutput(
			RealmAssemblyPrototypeFixture.GetDisconnectedPlacementAssemblyInput()
		)
		assertEqual(output.integrity.passed, false, "block52 integrity failed")
		assertIssueCode(output, "disconnected_placement", "block52 disconnected issue")
		assertEqual(output.validatorHandoff.descriptorReady, false, "block52 descriptor blocked")
		assertEqual(
			output.validatorHandoff.blockingAssemblyIssueCodes[1],
			"disconnected_placement",
			"block52 first blocking code"
		)
	end

	-- BLOCK 53: Prototype route-transition metadata validates through the input contract.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, true, "block53 route transition contract valid")
		assertEqual(reason, nil, "block53 route transition reason nil")
		assertEqual(#input.chunkLibrary["Chunk_Start"].routeTransitions, 1, "block53 start transition count")
		assertEqual(
			input.chunkLibrary["Chunk_Start"].routeTransitions[1].transitionKind,
			"main",
			"block53 transition kind"
		)
	end

	-- BLOCK 54: Route-transition metadata is preserved in resolved output and validator handoff.
	do
		local output =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		assertEqual(#output.resolvedRouteTransitions, 2, "block54 resolved transition count")
		assertEqual(
			#output.resolvedRouteTransitionsByPlacement["P_Start"],
			1,
			"block54 start placement transition count"
		)
		local startTransition = output.resolvedRouteTransitionsByPlacement["P_Start"][1]
		assertEqual(startTransition.placementId, "P_Start", "block54 placement id")
		assertEqual(startTransition.chunkId, "Chunk_Start", "block54 chunk id")
		assertEqual(startTransition.transitionId, "start_to_main", "block54 transition id")
		assertEqual(startTransition.socketId, "east_path", "block54 socket id")
		assertEqual(startTransition.transitionRole, "exit", "block54 transition role")
		assertEqual(startTransition.tags[1], "PrimaryRoute", "block54 first tag")
		assertTrue(startTransition.worldSocket ~= nil, "block54 world socket present")
		assertEqual(startTransition.worldSocket.socketId, "east_path", "block54 world socket id")
		assertEqual(#output.validatorHandoff.routeTransitions, 2, "block54 handoff transition count")
		assertEqual(
			output.validatorHandoff.routeTransitionsByPlacement["P_Exit"][1].transitionId,
			"main_to_exit",
			"block54 handoff by placement"
		)
	end

	-- BLOCK 55: Repeated runs preserve route-transition metadata ordering deterministically.
	do
		local outA =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		local outB =
			RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
		assertEqual(#outA.resolvedRouteTransitions, #outB.resolvedRouteTransitions, "block55 transition count stable")
		for index, transitionA in ipairs(outA.resolvedRouteTransitions) do
			local transitionB = outB.resolvedRouteTransitions[index]
			assertEqual(
				transitionA.placementId,
				transitionB.placementId,
				"block55 placement stable " .. tostring(index)
			)
			assertEqual(
				transitionA.transitionId,
				transitionB.transitionId,
				"block55 transition id stable " .. tostring(index)
			)
			assertEqual(
				transitionA.transitionKind,
				transitionB.transitionKind,
				"block55 transition kind stable " .. tostring(index)
			)
			assertEqual(
				transitionA.transitionRole,
				transitionB.transitionRole,
				"block55 transition role stable " .. tostring(index)
			)
		end
	end

	-- BLOCK 56: Assembly input contract rejects duplicate route-transition ids per chunk.
	do
		local input = RealmAssemblyPrototypeFixture.GetDuplicateRouteTransitionAssemblyInput()
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block56 duplicate transition id invalid")
		assertEqual(
			reason,
			"assembly_input_chunk_route_transition_id_duplicate",
			"block56 duplicate transition id reason"
		)
	end

	-- BLOCK 57: Assembly input contract rejects invalid route-transition enum fields.
	do
		local input = RealmAssemblyPrototypeFixture.GetMalformedRouteTransitionAssemblyInput()
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block57 malformed transition invalid")
		assertEqual(reason, "assembly_input_chunk_route_transition_invalid", "block57 malformed transition reason")
	end

	-- BLOCK 58: Assembly input contract rejects duplicate route-transition tags.
	do
		local input = RealmAssemblyPrototypeFixture.GetRouteTransitionDuplicateTagsAssemblyInput()
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block58 duplicate transition tags invalid")
		assertEqual(reason, "assembly_input_chunk_route_transition_invalid", "block58 duplicate transition tags reason")
	end

	-- BLOCK 59: Assembly input contract rejects route transitions pointing at missing sockets.
	do
		local input = RealmAssemblyPrototypeFixture.GetRouteTransitionMissingSocketAssemblyInput()
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block59 missing transition socket invalid")
		assertEqual(reason, "assembly_input_chunk_route_transition_invalid", "block59 missing transition socket reason")
	end

	-- BLOCK 60: Assembly input contract rejects sparse route-transition arrays.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local transition = input.chunkLibrary["Chunk_Start"].routeTransitions[1]
		input.chunkLibrary["Chunk_Start"].routeTransitions = {
			[2] = transition,
		}
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block60 sparse route transitions invalid")
		assertEqual(reason, "assembly_input_chunk_route_transitions_invalid", "block60 sparse route transitions reason")
	end

	-- BLOCK 61: Assembly input contract rejects map-shaped route-transition tables.
	do
		local input = RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		local transition = input.chunkLibrary["Chunk_Start"].routeTransitions[1]
		input.chunkLibrary["Chunk_Start"].routeTransitions = {
			bogus = transition,
		}
		local valid, reason = RealmChunkAssemblySchema.ValidateAssemblyInputContract(input)
		assertEqual(valid, false, "block61 map route transitions invalid")
		assertEqual(reason, "assembly_input_chunk_route_transitions_invalid", "block61 map route transitions reason")
	end

	print("realm_chunk_assembly_schema: all checks passed")
end

run()
