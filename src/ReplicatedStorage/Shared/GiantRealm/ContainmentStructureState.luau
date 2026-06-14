--!strict

local ContainmentStructureState = {}

type Config = any

export type StructureRecord = {
	structureId: string,
	structureType: string,
	zoneId: string,
	capacity: number,
	occupantUserIds: { number },
	enabled: boolean,
	escapeInteractionEnabled: boolean,
}

export type Snapshot = {
	structureId: string,
	structureType: string,
	zoneId: string,
	capacity: number,
	occupantCount: number,
	occupantUserIds: { number },
	enabled: boolean,
	escapeInteractionEnabled: boolean,
	status: string,
	hasCapacity: boolean,
}

local function cloneOccupants(occupantUserIds: { number }): { number }
	local cloned: { number } = {}
	for _, userId in ipairs(occupantUserIds) do
		table.insert(cloned, userId)
	end
	return cloned
end

local function validUserId(userId: any): boolean
	return type(userId) == "number" and userId > 0 and userId == math.floor(userId)
end

function ContainmentStructureState.ValidateStructureType(config: Config, structureType: any): boolean
	return type(structureType) == "string" and type(config.StructureTypes[structureType]) == "table"
end

function ContainmentStructureState.ResolveStructureTypeNumber(
	config: Config,
	structureType: string,
	key: string,
	fallback: number
): number
	local catalog = config.StructureTypes[structureType]
	if type(catalog) == "table" and type(catalog[key]) == "number" then
		return catalog[key]
	end
	return fallback
end

function ContainmentStructureState.NewRecord(
	structureId: string,
	structureType: string,
	zoneId: string,
	capacity: number,
	enabled: boolean,
	escapeInteractionEnabled: boolean?,
	config: Config?
): StructureRecord
	local resolvedConfig = config or { StructureTypes = {}, DefaultCapacity = 1 }
	local resolvedCapacity = capacity
	if resolvedCapacity <= 0 then
		resolvedCapacity = ContainmentStructureState.ResolveStructureTypeNumber(
			resolvedConfig,
			structureType,
			"defaultCapacity",
			resolvedConfig.DefaultCapacity or 1
		)
	end
	local escapeEnabled = escapeInteractionEnabled == true
	if escapeEnabled ~= true then
		local catalog = resolvedConfig.StructureTypes and resolvedConfig.StructureTypes[structureType]
		escapeEnabled = type(catalog) == "table" and catalog.escapeInteractionEnabled == true
	end
	return {
		structureId = structureId,
		structureType = structureType,
		zoneId = zoneId,
		capacity = math.max(1, math.floor(resolvedCapacity)),
		occupantUserIds = {},
		enabled = enabled,
		escapeInteractionEnabled = escapeEnabled,
	}
end

function ContainmentStructureState.OccupantCount(record: StructureRecord?): number
	if record == nil then
		return 0
	end
	return #record.occupantUserIds
end

function ContainmentStructureState.ResolveStatus(config: Config, record: StructureRecord?): string
	if record == nil or record.enabled ~= true then
		return config.Status.Disabled
	end
	local count = ContainmentStructureState.OccupantCount(record)
	if count <= 0 then
		return config.Status.Ready
	end
	if count >= record.capacity then
		return config.Status.Full
	end
	return config.Status.Occupied
end

function ContainmentStructureState.Snapshot(config: Config, record: StructureRecord?): Snapshot?
	if record == nil then
		return nil
	end
	local occupantUserIds = cloneOccupants(record.occupantUserIds)
	local occupantCount = #occupantUserIds
	return {
		structureId = record.structureId,
		structureType = record.structureType,
		zoneId = record.zoneId,
		capacity = record.capacity,
		occupantCount = occupantCount,
		occupantUserIds = occupantUserIds,
		enabled = record.enabled,
		escapeInteractionEnabled = record.escapeInteractionEnabled,
		status = ContainmentStructureState.ResolveStatus(config, record),
		hasCapacity = occupantCount < record.capacity,
	}
end

function ContainmentStructureState.HasEscapeInteraction(_config: Config, record: StructureRecord?): boolean
	return record ~= nil and record.enabled == true and record.escapeInteractionEnabled == true
end

function ContainmentStructureState.IsOccupant(record: StructureRecord?, targetUserId: number): boolean
	if record == nil or not validUserId(targetUserId) then
		return false
	end
	for _, occupantUserId in ipairs(record.occupantUserIds) do
		if occupantUserId == targetUserId then
			return true
		end
	end
	return false
end

function ContainmentStructureState.AssignOccupant(record: StructureRecord?, targetUserId: number): any
	if record == nil then
		return { accepted = false, reason = "structure_missing", record = nil, snapshot = nil }
	end
	if record.enabled ~= true then
		return {
			accepted = false,
			reason = "structure_disabled",
			record = record,
			snapshot = nil,
		}
	end
	if not validUserId(targetUserId) then
		return {
			accepted = false,
			reason = "occupant_user_id_invalid",
			record = record,
			snapshot = nil,
		}
	end
	if ContainmentStructureState.IsOccupant(record, targetUserId) then
		return {
			accepted = false,
			reason = "occupant_already_assigned",
			record = record,
			snapshot = nil,
		}
	end
	if #record.occupantUserIds >= record.capacity then
		return {
			accepted = false,
			reason = "structure_capacity_full",
			record = record,
			snapshot = nil,
		}
	end

	local nextRecord: StructureRecord = {
		structureId = record.structureId,
		structureType = record.structureType,
		zoneId = record.zoneId,
		capacity = record.capacity,
		occupantUserIds = cloneOccupants(record.occupantUserIds),
		enabled = record.enabled,
		escapeInteractionEnabled = record.escapeInteractionEnabled,
	}
	table.insert(nextRecord.occupantUserIds, targetUserId)
	table.sort(nextRecord.occupantUserIds)

	return {
		accepted = true,
		reason = "accepted",
		record = nextRecord,
		snapshot = nil,
	}
end

function ContainmentStructureState.RemoveOccupant(record: StructureRecord?, targetUserId: number): any
	if record == nil then
		return { accepted = false, reason = "structure_missing", record = nil }
	end
	if not validUserId(targetUserId) then
		return { accepted = false, reason = "occupant_user_id_invalid", record = record }
	end
	if not ContainmentStructureState.IsOccupant(record, targetUserId) then
		return { accepted = false, reason = "occupant_not_found", record = record }
	end

	local nextOccupants: { number } = {}
	for _, occupantUserId in ipairs(record.occupantUserIds) do
		if occupantUserId ~= targetUserId then
			table.insert(nextOccupants, occupantUserId)
		end
	end

	local nextRecord: StructureRecord = {
		structureId = record.structureId,
		structureType = record.structureType,
		zoneId = record.zoneId,
		capacity = record.capacity,
		occupantUserIds = nextOccupants,
		enabled = record.enabled,
		escapeInteractionEnabled = record.escapeInteractionEnabled,
	}

	return {
		accepted = true,
		reason = "accepted",
		record = nextRecord,
	}
end

function ContainmentStructureState.CanRescueOccupant(
	_config: Config,
	record: StructureRecord?,
	rescuerUserId: number,
	targetUserId: number,
	rescuerAlive: boolean,
	inRange: boolean,
	_distanceStuds: number?
): any
	if record == nil then
		return { accepted = false, reason = "structure_missing" }
	end
	if not validUserId(rescuerUserId) or not validUserId(targetUserId) then
		return { accepted = false, reason = "user_id_invalid" }
	end
	if rescuerAlive ~= true then
		return { accepted = false, reason = "rescuer_not_alive" }
	end
	if inRange ~= true then
		return { accepted = false, reason = "rescuer_out_of_range" }
	end
	if not ContainmentStructureState.IsOccupant(record, targetUserId) then
		return { accepted = false, reason = "occupant_not_found" }
	end
	return { accepted = true, reason = "accepted", structureId = record.structureId }
end

return ContainmentStructureState
