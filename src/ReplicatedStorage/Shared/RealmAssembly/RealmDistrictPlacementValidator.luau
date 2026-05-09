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
-- subjectType: "critical_point" | "route_edge" | "chunk_density"
-- sortKey: category precedence, then category/factor/subjectType/subjectName.
export type DistrictPlacementDevaluationPenalty = {
	factor: string,
	category: string,
	score: number,
	message: string,
	subjectType: string,
	subjectName: string,
	sortKey: string,
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

export type DistrictPlacementDevaluationGroupSummary = {
	category: string,
	penaltyCount: number,
	totalScore: number,
	firstSortKey: string?,
	lastSortKey: string?,
}

export type DistrictPlacementDevaluationFactorSummary = {
	factor: string,
	penaltyCount: number,
	totalScore: number,
	firstSortKey: string,
	lastSortKey: string,
}

export type DistrictPlacementDevaluationSubjectSummary = {
	subjectType: string,
	subjectName: string,
	penaltyCount: number,
	totalScore: number,
	firstSortKey: string,
	lastSortKey: string,
}

export type DistrictPlacementDevaluationConfigSnapshot = {
	criticalPointSoftRadii: {
		tinyfolk_spawn: number,
		escape_route: number,
		return_point: number,
		station: number,
		construction_site: number,
		capture_zone: number,
		control_zone: number,
	},
	routeEdgeSoftRadius: number,
	densityPressurePenaltyScores: {
		open: number,
		sparse: number,
		moderate: number,
		dense: number,
	},
}

-- Aggregated soft devaluation contract:
--   penalties: full ordered soft penalty entries.
--   categoryTotals: deterministic score totals ordered proximity, route_pressure, density_pressure.
--   groupSummaries: category-level counts/scores/sort-key bounds in the same category order.
--   factorSummaries: factor-level counts/scores/sort-key bounds ordered by firstSortKey.
--   subjectSummaries: subject-level counts/scores/sort-key bounds ordered by firstSortKey.
--   configSnapshot: effective soft tuning used for scoring.
export type DistrictPlacementDevaluationResult = {
	totalPenalty: number,
	penalties: { DistrictPlacementDevaluationPenalty },
	categoryTotals: { DistrictPlacementDevaluationCategoryTotal },
	groupSummaries: { DistrictPlacementDevaluationGroupSummary },
	factorSummaries: { DistrictPlacementDevaluationFactorSummary },
	subjectSummaries: { DistrictPlacementDevaluationSubjectSummary },
	configSnapshot: DistrictPlacementDevaluationConfigSnapshot,
}

export type DistrictPlacementDevaluationInvariantResult = {
	passed: boolean,
	errors: { string },
}

export type DistrictPlacementHardConfigSnapshot = {
	criticalExclusionRadii: {
		tinyfolk_spawn: number,
		escape_route: number,
		return_point: number,
		station: number,
		construction_site: number,
		capture_zone: number,
		control_zone: number,
	},
	policy: {
		allowedEnvironmentClasses: { string },
		allowedTraversalDensityClasses: { string },
		disallowedRecurringStructureTags: { string },
	},
}

export type DistrictPlacementValidationSnapshot = {
	hardConfig: DistrictPlacementHardConfigSnapshot,
	softConfig: DistrictPlacementDevaluationConfigSnapshot,
}

-- Soft scoring thresholds for Slice 7 devaluation.
-- Set a radius to 0 to disable that scoring factor.
export type DistrictPlacementSoftConfig = {
	criticalPointSoftRadius: number?,
	tinyfolkSpawnSoftRadius: number?,
	escapeRouteSoftRadius: number?,
	returnPointSoftRadius: number?,
	stationSoftRadius: number?,
	constructionSiteSoftRadius: number?,
	captureZoneSoftRadius: number?,
	controlZoneSoftRadius: number?,
	routeEdgeSoftRadius: number?,
	nearCriticalPointSoftRadius: number?,
	nearRouteEdgeSoftRadius: number?,
	penalizedTraversalDensityClasses: { string }?,
	densityPressurePenaltyScore: number?,
	openDensityPressurePenaltyScore: number?,
	sparseDensityPressurePenaltyScore: number?,
	moderateDensityPressurePenaltyScore: number?,
	denseDensityPressurePenaltyScore: number?,
}

-- District placement validation result contract:
--   accepted/rejectReasons: hard legality result and deterministic reject details.
--   devaluation: soft penalty details, summaries, invariants, and soft-config snapshot.
--   configSnapshot: legacy top-level effective hard-config snapshot.
--   validationSnapshot: unified effective hard+soft config snapshot for downstream consumers.
export type DistrictPlacementResult = {
	districtId: string,
	accepted: boolean,
	rejectReasons: { DistrictPlacementRejectReason },
	devaluation: DistrictPlacementDevaluationResult,
	configSnapshot: DistrictPlacementHardConfigSnapshot,
	validationSnapshot: DistrictPlacementValidationSnapshot,
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

local function softPenaltyCategorySortRank(category: string): string
	if category == "proximity" then
		return "01"
	elseif category == "route_pressure" then
		return "02"
	elseif category == "density_pressure" then
		return "03"
	end
	return "99"
end

local function makeSoftPenaltySortKey(
	category: string,
	factor: string,
	subjectType: string,
	subjectName: string
): string
	return softPenaltyCategorySortRank(category)
		.. ":"
		.. category
		.. "|"
		.. factor
		.. "|"
		.. subjectType
		.. "|"
		.. subjectName
end

local function sortFactorSummaries(
	left: DistrictPlacementDevaluationFactorSummary,
	right: DistrictPlacementDevaluationFactorSummary
): boolean
	if left.firstSortKey == right.firstSortKey then
		return left.factor < right.factor
	end
	return left.firstSortKey < right.firstSortKey
end

local function sortSubjectSummaries(
	left: DistrictPlacementDevaluationSubjectSummary,
	right: DistrictPlacementDevaluationSubjectSummary
): boolean
	if left.firstSortKey == right.firstSortKey then
		if left.subjectType == right.subjectType then
			return left.subjectName < right.subjectName
		end
		return left.subjectType < right.subjectType
	end
	return left.firstSortKey < right.firstSortKey
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
					message = "Soft penalty: near_critical_point subject=" .. pointName .. " reason=within_soft_radius",
					subjectType = "critical_point",
					subjectName = pointName,
					sortKey = makeSoftPenaltySortKey("proximity", "near_critical_point", "critical_point", pointName),
					districtBoxTag = box.tag,
					nearCriticalPointName = pointName,
					nearCriticalPointCategory = category,
				})
			end
			return
		end
	end
end

local function resolveDensityPressurePenaltyScore(
	softConfig: DistrictPlacementSoftConfig,
	densityClass: string
): number
	if densityClass == "open" and softConfig.openDensityPressurePenaltyScore ~= nil then
		return softConfig.openDensityPressurePenaltyScore
	elseif densityClass == "sparse" and softConfig.sparseDensityPressurePenaltyScore ~= nil then
		return softConfig.sparseDensityPressurePenaltyScore
	elseif densityClass == "moderate" and softConfig.moderateDensityPressurePenaltyScore ~= nil then
		return softConfig.moderateDensityPressurePenaltyScore
	elseif densityClass == "dense" and softConfig.denseDensityPressurePenaltyScore ~= nil then
		return softConfig.denseDensityPressurePenaltyScore
	end
	local penalizedClasses = softConfig.penalizedTraversalDensityClasses
	local sharedPenaltyScore = softConfig.densityPressurePenaltyScore or 0
	if penalizedClasses == nil or sharedPenaltyScore <= 0 then
		return 0
	end
	for _, penalizedClass in ipairs(penalizedClasses) do
		if penalizedClass == densityClass then
			return sharedPenaltyScore
		end
	end
	return 0
end

local function addDensityPressurePenalties(
	request: DistrictPlacementRequest,
	assemblyOutput: AssemblyOutput,
	softConfig: DistrictPlacementSoftConfig,
	penalties: { DistrictPlacementDevaluationPenalty }
)
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
				if meta ~= nil and meta.traversalDensityClass ~= nil then
					local penaltyScore = resolveDensityPressurePenaltyScore(softConfig, meta.traversalDensityClass)
					if penaltyScore > 0 then
						table.insert(penalties, {
							factor = "density_pressure",
							category = "density_pressure",
							score = penaltyScore,
							subjectType = "chunk_density",
							subjectName = assembledBox.placementId .. "/" .. assembledBox.chunkId,
							sortKey = makeSoftPenaltySortKey(
								"density_pressure",
								"density_pressure",
								"chunk_density",
								assembledBox.placementId .. "/" .. assembledBox.chunkId
							),
							message = "Soft penalty: density_pressure subject="
								.. assembledBox.placementId
								.. "/"
								.. assembledBox.chunkId
								.. " reason=penalized_density_class",
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
end

local function resolveCriticalPointSoftRadius(softConfig: DistrictPlacementSoftConfig, category: string): number
	local sharedRadius = softConfig.criticalPointSoftRadius or softConfig.nearCriticalPointSoftRadius or 0
	if category == "tinyfolk_spawn" and softConfig.tinyfolkSpawnSoftRadius ~= nil then
		return softConfig.tinyfolkSpawnSoftRadius
	elseif category == "escape_route" and softConfig.escapeRouteSoftRadius ~= nil then
		return softConfig.escapeRouteSoftRadius
	elseif category == "return_point" and softConfig.returnPointSoftRadius ~= nil then
		return softConfig.returnPointSoftRadius
	elseif category == "station" and softConfig.stationSoftRadius ~= nil then
		return softConfig.stationSoftRadius
	elseif category == "construction_site" and softConfig.constructionSiteSoftRadius ~= nil then
		return softConfig.constructionSiteSoftRadius
	elseif category == "capture_zone" and softConfig.captureZoneSoftRadius ~= nil then
		return softConfig.captureZoneSoftRadius
	elseif category == "control_zone" and softConfig.controlZoneSoftRadius ~= nil then
		return softConfig.controlZoneSoftRadius
	end
	return sharedRadius
end

local function buildSoftConfigSnapshot(
	softConfig: DistrictPlacementSoftConfig?
): DistrictPlacementDevaluationConfigSnapshot
	if softConfig == nil then
		return {
			criticalPointSoftRadii = {
				tinyfolk_spawn = 0,
				escape_route = 0,
				return_point = 0,
				station = 0,
				construction_site = 0,
				capture_zone = 0,
				control_zone = 0,
			},
			routeEdgeSoftRadius = 0,
			densityPressurePenaltyScores = {
				open = 0,
				sparse = 0,
				moderate = 0,
				dense = 0,
			},
		}
	end

	return {
		criticalPointSoftRadii = {
			tinyfolk_spawn = resolveCriticalPointSoftRadius(softConfig, "tinyfolk_spawn"),
			escape_route = resolveCriticalPointSoftRadius(softConfig, "escape_route"),
			return_point = resolveCriticalPointSoftRadius(softConfig, "return_point"),
			station = resolveCriticalPointSoftRadius(softConfig, "station"),
			construction_site = resolveCriticalPointSoftRadius(softConfig, "construction_site"),
			capture_zone = resolveCriticalPointSoftRadius(softConfig, "capture_zone"),
			control_zone = resolveCriticalPointSoftRadius(softConfig, "control_zone"),
		},
		routeEdgeSoftRadius = softConfig.routeEdgeSoftRadius or softConfig.nearRouteEdgeSoftRadius or 0,
		densityPressurePenaltyScores = {
			open = resolveDensityPressurePenaltyScore(softConfig, "open"),
			sparse = resolveDensityPressurePenaltyScore(softConfig, "sparse"),
			moderate = resolveDensityPressurePenaltyScore(softConfig, "moderate"),
			dense = resolveDensityPressurePenaltyScore(softConfig, "dense"),
		},
	}
end

local function copyStringList(values: { string }?): { string }
	local copy: { string } = {}
	if values == nil then
		return copy
	end
	for _, value in ipairs(values) do
		table.insert(copy, value)
	end
	return copy
end

local function buildHardConfigSnapshot(hardConfig: DistrictPlacementHardConfig): DistrictPlacementHardConfigSnapshot
	local criticalExclusion = hardConfig.criticalExclusion
	local policy = hardConfig.policy
	return {
		criticalExclusionRadii = {
			tinyfolk_spawn = if criticalExclusion ~= nil then criticalExclusion.tinyfolkSpawnExclusionRadius else 0,
			escape_route = if criticalExclusion ~= nil then criticalExclusion.escapeRouteExclusionRadius else 0,
			return_point = if criticalExclusion ~= nil then criticalExclusion.returnPointExclusionRadius else 0,
			station = if criticalExclusion ~= nil then criticalExclusion.stationExclusionRadius else 0,
			construction_site = if criticalExclusion ~= nil then criticalExclusion.constructionSiteExclusionRadius else 0,
			capture_zone = if criticalExclusion ~= nil then criticalExclusion.captureZoneExclusionRadius else 0,
			control_zone = if criticalExclusion ~= nil then criticalExclusion.controlZoneExclusionRadius else 0,
		},
		policy = {
			allowedEnvironmentClasses = if policy ~= nil then copyStringList(policy.allowedEnvironmentClasses) else {},
			allowedTraversalDensityClasses = if policy ~= nil
				then copyStringList(policy.allowedTraversalDensityClasses)
				else {},
			disallowedRecurringStructureTags = if policy ~= nil
				then copyStringList(policy.disallowedRecurringStructureTags)
				else {},
		},
	}
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
		local nearEdgeRadius = softConfig.routeEdgeSoftRadius or softConfig.nearRouteEdgeSoftRadius or 0
		local descriptor = assemblyOutput.descriptor
		local proposed = request.proposedOccupiedSpace

		-- Factor 1: near protected critical points (category: proximity).
		-- Checks the same categories as the Slice 3 hard gate.
		for _, part in ipairs(descriptor.spawns) do
			if string.find(part.name, "TinyfolkSpawn", 1, true) then
				local radius = resolveCriticalPointSoftRadius(softConfig, "tinyfolk_spawn")
				addSoftProximityPenalty(
					part.name,
					part.position,
					proposed,
					radius,
					"tinyfolk_spawn",
					"proximity",
					penalties
				)
			end
		end
		for _, part in ipairs(descriptor.escapeRoutes) do
			local radius = resolveCriticalPointSoftRadius(softConfig, "escape_route")
			addSoftProximityPenalty(part.name, part.position, proposed, radius, "escape_route", "proximity", penalties)
		end
		for _, part in ipairs(descriptor.returnPoints) do
			local radius = resolveCriticalPointSoftRadius(softConfig, "return_point")
			addSoftProximityPenalty(part.name, part.position, proposed, radius, "return_point", "proximity", penalties)
		end
		for _, part in ipairs(descriptor.stations) do
			local radius = resolveCriticalPointSoftRadius(softConfig, "station")
			addSoftProximityPenalty(part.name, part.position, proposed, radius, "station", "proximity", penalties)
		end
		for _, part in ipairs(descriptor.constructionSites) do
			local radius = resolveCriticalPointSoftRadius(softConfig, "construction_site")
			addSoftProximityPenalty(part.name, part.position, proposed, radius, "construction_site", "proximity", penalties)
		end
		for _, zone in ipairs(descriptor.captureZones) do
			local radius = resolveCriticalPointSoftRadius(softConfig, "capture_zone")
			addSoftProximityPenalty(zone.name, zone.position, proposed, radius, "capture_zone", "proximity", penalties)
		end
		for _, zone in ipairs(descriptor.controlZones) do
			local radius = resolveCriticalPointSoftRadius(softConfig, "control_zone")
			addSoftProximityPenalty(zone.name, zone.position, proposed, radius, "control_zone", "proximity", penalties)
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
												subjectType = "route_edge",
												subjectName = fromName .. "->" .. toName,
												sortKey = makeSoftPenaltySortKey(
													"route_pressure",
													"near_route_edge",
													"route_edge",
													fromName .. "->" .. toName
												),
												message = "Soft penalty: near_route_edge subject="
													.. fromName
													.. "->"
													.. toName
													.. " reason=within_soft_radius",
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
	local categoryCounts: { [string]: number } = {
		proximity = 0,
		route_pressure = 0,
		density_pressure = 0,
	}
	local categoryFirstSortKeys: { [string]: string } = {}
	local categoryLastSortKeys: { [string]: string } = {}
	local factorSummariesByFactor: { [string]: DistrictPlacementDevaluationFactorSummary } = {}
	local subjectSummariesBySubject: { [string]: DistrictPlacementDevaluationSubjectSummary } = {}
	for _, penalty in ipairs(penalties) do
		if categoryScores[penalty.category] ~= nil then
			categoryScores[penalty.category] += penalty.score
			categoryCounts[penalty.category] += 1
			local firstSortKey = categoryFirstSortKeys[penalty.category]
			local lastSortKey = categoryLastSortKeys[penalty.category]
			if firstSortKey == nil or penalty.sortKey < firstSortKey then
				categoryFirstSortKeys[penalty.category] = penalty.sortKey
			end
			if lastSortKey == nil or penalty.sortKey > lastSortKey then
				categoryLastSortKeys[penalty.category] = penalty.sortKey
			end
		end
		local factorSummary = factorSummariesByFactor[penalty.factor]
		if factorSummary == nil then
			factorSummariesByFactor[penalty.factor] = {
				factor = penalty.factor,
				penaltyCount = 1,
				totalScore = penalty.score,
				firstSortKey = penalty.sortKey,
				lastSortKey = penalty.sortKey,
			}
		else
			factorSummary.penaltyCount += 1
			factorSummary.totalScore += penalty.score
			if penalty.sortKey < factorSummary.firstSortKey then
				factorSummary.firstSortKey = penalty.sortKey
			end
			if penalty.sortKey > factorSummary.lastSortKey then
				factorSummary.lastSortKey = penalty.sortKey
			end
		end
		local subjectKey = penalty.subjectType .. "|" .. penalty.subjectName
		local subjectSummary = subjectSummariesBySubject[subjectKey]
		if subjectSummary == nil then
			subjectSummariesBySubject[subjectKey] = {
				subjectType = penalty.subjectType,
				subjectName = penalty.subjectName,
				penaltyCount = 1,
				totalScore = penalty.score,
				firstSortKey = penalty.sortKey,
				lastSortKey = penalty.sortKey,
			}
		else
			subjectSummary.penaltyCount += 1
			subjectSummary.totalScore += penalty.score
			if penalty.sortKey < subjectSummary.firstSortKey then
				subjectSummary.firstSortKey = penalty.sortKey
			end
			if penalty.sortKey > subjectSummary.lastSortKey then
				subjectSummary.lastSortKey = penalty.sortKey
			end
		end
	end
	local groupSummaries: { DistrictPlacementDevaluationGroupSummary } = {}
	for _, cat in ipairs({ "proximity", "route_pressure", "density_pressure" }) do
		table.insert(categoryTotals, {
			category = cat,
			totalScore = categoryScores[cat],
		})
		table.insert(groupSummaries, {
			category = cat,
			penaltyCount = categoryCounts[cat],
			totalScore = categoryScores[cat],
			firstSortKey = categoryFirstSortKeys[cat],
			lastSortKey = categoryLastSortKeys[cat],
		})
	end
	local factorSummaries: { DistrictPlacementDevaluationFactorSummary } = {}
	for _, summary in pairs(factorSummariesByFactor) do
		table.insert(factorSummaries, summary)
	end
	table.sort(factorSummaries, sortFactorSummaries)
	local subjectSummaries: { DistrictPlacementDevaluationSubjectSummary } = {}
	for _, summary in pairs(subjectSummariesBySubject) do
		table.insert(subjectSummaries, summary)
	end
	table.sort(subjectSummaries, sortSubjectSummaries)

	return {
		totalPenalty = totalPenalty,
		penalties = penalties,
		categoryTotals = categoryTotals,
		groupSummaries = groupSummaries,
		factorSummaries = factorSummaries,
		subjectSummaries = subjectSummaries,
		configSnapshot = buildSoftConfigSnapshot(softConfig),
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
		or config.tinyfolkSpawnSoftRadius ~= nil
		or config.escapeRouteSoftRadius ~= nil
		or config.returnPointSoftRadius ~= nil
		or config.stationSoftRadius ~= nil
		or config.constructionSiteSoftRadius ~= nil
		or config.captureZoneSoftRadius ~= nil
		or config.controlZoneSoftRadius ~= nil
		or config.routeEdgeSoftRadius ~= nil
		or config.nearCriticalPointSoftRadius ~= nil
		or config.nearRouteEdgeSoftRadius ~= nil
		or config.penalizedTraversalDensityClasses ~= nil
		or config.densityPressurePenaltyScore ~= nil
		or config.openDensityPressurePenaltyScore ~= nil
		or config.sparseDensityPressurePenaltyScore ~= nil
		or config.moderateDensityPressurePenaltyScore ~= nil
		or config.denseDensityPressurePenaltyScore ~= nil
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

local function appendInvariantError(errors: { string }, label: string)
	table.insert(errors, label)
end

local function validateSummaryScoreAndCount(
	errors: { string },
	label: string,
	actualCount: number,
	actualScore: number,
	expectedCount: number,
	expectedScore: number
)
	if actualCount ~= expectedCount then
		appendInvariantError(
			errors,
			string.format("%s penaltyCount mismatch: expected=%d actual=%d", label, expectedCount, actualCount)
		)
	end
	if actualScore ~= expectedScore then
		appendInvariantError(
			errors,
			string.format("%s totalScore mismatch: expected=%d actual=%d", label, expectedScore, actualScore)
		)
	end
end

function RealmDistrictPlacementValidator.ValidateDevaluationSummaryConsistency(
	devaluation: DistrictPlacementDevaluationResult
): DistrictPlacementDevaluationInvariantResult
	local errors: { string } = {}
	local totalScore = 0
	local categoryScores: { [string]: number } = {}
	local categoryCounts: { [string]: number } = {}
	local factorScores: { [string]: number } = {}
	local factorCounts: { [string]: number } = {}
	local subjectScores: { [string]: number } = {}
	local subjectCounts: { [string]: number } = {}
	local seenCategoryTotals: { [string]: boolean } = {}
	local seenGroupSummaries: { [string]: boolean } = {}
	local seenFactorSummaries: { [string]: boolean } = {}
	local seenSubjectSummaries: { [string]: boolean } = {}

	for _, penalty in ipairs(devaluation.penalties) do
		totalScore += penalty.score
		categoryScores[penalty.category] = (categoryScores[penalty.category] or 0) + penalty.score
		categoryCounts[penalty.category] = (categoryCounts[penalty.category] or 0) + 1
		factorScores[penalty.factor] = (factorScores[penalty.factor] or 0) + penalty.score
		factorCounts[penalty.factor] = (factorCounts[penalty.factor] or 0) + 1
		local subjectKey = penalty.subjectType .. "|" .. penalty.subjectName
		subjectScores[subjectKey] = (subjectScores[subjectKey] or 0) + penalty.score
		subjectCounts[subjectKey] = (subjectCounts[subjectKey] or 0) + 1
	end

	if devaluation.totalPenalty ~= totalScore then
		appendInvariantError(
			errors,
			string.format("totalPenalty mismatch: expected=%d actual=%d", totalScore, devaluation.totalPenalty)
		)
	end

	for _, categoryTotal in ipairs(devaluation.categoryTotals) do
		seenCategoryTotals[categoryTotal.category] = true
		local expectedScore = categoryScores[categoryTotal.category] or 0
		if categoryTotal.totalScore ~= expectedScore then
			appendInvariantError(
				errors,
				string.format(
					"categoryTotals[%s] totalScore mismatch: expected=%d actual=%d",
					categoryTotal.category,
					expectedScore,
					categoryTotal.totalScore
				)
			)
		end
	end

	for _, summary in ipairs(devaluation.groupSummaries) do
		seenGroupSummaries[summary.category] = true
		validateSummaryScoreAndCount(
			errors,
			"groupSummaries[" .. summary.category .. "]",
			summary.penaltyCount,
			summary.totalScore,
			categoryCounts[summary.category] or 0,
			categoryScores[summary.category] or 0
		)
	end

	for _, summary in ipairs(devaluation.factorSummaries) do
		seenFactorSummaries[summary.factor] = true
		validateSummaryScoreAndCount(
			errors,
			"factorSummaries[" .. summary.factor .. "]",
			summary.penaltyCount,
			summary.totalScore,
			factorCounts[summary.factor] or 0,
			factorScores[summary.factor] or 0
		)
	end

	for _, summary in ipairs(devaluation.subjectSummaries) do
		local subjectKey = summary.subjectType .. "|" .. summary.subjectName
		seenSubjectSummaries[subjectKey] = true
		validateSummaryScoreAndCount(
			errors,
			"subjectSummaries[" .. subjectKey .. "]",
			summary.penaltyCount,
			summary.totalScore,
			subjectCounts[subjectKey] or 0,
			subjectScores[subjectKey] or 0
		)
	end

	for category in pairs(categoryScores) do
		if not seenCategoryTotals[category] then
			appendInvariantError(errors, "categoryTotals missing category: " .. category)
		end
		if not seenGroupSummaries[category] then
			appendInvariantError(errors, "groupSummaries missing category: " .. category)
		end
	end
	for factor in pairs(factorScores) do
		if not seenFactorSummaries[factor] then
			appendInvariantError(errors, "factorSummaries missing factor: " .. factor)
		end
	end
	for subjectKey in pairs(subjectScores) do
		if not seenSubjectSummaries[subjectKey] then
			appendInvariantError(errors, "subjectSummaries missing subject: " .. subjectKey)
		end
	end

	return {
		passed = #errors == 0,
		errors = errors,
	}
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

	local devaluation = computeDevaluation(request, assemblyOutput, softConfig)
	local hardSnapshot = buildHardConfigSnapshot(hardConfig)

	return {
		districtId = request.districtId,
		accepted = #rejectReasons == 0,
		rejectReasons = rejectReasons,
		devaluation = devaluation,
		configSnapshot = hardSnapshot,
		validationSnapshot = {
			hardConfig = hardSnapshot,
			softConfig = devaluation.configSnapshot,
		},
	}
end

return RealmDistrictPlacementValidator
