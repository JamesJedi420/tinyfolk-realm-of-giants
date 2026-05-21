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

export type ShrineSaveRecord = {
	shrineId: string,
	isActive: boolean,
	essenceTotal: number,
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
}

export type ShrinePersistenceSaveRecord = {
	shrines: { ShrineSaveRecord },
}

export type GiantRealmSaveRoot = {
	schemaVersion: number,
	ownerUserId: number,
	placedStructures: { PlacedStructureSaveRecord },
	emergencyReinforcement: EmergencyReinforcementSaveRecord?,
	shrinePersistence: ShrinePersistenceSaveRecord?,
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

local function isWholeNumber(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end

	return value % 1 == 0
end

function GiantRealmSaveSchema.ValidateShrineSaveRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "shrine_record_invalid"
	end
	if type(record.shrineId) ~= "string" or record.shrineId == "" then
		return false, "shrine_id_invalid"
	end
	if type(record.isActive) ~= "boolean" then
		return false, "shrine_is_active_invalid"
	end
	if not isFiniteNumber(record.essenceTotal) or record.essenceTotal < 0 then
		return false, "shrine_essence_total_invalid"
	end
	if not isWholeNumber(record.tickCount) or record.tickCount < 0 then
		return false, "shrine_tick_count_invalid"
	end
	if not isFiniteNumber(record.lastTickAt) or record.lastTickAt < 0 then
		return false, "shrine_last_tick_at_invalid"
	end
	if record.activatedByUserId ~= nil and not isPositiveNumber(record.activatedByUserId) then
		return false, "shrine_activated_by_user_id_invalid"
	end
	if record.isActive == true and record.activatedByUserId == nil then
		return false, "shrine_activated_by_user_id_missing"
	end

	return true, nil
end

function GiantRealmSaveSchema.ValidateShrinePersistenceRecord(record: any): (boolean, string?)
	if record == nil then
		return true, nil
	end
	if type(record) ~= "table" then
		return false, "shrine_persistence_invalid"
	end
	if type(record.shrines) ~= "table" then
		return false, "shrine_persistence_shrines_invalid"
	end

	local seenShrineIds: { [string]: boolean } = {}
	for index, shrineRecord in ipairs(record.shrines) do
		local valid, reason = GiantRealmSaveSchema.ValidateShrineSaveRecord(shrineRecord)
		if not valid then
			return false, string.format("%s index=%d", reason or "shrine_record_invalid", index)
		end

		local shrineId = shrineRecord.shrineId
		if seenShrineIds[shrineId] then
			return false, string.format("shrine_id_duplicate index=%d", index)
		end
		seenShrineIds[shrineId] = true
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

	local shrineValid, shrineReason = GiantRealmSaveSchema.ValidateShrinePersistenceRecord(root.shrinePersistence)
	if not shrineValid then
		return false, shrineReason
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

function GiantRealmSaveSchema.SerializeShrineSaveRecord(state: any): ShrineSaveRecord
	return {
		shrineId = state.shrineId,
		isActive = state.isActive == true,
		essenceTotal = state.essenceTotal,
		tickCount = state.tickCount,
		lastTickAt = state.lastTickAt,
		activatedByUserId = state.activatedByUserId,
	}
end

function GiantRealmSaveSchema.SerializeShrinePersistenceRecord(state: any): ShrinePersistenceSaveRecord?
	if state == nil then
		return nil
	end

	local shrineEntries = state.shrines
	if type(shrineEntries) ~= "table" then
		return {
			shrines = {},
		}
	end

	local shrineIds = {}
	for _, shrineState in ipairs(shrineEntries) do
		if type(shrineState) == "table" and type(shrineState.shrineId) == "string" and shrineState.shrineId ~= "" then
			table.insert(shrineIds, shrineState.shrineId)
		end
	end
	table.sort(shrineIds)

	local shrineById: { [string]: any } = {}
	for _, shrineState in ipairs(shrineEntries) do
		if type(shrineState) == "table" and type(shrineState.shrineId) == "string" then
			shrineById[shrineState.shrineId] = shrineState
		end
	end

	local serializedShrines = {}
	for _, shrineId in ipairs(shrineIds) do
		table.insert(serializedShrines, GiantRealmSaveSchema.SerializeShrineSaveRecord(shrineById[shrineId]))
	end

	return {
		shrines = serializedShrines,
	}
end

function GiantRealmSaveSchema.BuildSaveRoot(
	ownerUserId: number,
	statesById: { [string]: any },
	emergencyReinforcementState: any?,
	shrinePersistenceState: any?
): GiantRealmSaveRoot
	local root: GiantRealmSaveRoot = {
		schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
		ownerUserId = ownerUserId,
		placedStructures = GiantRealmSaveSchema.SerializePlacedStructuresById(statesById),
		emergencyReinforcement = nil,
		shrinePersistence = nil,
	}

	local reinforcementRecord = GiantRealmSaveSchema.SerializeEmergencyReinforcementRecord(emergencyReinforcementState)
	if reinforcementRecord ~= nil then
		root.emergencyReinforcement = reinforcementRecord
	end

	local shrineRecord = GiantRealmSaveSchema.SerializeShrinePersistenceRecord(shrinePersistenceState)
	if shrineRecord ~= nil then
		root.shrinePersistence = shrineRecord
	end

	return root
end

return GiantRealmSaveSchema
