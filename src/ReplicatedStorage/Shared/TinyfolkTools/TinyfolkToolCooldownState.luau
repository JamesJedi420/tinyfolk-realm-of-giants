--!strict

local TinyfolkToolCatalogSchema = require("../Config/TinyfolkToolCatalogSchema")

local TinyfolkToolCooldownState: any = {}

export type ToolCooldownRuntimeRecord = {
	toolId: string,
	cooldownSeconds: number,
	cooldownReadyAt: number?,
	chargesMax: number?,
	chargesRemaining: number?,
}

export type ToolCooldownStateRecord = {
	schemaVersion: number,
	byToolId: { [string]: ToolCooldownRuntimeRecord },
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

local cloneTable: (value: any) -> any
cloneTable = function(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local cloned = {}
	for key, child in pairs(value) do
		cloned[key] = cloneTable(child)
	end
	return cloned
end

function TinyfolkToolCooldownState.NewState(): ToolCooldownStateRecord
	return {
		schemaVersion = 1,
		byToolId = {},
	}
end

function TinyfolkToolCooldownState.ValidateState(state: any): (boolean, string?)
	if type(state) ~= "table" then
		return false, "tool_cooldown_state_invalid"
	end
	if state.schemaVersion ~= 1 then
		return false, "tool_cooldown_state_schema_version_invalid"
	end
	if type(state.byToolId) ~= "table" then
		return false, "tool_cooldown_state_by_tool_invalid"
	end

	for toolId, record in pairs(state.byToolId) do
		if type(toolId) ~= "string" or toolId == "" then
			return false, "tool_cooldown_state_tool_id_invalid"
		end
		if type(record) ~= "table" then
			return false, "tool_cooldown_state_record_invalid"
		end
		if record.toolId ~= toolId then
			return false, "tool_cooldown_state_record_mismatch"
		end
		if not isFiniteNumber(record.cooldownSeconds) or record.cooldownSeconds < 0 then
			return false, "tool_cooldown_seconds_invalid"
		end
		if
			record.cooldownReadyAt ~= nil
			and (not isFiniteNumber(record.cooldownReadyAt) or record.cooldownReadyAt < 0)
		then
			return false, "tool_cooldown_ready_at_invalid"
		end
		if record.chargesMax ~= nil and (not isFiniteNumber(record.chargesMax) or record.chargesMax <= 0) then
			return false, "tool_charges_max_invalid"
		end
		if
			record.chargesRemaining ~= nil
			and (not isFiniteNumber(record.chargesRemaining) or record.chargesRemaining < 0)
		then
			return false, "tool_charges_remaining_invalid"
		end
		if
			record.chargesMax ~= nil
			and record.chargesRemaining ~= nil
			and record.chargesRemaining > record.chargesMax
		then
			return false, "tool_charges_remaining_exceeds_max"
		end
	end

	return true, nil
end

function TinyfolkToolCooldownState.BuildFromSelectedLoadout(selectedBySlot: any, catalog: any?): ToolCooldownStateRecord
	local state = TinyfolkToolCooldownState.NewState()
	if type(selectedBySlot) ~= "table" then
		return state
	end

	for _, toolId in pairs(selectedBySlot) do
		if type(toolId) == "string" and toolId ~= "" and state.byToolId[toolId] == nil then
			local record = TinyfolkToolCatalogSchema.GetToolRecord(toolId, catalog)
			if record ~= nil then
				local cooldownSeconds = 0
				if type(record.cooldown) == "table" and isFiniteNumber(record.cooldown.seconds) then
					cooldownSeconds = math.max(0, record.cooldown.seconds)
				end
				state.byToolId[toolId] = {
					toolId = toolId,
					cooldownSeconds = cooldownSeconds,
					cooldownReadyAt = 0,
					chargesMax = record.chargesMax,
					chargesRemaining = record.chargesMax,
				}
			end
		end
	end

	return state
end

function TinyfolkToolCooldownState.GetRecord(state: any, toolId: any): ToolCooldownRuntimeRecord?
	if type(state) ~= "table" or type(state.byToolId) ~= "table" then
		return nil
	end
	if type(toolId) ~= "string" or toolId == "" then
		return nil
	end
	local record = state.byToolId[toolId]
	if type(record) ~= "table" then
		return nil
	end
	return cloneTable(record)
end

function TinyfolkToolCooldownState.Snapshot(state: any): ToolCooldownStateRecord
	local valid, _ = TinyfolkToolCooldownState.ValidateState(state)
	if not valid then
		return TinyfolkToolCooldownState.NewState()
	end
	return cloneTable(state)
end

return TinyfolkToolCooldownState
