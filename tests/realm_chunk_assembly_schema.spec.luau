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

local function assertIssueCode(output, expectedCode, label)
	for _, issue in output.integrity.issues do
		if issue.code == expectedCode then
			return
		end
	end
	error("assertIssueCode failed [" .. label .. "]: missing code=" .. expectedCode)
end

local function run()
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

	print("realm_chunk_assembly_schema: all checks passed")
end

run()
