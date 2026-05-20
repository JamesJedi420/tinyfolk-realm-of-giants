--!strict

local GiantRealmSaveSchema: any = {}

GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION = 1

export type Vector3Data = {
	x: number,
	y: number,
	z: number,
}

export type OccupiedSpaceBoxRecord = {
	tag: string?,
	worldCenter: Vector3Data,
	halfExtents: Vector3Data,
}

export type PlacedStructureSaveRecord = {
	structureId: string,
	placedByUserId: number,
	placedAt: number,
	proposedOccupiedSpace: { OccupiedSpaceBoxRecord },
}

export type EmergencyReinforcementSaveRecord = {
	used: boolean,
	callStartedAt: number?,
	cooldownEndsAt: number?,
	triggeredByUserId: number?,
	spawnedUserId: number?,
	lastReason: string?,
	lastObjectiveId: string?,
}

export type GiantRealmSaveRoot = {
	schemaVersion: number,
	ownerUserId: number,
	placedStructures: { PlacedStructureSaveRecord },
	emergencyReinforcement: EmergencyReinforcementSaveRecord?,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveNumber(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	return value > 0
end

local function isVector3Data(value: any): boolean
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

local function copyVector3Data(value: Vector3Data): Vector3Data
	return {
		x = value.x,
		y = value.y,
		z = value.z,
	}
end

local function copyOccupiedSpace(source: { OccupiedSpaceBoxRecord }): { OccupiedSpaceBoxRecord }
	local copied = {}
	for _, box in ipairs(source) do
		local copiedBox: OccupiedSpaceBoxRecord = {
			tag = nil,
			worldCenter = copyVector3Data(box.worldCenter),
			halfExtents = copyVector3Data(box.halfExtents),
		}
		if box.tag ~= nil then
			copiedBox.tag = box.tag
		end
		table.insert(copied, copiedBox)
	end
	return copied
end

function GiantRealmSaveSchema.ValidateOccupiedSpaceBox(box: any): (boolean, string?)
	if type(box) ~= "table" then
		return false, "occupied_space_box_malformed"
	end
	if box.tag ~= nil and type(box.tag) ~= "string" then
		return false, "occupied_space_box_tag_invalid"
	end
	if not isVector3Data(box.worldCenter) then
		return false, "occupied_space_box_world_center_invalid"
	end
	if not isVector3Data(box.halfExtents) then
		return false, "occupied_space_box_half_extents_invalid"
	end
	if box.halfExtents.x <= 0 or box.halfExtents.y <= 0 or box.halfExtents.z <= 0 then
		return false, "occupied_space_box_half_extents_invalid"
	end
	return true, nil
end

function GiantRealmSaveSchema.ValidateOccupiedSpace(occupiedSpace: any): (boolean, string?)
	if type(occupiedSpace) ~= "table" then
		return false, "placed_structure_occupied_space_invalid"
	end
	if #occupiedSpace < 1 then
		return false, "placed_structure_occupied_space_empty"
	end
	for index, box in ipairs(occupiedSpace) do
		local valid, reason = GiantRealmSaveSchema.ValidateOccupiedSpaceBox(box)
		if not valid then
			return false, string.format("%s index=%d", reason or "occupied_space_box_invalid", index)
		end
	end
	return true, nil
end

function GiantRealmSaveSchema.ValidatePlacedStructureRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "placed_structure_record_invalid"
	end
	if type(record.structureId) ~= "string" or record.structureId == "" then
		return false, "placed_structure_structure_id_invalid"
	end
	if not isPositiveNumber(record.placedByUserId) then
		return false, "placed_structure_placed_by_user_id_invalid"
	end
	if not isFiniteNumber(record.placedAt) or record.placedAt < 0 then
		return false, "placed_structure_placed_at_invalid"
	end

	local occupiedSpaceValid, occupiedSpaceReason =
		GiantRealmSaveSchema.ValidateOccupiedSpace(record.proposedOccupiedSpace)
	if not occupiedSpaceValid then
		return false, occupiedSpaceReason
	end

	return true, nil
end

function GiantRealmSaveSchema.ValidateEmergencyReinforcementRecord(record: any): (boolean, string?)
	if record == nil then
		return true, nil
	end
	if type(record) ~= "table" then
		return false, "emergency_reinforcement_record_invalid"
	end
	if type(record.used) ~= "boolean" then
		return false, "emergency_reinforcement_used_invalid"
	end
	if record.callStartedAt ~= nil and not isFiniteNumber(record.callStartedAt) then
		return false, "emergency_reinforcement_call_started_at_invalid"
	end
	if record.cooldownEndsAt ~= nil and not isFiniteNumber(record.cooldownEndsAt) then
		return false, "emergency_reinforcement_cooldown_ends_at_invalid"
	end
	if record.triggeredByUserId ~= nil and not isPositiveNumber(record.triggeredByUserId) then
		return false, "emergency_reinforcement_triggered_by_user_id_invalid"
	end
	if record.spawnedUserId ~= nil and not isPositiveNumber(record.spawnedUserId) then
		return false, "emergency_reinforcement_spawned_user_id_invalid"
	end
	if record.lastReason ~= nil and type(record.lastReason) ~= "string" then
		return false, "emergency_reinforcement_last_reason_invalid"
	end
	if record.lastObjectiveId ~= nil and type(record.lastObjectiveId) ~= "string" then
		return false, "emergency_reinforcement_last_objective_id_invalid"
	end
	return true, nil
end

function GiantRealmSaveSchema.ValidateSaveRoot(root: any): (boolean, string?)
	if type(root) ~= "table" then
		return false, "save_root_invalid"
	end
	if root.schemaVersion ~= GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION then
		return false, "save_root_schema_version_invalid"
	end
	if not isPositiveNumber(root.ownerUserId) then
		return false, "save_root_owner_user_id_invalid"
	end
	if type(root.placedStructures) ~= "table" then
		return false, "save_root_placed_structures_invalid"
	end

	for index, record in ipairs(root.placedStructures) do
		local valid, reason = GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		if not valid then
			return false, string.format("%s index=%d", reason or "placed_structure_record_invalid", index)
		end
	end

	local reinforcementValid, reinforcementReason =
		GiantRealmSaveSchema.ValidateEmergencyReinforcementRecord(root.emergencyReinforcement)
	if not reinforcementValid then
		return false, reinforcementReason
	end

	return true, nil
end

function GiantRealmSaveSchema.SerializePlacedStructureRecord(state: any): PlacedStructureSaveRecord
	return {
		structureId = state.structureId,
		placedByUserId = state.placedByUserId,
		placedAt = state.placedAt,
		proposedOccupiedSpace = copyOccupiedSpace(state.proposedOccupiedSpace),
	}
end

function GiantRealmSaveSchema.SerializePlacedStructuresById(
	statesById: { [string]: any }
): { PlacedStructureSaveRecord }
	local structureIds = {}
	for structureId in pairs(statesById) do
		table.insert(structureIds, structureId)
	end
	table.sort(structureIds)

	local records = {}
	for _, structureId in ipairs(structureIds) do
		table.insert(records, GiantRealmSaveSchema.SerializePlacedStructureRecord(statesById[structureId]))
	end
	return records
end

function GiantRealmSaveSchema.SerializeEmergencyReinforcementRecord(state: any): EmergencyReinforcementSaveRecord?
	if state == nil then
		return nil
	end

	return {
		used = state.used == true,
		callStartedAt = state.callStartedAt,
		cooldownEndsAt = state.cooldownEndsAt,
		triggeredByUserId = state.triggeredByUserId,
		spawnedUserId = state.spawnedUserId,
		lastReason = state.lastReason,
		lastObjectiveId = state.lastObjectiveId,
	}
end

function GiantRealmSaveSchema.BuildSaveRoot(
	ownerUserId: number,
	statesById: { [string]: any },
	emergencyReinforcementState: any?
): GiantRealmSaveRoot
	local root: GiantRealmSaveRoot = {
		schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
		ownerUserId = ownerUserId,
		placedStructures = GiantRealmSaveSchema.SerializePlacedStructuresById(statesById),
		emergencyReinforcement = nil,
	}

	local reinforcementRecord = GiantRealmSaveSchema.SerializeEmergencyReinforcementRecord(emergencyReinforcementState)
	if reinforcementRecord ~= nil then
		root.emergencyReinforcement = reinforcementRecord
	end

	return root
end

return GiantRealmSaveSchema
