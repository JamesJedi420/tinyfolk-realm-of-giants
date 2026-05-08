--!strict

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
		}
	end

	-- BLOCK 21: Prototype assembly output exposes resolvedOccupiedSpace and resolvedOccupiedSpaceByPlacement.
	do
		local out = RealmChunkAssemblySchema.BuildAssemblyOutput(RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput())
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
		local out = RealmChunkAssemblySchema.BuildAssemblyOutput(
			makeOccupiedSpaceProbeInput(0, { x = 100, y = 20, z = -40 })
		)
		local box = out.resolvedOccupiedSpace[1]
		assertVector3Equal(box.worldCenter, { x = 110, y = 20, z = -35 }, "block22 worldCenter")
		assertVector3Equal(box.halfExtents, { x = 8, y = 3, z = 4 }, "block22 halfExtents unchanged")
		assertEqual(box.tag, "body", "block22 tag preserved")
	end

	-- BLOCK 23: 90-degree turn (1) rotates center and swaps x/z half-extents.
	do
		local out = RealmChunkAssemblySchema.BuildAssemblyOutput(
			makeOccupiedSpaceProbeInput(1, { x = 100, y = 20, z = -40 })
		)
		local box = out.resolvedOccupiedSpace[1]
		-- rotate(10,0,5) at 1 turn → (-5,0,10); worldCenter = (95,20,-30)
		assertVector3Equal(box.worldCenter, { x = 95, y = 20, z = -30 }, "block23 worldCenter")
		-- halfExtents x/z swapped: (8,3,4) → (4,3,8)
		assertVector3Equal(box.halfExtents, { x = 4, y = 3, z = 8 }, "block23 halfExtents swapped")
	end

	-- BLOCK 24: 180-degree turn (2) rotates center; halfExtents unchanged (symmetric swap).
	do
		local out = RealmChunkAssemblySchema.BuildAssemblyOutput(
			makeOccupiedSpaceProbeInput(2, { x = 100, y = 20, z = -40 })
		)
		local box = out.resolvedOccupiedSpace[1]
		-- rotate(10,0,5) at 2 turns → (-10,0,-5); worldCenter = (90,20,-45)
		assertVector3Equal(box.worldCenter, { x = 90, y = 20, z = -45 }, "block24 worldCenter")
		-- halfExtents unchanged at 180°
		assertVector3Equal(box.halfExtents, { x = 8, y = 3, z = 4 }, "block24 halfExtents unchanged")
	end

	-- BLOCK 25: 270-degree turn (3) rotates center and swaps x/z half-extents.
	do
		local out = RealmChunkAssemblySchema.BuildAssemblyOutput(
			makeOccupiedSpaceProbeInput(3, { x = 100, y = 20, z = -40 })
		)
		local box = out.resolvedOccupiedSpace[1]
		-- rotate(10,0,5) at 3 turns → (5,0,-10); worldCenter = (105,20,-50)
		assertVector3Equal(box.worldCenter, { x = 105, y = 20, z = -50 }, "block25 worldCenter")
		-- halfExtents x/z swapped: (8,3,4) → (4,3,8)
		assertVector3Equal(box.halfExtents, { x = 4, y = 3, z = 8 }, "block25 halfExtents swapped")
	end

	-- BLOCK 26: Repeated runs produce identical resolved occupied space ordering.
	do
		local outA = RealmChunkAssemblySchema.BuildAssemblyOutput(
			RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		)
		local outB = RealmChunkAssemblySchema.BuildAssemblyOutput(
			RealmAssemblyPrototypeFixture.GetPrototypeAssemblyInput()
		)
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

	print("realm_chunk_assembly_schema: all checks passed")
end

run()
