--!strict

local RealmChunkAssemblySchema = require("./RealmChunkAssemblySchema")

local RealmDistrictPlacementValidator = {}

export type Vector3Data = {
	x: number,
	y: number,
	z: number,
}

export type NamedPart = {
	name: string,
	position: Vector3Data,
}

export type NamedZone = {
	name: string,
	position: Vector3Data,
	radius: number,
	tag: string,
}

export type NamedProp = {
	name: string,
	position: Vector3Data,
	propType: string,
}

export type NamedNode = {
	name: string,
	position: Vector3Data,
	nodeType: "spawn" | "waypoint" | "escape" | "station",
	tier: ("primary" | "fallback")?,
}

export type RouteEdge = {
	from: string,
	to: string,
	distance: number,
}

export type RealmDescriptor = {
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
	tileSizeClass: string?,
	recurringStructureTags: { string }?,
	environmentClass: string?,
	traversalDensityClass: string?,
}

export type AssemblyOutput = {
	descriptor: RealmDescriptor,
	resolvedOccupiedSpace: { ResolvedOccupiedBox },
	resolvedMetadata: { ResolvedChunkMetadata },
	resolvedMetadataByPlacement: { [string]: ResolvedChunkMetadata },
}

-- A proposed occupied-space box for a district placement, axis-aligned,
-- expressed as world-space center + half-extents (matching ResolvedOccupiedBox).
export type DistrictOccupiedBox = {
	tag: string?,
	worldCenter: Vector3Data,
	halfExtents: Vector3Data,
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
	-- Slice 5 fields (nil for Slice 1/2/3/4 reasons).
	conflictingEnvironmentClass: string?,
	conflictingTraversalDensityClass: string?,
	-- Slice 6 fields (nil for Slice 1/2/3/4/5 reasons).
	conflictingRecurringStructureTag: string?,
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

-- A single soft devaluation penalty entry (Slice 7).
-- factor: "near_critical_point" | "near_route_edge"
-- score: math.floor(softRadius - distance); always >= 1
-- category: "proximity" | "route_pressure" | "density_pressure" (Slice 8)
export type DistrictPlacementDevaluationPenalty = {
	factor: string,
	category: string,
	score: number,
	message: string,
	districtBoxTag: string?,
	nearCriticalPointName: string?,
	nearCriticalPointCategory: string?,
	nearRouteEdgeFrom: string?,
	nearRouteEdgeTo: string?,
	densityPressurePlacementId: string?,
	densityPressureChunkId: string?,
	densityPressureClass: string?,
}

-- Category-wise penalty total (Slice 8).
export type DistrictPlacementDevaluationCategoryTotal = {
	category: string,
	totalScore: number,
}

-- Aggregated soft devaluation result (Slice 7-8).
-- categoryTotals is deterministically ordered: proximity, route_pressure, density_pressure.
export type DistrictPlacementDevaluationResult = {
	totalPenalty: number,
	penalties: { DistrictPlacementDevaluationPenalty },
	categoryTotals: { DistrictPlacementDevaluationCategoryTotal },
}

-- Soft scoring thresholds for Slice 7 devaluation.
-- Set a radius to 0 to disable that scoring factor.
export type DistrictPlacementSoftConfig = {
	criticalPointSoftRadius: number?,
	routeEdgeSoftRadius: number?,
	nearCriticalPointSoftRadius: number?,
	nearRouteEdgeSoftRadius: number?,
	penalizedTraversalDensityClasses: { string }?,
	densityPressurePenaltyScore: number?,
}

-- The result of validating a single district placement request.
export type DistrictPlacementResult = {
	districtId: string,
	accepted: boolean,
	rejectReasons: { DistrictPlacementRejectReason },
	devaluation: DistrictPlacementDevaluationResult,
}

-- Allowed environment/density classes and disallowed recurring-structure tags
-- for a district placement (Slices 5-6).
-- Empty array for a field = that policy dimension is not enforced.
export type DistrictPlacementPolicyConfig = {
	allowedEnvironmentClasses: { string },
	allowedTraversalDensityClasses: { string },
	disallowedRecurringStructureTags: { string }?,
}

-- Hard reject tuning for Slice 9.
-- Nil nested configs leave that hard-policy dimension inactive while preserving
-- always-on occupied-space, escape-route, and route-edge preservation checks.
export type DistrictPlacementHardConfig = {
	criticalExclusion: DistrictCriticalExclusionConfig?,
	policy: DistrictPlacementPolicyConfig?,
}

-- Returns the Euclidean distance from a world-space point to the nearest surface
-- of an AABB (0 when the point is strictly inside the AABB).
local function distPointToAABB(
	point: Vector3Data,
	center: Vector3Data,
	halfExtents: Vector3Data
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
	pointPos: Vector3Data,
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
	assemblyOutput: AssemblyOutput,
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
	centerA: Vector3Data,
	halfA: Vector3Data,
	centerB: Vector3Data,
	halfB: Vector3Data
): boolean
	local dx = math.abs(centerA.x - centerB.x)
	local dy = math.abs(centerA.y - centerB.y)
	local dz = math.abs(centerA.z - centerB.z)
	if dx < halfA.x + halfB.x and dy < halfA.y + halfB.y and dz < halfA.z + halfB.z then
		return true
	end
	return false
end

-- Returns true if two AABBs overlap or touch at a boundary.
local function aabbsTouchOrOverlap(
	centerA: Vector3Data,
	halfA: Vector3Data,
	centerB: Vector3Data,
	halfB: Vector3Data
): boolean
	local dx = math.abs(centerA.x - centerB.x)
	local dy = math.abs(centerA.y - centerB.y)
	local dz = math.abs(centerA.z - centerB.z)
	if dx <= halfA.x + halfB.x and dy <= halfA.y + halfB.y and dz <= halfA.z + halfB.z then
		return true
	end
	return false
end

-- Returns true if a world-space point falls strictly inside an AABB
-- (same boundary convention as aabbsOverlap: boundary touch is NOT inside).
local function pointInsideAABB(
	point: Vector3Data,
	center: Vector3Data,
	halfExtents: Vector3Data
): boolean
	if
		math.abs(point.x - center.x) < halfExtents.x
		and math.abs(point.y - center.y) < halfExtents.y
		and math.abs(point.z - center.z) < halfExtents.z
	then
		return true
	end
	return false
end

-- Returns the subset of escapeRoutes whose positions are NOT inside any proposed box.
-- "Blocked" escape routes are those whose center point falls strictly inside a district box.
local function survivingEscapeRoutes(
	escapeRoutes: { NamedPart },
	proposedOccupiedSpace: { DistrictOccupiedBox }
): { NamedPart }
	local surviving: { NamedPart } = {}
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
	point: Vector3Data,
	p1: Vector3Data,
	p2: Vector3Data
): Vector3Data
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
	point: Vector3Data,
	center: Vector3Data,
	halfExtents: Vector3Data
): number
	local dx = math.max(0, math.abs(point.x - center.x) - halfExtents.x)
	local dy = math.max(0, math.abs(point.y - center.y) - halfExtents.y)
	local dz = math.max(0, math.abs(point.z - center.z) - halfExtents.z)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Returns true if line segment intersects AABB.
local function lineSegmentIntersectsAABB(
	p1: Vector3Data,
	p2: Vector3Data,
	boxCenter: Vector3Data,
	boxHalfExtents: Vector3Data
): boolean
	local closest = closestPointOnSegment(boxCenter, p1, p2)
	return distPointToAABB(closest, boxCenter, boxHalfExtents) == 0
end

-- Build protected route edges (spawn-to-escape paths via BFS).
local function buildProtectedRouteEdges(descriptor: RealmDescriptor): { [string]: boolean }
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
	assemblyOutput: AssemblyOutput,
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
	assemblyOutput: AssemblyOutput,
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
	assemblyOutput: AssemblyOutput,
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
	local nodesByName: { [string]: NamedNode } = {}
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
						if
							lineSegmentIntersectsAABB(
								fromNode.position,
								toNode.position,
								box.worldCenter,
								box.halfExtents
							)
						then
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

-- Slice 5: environment-class and traversal-density policy gate.
-- Rejects any proposed district box that overlaps an assembled chunk whose
-- environmentClass or traversalDensityClass is outside the allowed sets.
-- Empty allowed-classes array for a dimension = that dimension is not enforced.
local function checkEnvironmentAndDensityPolicy(
	request: DistrictPlacementRequest,
	assemblyOutput: AssemblyOutput,
	policyConfig: DistrictPlacementPolicyConfig,
	rejectReasons: { DistrictPlacementRejectReason }
)
	local allowedEnv: { [string]: boolean } = {}
	for _, cls in ipairs(policyConfig.allowedEnvironmentClasses) do
		allowedEnv[cls] = true
	end
	local allowedDensity: { [string]: boolean } = {}
	for _, cls in ipairs(policyConfig.allowedTraversalDensityClasses) do
		allowedDensity[cls] = true
	end
	local checkEnv = #policyConfig.allowedEnvironmentClasses > 0
	local checkDensity = #policyConfig.allowedTraversalDensityClasses > 0
	if not checkEnv and not checkDensity then
		return
	end
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
				if meta ~= nil then
					if checkEnv and meta.environmentClass ~= nil and not allowedEnv[meta.environmentClass] then
						table.insert(rejectReasons, {
							code = "environment_class_exclusion",
							message = "Proposed district overlaps placement '"
								.. assembledBox.placementId
								.. "' with incompatible environment class '"
								.. meta.environmentClass
								.. "'",
							districtBoxTag = districtBox.tag,
							conflictingPlacementId = assembledBox.placementId,
							conflictingChunkId = assembledBox.chunkId,
							conflictingBoxTag = assembledBox.tag,
							isLandmarkConflict = false,
							conflictingEnvironmentClass = meta.environmentClass,
						})
					end
					if
						checkDensity
						and meta.traversalDensityClass ~= nil
						and not allowedDensity[meta.traversalDensityClass]
					then
						table.insert(rejectReasons, {
							code = "traversal_density_exclusion",
							message = "Proposed district overlaps placement '"
								.. assembledBox.placementId
								.. "' with disallowed traversal density '"
								.. meta.traversalDensityClass
								.. "'",
							districtBoxTag = districtBox.tag,
							conflictingPlacementId = assembledBox.placementId,
							conflictingChunkId = assembledBox.chunkId,
							conflictingBoxTag = assembledBox.tag,
							isLandmarkConflict = false,
							conflictingTraversalDensityClass = meta.traversalDensityClass,
						})
					end
				end
			end
		end
	end
end

-- Slice 6: recurring-structure policy gate.
-- Rejects any proposed district box that overlaps an assembled chunk whose
-- recurringStructureTags contain at least one disallowed tag.
-- Each disallowed tag found in an overlapping chunk produces one reason.
local function checkRecurringStructurePolicy(
	request: DistrictPlacementRequest,
	assemblyOutput: AssemblyOutput,
	policyConfig: DistrictPlacementPolicyConfig,
	rejectReasons: { DistrictPlacementRejectReason }
)
	local disallowedTags = policyConfig.disallowedRecurringStructureTags
	if disallowedTags == nil or #disallowedTags == 0 then
		return
	end
	local disallowedSet: { [string]: boolean } = {}
	for _, tag in ipairs(disallowedTags) do
		disallowedSet[tag] = true
	end
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
				if meta ~= nil and meta.recurringStructureTags ~= nil then
					for _, structureTag in ipairs(meta.recurringStructureTags) do
						if disallowedSet[structureTag] then
							table.insert(rejectReasons, {
								code = "recurring_structure_tag_exclusion",
								message = "Proposed district overlaps placement '"
									.. assembledBox.placementId
									.. "' which carries disallowed recurring-structure tag '"
									.. structureTag
									.. "'",
								districtBoxTag = districtBox.tag,
								conflictingPlacementId = assembledBox.placementId,
								conflictingChunkId = assembledBox.chunkId,
								conflictingBoxTag = assembledBox.tag,
								isLandmarkConflict = false,
								conflictingRecurringStructureTag = structureTag,
							})
						end
					end
				end
			end
		end
	end
end

-- Slice 7-8: soft proximity penalty helper for near-critical-point scoring.
-- Emits at most one penalty per critical point (first triggering box wins).
-- Only fires when dist > 0 (no hard intersection) and dist < softRadius.
-- Slice 8: adds penaltyCategory parameter to categorize the penalty.
local function addSoftProximityPenalty(
	pointName: string,
	pointPos: Vector3Data,
	proposedOccupiedSpace: { DistrictOccupiedBox },
	softRadius: number,
	category: string,
	penaltyCategory: string,
	penalties: { DistrictPlacementDevaluationPenalty }
)
	if softRadius <= 0 then
		return
	end
	for _, box in ipairs(proposedOccupiedSpace) do
		local dist = distPointToAABB(pointPos, box.worldCenter, box.halfExtents)
		if dist > 0 and dist < softRadius then
			local score = math.floor(softRadius - dist)
			if score > 0 then
				table.insert(penalties, {
					factor = "near_critical_point",
					category = penaltyCategory,
					score = score,
					message = string.format(
						"Proposed district is within soft proximity radius (%.0f studs) of %s '%s' at distance %.1f",
						softRadius,
						category,
						pointName,
						dist
					),
					districtBoxTag = box.tag,
					nearCriticalPointName = pointName,
					nearCriticalPointCategory = category,
				})
			end
			return
		end
	end
end

local function addDensityPressurePenalties(
	request: DistrictPlacementRequest,
	assemblyOutput: AssemblyOutput,
	softConfig: DistrictPlacementSoftConfig,
	penalties: { DistrictPlacementDevaluationPenalty }
)
	local penalizedClasses = softConfig.penalizedTraversalDensityClasses
	local penaltyScore = softConfig.densityPressurePenaltyScore
	if penalizedClasses == nil or #penalizedClasses == 0 or penaltyScore == nil or penaltyScore <= 0 then
		return
	end

	local penalizedSet: { [string]: boolean } = {}
	for _, densityClass in ipairs(penalizedClasses) do
		penalizedSet[densityClass] = true
	end

	for _, districtBox in ipairs(request.proposedOccupiedSpace) do
		for _, assembledBox in ipairs(assemblyOutput.resolvedOccupiedSpace) do
			if
				aabbsTouchOrOverlap(
					districtBox.worldCenter,
					districtBox.halfExtents,
					assembledBox.worldCenter,
					assembledBox.halfExtents
				)
			then
				local meta = assemblyOutput.resolvedMetadataByPlacement[assembledBox.placementId]
				if meta ~= nil and meta.traversalDensityClass ~= nil and penalizedSet[meta.traversalDensityClass] then
					table.insert(penalties, {
						factor = "density_pressure",
						category = "density_pressure",
						score = penaltyScore,
						message = "Proposed district touches placement '"
							.. assembledBox.placementId
							.. "' with penalized traversal density '"
							.. meta.traversalDensityClass
							.. "'",
						districtBoxTag = districtBox.tag,
						densityPressurePlacementId = assembledBox.placementId,
						densityPressureChunkId = assembledBox.chunkId,
						densityPressureClass = meta.traversalDensityClass,
					})
				end
			end
		end
	end
end

-- Slice 7-8: compute soft devaluation result for a placement request.
-- Slice 7 runs scoring factors; Slice 8 categorizes penalties.
-- Runs both scoring factors when softConfig is provided.
-- Always returns a valid DevaluationResult (empty when softConfig is nil).
local function computeDevaluation(
	request: DistrictPlacementRequest,
	assemblyOutput: AssemblyOutput,
	softConfig: DistrictPlacementSoftConfig?
): DistrictPlacementDevaluationResult
	local penalties: { DistrictPlacementDevaluationPenalty } = {}

	if softConfig ~= nil then
		local nearCritRadius = softConfig.criticalPointSoftRadius or softConfig.nearCriticalPointSoftRadius or 0
		local nearEdgeRadius = softConfig.routeEdgeSoftRadius or softConfig.nearRouteEdgeSoftRadius or 0
		local descriptor = assemblyOutput.descriptor
		local proposed = request.proposedOccupiedSpace

		-- Factor 1: near protected critical points (category: proximity).
		-- Checks the same categories as the Slice 3 hard gate.
		if nearCritRadius > 0 then
			for _, part in ipairs(descriptor.spawns) do
				if string.find(part.name, "TinyfolkSpawn", 1, true) then
					addSoftProximityPenalty(
						part.name,
						part.position,
						proposed,
						nearCritRadius,
						"tinyfolk_spawn",
						"proximity",
						penalties
					)
				end
			end
			for _, part in ipairs(descriptor.escapeRoutes) do
				addSoftProximityPenalty(
					part.name,
					part.position,
					proposed,
					nearCritRadius,
					"escape_route",
					"proximity",
					penalties
				)
			end
			for _, part in ipairs(descriptor.returnPoints) do
				addSoftProximityPenalty(
					part.name,
					part.position,
					proposed,
					nearCritRadius,
					"return_point",
					"proximity",
					penalties
				)
			end
			for _, part in ipairs(descriptor.stations) do
				addSoftProximityPenalty(
					part.name,
					part.position,
					proposed,
					nearCritRadius,
					"station",
					"proximity",
					penalties
				)
			end
			for _, part in ipairs(descriptor.constructionSites) do
				addSoftProximityPenalty(
					part.name,
					part.position,
					proposed,
					nearCritRadius,
					"construction_site",
					"proximity",
					penalties
				)
			end
			for _, zone in ipairs(descriptor.captureZones) do
				addSoftProximityPenalty(
					zone.name,
					zone.position,
					proposed,
					nearCritRadius,
					"capture_zone",
					"proximity",
					penalties
				)
			end
			for _, zone in ipairs(descriptor.controlZones) do
				addSoftProximityPenalty(
					zone.name,
					zone.position,
					proposed,
					nearCritRadius,
					"control_zone",
					"proximity",
					penalties
				)
			end
		end

		-- Factor 2: near protected route edges but not intersecting (category: route_pressure).
		if nearEdgeRadius > 0 and #descriptor.routeGraph.nodes > 0 and #descriptor.routeGraph.edges > 0 then
			local protectedEdges = buildProtectedRouteEdges(descriptor)
			if next(protectedEdges) then
				local nodesByName: { [string]: NamedNode } = {}
				for _, node in ipairs(descriptor.routeGraph.nodes) do
					nodesByName[node.name] = node
				end
				for edgeKey in pairs(protectedEdges) do
					local fromIdx = string.find(edgeKey, "::", 1, true)
					if fromIdx ~= nil then
						local fromName = string.sub(edgeKey, 1, fromIdx - 1)
						local toName = string.sub(edgeKey, fromIdx + 2)
						local fromNode = nodesByName[fromName]
						local toNode = nodesByName[toName]
						if fromNode ~= nil and toNode ~= nil then
							local found = false
							for _, box in ipairs(proposed) do
								if not found then
									local closest =
										closestPointOnSegment(box.worldCenter, fromNode.position, toNode.position)
									local dist = distPointToAABB(closest, box.worldCenter, box.halfExtents)
									if dist > 0 and dist < nearEdgeRadius then
										local score = math.floor(nearEdgeRadius - dist)
										if score > 0 then
											table.insert(penalties, {
												factor = "near_route_edge",
												category = "route_pressure",
												score = score,
												message = string.format(
													"Proposed district is within soft proximity radius (%.0f studs) of protected route edge '%s' -> '%s'",
													nearEdgeRadius,
													fromName,
													toName
												),
												districtBoxTag = box.tag,
												nearRouteEdgeFrom = fromName,
												nearRouteEdgeTo = toName,
											})
											found = true
										end
									end
								end
							end
						end
					end
				end
			end
		end

		-- Factor 3: touch/overlap with configured traversal-density classes.
		addDensityPressurePenalties(request, assemblyOutput, softConfig, penalties)
	end

	local totalPenalty = 0
	for _, penalty in ipairs(penalties) do
		totalPenalty += penalty.score
	end

	-- Slice 8: compute category totals (deterministic order: proximity, route_pressure, density_pressure).
	-- Always include all three categories for deterministic representation.
	local categoryTotals: { DistrictPlacementDevaluationCategoryTotal } = {}
	local categoryScores: { [string]: number } = {
		proximity = 0,
		route_pressure = 0,
		density_pressure = 0,
	}
	for _, penalty in ipairs(penalties) do
		if categoryScores[penalty.category] ~= nil then
			categoryScores[penalty.category] += penalty.score
		end
	end
	for _, cat in ipairs({ "proximity", "route_pressure", "density_pressure" }) do
		table.insert(categoryTotals, {
			category = cat,
			totalScore = categoryScores[cat],
		})
	end

	return {
		totalPenalty = totalPenalty,
		penalties = penalties,
		categoryTotals = categoryTotals,
	}
end

local function isHardConfig(config: any): boolean
	if type(config) ~= "table" then
		return false
	end
	if config.criticalExclusion ~= nil or config.policy ~= nil then
		return true
	end
	if
		config.tinyfolkSpawnExclusionRadius ~= nil
		or config.allowedEnvironmentClasses ~= nil
		or config.nearCriticalPointSoftRadius ~= nil
	then
		return false
	end
	return true
end

local function isSoftConfig(config: any): boolean
	if type(config) ~= "table" then
		return false
	end
	return config.criticalPointSoftRadius ~= nil
		or config.routeEdgeSoftRadius ~= nil
		or config.nearCriticalPointSoftRadius ~= nil
		or config.nearRouteEdgeSoftRadius ~= nil
		or config.penalizedTraversalDensityClasses ~= nil
		or config.densityPressurePenaltyScore ~= nil
end

local function resolveValidationConfigs(
	hardOrCriticalConfig: DistrictPlacementHardConfig | DistrictCriticalExclusionConfig | nil,
	policyOrSoftConfig: DistrictPlacementPolicyConfig | DistrictPlacementSoftConfig | nil,
	legacySoftConfig: DistrictPlacementSoftConfig?
): (DistrictPlacementHardConfig, DistrictPlacementSoftConfig?)
	if isHardConfig(hardOrCriticalConfig) then
		return hardOrCriticalConfig :: DistrictPlacementHardConfig, policyOrSoftConfig :: DistrictPlacementSoftConfig?
	end
	if hardOrCriticalConfig == nil and isSoftConfig(policyOrSoftConfig) then
		return {}, policyOrSoftConfig :: DistrictPlacementSoftConfig
	end

	return {
		criticalExclusion = hardOrCriticalConfig :: DistrictCriticalExclusionConfig?,
		policy = policyOrSoftConfig :: DistrictPlacementPolicyConfig?,
	}, legacySoftConfig
end

-- Validate a district placement request against an assembled realm output.
-- Runs all active gate checks in a single deterministic pass:
--   Slice 1: occupied-space and landmark exclusion
--   Slice 2: route/escape preservation
--   Slice 3: critical-point proximity (when hardConfig.criticalExclusion is provided)
--   Slice 4: route-graph edge preservation
--   Slice 5: environment-class and traversal-density policy (when hardConfig.policy is provided)
--   Slice 6: recurring-structure tag policy (when hardConfig.policy is provided)
--   Slice 7: soft devaluation scoring (when softConfig is provided)
-- Preferred Slice 9 call shape: ValidatePlacement(request, assemblyOutput, hardConfig, softConfig)
-- Legacy call shape remains supported: ValidatePlacement(request, assemblyOutput, criticalConfig, policyConfig, softConfig)
function RealmDistrictPlacementValidator.ValidatePlacement(
	request: DistrictPlacementRequest,
	assemblyOutput: AssemblyOutput,
	hardOrCriticalConfig: DistrictPlacementHardConfig | DistrictCriticalExclusionConfig | nil,
	policyOrSoftConfig: DistrictPlacementPolicyConfig | DistrictPlacementSoftConfig | nil,
	legacySoftConfig: DistrictPlacementSoftConfig?
): DistrictPlacementResult
	local rejectReasons: { DistrictPlacementRejectReason } = {}
	local hardConfig, softConfig = resolveValidationConfigs(hardOrCriticalConfig, policyOrSoftConfig, legacySoftConfig)

	checkOccupiedSpaceExclusion(request, assemblyOutput, rejectReasons)
	checkRouteEscapePreservation(request, assemblyOutput, rejectReasons)
	if hardConfig.criticalExclusion ~= nil then
		checkCriticalPointProximity(request, assemblyOutput, hardConfig.criticalExclusion, rejectReasons)
	end
	checkRouteGraphEdgePreservation(request, assemblyOutput, rejectReasons)
	if hardConfig.policy ~= nil then
		checkEnvironmentAndDensityPolicy(request, assemblyOutput, hardConfig.policy, rejectReasons)
		checkRecurringStructurePolicy(request, assemblyOutput, hardConfig.policy, rejectReasons)
	end

	return {
		districtId = request.districtId,
		accepted = #rejectReasons == 0,
		rejectReasons = rejectReasons,
		devaluation = computeDevaluation(request, assemblyOutput, softConfig),
	}
end

return RealmDistrictPlacementValidator
