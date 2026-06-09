--!strict

local RealmMetadataRegistry = require("./RealmMetadataRegistry")
local RealmThemeFamilySchema = require("./RealmThemeFamilySchema")
local RealmChunkAssemblySchema = require("./RealmChunkAssemblySchema")

local Fixture: any = {}

local function hasString(values: { string }, expected: string): boolean
	for _, value in ipairs(values) do
		if value == expected then
			return true
		end
	end
	return false
end

local function applyMetadataToPrototypeInput(input: any, record: any, themeRecord: any): any
	local startChunk = input.chunkLibrary["Chunk_Start"]
	if startChunk ~= nil then
		if not hasString(startChunk.tags, record.realmTemplateId) then
			table.insert(startChunk.tags, record.realmTemplateId)
		end
		if not hasString(startChunk.tags, record.themeId) then
			table.insert(startChunk.tags, record.themeId)
		end
		if not hasString(startChunk.tags, "ThemeFamily:" .. themeRecord.themeId) then
			table.insert(startChunk.tags, "ThemeFamily:" .. themeRecord.themeId)
		end
		if startChunk.structuralMetadata ~= nil then
			startChunk.structuralMetadata.recurringStructureTags = table.clone(record.recurringStructureTags)
			startChunk.structuralMetadata.traversalDensityClass = record.traversalDensity
		end
	end

	local exitChunk = input.chunkLibrary["Chunk_Exit"]
	if exitChunk ~= nil then
		if not hasString(exitChunk.tags, record.realmTemplateId) then
			table.insert(exitChunk.tags, record.realmTemplateId)
		end
		if not hasString(exitChunk.tags, "ThemeFamily:" .. themeRecord.themeId) then
			table.insert(exitChunk.tags, "ThemeFamily:" .. themeRecord.themeId)
		end
		if exitChunk.structuralMetadata ~= nil then
			exitChunk.structuralMetadata.recurringStructureTags = table.clone(record.recurringStructureTags)
			exitChunk.structuralMetadata.traversalDensityClass = record.traversalDensity
		end
	end

	return input
end

function Fixture.GetPrototypeAssemblyInput(): any
	local startChunk: any = {
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
		routeTransitions = {
			{
				transitionId = "start_to_main",
				socketId = "east_path",
				transitionKind = "main",
				transitionRole = "exit",
				tags = { "PrimaryRoute", "SpawnToExit" },
			},
		},
		occupiedSpace = {
			{ tag = "main", localCenter = { x = 30, y = 0, z = 0 }, halfExtents = { x = 60, y = 4, z = 40 } },
		},
		structuralMetadata = {
			isLandmarkAnchor = true,
			landmarkAnchorId = "start_anchor",
			tileSizeClass = "large",
			recurringStructureTags = { "spawn_chamber", "entry_hub" },
			environmentClass = "outdoor",
			traversalDensityClass = "moderate",
		},
		validatorMetadata = {
			validatorProfileId = "prototype_chunk_start_v1",
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
				{ name = "Farm_A", position = { x = -95, y = 0, z = 70 } },
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
					{ name = "StartNode", position = { x = 0, y = 0, z = 0 }, nodeType = "spawn", tier = "primary" },
					{ name = "MidNode", position = { x = 60, y = 0, z = 0 }, nodeType = "waypoint", tier = "primary" },
				},
				edges = {
					{ from = "StartNode", to = "MidNode", distance = 60 },
				},
			},
		},
	}

	local exitChunk: any = {
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
		routeTransitions = {
			{
				transitionId = "main_to_exit",
				socketId = "west_path",
				transitionKind = "main",
				transitionRole = "entry",
				tags = { "PrimaryRoute", "ExitApproach" },
			},
		},
		occupiedSpace = {
			{ tag = "main", localCenter = { x = -30, y = 0, z = 0 }, halfExtents = { x = 60, y = 4, z = 40 } },
		},
		structuralMetadata = {
			isLandmarkAnchor = false,
			tileSizeClass = "medium",
			recurringStructureTags = { "exit_chamber" },
			environmentClass = "indoor",
			traversalDensityClass = "sparse",
		},
		validatorMetadata = {
			validatorProfileId = "prototype_chunk_exit_v1",
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
					{
						name = "EntryNode",
						position = { x = -60, y = 0, z = 0 },
						nodeType = "waypoint",
						tier = "primary",
					},
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
		validatorMetadata = {
			validatorProfileId = "prototype_realm_topology_v1",
		},
	}
end

function Fixture.GetMissingChunkAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Exit"] = nil
	return input
end

function Fixture.GetMissingSocketAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.declaredConnections[1].toSocketId = "missing_socket"
	return input
end

function Fixture.GetIncompatibleSocketAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Exit"].sockets[1].compatibility.connectionClass = "route_side"
	return input
end

function Fixture.GetMisalignedSocketAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.placements[2].transform.position.x += 0.01
	return input
end

function Fixture.GetMisorientedSocketAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Exit"].sockets[1].localForward = { x = 1, y = 0, z = 0 }
	return input
end

function Fixture.GetDisconnectedPlacementAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.placements[2].transform.position.x = 260
	input.declaredConnections = {}
	return input
end

function Fixture.GetDuplicateSocketUseAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	table.insert(input.declaredConnections, {
		fromPlacementId = "P_Start",
		fromSocketId = "east_path",
		toPlacementId = "P_Exit",
		toSocketId = "west_path",
	})
	return input
end

function Fixture.GetDuplicateRouteTransitionAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	table.insert(input.chunkLibrary["Chunk_Start"].routeTransitions, {
		transitionId = "start_to_main",
		socketId = "east_path",
		transitionKind = "side",
		transitionRole = "through",
		tags = { "SecondaryRoute" },
	})
	return input
end

function Fixture.GetMalformedRouteTransitionAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Start"].routeTransitions[1].transitionKind = "shortcut"
	return input
end

function Fixture.GetRouteTransitionDuplicateTagsAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Start"].routeTransitions[1].tags = { "PrimaryRoute", "PrimaryRoute" }
	return input
end

function Fixture.GetRouteTransitionMissingSocketAssemblyInput(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.chunkLibrary["Chunk_Start"].routeTransitions[1].socketId = "missing_socket"
	return input
end

function Fixture.GetSelfConnectionAssemblyInput(allowSelfConnection: boolean?): any
	local input = Fixture.GetPrototypeAssemblyInput()
	input.placements = { input.placements[1] }
	table.insert(input.chunkLibrary["Chunk_Start"].sockets, {
		socketId = "west_path_self",
		localPosition = { x = 60, y = 0, z = 0 },
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

function Fixture.GetAssemblyInputForTemplate(realmTemplateId: any, registry: any?): (any?, string?)
	local record, reason = RealmMetadataRegistry.GetRealmMetadataRecord(realmTemplateId, registry)
	if record == nil then
		return nil, reason or "realm_metadata_missing"
	end

	local themeRecord, themeReason = RealmThemeFamilySchema.GetThemeFamilyRecord(record.themeId)
	if themeRecord == nil then
		return nil, themeReason or "theme_family_missing"
	end

	local input = Fixture.GetPrototypeAssemblyInput()
	return applyMetadataToPrototypeInput(input, record, themeRecord), nil
end

function Fixture.SelectAssemblyInputFromMetadata(selectionInput: any?, registry: any?): (any, string)
	local candidates = RealmMetadataRegistry.SelectRealmCandidates(selectionInput, registry)
	if #candidates == 0 then
		return Fixture.GetPrototypeAssemblyInput(), "prototype_fallback"
	end

	local selected = candidates[1]
	local input, reason = Fixture.GetAssemblyInputForTemplate(selected.realmTemplateId, registry)
	if input == nil then
		return Fixture.GetPrototypeAssemblyInput(), reason or "prototype_fallback"
	end

	return input, selected.realmTemplateId
end

function Fixture.GetPrototypeAssembledRealmDescriptorHandoff(): any
	local input = Fixture.GetPrototypeAssemblyInput()
	local output = RealmChunkAssemblySchema.BuildAssemblyOutput(input)
	return {
		descriptor = RealmChunkAssemblySchema.ToRealmDescriptor(output),
		handoff = output.validatorHandoff,
	}
end

return Fixture
