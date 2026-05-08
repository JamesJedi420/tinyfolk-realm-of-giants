--!strict

local RealmChunkAssemblySchema = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmChunkAssemblySchema")
local RealmAssemblyPrototypeFixture = require("../src/ReplicatedStorage/Shared/RealmAssembly/RealmAssemblyPrototypeFixture")
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

	print("realm_chunk_assembly_schema: all checks passed")
end

run()
