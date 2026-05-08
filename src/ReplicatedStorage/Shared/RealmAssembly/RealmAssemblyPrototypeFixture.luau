--!strict

local RealmChunkAssemblySchema = require("./RealmChunkAssemblySchema")

local Fixture = {}

function Fixture.GetPrototypeAssemblyInput(): RealmChunkAssemblySchema.AssemblyInput
	local startChunk: RealmChunkAssemblySchema.AuthoredChunk = {
		chunkId = "Chunk_Start",
		chunkKind = "start",
		authoringVersion = 1,
		tags = { "TinyfolkSpawnArea", "GiantSpawnArea" },
		sockets = {
			{
				socketId = "east_path",
				localPosition = { x = 60, y = 0, z = 0 },
				localForward = { x = 1, y = 0, z = 0 },
				compatibility = {
					connectionClass = "route_main",
					socketRole = "male",
					lane = "main",
					elevationTier = 0,
				},
				tags = { "PrimaryRoute" },
			},
		},
		occupiedSpace = {
			{ tag = "main", localCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 60, y = 4, z = 40 } },
		},
		content = {
			spawns = {
				{ name = "TinyfolkSpawn", position = { x = 0, y = 0, z = 0 } },
				{ name = "GiantSpawn", position = { x = 20, y = 0, z = 0 } },
			},
			escapeRoutes = {},
			returnPoints = {
				{ name = "TinyfolkReturnPoint", position = { x = -20, y = 0, z = 0 } },
			},
			stations = {
				{ name = "WorkStation_A", position = { x = 25, y = 0, z = 0 } },
			},
			constructionSites = {
				{ name = "ConstructionSite_A", position = { x = 15, y = 0, z = 10 } },
			},
			upgradeBoards = {
				{ name = "GiantUpgradeBoard_A", position = { x = 30, y = 0, z = 0 } },
			},
			controlZones = {},
			captureZones = {
				{
					name = "GiantCaptureZone_A",
					position = { x = 40, y = 0, z = 20 },
					radius = 10,
					tag = "GiantCapture",
				},
			},
			props = {
				{ name = "Cover_A", position = { x = 10, y = 0, z = -8 }, propType = "cover" },
			},
			routeGraph = {
				nodes = {
					{ name = "StartNode", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn" },
					{ name = "MidNode", position = { x = 60, y = 0, z = 0 }, nodeType = "waypoint" },
				},
				edges = {
					{ from = "StartNode", to = "MidNode", distance = 60 },
				},
			},
		},
	}

	local exitChunk: RealmChunkAssemblySchema.AuthoredChunk = {
		chunkId = "Chunk_Exit",
		chunkKind = "exit",
		authoringVersion = 1,
		tags = { "ExitArea" },
		sockets = {
			{
				socketId = "west_path",
				localPosition = { x = -60, y = 0, z = 0 },
				localForward = { x = -1, y = 0, z = 0 },
				compatibility = {
					connectionClass = "route_main",
					socketRole = "female",
					lane = "main",
					elevationTier = 0,
				},
				tags = { "PrimaryRoute" },
			},
		},
		occupiedSpace = {
			{ tag = "main", localCenter = { x = -30, y = 0, z = 0 }, halfExtents = { x = 60, y = 4, z = 40 } },
		},
		content = {
			spawns = {},
			escapeRoutes = {
				{ name = "EscapeRoute_A", position = { x = 0, y = 0, z = 0 } },
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
					{ name = "ExitNode", position = { x = 0, y = 0, z = 0 }, nodeType = "escape", tier = "primary" },
					{ name = "EntryNode", position = { x = -60, y = 0, z = 0 }, nodeType = "waypoint" },
				},
				edges = {
					{ from = "EntryNode", to = "ExitNode", distance = 60 },
				},
			},
		},
	}

	return {
		chunkLibrary = {
			[startChunk.chunkId] = startChunk,
			[exitChunk.chunkId] = exitChunk,
		},
		placements = {
			{
				placementId = "P_Start",
				chunkId = "Chunk_Start",
				transform = { position = { x = 0, y = 0, z = 0 }, yawQuarterTurns = 0 },
			},
			{
				placementId = "P_Exit",
				chunkId = "Chunk_Exit",
				transform = { position = { x = 120, y = 0, z = 0 }, yawQuarterTurns = 0 },
			},
		},
		declaredConnections = {
			{
				fromPlacementId = "P_Start",
				fromSocketId = "east_path",
				toPlacementId = "P_Exit",
				toSocketId = "west_path",
			},
		},
	}
end

function Fixture.GetMissingChunkAssemblyInput(): RealmChunkAssemblySchema.AssemblyInput
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Exit"] = nil
	return input
end

function Fixture.GetMissingSocketAssemblyInput(): RealmChunkAssemblySchema.AssemblyInput
	local input = Fixture.GetPrototypeAssemblyInput()
	input.declaredConnections[1].toSocketId = "missing_socket"
	return input
end

function Fixture.GetIncompatibleSocketAssemblyInput(): RealmChunkAssemblySchema.AssemblyInput
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Exit"].sockets[1].compatibility.connectionClass = "route_side"
	return input
end

function Fixture.GetDuplicateSocketUseAssemblyInput(): RealmChunkAssemblySchema.AssemblyInput
	local input = Fixture.GetPrototypeAssemblyInput()
	table.insert(input.declaredConnections, {
		fromPlacementId = "P_Start",
		fromSocketId = "east_path",
		toPlacementId = "P_Exit",
		toSocketId = "west_path",
	})
	return input
end

function Fixture.GetSelfConnectionAssemblyInput(allowSelfConnection: boolean?): RealmChunkAssemblySchema.AssemblyInput
	local input = Fixture.GetPrototypeAssemblyInput()
	table.insert(input.chunkLibrary["Chunk_Start"].sockets, {
		socketId = "west_path_self",
		localPosition = { x = -60, y = 0, z = 0 },
		localForward = { x = -1, y = 0, z = 0 },
		compatibility = {
			connectionClass = "route_main",
			socketRole = "female",
			lane = "main",
			elevationTier = 0,
		},
		tags = { "PrimaryRoute" },
	})
	input.declaredConnections = {
		{
			fromPlacementId = "P_Start",
			fromSocketId = "east_path",
			toPlacementId = "P_Start",
			toSocketId = "west_path_self",
			allowSelfConnection = allowSelfConnection,
		},
	}
	return input
end

return Fixture
