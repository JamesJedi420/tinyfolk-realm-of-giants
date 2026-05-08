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

export type AuthoredChunk = {
	chunkId: string,
	chunkKind: string,
	authoringVersion: number,
	tags: { string },
	sockets: { ChunkSocket },
	content: ChunkLocalContent,
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

export type AssemblyOutput = {
	descriptor: RealmDescriptor,
	placements: { ChunkPlacement },
	resolvedWorldSockets: { ResolvedWorldSocket },
	resolvedWorldSocketsByPlacement: { [string]: { ResolvedWorldSocket } },
	resolvedConnections: { ResolvedChunkConnection },
	stitchedGraph: AssemblyStitchedGraph,
	integrity: AssemblyIntegrityResult,
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

local function resolveWorldSocket(
	placement: ChunkPlacement,
	socket: ChunkSocket
): ResolvedWorldSocket
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
	for _, placement in ipairs(input.placements) do
		stitchedGraph.adjacencyByPlacement[placement.placementId] = {}
		resolvedWorldSocketsByPlacement[placement.placementId] = {}
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
			resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(placement.placementId, socket.socketId)] = resolvedSocket
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
		local toWorldSocket = resolvedWorldSocketByPlacementSocketId[resolvedSocketKey(conn.toPlacementId, conn.toSocketId)]
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

	local integrity: AssemblyIntegrityResult = {
		passed = #integrityIssues == 0,
		issues = integrityIssues,
	}

	return {
		descriptor = descriptor,
		placements = input.placements,
		resolvedWorldSockets = resolvedWorldSockets,
		resolvedWorldSocketsByPlacement = resolvedWorldSocketsByPlacement,
		resolvedConnections = resolvedConnections,
		stitchedGraph = stitchedGraph,
		integrity = integrity,
	}
end

function RealmChunkAssemblySchema.ToRealmDescriptor(output: AssemblyOutput): RealmDescriptor
	return output.descriptor
end

return RealmChunkAssemblySchema
