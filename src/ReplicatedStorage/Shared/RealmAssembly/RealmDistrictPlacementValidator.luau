--!strict

local RealmChunkAssemblySchema = require("./RealmChunkAssemblySchema")

local RealmDistrictPlacementValidator = {}

-- A proposed occupied-space box for a district placement, axis-aligned,
-- expressed as world-space center + half-extents (matching ResolvedOccupiedBox).
export type DistrictOccupiedBox = {
	tag: string?,
	worldCenter: RealmChunkAssemblySchema.Vector3Data,
	halfExtents: RealmChunkAssemblySchema.Vector3Data,
}

-- The minimal district placement request: an identifier and proposed occupied space.
export type DistrictPlacementRequest = {
	districtId: string,
	proposedOccupiedSpace: { DistrictOccupiedBox },
}

-- A single reject reason record.
export type DistrictPlacementRejectReason = {
	code: string,
	message: string,
	districtBoxTag: string?,
	conflictingPlacementId: string?,
	conflictingChunkId: string?,
	conflictingBoxTag: string?,
	isLandmarkConflict: boolean,
	-- Slice 3 fields (nil for Slice 1/2 reasons).
	conflictingCriticalPointName: string?,
	criticalCategory: string?,
	-- Slice 4 fields (nil for Slice 1/2/3 reasons).
	conflictingRouteEdgeFrom: string?,
	conflictingRouteEdgeTo: string?,
}

-- Per-category exclusion radii (studs) for Slice 3 proximity gate.
-- A radius of 0 disables the check for that category.
export type DistrictCriticalExclusionConfig = {
	tinyfolkSpawnExclusionRadius: number,
	escapeRouteExclusionRadius: number,
	returnPointExclusionRadius: number,
	stationExclusionRadius: number,
	constructionSiteExclusionRadius: number,
	captureZoneExclusionRadius: number,
	controlZoneExclusionRadius: number,
}

-- The result of validating a single district placement request.
export type DistrictPlacementResult = {
	districtId: string,
	accepted: boolean,
	rejectReasons: { DistrictPlacementRejectReason },
}

-- Returns the Euclidean distance from a world-space point to the nearest surface
-- of an AABB (0 when the point is strictly inside the AABB).
local function distPointToAABB(
	point: RealmChunkAssemblySchema.Vector3Data,
	center: RealmChunkAssemblySchema.Vector3Data,
	halfExtents: RealmChunkAssemblySchema.Vector3Data
): number
	local dx = math.max(0, math.abs(point.x - center.x) - halfExtents.x)
	local dy = math.max(0, math.abs(point.y - center.y) - halfExtents.y)
	local dz = math.max(0, math.abs(point.z - center.z) - halfExtents.z)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Appends one reject reason if any proposed box is within exclusionRadius of pointPos.
-- Reports at most once per critical point (first triggering box wins).
-- No-ops when exclusionRadius <= 0.
local function rejectIfProximity(
	pointName: string,
	pointPos: RealmChunkAssemblySchema.Vector3Data,
	proposedOccupiedSpace: { DistrictOccupiedBox },
	exclusionRadius: number,
	code: string,
	category: string,
	rejectReasons: { DistrictPlacementRejectReason }
)
	if exclusionRadius <= 0 then
		return
	end
	for _, box in ipairs(proposedOccupiedSpace) do
		if distPointToAABB(pointPos, box.worldCenter, box.halfExtents) < exclusionRadius then
			table.insert(rejectReasons, {
				code = code,
				message = string.format(
					"Proposed district is within exclusion radius (%.0f studs) of %s '%s'",
					exclusionRadius,
					category,
					pointName
				),
				districtBoxTag = box.tag,
				conflictingPlacementId = nil,
				conflictingChunkId = nil,
				conflictingBoxTag = nil,
				isLandmarkConflict = false,
				conflictingCriticalPointName = pointName,
				criticalCategory = category,
			})
			return
		end
	end
end

-- Check Slice 3: critical-point proximity (containment/objective/rescue-route overlap rejection).
-- For each protected category, any proposed box within the configured exclusion radius
-- of a protected world-space point produces a deterministic reject reason.
local function checkCriticalPointProximity(
	request: DistrictPlacementRequest,
	assemblyOutput: RealmChunkAssemblySchema.AssemblyOutput,
	config: DistrictCriticalExclusionConfig,
	rejectReasons: { DistrictPlacementRejectReason }
)
	local descriptor = assemblyOutput.descriptor
	local proposed = request.proposedOccupiedSpace

	-- Tinyfolk spawns (filter by name containing "TinyfolkSpawn" — consistent with
	-- topology prefix convention; Giant spawns are not protected by this gate).
	for _, part in ipairs(descriptor.spawns) do
		if string.find(part.name, "TinyfolkSpawn", 1, true) then
			rejectIfProximity(
				part.name,
				part.position,
				proposed,
				config.tinyfolkSpawnExclusionRadius,
				"tinyfolk_spawn_exclusion",
				"tinyfolk_spawn",
				rejectReasons
			)
		end
	end

	-- Escape routes.
	for _, part in ipairs(descriptor.escapeRoutes) do
		rejectIfProximity(
			part.name,
			part.position,
			proposed,
			config.escapeRouteExclusionRadius,
			"escape_route_exclusion",
			"escape_route",
			rejectReasons
		)
	end

	-- Return points / rescue-route critical points.
	for _, part in ipairs(descriptor.returnPoints) do
		rejectIfProximity(
			part.name,
			part.position,
			proposed,
			config.returnPointExclusionRadius,
			"return_point_exclusion",
			"return_point",
			rejectReasons
		)
	end

	-- Required specialist stations (objective points).
	for _, part in ipairs(descriptor.stations) do
		rejectIfProximity(
			part.name,
			part.position,
			proposed,
			config.stationExclusionRadius,
			"station_exclusion",
			"station",
			rejectReasons
		)
	end

	-- Unfinished construction objectives.
	for _, part in ipairs(descriptor.constructionSites) do
		rejectIfProximity(
			part.name,
			part.position,
			proposed,
			config.constructionSiteExclusionRadius,
			"construction_site_exclusion",
			"construction_site",
			rejectReasons
		)
	end

	-- Capture zones.
	for _, zone in ipairs(descriptor.captureZones) do
		rejectIfProximity(
			zone.name,
			zone.position,
			proposed,
			config.captureZoneExclusionRadius,
			"capture_zone_exclusion",
			"capture_zone",
			rejectReasons
		)
	end

	-- Control zones.
	for _, zone in ipairs(descriptor.controlZones) do
		rejectIfProximity(
			zone.name,
			zone.position,
			proposed,
			config.controlZoneExclusionRadius,
			"control_zone_exclusion",
			"control_zone",
			rejectReasons
		)
	end
end

-- Returns true if two AABBs overlap (strict: boundary-touch is NOT overlap).
local function aabbsOverlap(
	centerA: RealmChunkAssemblySchema.Vector3Data,
	halfA: RealmChunkAssemblySchema.Vector3Data,
	centerB: RealmChunkAssemblySchema.Vector3Data,
	halfB: RealmChunkAssemblySchema.Vector3Data
): boolean
	local dx = math.abs(centerA.x - centerB.x)
	local dy = math.abs(centerA.y - centerB.y)
	local dz = math.abs(centerA.z - centerB.z)
	return dx < halfA.x + halfB.x and dy < halfA.y + halfB.y and dz < halfA.z + halfB.z
end

-- Returns true if a world-space point falls strictly inside an AABB
-- (same boundary convention as aabbsOverlap: boundary touch is NOT inside).
local function pointInsideAABB(
	point: RealmChunkAssemblySchema.Vector3Data,
	center: RealmChunkAssemblySchema.Vector3Data,
	halfExtents: RealmChunkAssemblySchema.Vector3Data
): boolean
	return math.abs(point.x - center.x) < halfExtents.x
		and math.abs(point.y - center.y) < halfExtents.y
		and math.abs(point.z - center.z) < halfExtents.z
end

-- Returns the subset of escapeRoutes whose positions are NOT inside any proposed box.
-- "Blocked" escape routes are those whose center point falls strictly inside a district box.
local function survivingEscapeRoutes(
	escapeRoutes: { RealmChunkAssemblySchema.NamedPart },
	proposedOccupiedSpace: { DistrictOccupiedBox }
): { RealmChunkAssemblySchema.NamedPart }
	local surviving: { RealmChunkAssemblySchema.NamedPart } = {}
	for _, route in ipairs(escapeRoutes) do
		local blocked = false
		for _, box in ipairs(proposedOccupiedSpace) do
			if pointInsideAABB(route.position, box.worldCenter, box.halfExtents) then
				blocked = true
				break
			end
		end
		if not blocked then
			table.insert(surviving, route)
		end
	end
	return surviving
end

-- Returns the closest point on a line segment p1-p2 to a given point.
local function closestPointOnSegment(
	point: RealmChunkAssemblySchema.Vector3Data,
	p1: RealmChunkAssemblySchema.Vector3Data,
	p2: RealmChunkAssemblySchema.Vector3Data
): RealmChunkAssemblySchema.Vector3Data
	local dx = p2.x - p1.x
	local dy = p2.y - p1.y
	local dz = p2.z - p1.z
	local lenSq = dx * dx + dy * dy + dz * dz

	if lenSq == 0 then
		return p1
	end

	local t = ((point.x - p1.x) * dx + (point.y - p1.y) * dy + (point.z - p1.z) * dz) / lenSq
	t = math.max(0, math.min(1, t))

	return {
		x = p1.x + t * dx,
		y = p1.y + t * dy,
		z = p1.z + t * dz,
	}
end

-- Returns distance from point to AABB surface (0 if inside).
local function distPointToAABB(
	point: RealmChunkAssemblySchema.Vector3Data,
	center: RealmChunkAssemblySchema.Vector3Data,
	halfExtents: RealmChunkAssemblySchema.Vector3Data
): number
	local dx = math.max(0, math.abs(point.x - center.x) - halfExtents.x)
	local dy = math.max(0, math.abs(point.y - center.y) - halfExtents.y)
	local dz = math.max(0, math.abs(point.z - center.z) - halfExtents.z)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Returns true if line segment intersects AABB.
local function lineSegmentIntersectsAABB(
	p1: RealmChunkAssemblySchema.Vector3Data,
	p2: RealmChunkAssemblySchema.Vector3Data,
	boxCenter: RealmChunkAssemblySchema.Vector3Data,
	boxHalfExtents: RealmChunkAssemblySchema.Vector3Data
): boolean
	local closest = closestPointOnSegment(boxCenter, p1, p2)
	return distPointToAABB(closest, boxCenter, boxHalfExtents) == 0
end

-- Build protected route edges (spawn-to-escape paths via BFS).
local function buildProtectedRouteEdges(descriptor: RealmChunkAssemblySchema.RealmDescriptor): { [string]: boolean }
	local graph = descriptor.routeGraph
	local protected: { [string]: boolean } = {}

	-- Find spawn and escape nodes.
	local spawnNodeNames: { [string]: boolean } = {}
	local escapeNodeNames: { [string]: boolean } = {}
	for _, node in ipairs(graph.nodes) do
		if node.nodeType == "spawn" then
			spawnNodeNames[node.name] = true
		elseif node.nodeType == "escape" then
			escapeNodeNames[node.name] = true
		end
	end

	-- If no spawns or escapes, no protected edges.
	if not next(spawnNodeNames) or not next(escapeNodeNames) then
		return protected
	end

	-- BFS forward from all spawn nodes.
	local reachableFromSpawn: { [string]: boolean } = {}
	local queue: { string } = {}
	for name in pairs(spawnNodeNames) do
		table.insert(queue, name)
		reachableFromSpawn[name] = true
	end

	local front = 1
	while front <= #queue do
		local fromName = queue[front]
		front = front + 1
		for _, edge in ipairs(graph.edges) do
			if edge.from == fromName and not reachableFromSpawn[edge.to] then
				reachableFromSpawn[edge.to] = true
				table.insert(queue, edge.to)
			end
		end
	end

	-- BFS backward from all escape nodes (reverse edges).
	local canReachEscape: { [string]: boolean } = {}
	queue = {}
	for name in pairs(escapeNodeNames) do
		table.insert(queue, name)
		canReachEscape[name] = true
	end

	front = 1
	while front <= #queue do
		local toName = queue[front]
		front = front + 1
		for _, edge in ipairs(graph.edges) do
			if edge.to == toName and not canReachEscape[edge.from] then
				canReachEscape[edge.from] = true
				table.insert(queue, edge.from)
			end
		end
	end

	-- Mark edges as protected if they bridge reachable-from-spawn to reachable-to-escape.
	for _, edge in ipairs(graph.edges) do
		if reachableFromSpawn[edge.from] and canReachEscape[edge.to] then
			protected[edge.from .. "::" .. edge.to] = true
		end
	end

	return protected
end

-- Check Slice 1: occupied-space and landmark exclusion.
local function checkOccupiedSpaceExclusion(
	request: DistrictPlacementRequest,
	assemblyOutput: RealmChunkAssemblySchema.AssemblyOutput,
	rejectReasons: { DistrictPlacementRejectReason }
)
	for _, districtBox in ipairs(request.proposedOccupiedSpace) do
		for _, assembledBox in ipairs(assemblyOutput.resolvedOccupiedSpace) do
			if
				aabbsOverlap(
					districtBox.worldCenter,
					districtBox.halfExtents,
					assembledBox.worldCenter,
					assembledBox.halfExtents
				)
			then
				local meta = assemblyOutput.resolvedMetadataByPlacement[assembledBox.placementId]
				local isLandmark = meta ~= nil and meta.isLandmarkAnchor == true
				local code = if isLandmark then "landmark_anchor_exclusion" else "occupied_space_overlap"
				table.insert(rejectReasons, {
					code = code,
					message = if isLandmark
						then "Proposed district overlaps landmark-anchored occupied space of placement '"
							.. assembledBox.placementId
							.. "'"
						else "Proposed district overlaps assembled occupied space of placement '"
							.. assembledBox.placementId
							.. "'",
					districtBoxTag = districtBox.tag,
					conflictingPlacementId = assembledBox.placementId,
					conflictingChunkId = assembledBox.chunkId,
					conflictingBoxTag = assembledBox.tag,
					isLandmarkConflict = isLandmark,
				})
			end
		end
	end
end

-- Check Slice 2: route/escape preservation.
-- Simulates the post-placement descriptor by removing escape routes whose positions
-- fall inside any proposed box. Rejects if the simulated realm would have no
-- remaining escape routes (violating the topology escape_route_exists invariant).
local function checkRouteEscapePreservation(
	request: DistrictPlacementRequest,
	assemblyOutput: RealmChunkAssemblySchema.AssemblyOutput,
	rejectReasons: { DistrictPlacementRejectReason }
)
	local descriptor = assemblyOutput.descriptor
	local baseEscapeRoutes = descriptor.escapeRoutes

	-- Vacuous pass: no escape routes to lose.
	if #baseEscapeRoutes == 0 then
		return
	end

	local surviving = survivingEscapeRoutes(baseEscapeRoutes, request.proposedOccupiedSpace)

	if #surviving == 0 then
		-- All escape routes are blocked — topology escape_route_exists invariant would fail.
		local blockedNames: { string } = {}
		for _, route in ipairs(baseEscapeRoutes) do
			table.insert(blockedNames, route.name)
		end
		table.sort(blockedNames)
		table.insert(rejectReasons, {
			code = "route_escape_preservation_failure",
			message = "Proposed district blocks all assembled escape routes: " .. table.concat(blockedNames, ", "),
			districtBoxTag = nil,
			conflictingPlacementId = nil,
			conflictingChunkId = nil,
			conflictingBoxTag = nil,
			isLandmarkConflict = false,
		})
	end
end

-- Check Slice 4: route-graph edge preservation.
-- Rejects when proposed occupied space intersects protected route edges.
local function checkRouteGraphEdgePreservation(
	request: DistrictPlacementRequest,
	assemblyOutput: RealmChunkAssemblySchema.AssemblyOutput,
	rejectReasons: { DistrictPlacementRejectReason }
)
	local descriptor = assemblyOutput.descriptor
	local graph = descriptor.routeGraph
	local proposed = request.proposedOccupiedSpace

	-- Vacuous pass: no route graph.
	if #graph.nodes == 0 or #graph.edges == 0 then
		return
	end

	-- Build the set of protected route edges (spawn-to-escape paths).
	local protectedEdges = buildProtectedRouteEdges(descriptor)

	-- Vacuous pass: no protected edges.
	if not next(protectedEdges) then
		return
	end

	-- Build a name-to-node map for efficient position lookup.
	local nodesByName: { [string]: RealmChunkAssemblySchema.NamedNode } = {}
	for _, node in ipairs(graph.nodes) do
		nodesByName[node.name] = node
	end

	-- For each protected edge, check intersection against all proposed boxes.
	for edgeKey in pairs(protectedEdges) do
		-- Split the edge key "from::to" into components.
		local fromIdx = string.find(edgeKey, "::", 1, true)
		if fromIdx ~= nil then
			local fromName = string.sub(edgeKey, 1, fromIdx - 1)
			local toName = string.sub(edgeKey, fromIdx + 2)
			local fromNode = nodesByName[fromName]
			local toNode = nodesByName[toName]

			-- Sanity check (should not happen if buildProtectedRouteEdges is correct).
			if fromNode ~= nil and toNode ~= nil then
				-- Test each proposed box against this edge segment.
				local found = false
				for _, box in ipairs(proposed) do
					if not found then
						if lineSegmentIntersectsAABB(fromNode.position, toNode.position, box.worldCenter, box.halfExtents) then
							table.insert(rejectReasons, {
								code = "route_edge_intersection",
								message = "Proposed district intersects protected route edge",
								districtBoxTag = box.tag,
								conflictingPlacementId = nil,
								conflictingChunkId = nil,
								conflictingBoxTag = nil,
								isLandmarkConflict = false,
								conflictingCriticalPointName = nil,
								criticalCategory = nil,
								conflictingRouteEdgeFrom = fromName,
								conflictingRouteEdgeTo = toName,
							})
							found = true
						end
					end
				end
			end
		end
	end
end

-- Validate a district placement request against an assembled realm output.
-- Runs all active gate checks in a single deterministic pass:
--   Slice 1: occupied-space and landmark exclusion
--   Slice 2: route/escape preservation
--   Slice 3: critical-point proximity (when criticalConfig is provided)
--   Slice 4: route-graph edge preservation
function RealmDistrictPlacementValidator.ValidatePlacement(
	request: DistrictPlacementRequest,
	assemblyOutput: RealmChunkAssemblySchema.AssemblyOutput,
	criticalConfig: DistrictCriticalExclusionConfig?
): DistrictPlacementResult
	local rejectReasons: { DistrictPlacementRejectReason } = {}

	checkOccupiedSpaceExclusion(request, assemblyOutput, rejectReasons)
	checkRouteEscapePreservation(request, assemblyOutput, rejectReasons)
	if criticalConfig ~= nil then
		checkCriticalPointProximity(request, assemblyOutput, criticalConfig, rejectReasons)
	end
	checkRouteGraphEdgePreservation(request, assemblyOutput, rejectReasons)

	return {
		districtId = request.districtId,
		accepted = #rejectReasons == 0,
		rejectReasons = rejectReasons,
	}
end

return RealmDistrictPlacementValidator
