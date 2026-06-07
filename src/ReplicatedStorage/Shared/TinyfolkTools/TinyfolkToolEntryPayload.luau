--!strict

local TinyfolkToolCatalogSchema = require("../Config/TinyfolkToolCatalogSchema")
local TinyfolkToolCooldownState = require("./TinyfolkToolCooldownState")

local TinyfolkToolEntryPayload: any = {}

export type EntryToolRecord = {
	slotId: string,
	toolId: string,
	displayName: string,
	categories: { string },
	cooldownSeconds: number,
	chargesMax: number?,
	chargesRemaining: number?,
	cooldownReadyAt: number,
	tags: { string }?,
}

export type EntryPayloadRecord = {
	schemaVersion: number,
	ownerUserId: number,
	role: string,
	source: string,
	transferId: string,
	tools: { EntryToolRecord },
	validation: {
		validatedAt: number,
		catalogVersion: string?,
		loadoutStateVersion: number?,
	},
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
	if value <= 0 then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function cloneStringArray(source: { string }): { string }
	local copied = {}
	for _, value in ipairs(source) do
		table.insert(copied, value)
	end
	return copied
end

local function compareSlots(left: any, right: any): boolean
	return tostring(left.slotId) < tostring(right.slotId)
end

function TinyfolkToolEntryPayload.ValidatePayload(payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "tinyfolk_tool_entry_payload_invalid"
	end
	if payload.schemaVersion ~= 1 then
		return false, "tinyfolk_tool_entry_schema_version_invalid"
	end
	if not isPositiveInteger(payload.ownerUserId) then
		return false, "tinyfolk_tool_entry_owner_user_id_invalid"
	end
	if payload.role ~= TinyfolkToolCatalogSchema.Roles.Tinyfolk then
		return false, "tinyfolk_tool_entry_role_invalid"
	end
	if payload.source ~= "shared_hub_loadout" then
		return false, "tinyfolk_tool_entry_source_invalid"
	end
	if not isNonEmptyString(payload.transferId) then
		return false, "tinyfolk_tool_entry_transfer_id_invalid"
	end
	if type(payload.tools) ~= "table" then
		return false, "tinyfolk_tool_entry_tools_invalid"
	end
	if type(payload.validation) ~= "table" then
		return false, "tinyfolk_tool_entry_validation_invalid"
	end
	if not isFiniteNumber(payload.validation.validatedAt) then
		return false, "tinyfolk_tool_entry_validated_at_invalid"
	end

	for _, record in ipairs(payload.tools) do
		if type(record) ~= "table" then
			return false, "tinyfolk_tool_entry_tool_record_invalid"
		end
		if not isNonEmptyString(record.slotId) then
			return false, "tinyfolk_tool_entry_slot_id_invalid"
		end
		if not isNonEmptyString(record.toolId) then
			return false, "tinyfolk_tool_entry_tool_id_invalid"
		end
		if not isNonEmptyString(record.displayName) then
			return false, "tinyfolk_tool_entry_display_name_invalid"
		end
		if type(record.categories) ~= "table" or #record.categories <= 0 then
			return false, "tinyfolk_tool_entry_categories_invalid"
		end
		if not isFiniteNumber(record.cooldownSeconds) or record.cooldownSeconds < 0 then
			return false, "tinyfolk_tool_entry_cooldown_seconds_invalid"
		end
		if not isFiniteNumber(record.cooldownReadyAt) or record.cooldownReadyAt < 0 then
			return false, "tinyfolk_tool_entry_cooldown_ready_at_invalid"
		end
	end

	return true, nil
end

function TinyfolkToolEntryPayload.Build(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "entry_payload_input_invalid", payload = nil }
	end
	if not isPositiveInteger(input.ownerUserId) then
		return { accepted = false, reason = "entry_payload_owner_user_id_invalid", payload = nil }
	end
	if not isNonEmptyString(input.operationId) then
		return { accepted = false, reason = "entry_payload_operation_id_invalid", payload = nil }
	end

	local selectedBySlot = if type(input.selectedBySlot) == "table" then input.selectedBySlot else {}
	local nowAt = if isFiniteNumber(input.now) and input.now >= 0 then input.now else os.clock()
	local cooldownState = TinyfolkToolCooldownState.BuildFromSelectedLoadout(selectedBySlot, input.catalog)

	local tools = {}
	for slotId, toolId in pairs(selectedBySlot) do
		if type(slotId) ~= "string" or slotId == "" then
			return { accepted = false, reason = "entry_payload_slot_id_invalid", payload = nil }
		end
		if type(toolId) ~= "string" or toolId == "" then
			return { accepted = false, reason = "entry_payload_tool_id_invalid", payload = nil }
		end

		local toolRecord, lookupReason = TinyfolkToolCatalogSchema.GetToolRecord(toolId, input.catalog)
		if toolRecord == nil then
			return { accepted = false, reason = lookupReason or "tool_missing", payload = nil }
		end
		if toolRecord.availability ~= TinyfolkToolCatalogSchema.Availability.Available then
			return { accepted = false, reason = "tool_locked_or_unavailable", payload = nil }
		end
		if type(toolRecord.cooldown) ~= "table" then
			return { accepted = false, reason = "tool_cooldown_metadata_missing", payload = nil }
		end

		local cooldownRecord = TinyfolkToolCooldownState.GetRecord(cooldownState, toolId)

		table.insert(tools, {
			slotId = slotId,
			toolId = toolRecord.toolId,
			displayName = toolRecord.displayName,
			categories = cloneStringArray(toolRecord.categories),
			cooldownSeconds = toolRecord.cooldown.seconds,
			chargesMax = toolRecord.chargesMax,
			chargesRemaining = if type(cooldownRecord) == "table"
				then cooldownRecord.chargesRemaining
				else toolRecord.chargesMax,
			cooldownReadyAt = 0,
			tags = if type(toolRecord.tags) == "table" then cloneStringArray(toolRecord.tags) else nil,
		})
	end

	table.sort(tools, compareSlots)

	local payload: EntryPayloadRecord = {
		schemaVersion = 1,
		ownerUserId = input.ownerUserId,
		role = TinyfolkToolCatalogSchema.Roles.Tinyfolk,
		source = "shared_hub_loadout",
		transferId = string.format("tool_loadout:%d:%s", input.ownerUserId, input.operationId),
		tools = tools,
		validation = {
			validatedAt = nowAt,
			catalogVersion = TinyfolkToolCatalogSchema.CATALOG_VERSION,
			loadoutStateVersion = if type(input.loadoutStateVersion) == "number" then input.loadoutStateVersion else 1,
		},
	}

	local valid, reason = TinyfolkToolEntryPayload.ValidatePayload(payload)
	if not valid then
		return { accepted = false, reason = reason or "tinyfolk_tool_entry_payload_invalid", payload = nil }
	end

	return {
		accepted = true,
		reason = "accepted",
		payload = payload,
	}
end

return TinyfolkToolEntryPayload
