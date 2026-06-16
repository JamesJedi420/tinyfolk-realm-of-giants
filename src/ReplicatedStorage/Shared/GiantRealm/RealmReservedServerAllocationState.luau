--!strict

local LiveRealmRegistryState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("LiveRealmRegistryState"))
	else (require :: any)("./LiveRealmRegistryState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferState"))
	else (require :: any)("./RealmTransferState")

local RealmReservedServerAllocationState: any = {}

RealmReservedServerAllocationState.ENCODE_VERSION = "v1"
RealmReservedServerAllocationState.ALLOCATION_VERSION = 1

export type AllocationRecord = {
	realmId: string,
	ownerUserId: number,
	reservedAccessCode: string,
	destinationPlaceId: number,
	allocatedAt: number,
	allocationVersion: number,
}

export type MirrorRecord = AllocationRecord & {
	updatedAt: number,
}

export type EnsureResult = {
	accepted: boolean,
	reason: string,
	record: AllocationRecord?,
	created: boolean,
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

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isSafeEncodedSegment(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	if string.len(value) > 96 then
		return false
	end
	return string.match(value, "^[%w_%.%-]*$") ~= nil
end

local function isValidTimestamp(value: any): boolean
	return isFiniteNumber(value) and value >= 0
end

local function realmIdMatchesOwner(realmId: string, ownerUserId: number): boolean
	return realmId == RealmTransferState.FormatRealmId(ownerUserId)
end

function RealmReservedServerAllocationState.IsStablePlaceholderAccessCode(accessCode: any, ownerUserId: any): boolean
	if not isNonEmptyString(accessCode) or not isPositiveInteger(ownerUserId) then
		return false
	end
	return accessCode == LiveRealmRegistryState.ResolveStablePrivateServerId(ownerUserId, nil)
end

function RealmReservedServerAllocationState.IsUsableReservedAccessCode(accessCode: any, ownerUserId: any): boolean
	if not isSafeEncodedSegment(accessCode) or accessCode == "" then
		return false
	end
	if not isPositiveInteger(ownerUserId) then
		return false
	end
	return not RealmReservedServerAllocationState.IsStablePlaceholderAccessCode(accessCode, ownerUserId)
end

function RealmReservedServerAllocationState.ValidateAllocationRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "allocation_record_invalid"
	end
	if not isNonEmptyString(record.realmId) then
		return false, "allocation_realm_id_invalid"
	end
	if not isPositiveInteger(record.ownerUserId) then
		return false, "allocation_owner_user_id_invalid"
	end
	if not realmIdMatchesOwner(record.realmId, record.ownerUserId) then
		return false, "allocation_realm_owner_mismatch"
	end
	if
		not RealmReservedServerAllocationState.IsUsableReservedAccessCode(record.reservedAccessCode, record.ownerUserId)
	then
		return false, "allocation_reserved_access_code_invalid"
	end
	if not isPositiveInteger(record.destinationPlaceId) then
		return false, "allocation_destination_place_invalid"
	end
	if not isValidTimestamp(record.allocatedAt) then
		return false, "allocation_allocated_at_invalid"
	end
	if record.allocationVersion ~= RealmReservedServerAllocationState.ALLOCATION_VERSION then
		return false, "allocation_version_invalid"
	end
	return true, nil
end

function RealmReservedServerAllocationState.ValidateMirrorRecord(record: any): (boolean, string?)
	local valid, reason = RealmReservedServerAllocationState.ValidateAllocationRecord(record)
	if not valid then
		return false, reason
	end
	if not isValidTimestamp((record :: MirrorRecord).updatedAt) then
		return false, "allocation_updated_at_invalid"
	end
	return true, nil
end

function RealmReservedServerAllocationState.BuildAllocationRecord(input: any): EnsureResult
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "input_invalid",
			record = nil,
			created = false,
		}
	end
	if not isPositiveInteger(input.ownerUserId) then
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
			record = nil,
			created = false,
		}
	end
	if not isPositiveInteger(input.destinationPlaceId) then
		return {
			accepted = false,
			reason = "destination_place_invalid",
			record = nil,
			created = false,
		}
	end
	if not isValidTimestamp(input.allocatedAt) then
		return {
			accepted = false,
			reason = "allocated_at_invalid",
			record = nil,
			created = false,
		}
	end
	if
		not RealmReservedServerAllocationState.IsUsableReservedAccessCode(input.reservedAccessCode, input.ownerUserId)
	then
		return {
			accepted = false,
			reason = "reserved_access_code_invalid",
			record = nil,
			created = false,
		}
	end

	local ownerUserId = math.floor(input.ownerUserId)
	local record: AllocationRecord = {
		realmId = RealmTransferState.FormatRealmId(ownerUserId),
		ownerUserId = ownerUserId,
		reservedAccessCode = input.reservedAccessCode,
		destinationPlaceId = math.floor(input.destinationPlaceId),
		allocatedAt = input.allocatedAt,
		allocationVersion = RealmReservedServerAllocationState.ALLOCATION_VERSION,
	}
	local valid, reason = RealmReservedServerAllocationState.ValidateAllocationRecord(record)
	if not valid then
		return {
			accepted = false,
			reason = reason or "allocation_record_invalid",
			record = nil,
			created = false,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		record = record,
		created = input.created == true,
	}
end

function RealmReservedServerAllocationState.EnsureAllocation(existing: AllocationRecord?, input: any): EnsureResult
	if existing ~= nil then
		local valid, reason = RealmReservedServerAllocationState.ValidateAllocationRecord(existing)
		if valid then
			return {
				accepted = true,
				reason = "accepted",
				record = existing,
				created = false,
			}
		end
		return {
			accepted = false,
			reason = reason or "existing_allocation_invalid",
			record = nil,
			created = false,
		}
	end

	local built = RealmReservedServerAllocationState.BuildAllocationRecord(input)
	if built.accepted ~= true or built.record == nil then
		return built
	end
	return {
		accepted = true,
		reason = "accepted",
		record = built.record,
		created = true,
	}
end

function RealmReservedServerAllocationState.ToMirrorRecord(record: AllocationRecord, updatedAt: number): MirrorRecord?
	local mirror: MirrorRecord = {
		realmId = record.realmId,
		ownerUserId = record.ownerUserId,
		reservedAccessCode = record.reservedAccessCode,
		destinationPlaceId = record.destinationPlaceId,
		allocatedAt = record.allocatedAt,
		allocationVersion = record.allocationVersion,
		updatedAt = updatedAt,
	}
	local valid, _ = RealmReservedServerAllocationState.ValidateMirrorRecord(mirror)
	if not valid then
		return nil
	end
	return mirror
end

function RealmReservedServerAllocationState.EncodeMirrorRecord(record: MirrorRecord): (string?, string?)
	local valid, reason = RealmReservedServerAllocationState.ValidateMirrorRecord(record)
	if not valid then
		return nil, reason or "mirror_record_invalid"
	end
	local encoded = table.concat({
		RealmReservedServerAllocationState.ENCODE_VERSION,
		record.realmId,
		tostring(record.ownerUserId),
		record.reservedAccessCode,
		tostring(record.destinationPlaceId),
		tostring(record.allocatedAt),
		tostring(record.allocationVersion),
		tostring(record.updatedAt),
	}, "|")
	return encoded, nil
end

function RealmReservedServerAllocationState.DecodeMirrorRecord(encoded: any): (MirrorRecord?, string?)
	if type(encoded) ~= "string" or encoded == "" then
		return nil, "mirror_payload_invalid"
	end
	local parts = string.split(encoded, "|")
	if #parts ~= 8 then
		return nil, "mirror_payload_invalid"
	end
	if parts[1] ~= RealmReservedServerAllocationState.ENCODE_VERSION then
		return nil, "mirror_encode_version_invalid"
	end

	local ownerUserId = tonumber(parts[3])
	local destinationPlaceId = tonumber(parts[5])
	local allocatedAt = tonumber(parts[6])
	local allocationVersion = tonumber(parts[7])
	local updatedAt = tonumber(parts[8])
	if
		ownerUserId == nil
		or destinationPlaceId == nil
		or allocatedAt == nil
		or allocationVersion == nil
		or updatedAt == nil
	then
		return nil, "mirror_payload_invalid"
	end

	local mirror: MirrorRecord = {
		realmId = parts[2],
		ownerUserId = ownerUserId,
		reservedAccessCode = parts[4],
		destinationPlaceId = destinationPlaceId,
		allocatedAt = allocatedAt,
		allocationVersion = allocationVersion,
		updatedAt = updatedAt,
	}
	local valid, decodeReason = RealmReservedServerAllocationState.ValidateMirrorRecord(mirror)
	if not valid then
		return nil, decodeReason or "mirror_record_invalid"
	end
	return mirror, nil
end

function RealmReservedServerAllocationState.ToSaveRecord(record: AllocationRecord): any
	return {
		reservedAccessCode = record.reservedAccessCode,
		destinationPlaceId = record.destinationPlaceId,
		allocatedAt = record.allocatedAt,
	}
end

function RealmReservedServerAllocationState.FromSaveRecord(ownerUserId: number, saveRecord: any): AllocationRecord?
	if type(saveRecord) ~= "table" then
		return nil
	end
	local built = RealmReservedServerAllocationState.BuildAllocationRecord({
		ownerUserId = ownerUserId,
		reservedAccessCode = saveRecord.reservedAccessCode,
		destinationPlaceId = saveRecord.destinationPlaceId,
		allocatedAt = saveRecord.allocatedAt,
		created = false,
	})
	if built.accepted ~= true then
		return nil
	end
	return built.record
end

function RealmReservedServerAllocationState.ValidateSaveRecord(record: any, ownerUserId: any): (boolean, string?)
	if record == nil then
		return true, nil
	end
	if type(record) ~= "table" then
		return false, "realm_server_allocation_invalid"
	end
	if not isPositiveInteger(ownerUserId) then
		return false, "realm_server_allocation_owner_invalid"
	end
	if not RealmReservedServerAllocationState.IsUsableReservedAccessCode(record.reservedAccessCode, ownerUserId) then
		return false, "realm_server_allocation_access_code_invalid"
	end
	if not isPositiveInteger(record.destinationPlaceId) then
		return false, "realm_server_allocation_destination_place_invalid"
	end
	if not isValidTimestamp(record.allocatedAt) then
		return false, "realm_server_allocation_allocated_at_invalid"
	end
	return true, nil
end

function RealmReservedServerAllocationState.ValidateDispatchAdmission(entryType: any, snapshot: any): (boolean, string)
	if entryType ~= "standard" then
		return true, "accepted"
	end
	if type(snapshot) ~= "table" then
		return false, "target_realm_unavailable"
	end
	if
		snapshot.accessMode ~= LiveRealmRegistryState.AccessMode.Public
		and snapshot.accessMode ~= LiveRealmRegistryState.AccessMode.RaidEnabled
	then
		return false, "entry_access_mode_rejected"
	end
	return true, "accepted"
end

return RealmReservedServerAllocationState
