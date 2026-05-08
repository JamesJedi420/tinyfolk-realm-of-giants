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

-- Validate a district placement request against an assembled realm output.
-- Rejects if any proposed box overlaps any assembled resolved occupied box.
-- Rejects with isLandmarkConflict=true when the conflicting box belongs to a
-- landmark-anchored chunk (resolvedMetadataByPlacement marks isLandmarkAnchor=true).
function RealmDistrictPlacementValidator.ValidatePlacement(
	request: DistrictPlacementRequest,
	assemblyOutput: RealmChunkAssemblySchema.AssemblyOutput
): DistrictPlacementResult
	local rejectReasons: { DistrictPlacementRejectReason } = {}

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

	return {
		districtId = request.districtId,
		accepted = #rejectReasons == 0,
		rejectReasons = rejectReasons,
	}
end

return RealmDistrictPlacementValidator
