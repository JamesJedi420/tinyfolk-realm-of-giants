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
}

export type AssemblyInput = {
	chunkLibrary: { [string]: AuthoredChunk },
	placements: { ChunkPlacement },
	declaredConnections: { DeclaredChunkConnection },
}

export type ResolvedChunkConnection = {
	fromPlacementId: string,
	fromSocketId: string,
	toPlacementId: string,
	toSocketId: string,
	compatible: boolean,
	reason: string?,
}

export type AssemblyOutput = {
	descriptor: RealmDescriptor,
	placements: { ChunkPlacement },
	resolvedConnections: { ResolvedChunkConnection },
}

local function rotateYawQuarterTurns(point: Vector3Data, turns: number): Vector3Data
	if turns == 0 then
		return { x = point.x, y = point.y, z = point.z }
	elseif turns == 1 then
		return { x = -point.z, y = point.y, z = point.x }
	elseif turns == 2 then
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

function RealmChunkAssemblySchema.BuildAssemblyOutput(input: AssemblyInput): AssemblyOutput
	local placementById: { [string]: ChunkPlacement } = {}
	for _, placement in input.placements do
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

	for _, placement in input.placements do
		local chunk = input.chunkLibrary[placement.chunkId]
		if chunk == nil then
			error("missing chunk in library for chunkId=" .. placement.chunkId)
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
	for _, conn in input.declaredConnections do
		local fromPlacement = placementById[conn.fromPlacementId]
		local toPlacement = placementById[conn.toPlacementId]
		if fromPlacement == nil or toPlacement == nil then
			table.insert(resolvedConnections, {
				fromPlacementId = conn.fromPlacementId,
				fromSocketId = conn.fromSocketId,
				toPlacementId = conn.toPlacementId,
				toSocketId = conn.toSocketId,
				compatible = false,
				reason = "placement missing",
			})
			continue
		end

		local fromChunk = input.chunkLibrary[fromPlacement.chunkId]
		local toChunk = input.chunkLibrary[toPlacement.chunkId]
		if fromChunk == nil or toChunk == nil then
			table.insert(resolvedConnections, {
				fromPlacementId = conn.fromPlacementId,
				fromSocketId = conn.fromSocketId,
				toPlacementId = conn.toPlacementId,
				toSocketId = conn.toSocketId,
				compatible = false,
				reason = "chunk missing",
			})
			continue
		end

		local fromSocket = getSocketById(fromChunk, conn.fromSocketId)
		local toSocket = getSocketById(toChunk, conn.toSocketId)
		if fromSocket == nil or toSocket == nil then
			table.insert(resolvedConnections, {
				fromPlacementId = conn.fromPlacementId,
				fromSocketId = conn.fromSocketId,
				toPlacementId = conn.toPlacementId,
				toSocketId = conn.toSocketId,
				compatible = false,
				reason = "socket missing",
			})
			continue
		end

		local compatible, reason = RealmChunkAssemblySchema.AreSocketsCompatible(
			fromSocket.compatibility,
			toSocket.compatibility
		)
		table.insert(resolvedConnections, {
			fromPlacementId = conn.fromPlacementId,
			fromSocketId = conn.fromSocketId,
			toPlacementId = conn.toPlacementId,
			toSocketId = conn.toSocketId,
			compatible = compatible,
			reason = reason,
		})
	end

	return {
		descriptor = descriptor,
		placements = input.placements,
		resolvedConnections = resolvedConnections,
	}
end

function RealmChunkAssemblySchema.ToRealmDescriptor(output: AssemblyOutput): RealmDescriptor
	return output.descriptor
end

return RealmChunkAssemblySchema
