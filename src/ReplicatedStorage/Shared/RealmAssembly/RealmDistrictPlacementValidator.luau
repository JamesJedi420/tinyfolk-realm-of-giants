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
}

-- The result of validating a single district placement request.
export type DistrictPlacementResult = {
	districtId: string,
	accepted: boolean,
	rejectReasons: { DistrictPlacementRejectReason },
}

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
			message = "Proposed district blocks all assembled escape routes: "
				.. table.concat(blockedNames, ", "),
			districtBoxTag = nil,
			conflictingPlacementId = nil,
			conflictingChunkId = nil,
			conflictingBoxTag = nil,
			isLandmarkConflict = false,
		})
	end
end

-- Validate a district placement request against an assembled realm output.
-- Runs all active gate checks in a single deterministic pass:
--   Slice 1: occupied-space and landmark exclusion
--   Slice 2: route/escape preservation
function RealmDistrictPlacementValidator.ValidatePlacement(
	request: DistrictPlacementRequest,
	assemblyOutput: RealmChunkAssemblySchema.AssemblyOutput
): DistrictPlacementResult
	local rejectReasons: { DistrictPlacementRejectReason } = {}

	checkOccupiedSpaceExclusion(request, assemblyOutput, rejectReasons)
	checkRouteEscapePreservation(request, assemblyOutput, rejectReasons)

	return {
		districtId = request.districtId,
		accepted = #rejectReasons == 0,
		rejectReasons = rejectReasons,
	}
end

return RealmDistrictPlacementValidator

