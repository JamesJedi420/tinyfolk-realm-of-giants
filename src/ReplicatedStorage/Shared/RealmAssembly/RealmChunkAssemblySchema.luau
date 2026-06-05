--!strict

local RealmTopologyValidator = require("../RealmTopology/RealmTopologyValidator")

local RealmChunkAssemblySchema = {}

export type Vector3Data = RealmTopologyValidator.Vector3Data
export type NamedPart = RealmTopologyValidator.NamedPart
export type NamedZone = RealmTopologyValidator.NamedZone
export type NamedProp = RealmTopologyValidator.NamedProp
export type NamedNode = RealmTopologyValidator.NamedNode
export type RouteEdge = RealmTopologyValidator.RouteEdge
export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor

export type SocketRole = "male" | "female"

export type ChunkValidatorMetadata = {
	validatorProfileId: string,
}

export type ChunkSocketCompatibility = {
	connectionClass: string,
	socketRole: SocketRole,
	lane: string?,
	elevationTier: number?,
}

export type ChunkSocket = {
	socketId: string,
	localPosition: Vector3Data,
	localForward: Vector3Data,
	compatibility: ChunkSocketCompatibility,
	allowMultipleConnections: boolean?,
	tags: { string }?,
}

export type ChunkLocalContent = {
	spawns: { NamedPart },
	escapeRoutes: { NamedPart },
	returnPoints: { NamedPart },
	stations: { NamedPart },
	constructionSites: { NamedPart },
	upgradeBoards: { NamedPart },
	controlZones: { NamedZone },
	captureZones: { NamedZone },
	props: { NamedProp },
	routeGraph: {
		nodes: { NamedNode },
		edges: { RouteEdge },
	},
}

export type ChunkOccupiedBox = {
	tag: string?,
	localCenter: Vector3Data,
	halfExtents: Vector3Data,
}

export type ChunkTileSizeClass = "small" | "medium" | "large" | "xlarge"
export type ChunkTraversalDensityClass = "open" | "sparse" | "moderate" | "dense"
export type ChunkEnvironmentClass = "indoor" | "outdoor" | "mixed"
export type ChunkRouteTransitionKind = "main" | "side" | "rescue" | "service"
export type ChunkRouteTransitionRole = "entry" | "exit" | "through"

export type ChunkRouteTransitionMetadata = {
	transitionId: string,
	socketId: string,
	transitionKind: ChunkRouteTransitionKind,
	transitionRole: ChunkRouteTransitionRole,
	tags: { string }?,
}

export type ChunkStructuralMetadata = {
	isLandmarkAnchor: boolean?,
	landmarkAnchorId: string?,
	tileSizeClass: ChunkTileSizeClass?,
	recurringStructureTags: { string }?,
	environmentClass: ChunkEnvironmentClass?,
	traversalDensityClass: ChunkTraversalDensityClass?,
}

export type AuthoredChunk = {
	chunkId: string,
	chunkKind: string,
	authoringVersion: number,
	tags: { string },
	sockets: { ChunkSocket },
	routeTransitions: { ChunkRouteTransitionMetadata }?,
	occupiedSpace: { ChunkOccupiedBox }?,
	structuralMetadata: ChunkStructuralMetadata?,
	validatorMetadata: ChunkValidatorMetadata,
	content: ChunkLocalContent,
}

export type AssemblyValidatorMetadata = {
	validatorProfileId: string,
}

export type ChunkTransform = {
	position: Vector3Data,
	yawQuarterTurns: number,
}

export type ChunkPlacement = {
	placementId: string,
	chunkId: string,
	transform: ChunkTransform,
}

export type DeclaredChunkConnection = {
	fromPlacementId: string,
	fromSocketId: string,
	toPlacementId: string,
	toSocketId: string,
	allowSelfConnection: boolean?,
}

export type AssemblyInput = {
	chunkLibrary: { [string]: AuthoredChunk },
	placements: { ChunkPlacement },
	declaredConnections: { DeclaredChunkConnection },
	validatorMetadata: AssemblyValidatorMetadata,
}

export type ResolvedWorldSocket = {
	placementId: string,
	chunkId: string,
	socketId: string,
	worldPosition: Vector3Data,
	worldForward: Vector3Data,
	compatibility: ChunkSocketCompatibility,
	allowMultipleConnections: boolean?,
	tags: { string }?,
}

export type ResolvedOccupiedBox = {
	placementId: string,
	chunkId: string,
	tag: string?,
	worldCenter: Vector3Data,
	halfExtents: Vector3Data,
}

export type ResolvedChunkMetadata = {
	placementId: string,
	chunkId: string,
	isLandmarkAnchor: boolean?,
	landmarkAnchorId: string?,
	tileSizeClass: ChunkTileSizeClass?,
	recurringStructureTags: { string }?,
	environmentClass: ChunkEnvironmentClass?,
	traversalDensityClass: ChunkTraversalDensityClass?,
}

export type ResolvedRouteTransitionMetadata = {
	placementId: string,
	chunkId: string,
	transitionId: string,
	socketId: string,
	transitionKind: ChunkRouteTransitionKind,
	transitionRole: ChunkRouteTransitionRole,
	tags: { string }?,
	worldSocket: ResolvedWorldSocket?,
}

export type ResolvedChunkConnection = {
	fromPlacementId: string,
	fromSocketId: string,
	toPlacementId: string,
	toSocketId: string,
	declaredConnectionIndex: number,
	stitched: boolean,
	compatible: boolean,
	fromWorldSocket: ResolvedWorldSocket?,
	toWorldSocket: ResolvedWorldSocket?,
	reason: string?,
}

export type StitchedConnectionEdge = {
	declaredConnectionIndex: number,
	fromPlacementId: string,
	fromSocketId: string,
	toPlacementId: string,
	toSocketId: string,
}

export type StitchedAdjacencyEntry = {
	declaredConnectionIndex: number,
	placementId: string,
	neighborPlacementId: string,
	viaSocketId: string,
	neighborSocketId: string,
}

export type AssemblyStitchedGraph = {
	edges: { StitchedConnectionEdge },
	adjacencyByPlacement: { [string]: { StitchedAdjacencyEntry } },
}

export type AssemblyIntegrityIssue = {
	code: string,
	message: string,
	declaredConnectionIndex: number?,
	fromPlacementId: string?,
	fromSocketId: string?,
	toPlacementId: string?,
	toSocketId: string?,
}

export type AssemblyIntegrityResult = {
	passed: boolean,
	issues: { AssemblyIntegrityIssue },
}

export type ValidatorHandoff = {
	descriptorReady: boolean,
	validatorProfileId: string,
	blockingAssemblyIssueCodes: { string },
	routeTransitions: { ResolvedRouteTransitionMetadata },
	routeTransitionsByPlacement: { [string]: { ResolvedRouteTransitionMetadata } },
}

export type AssemblyOutput = {
	descriptor: RealmDescriptor,
	placements: { ChunkPlacement },
	resolvedWorldSockets: { ResolvedWorldSocket },
	resolvedWorldSocketsByPlacement: { [string]: { ResolvedWorldSocket } },
	resolvedOccupiedSpace: { ResolvedOccupiedBox },
	resolvedOccupiedSpaceByPlacement: { [string]: { ResolvedOccupiedBox } },
	resolvedMetadata: { ResolvedChunkMetadata },
	resolvedMetadataByPlacement: { [string]: ResolvedChunkMetadata },
	resolvedRouteTransitions: { ResolvedRouteTransitionMetadata },
	resolvedRouteTransitionsByPlacement: { [string]: { ResolvedRouteTransitionMetadata } },
	resolvedConnections: { ResolvedChunkConnection },
	stitchedGraph: AssemblyStitchedGraph,
	integrity: AssemblyIntegrityResult,
	validatorHandoff: ValidatorHandoff,
}

local function normalizeYawQuarterTurns(turns: number): number
	local normalized = turns % 4
	if normalized < 0 then
		return normalized + 4
	end
	return normalized
end

local function rotateYawQuarterTurns(point: Vector3Data, turns: number): Vector3Data
	local normalizedTurns = normalizeYawQuarterTurns(turns)
	if normalizedTurns == 0 then
		return { x = point.x, y = point.y, z = point.z }
	elseif normalizedTurns == 1 then
		return { x = -point.z, y = point.y, z = point.x }
	elseif normalizedTurns == 2 then
		return { x = -point.x, y = point.y, z = -point.z }
	else
		return { x = point.z, y = point.y, z = -point.x }
	end
end

local function transformPoint(localPos: Vector3Data, transform: ChunkTransform): Vector3Data
	local rotated = rotateYawQuarterTurns(localPos, transform.yawQuarterTurns)
	return {
		x = rotated.x + transform.position.x,
		y = rotated.y + transform.position.y,
		z = rotated.z + transform.position.z,
	}
end

local function prefixName(placementId: string, localName: string): string
	return placementId .. "::" .. localName
end

local function appendTransformedPartList(
	outParts: { NamedPart },
	parts: { NamedPart },
	placementId: string,
	transform: ChunkTransform
)
	for _, part in parts do
		table.insert(outParts, {
			name = prefixName(placementId, part.name),
			position = transformPoint(part.position, transform),
		})
	end
end

local function appendTransformedZoneList(
	outZones: { NamedZone },
	zones: { NamedZone },
	placementId: string,
	transform: ChunkTransform
)
	for _, zone in zones do
		table.insert(outZones, {
			name = prefixName(placementId, zone.name),
			position = transformPoint(zone.position, transform),
			radius = zone.radius,
			tag = zone.tag,
		})
	end
end

local function appendTransformedPropList(
	outProps: { NamedProp },
	props: { NamedProp },
	placementId: string,
	transform: ChunkTransform
)
	for _, prop in props do
		table.insert(outProps, {
			name = prefixName(placementId, prop.name),
			position = transformPoint(prop.position, transform),
			propType = prop.propType,
		})
	end
end

local function appendTransformedRouteGraph(
	nodesOut: { NamedNode },
	edgesOut: { RouteEdge },
	graph: { nodes: { NamedNode }, edges: { RouteEdge } },
	placementId: string,
	transform: ChunkTransform
)
	for _, node in graph.nodes do
		table.insert(nodesOut, {
			name = prefixName(placementId, node.name),
			position = transformPoint(node.position, transform),
			nodeType = node.nodeType,
			tier = node.tier,
		})
	end
	for _, edge in graph.edges do
		table.insert(edgesOut, {
			from = prefixName(placementId, edge.from),
			to = prefixName(placementId, edge.to),
			distance = edge.distance,
		})
	end
end

local function getSocketById(chunk: AuthoredChunk, socketId: string): ChunkSocket?
	for _, socket in chunk.sockets do
		if socket.socketId == socketId then
			return socket
		end
	end
	return nil
end

function RealmChunkAssemblySchema.AreSocketsCompatible(
	a: ChunkSocketCompatibility,
	b: ChunkSocketCompatibility
): (boolean, string?)
	if a.connectionClass ~= b.connectionClass then
		return false, "connectionClass mismatch"
	end

	if a.socketRole == b.socketRole then
		return false, "socketRole mismatch"
	end

	if a.lane ~= nil and b.lane ~= nil and a.lane ~= b.lane then
		return false, "lane mismatch"
	end

	if a.elevationTier ~= nil and b.elevationTier ~= nil and a.elevationTier ~= b.elevationTier then
		return false, "elevationTier mismatch"
	end

	return true, nil
end

local function socketUsageKey(placementId: string, socketId: string): string
	return placementId .. "::" .. socketId
end

local function resolvedSocketKey(placementId: string, socketId: string): string
	return placementId .. "::" .. socketId
end

local function addIntegrityIssue(issues: { AssemblyIntegrityIssue }, issue: AssemblyIntegrityIssue)
	table.insert(issues, issue)
end

local SOCKET_ALIGNMENT_TOLERANCE = 0.001

local function collectBlockingIssueCodes(issues: { AssemblyIntegrityIssue }): { string }
	local codes: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, issue in ipairs(issues) do
		if not seen[issue.code] then
			seen[issue.code] = true
			table.insert(codes, issue.code)
		end
	end
	return codes
end

local function resolveWorldSocket(placement: ChunkPlacement, socket: ChunkSocket): ResolvedWorldSocket
	return {
		placementId = placement.placementId,
		chunkId = placement.chunkId,
		socketId = socket.socketId,
		worldPosition = transformPoint(socket.localPosition, placement.transform),
		worldForward = rotateYawQuarterTurns(socket.localForward, placement.transform.yawQuarterTurns),
		compatibility = socket.compatibility,
		allowMultipleConnections = socket.allowMultipleConnections,
		tags = socket.tags,
	}
end

local function resolveOccupiedBoxHalfExtents(halfExtents: Vector3Data, turns: number): Vector3Data
	local normalizedTurns = normalizeYawQuarterTurns(turns)
	if normalizedTurns == 1 or normalizedTurns == 3 then
		return { x = halfExtents.z, y = halfExtents.y, z = halfExtents.x }
	end
	return { x = halfExtents.x, y = halfExtents.y, z = halfExtents.z }
end

local function resolveOccupiedBox(placement: ChunkPlacement, box: ChunkOccupiedBox): ResolvedOccupiedBox
	return {
		placementId = placement.placementId,
		chunkId = placement.chunkId,
		tag = box.tag,
		worldCenter = transformPoint(box.localCenter, placement.transform),
		halfExtents = resolveOccupiedBoxHalfExtents(box.halfExtents, placement.transform.yawQuarterTurns),
	}
end

local function vectorDeltaWithinTolerance(a: Vector3Data, b: Vector3Data, tolerance: number): boolean
	return math.abs(a.x - b.x) <= tolerance and math.abs(a.y - b.y) <= tolerance and math.abs(a.z - b.z) <= tolerance
end

local function vectorsOpposeWithinTolerance(a: Vector3Data, b: Vector3Data, tolerance: number): boolean
	return math.abs(a.x + b.x) <= tolerance and math.abs(a.y + b.y) <= tolerance and math.abs(a.z + b.z) <= tolerance
end

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function isValidVector3Data(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if not isFiniteNumber(value.x) then
		return false
	end
	if not isFiniteNumber(value.y) then
		return false
	end
	if not isFiniteNumber(value.z) then
		return false
	end
	return true
end

local function isStringArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, item in ipairs(value) do
		if type(item) ~= "string" then
			return false
		end
	end
	return true
end

local function isStringArrayWithUniqueValues(value: any): boolean
	if not isStringArray(value) then
		return false
	end
	local seen: { [string]: boolean } = {}
	for _, item in ipairs(value) do
		if seen[item] then
			return false
		end
		seen[item] = true
	end
	return true
end

local function isDenseArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count += 1
	end
	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end
	return true
end

local function isValidOptionalBoolean(value: any): boolean
	return value == nil or type(value) == "boolean"
end

local function isValidOptionalString(value: any): boolean
	return value == nil or type(value) == "string"
end

local function isValidSocketCompatibility(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if not isNonEmptyString(value.connectionClass) then
		return false
	end
	if value.socketRole ~= "male" and value.socketRole ~= "female" then
		return false
	end
	if value.lane ~= nil and not isNonEmptyString(value.lane) then
		return false
	end
	if value.elevationTier ~= nil and (not isFiniteNumber(value.elevationTier) or value.elevationTier % 1 ~= 0) then
		return false
	end
	return true
end

local function isValidSocket(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if not isNonEmptyString(value.socketId) then
		return false
	end
	if not isValidVector3Data(value.localPosition) then
		return false
	end
	if not isValidVector3Data(value.localForward) then
		return false
	end
	if not isValidSocketCompatibility(value.compatibility) then
		return false
	end
	if not isValidOptionalBoolean(value.allowMultipleConnections) then
		return false
	end
	if value.tags ~= nil and not isStringArray(value.tags) then
		return false
	end
	return true
end

local function isValidNamedPart(value: any): boolean
	return type(value) == "table" and isNonEmptyString(value.name) and isValidVector3Data(value.position)
end

local function isValidNamedZone(value: any): boolean
	if not isValidNamedPart(value) then
		return false
	end
	if not isFiniteNumber(value.radius) or value.radius <= 0 then
		return false
	end
	return isValidOptionalString(value.tag)
end

local function isValidNamedProp(value: any): boolean
	if not isValidNamedPart(value) then
		return false
	end
	return isNonEmptyString(value.propType)
end

local function isValidPartArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, part in ipairs(value) do
		if not isValidNamedPart(part) then
			return false
		end
	end
	return true
end

local function isValidZoneArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, zone in ipairs(value) do
		if not isValidNamedZone(zone) then
			return false
		end
	end
	return true
end

local function isValidPropArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, prop in ipairs(value) do
		if not isValidNamedProp(prop) then
			return false
		end
	end
	return true
end

local function isValidRouteNode(value: any): boolean
	if not isValidNamedPart(value) then
		return false
	end
	if value.nodeType ~= nil and type(value.nodeType) ~= "string" then
		return false
	end
	if value.tier ~= nil and type(value.tier) ~= "string" then
		return false
	end
	return true
end

local function isValidRouteEdge(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if not isNonEmptyString(value.from) or not isNonEmptyString(value.to) then
		return false
	end
	if value.distance ~= nil and (not isFiniteNumber(value.distance) or value.distance < 0) then
		return false
	end
	return true
end

local function isValidOccupiedBox(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if value.tag ~= nil and type(value.tag) ~= "string" then
		return false
	end
	if not isValidVector3Data(value.localCenter) then
		return false
	end
	if not isValidVector3Data(value.halfExtents) then
		return false
	end
	return value.halfExtents.x >= 0 and value.halfExtents.y >= 0 and value.halfExtents.z >= 0
end

local function isValidValidatorMetadata(value: any): boolean
	return type(value) == "table" and isNonEmptyString(value.validatorProfileId)
end

local VALID_TILE_SIZE_CLASSES: { [string]: boolean } = {
	small = true,
	medium = true,
	large = true,
	xlarge = true,
}

local VALID_ENVIRONMENT_CLASSES: { [string]: boolean } = {
	indoor = true,
	outdoor = true,
	mixed = true,
}

local VALID_TRAVERSAL_DENSITY_CLASSES: { [string]: boolean } = {
	open = true,
	sparse = true,
	moderate = true,
	dense = true,
}

local VALID_ROUTE_TRANSITION_KINDS: { [string]: boolean } = {
	main = true,
	side = true,
	rescue = true,
	service = true,
}

local VALID_ROUTE_TRANSITION_ROLES: { [string]: boolean } = {
	entry = true,
	exit = true,
	through = true,
}

local function isValidOptionalEnum(value: any, allowed: { [string]: boolean }): boolean
	return value == nil or (type(value) == "string" and allowed[value] == true)
end

local function isValidStructuralMetadata(value: any): boolean
	if value == nil then
		return true
	end
	if type(value) ~= "table" then
		return false
	end
	if value.isLandmarkAnchor ~= nil and type(value.isLandmarkAnchor) ~= "boolean" then
		return false
	end
	if value.landmarkAnchorId ~= nil and not isNonEmptyString(value.landmarkAnchorId) then
		return false
	end
	if not isValidOptionalEnum(value.tileSizeClass, VALID_TILE_SIZE_CLASSES) then
		return false
	end
	if value.recurringStructureTags ~= nil and not isStringArray(value.recurringStructureTags) then
		return false
	end
	if not isValidOptionalEnum(value.environmentClass, VALID_ENVIRONMENT_CLASSES) then
		return false
	end
	if not isValidOptionalEnum(value.traversalDensityClass, VALID_TRAVERSAL_DENSITY_CLASSES) then
		return false
	end
	return true
end

local function isValidRouteTransitionMetadata(value: any, seenSocketIds: { [string]: boolean }): boolean
	if type(value) ~= "table" then
		return false
	end
	if not isNonEmptyString(value.transitionId) then
		return false
	end
	if not isNonEmptyString(value.socketId) or not seenSocketIds[value.socketId] then
		return false
	end
	if not isValidOptionalEnum(value.transitionKind, VALID_ROUTE_TRANSITION_KINDS) or value.transitionKind == nil then
		return false
	end
	if not isValidOptionalEnum(value.transitionRole, VALID_ROUTE_TRANSITION_ROLES) or value.transitionRole == nil then
		return false
	end
	if value.tags ~= nil and not isStringArrayWithUniqueValues(value.tags) then
		return false
	end
	return true
end

function RealmChunkAssemblySchema.ValidateAssemblyInputContract(input: any): (boolean, string?)
	if type(input) ~= "table" then
		return false, "assembly_input_invalid"
	end

	if type(input.chunkLibrary) ~= "table" then
		return false, "assembly_input_chunk_library_invalid"
	end
	if type(input.placements) ~= "table" then
		return false, "assembly_input_placements_invalid"
	end
	if type(input.declaredConnections) ~= "table" then
		return false, "assembly_input_declared_connections_invalid"
	end
	if not isValidValidatorMetadata(input.validatorMetadata) then
		return false, "assembly_input_validator_metadata_invalid"
	end

	local chunkCount = 0
	for chunkId, chunk in pairs(input.chunkLibrary) do
		chunkCount += 1
		if not isNonEmptyString(chunkId) then
			return false, "assembly_input_chunk_id_invalid"
		end
		if type(chunk) ~= "table" then
			return false, "assembly_input_chunk_record_invalid"
		end
		if not isNonEmptyString(chunk.chunkId) or chunk.chunkId ~= chunkId then
			return false, "assembly_input_chunk_record_chunk_id_invalid"
		end
		if not isNonEmptyString(chunk.chunkKind) then
			return false, "assembly_input_chunk_kind_invalid"
		end
		if
			type(chunk.authoringVersion) ~= "number"
			or chunk.authoringVersion < 1
			or chunk.authoringVersion % 1 ~= 0
		then
			return false, "assembly_input_chunk_authoring_version_invalid"
		end
		if type(chunk.tags) ~= "table" then
			return false, "assembly_input_chunk_tags_invalid"
		end
		if not isStringArray(chunk.tags) then
			return false, "assembly_input_chunk_tags_invalid"
		end
		if type(chunk.sockets) ~= "table" then
			return false, "assembly_input_chunk_sockets_invalid"
		end
		local seenSocketIds: { [string]: boolean } = {}
		for _, socket in ipairs(chunk.sockets) do
			if not isValidSocket(socket) then
				return false, "assembly_input_chunk_socket_invalid"
			end
			if seenSocketIds[socket.socketId] then
				return false, "assembly_input_chunk_socket_id_duplicate"
			end
			seenSocketIds[socket.socketId] = true
		end
		if chunk.routeTransitions ~= nil then
			if not isDenseArray(chunk.routeTransitions) then
				return false, "assembly_input_chunk_route_transitions_invalid"
			end
			local seenTransitionIds: { [string]: boolean } = {}
			for _, transition in ipairs(chunk.routeTransitions) do
				if not isValidRouteTransitionMetadata(transition, seenSocketIds) then
					return false, "assembly_input_chunk_route_transition_invalid"
				end
				if seenTransitionIds[transition.transitionId] then
					return false, "assembly_input_chunk_route_transition_id_duplicate"
				end
				seenTransitionIds[transition.transitionId] = true
			end
		end
		if chunk.occupiedSpace ~= nil then
			if type(chunk.occupiedSpace) ~= "table" then
				return false, "assembly_input_chunk_occupied_space_invalid"
			end
			for _, box in ipairs(chunk.occupiedSpace) do
				if not isValidOccupiedBox(box) then
					return false, "assembly_input_chunk_occupied_space_invalid"
				end
			end
		end
		if not isValidStructuralMetadata(chunk.structuralMetadata) then
			return false, "assembly_input_chunk_structural_metadata_invalid"
		end
		if not isValidValidatorMetadata(chunk.validatorMetadata) then
			return false, "assembly_input_chunk_validator_metadata_invalid"
		end
		if type(chunk.content) ~= "table" then
			return false, "assembly_input_chunk_content_invalid"
		end
		if
			not isValidPartArray(chunk.content.spawns)
			or not isValidPartArray(chunk.content.escapeRoutes)
			or not isValidPartArray(chunk.content.returnPoints)
			or not isValidPartArray(chunk.content.stations)
			or not isValidPartArray(chunk.content.constructionSites)
			or not isValidPartArray(chunk.content.upgradeBoards)
			or not isValidZoneArray(chunk.content.controlZones)
			or not isValidZoneArray(chunk.content.captureZones)
			or not isValidPropArray(chunk.content.props)
		then
			return false, "assembly_input_chunk_content_arrays_invalid"
		end
		if type(chunk.content.routeGraph) ~= "table" then
			return false, "assembly_input_chunk_route_graph_invalid"
		end
		if type(chunk.content.routeGraph.nodes) ~= "table" or type(chunk.content.routeGraph.edges) ~= "table" then
			return false, "assembly_input_chunk_route_graph_shape_invalid"
		end
		local seenNodeNames: { [string]: boolean } = {}
		for _, node in ipairs(chunk.content.routeGraph.nodes) do
			if not isValidRouteNode(node) then
				return false, "assembly_input_chunk_route_node_invalid"
			end
			if seenNodeNames[node.name] then
				return false, "assembly_input_chunk_route_node_name_duplicate"
			end
			seenNodeNames[node.name] = true
		end
		for _, edge in ipairs(chunk.content.routeGraph.edges) do
			if not isValidRouteEdge(edge) then
				return false, "assembly_input_chunk_route_edge_invalid"
			end
			if not seenNodeNames[edge.from] or not seenNodeNames[edge.to] then
				return false, "assembly_input_chunk_route_edge_node_missing"
			end
		end
	end
	if chunkCount < 1 then
		return false, "assembly_input_chunk_library_empty"
	end

	if #input.placements < 1 then
		return false, "assembly_input_placements_empty"
	end

	local seenPlacementIds: { [string]: boolean } = {}
	for _, placement in ipairs(input.placements) do
		if type(placement) ~= "table" then
			return false, "assembly_input_placement_record_invalid"
		end
		if not isNonEmptyString(placement.placementId) then
			return false, "assembly_input_placement_id_invalid"
		end
		if seenPlacementIds[placement.placementId] then
			return false, "assembly_input_placement_id_duplicate"
		end
		seenPlacementIds[placement.placementId] = true

		if not isNonEmptyString(placement.chunkId) then
			return false, "assembly_input_placement_chunk_id_invalid"
		end
		if input.chunkLibrary[placement.chunkId] == nil then
			return false, "assembly_input_placement_chunk_missing"
		end

		if type(placement.transform) ~= "table" then
			return false, "assembly_input_placement_transform_invalid"
		end
		if not isValidVector3Data(placement.transform.position) then
			return false, "assembly_input_placement_transform_position_invalid"
		end
		if not isFiniteNumber(placement.transform.yawQuarterTurns) or placement.transform.yawQuarterTurns % 1 ~= 0 then
			return false, "assembly_input_placement_transform_yaw_invalid"
		end
	end

	for _, connection in ipairs(input.declaredConnections) do
		if type(connection) ~= "table" then
			return false, "assembly_input_connection_record_invalid"
		end
		if not isNonEmptyString(connection.fromPlacementId) then
			return false, "assembly_input_connection_from_placement_invalid"
		end
		if not isNonEmptyString(connection.fromSocketId) then
			return false, "assembly_input_connection_from_socket_invalid"
		end
		if not isNonEmptyString(connection.toPlacementId) then
			return false, "assembly_input_connection_to_placement_invalid"
		end
		if not isNonEmptyString(connection.toSocketId) then
			return false, "assembly_input_connection_to_socket_invalid"
		end
	end

	return true, nil
end

function RealmChunkAssemblySchema.BuildAssemblyOutput(input: AssemblyInput): AssemblyOutput
	local placementById: { [string]: ChunkPlacement } = {}
	for _, placement in ipairs(input.placements) do
		placementById[placement.placementId] = placement
	end

	local descriptor: RealmDescriptor = {
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
	}
	local stitchedGraph: AssemblyStitchedGraph = {
		edges = {},
		adjacencyByPlacement = {},
	}
	local resolvedWorldSockets: { ResolvedWorldSocket } = {}
	local resolvedWorldSocketsByPlacement: { [string]: { ResolvedWorldSocket } } = {}
	local resolvedWorldSocketByPlacementSocketId: { [string]: ResolvedWorldSocket } = {}
	local resolvedOccupiedSpace: { ResolvedOccupiedBox } = {}
	local resolvedOccupiedSpaceByPlacement: { [string]: { ResolvedOccupiedBox } } = {}
	local resolvedMetadata: { ResolvedChunkMetadata } = {}
	local resolvedMetadataByPlacement: { [string]: ResolvedChunkMetadata } = {}
	local resolvedRouteTransitions: { ResolvedRouteTransitionMetadata } = {}
	local resolvedRouteTransitionsByPlacement: { [string]: { ResolvedRouteTransitionMetadata } } = {}
	for _, placement in ipairs(input.placements) do
		stitchedGraph.adjacencyByPlacement[placement.placementId] = {}
		resolvedWorldSocketsByPlacement[placement.placementId] = {}
		resolvedOccupiedSpaceByPlacement[placement.placementId] = {}
		resolvedRouteTransitionsByPlacement[placement.placementId] = {}
	end

	local integrityIssues: { AssemblyIntegrityIssue } = {}
	local socketUseCount: { [string]: number } = {}

	for _, placement in ipairs(input.placements) do
		local chunk = input.chunkLibrary[placement.chunkId]
		if chunk == nil then
			addIntegrityIssue(integrityIssues, {
				code = "missing_chunk_reference",
				message = "Placement '"
					.. placement.placementId
					.. "' references missing chunk '"
					.. placement.chunkId
					.. "'",
			})
			continue
		end

		for _, socket in ipairs(chunk.sockets) do
			local resolvedSocket = resolveWorldSocket(placement, socket)
			table.insert(resolvedWorldSockets, resolvedSocket)
			table.insert(resolvedWorldSocketsByPlacement[placement.placementId], resolvedSocket)
			resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(placement.placementId, socket.socketId)] =
				resolvedSocket
		end

		if chunk.routeTransitions ~= nil then
			for _, transition in ipairs(chunk.routeTransitions) do
				local resolvedTransition: ResolvedRouteTransitionMetadata = {
					placementId = placement.placementId,
					chunkId = placement.chunkId,
					transitionId = transition.transitionId,
					socketId = transition.socketId,
					transitionKind = transition.transitionKind,
					transitionRole = transition.transitionRole,
					tags = transition.tags,
					worldSocket = resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(
						placement.placementId,
						transition.socketId
					)],
				}
				table.insert(resolvedRouteTransitions, resolvedTransition)
				table.insert(resolvedRouteTransitionsByPlacement[placement.placementId], resolvedTransition)
			end
		end

		if chunk.occupiedSpace ~= nil then
			for _, box in ipairs(chunk.occupiedSpace) do
				local resolvedBox = resolveOccupiedBox(placement, box)
				table.insert(resolvedOccupiedSpace, resolvedBox)
				table.insert(resolvedOccupiedSpaceByPlacement[placement.placementId], resolvedBox)
			end
		end

		do
			local meta = chunk.structuralMetadata
			local resolved: ResolvedChunkMetadata = {
				placementId = placement.placementId,
				chunkId = placement.chunkId,
				isLandmarkAnchor = if meta ~= nil then meta.isLandmarkAnchor else nil,
				landmarkAnchorId = if meta ~= nil then meta.landmarkAnchorId else nil,
				tileSizeClass = if meta ~= nil then meta.tileSizeClass else nil,
				recurringStructureTags = if meta ~= nil then meta.recurringStructureTags else nil,
				environmentClass = if meta ~= nil then meta.environmentClass else nil,
				traversalDensityClass = if meta ~= nil then meta.traversalDensityClass else nil,
			}
			table.insert(resolvedMetadata, resolved)
			resolvedMetadataByPlacement[placement.placementId] = resolved
		end

		appendTransformedPartList(descriptor.spawns, chunk.content.spawns, placement.placementId, placement.transform)
		appendTransformedPartList(
			descriptor.escapeRoutes,
			chunk.content.escapeRoutes,
			placement.placementId,
			placement.transform
		)
		appendTransformedPartList(
			descriptor.returnPoints,
			chunk.content.returnPoints,
			placement.placementId,
			placement.transform
		)
		appendTransformedPartList(
			descriptor.stations,
			chunk.content.stations,
			placement.placementId,
			placement.transform
		)
		appendTransformedPartList(
			descriptor.constructionSites,
			chunk.content.constructionSites,
			placement.placementId,
			placement.transform
		)
		appendTransformedPartList(
			descriptor.upgradeBoards,
			chunk.content.upgradeBoards,
			placement.placementId,
			placement.transform
		)
		appendTransformedZoneList(
			descriptor.controlZones,
			chunk.content.controlZones,
			placement.placementId,
			placement.transform
		)
		appendTransformedZoneList(
			descriptor.captureZones,
			chunk.content.captureZones,
			placement.placementId,
			placement.transform
		)
		appendTransformedPropList(descriptor.props, chunk.content.props, placement.placementId, placement.transform)
		appendTransformedRouteGraph(
			descriptor.routeGraph.nodes,
			descriptor.routeGraph.edges,
			chunk.content.routeGraph,
			placement.placementId,
			placement.transform
		)
	end

	local resolvedConnections: { ResolvedChunkConnection } = {}
	for index, conn in ipairs(input.declaredConnections) do
		local issueCountBefore = #integrityIssues
		local fromPlacement = placementById[conn.fromPlacementId]
		local toPlacement = placementById[conn.toPlacementId]
		local fromChunk: AuthoredChunk? = nil
		local toChunk: AuthoredChunk? = nil
		local fromSocket: ChunkSocket? = nil
		local toSocket: ChunkSocket? = nil
		local compatibilityReason: string? = nil

		if fromPlacement == nil or toPlacement == nil then
			addIntegrityIssue(integrityIssues, {
				code = "missing_placement_reference",
				message = "Declared connection references missing placement",
				declaredConnectionIndex = index,
				fromPlacementId = conn.fromPlacementId,
				fromSocketId = conn.fromSocketId,
				toPlacementId = conn.toPlacementId,
				toSocketId = conn.toSocketId,
			})
		else
			fromChunk = input.chunkLibrary[fromPlacement.chunkId]
			toChunk = input.chunkLibrary[toPlacement.chunkId]
			if fromChunk == nil or toChunk == nil then
				addIntegrityIssue(integrityIssues, {
					code = "missing_chunk_reference",
					message = "Declared connection references placement with missing chunk",
					declaredConnectionIndex = index,
					fromPlacementId = conn.fromPlacementId,
					fromSocketId = conn.fromSocketId,
					toPlacementId = conn.toPlacementId,
					toSocketId = conn.toSocketId,
				})
			end
		end

		if fromPlacement ~= nil and toPlacement ~= nil and fromPlacement.placementId == toPlacement.placementId then
			if not conn.allowSelfConnection then
				addIntegrityIssue(integrityIssues, {
					code = "self_connection_not_allowed",
					message = "Declared self-connection is not explicitly allowed",
					declaredConnectionIndex = index,
					fromPlacementId = conn.fromPlacementId,
					fromSocketId = conn.fromSocketId,
					toPlacementId = conn.toPlacementId,
					toSocketId = conn.toSocketId,
				})
			end
		end

		if fromChunk ~= nil and toChunk ~= nil then
			fromSocket = getSocketById(fromChunk, conn.fromSocketId)
			toSocket = getSocketById(toChunk, conn.toSocketId)
			if fromSocket == nil or toSocket == nil then
				addIntegrityIssue(integrityIssues, {
					code = "missing_socket_reference",
					message = "Declared connection references missing socket",
					declaredConnectionIndex = index,
					fromPlacementId = conn.fromPlacementId,
					fromSocketId = conn.fromSocketId,
					toPlacementId = conn.toPlacementId,
					toSocketId = conn.toSocketId,
				})
			else
				local compatible, reason =
					RealmChunkAssemblySchema.AreSocketsCompatible(fromSocket.compatibility, toSocket.compatibility)
				if not compatible then
					compatibilityReason = reason
					addIntegrityIssue(integrityIssues, {
						code = "incompatible_socket_connection",
						message = "Declared connection is incompatible: " .. tostring(reason),
						declaredConnectionIndex = index,
						fromPlacementId = conn.fromPlacementId,
						fromSocketId = conn.fromSocketId,
						toPlacementId = conn.toPlacementId,
						toSocketId = conn.toSocketId,
					})
				end

				local fromWorldSocket =
					resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(conn.fromPlacementId, conn.fromSocketId)]
				local toWorldSocket =
					resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(conn.toPlacementId, conn.toSocketId)]
				if fromWorldSocket ~= nil and toWorldSocket ~= nil then
					if
						not vectorDeltaWithinTolerance(
							fromWorldSocket.worldPosition,
							toWorldSocket.worldPosition,
							SOCKET_ALIGNMENT_TOLERANCE
						)
					then
						addIntegrityIssue(integrityIssues, {
							code = "socket_position_mismatch",
							message = "Declared connection socket world positions do not align",
							declaredConnectionIndex = index,
							fromPlacementId = conn.fromPlacementId,
							fromSocketId = conn.fromSocketId,
							toPlacementId = conn.toPlacementId,
							toSocketId = conn.toSocketId,
						})
					end
					if
						not vectorsOpposeWithinTolerance(
							fromWorldSocket.worldForward,
							toWorldSocket.worldForward,
							SOCKET_ALIGNMENT_TOLERANCE
						)
					then
						addIntegrityIssue(integrityIssues, {
							code = "socket_forward_mismatch",
							message = "Declared connection socket worldForward vectors do not oppose",
							declaredConnectionIndex = index,
							fromPlacementId = conn.fromPlacementId,
							fromSocketId = conn.fromSocketId,
							toPlacementId = conn.toPlacementId,
							toSocketId = conn.toSocketId,
						})
					end
				end

				local fromKey = socketUsageKey(conn.fromPlacementId, conn.fromSocketId)
				local toKey = socketUsageKey(conn.toPlacementId, conn.toSocketId)
				local fromCount = socketUseCount[fromKey] or 0
				local toCount = socketUseCount[toKey] or 0
				if fromCount > 0 and not fromSocket.allowMultipleConnections then
					addIntegrityIssue(integrityIssues, {
						code = "duplicate_socket_use",
						message = "from socket is already consumed",
						declaredConnectionIndex = index,
						fromPlacementId = conn.fromPlacementId,
						fromSocketId = conn.fromSocketId,
						toPlacementId = conn.toPlacementId,
						toSocketId = conn.toSocketId,
					})
				end
				if toCount > 0 and not toSocket.allowMultipleConnections then
					addIntegrityIssue(integrityIssues, {
						code = "duplicate_socket_use",
						message = "to socket is already consumed",
						declaredConnectionIndex = index,
						fromPlacementId = conn.fromPlacementId,
						fromSocketId = conn.fromSocketId,
						toPlacementId = conn.toPlacementId,
						toSocketId = conn.toSocketId,
					})
				end

				local stitchable = #integrityIssues == issueCountBefore
				if stitchable then
					socketUseCount[fromKey] = fromCount + 1
					socketUseCount[toKey] = toCount + 1
					table.insert(stitchedGraph.edges, {
						declaredConnectionIndex = index,
						fromPlacementId = conn.fromPlacementId,
						fromSocketId = conn.fromSocketId,
						toPlacementId = conn.toPlacementId,
						toSocketId = conn.toSocketId,
					})
					table.insert(stitchedGraph.adjacencyByPlacement[conn.fromPlacementId], {
						declaredConnectionIndex = index,
						placementId = conn.fromPlacementId,
						neighborPlacementId = conn.toPlacementId,
						viaSocketId = conn.fromSocketId,
						neighborSocketId = conn.toSocketId,
					})
					table.insert(stitchedGraph.adjacencyByPlacement[conn.toPlacementId], {
						declaredConnectionIndex = index,
						placementId = conn.toPlacementId,
						neighborPlacementId = conn.fromPlacementId,
						viaSocketId = conn.toSocketId,
						neighborSocketId = conn.fromSocketId,
					})
				end
			end
		end

		local stitched = #integrityIssues == issueCountBefore
		if not stitched then
			addIntegrityIssue(integrityIssues, {
				code = "unstitchable_connection",
				message = "Declared connection cannot be stitched into a valid assembly graph",
				declaredConnectionIndex = index,
				fromPlacementId = conn.fromPlacementId,
				fromSocketId = conn.fromSocketId,
				toPlacementId = conn.toPlacementId,
				toSocketId = conn.toSocketId,
			})
		end

		local resolvedReason: string? = nil
		local fromWorldSocket =
			resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(conn.fromPlacementId, conn.fromSocketId)]
		local toWorldSocket =
			resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(conn.toPlacementId, conn.toSocketId)]
		if not stitched then
			resolvedReason = compatibilityReason
		end

		table.insert(resolvedConnections, {
			fromPlacementId = conn.fromPlacementId,
			fromSocketId = conn.fromSocketId,
			toPlacementId = conn.toPlacementId,
			toSocketId = conn.toSocketId,
			declaredConnectionIndex = index,
			stitched = stitched,
			compatible = stitched,
			fromWorldSocket = fromWorldSocket,
			toWorldSocket = toWorldSocket,
			reason = resolvedReason,
		})
	end

	if #input.placements > 1 then
		local visited: { [string]: boolean } = {}
		local queue: { string } = { input.placements[1].placementId }
		visited[input.placements[1].placementId] = true
		local cursor = 1
		while cursor <= #queue do
			local placementId = queue[cursor]
			cursor += 1
			local adjacency = stitchedGraph.adjacencyByPlacement[placementId]
			if adjacency ~= nil then
				for _, edge in ipairs(adjacency) do
					if not visited[edge.neighborPlacementId] then
						visited[edge.neighborPlacementId] = true
						table.insert(queue, edge.neighborPlacementId)
					end
				end
			end
		end

		for _, placement in ipairs(input.placements) do
			if not visited[placement.placementId] then
				addIntegrityIssue(integrityIssues, {
					code = "disconnected_placement",
					message = "Placement is not connected through stitched connections",
					fromPlacementId = placement.placementId,
				})
			end
		end
	end

	local integrity: AssemblyIntegrityResult = {
		passed = #integrityIssues == 0,
		issues = integrityIssues,
	}
	local validatorHandoff: ValidatorHandoff = {
		descriptorReady = integrity.passed,
		validatorProfileId = if input.validatorMetadata ~= nil
			then input.validatorMetadata.validatorProfileId
			else "unspecified_validator_profile",
		blockingAssemblyIssueCodes = collectBlockingIssueCodes(integrityIssues),
		routeTransitions = resolvedRouteTransitions,
		routeTransitionsByPlacement = resolvedRouteTransitionsByPlacement,
	}

	return {
		descriptor = descriptor,
		placements = input.placements,
		resolvedWorldSockets = resolvedWorldSockets,
		resolvedWorldSocketsByPlacement = resolvedWorldSocketsByPlacement,
		resolvedOccupiedSpace = resolvedOccupiedSpace,
		resolvedOccupiedSpaceByPlacement = resolvedOccupiedSpaceByPlacement,
		resolvedMetadata = resolvedMetadata,
		resolvedMetadataByPlacement = resolvedMetadataByPlacement,
		resolvedRouteTransitions = resolvedRouteTransitions,
		resolvedRouteTransitionsByPlacement = resolvedRouteTransitionsByPlacement,
		resolvedConnections = resolvedConnections,
		stitchedGraph = stitchedGraph,
		integrity = integrity,
		validatorHandoff = validatorHandoff,
	}
end

function RealmChunkAssemblySchema.ToRealmDescriptor(output: AssemblyOutput): RealmDescriptor
	return output.descriptor
end

return RealmChunkAssemblySchema
