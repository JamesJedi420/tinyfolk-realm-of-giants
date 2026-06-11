--!strict

local EventStateOwnershipModel: any = {}

EventStateOwnershipModel.SCHEMA_VERSION = 1

EventStateOwnershipModel.Owners = {
	playerProfile = "player_profile",
	realmProfile = "realm_profile",
	sessionRuntime = "session_runtime",
}

EventStateOwnershipModel.Outcomes = {
	capture = "capture",
	escape = "escape",
	defense = "defense",
	returnToRealm = "return",
}

local ownersByNamespace = {
	rolePreference = EventStateOwnershipModel.Owners.playerProfile,
	specialistPreference = EventStateOwnershipModel.Owners.playerProfile,
	trophyDisplayPreference = EventStateOwnershipModel.Owners.playerProfile,
	pendingRecovery = EventStateOwnershipModel.Owners.playerProfile,
	discoveredRealms = EventStateOwnershipModel.Owners.playerProfile,
	partyHistory = EventStateOwnershipModel.Owners.playerProfile,
	skillsProfileState = EventStateOwnershipModel.Owners.playerProfile,
	emergencyReinforcement = EventStateOwnershipModel.Owners.realmProfile,
	shrinePersistence = EventStateOwnershipModel.Owners.realmProfile,
	rescuePersistence = EventStateOwnershipModel.Owners.realmProfile,
	captureRuntime = EventStateOwnershipModel.Owners.sessionRuntime,
	escapeRuntime = EventStateOwnershipModel.Owners.sessionRuntime,
	defenseRuntime = EventStateOwnershipModel.Owners.sessionRuntime,
	returnRuntime = EventStateOwnershipModel.Owners.sessionRuntime,
}

local writeBackPlanByOutcome = {
	[EventStateOwnershipModel.Outcomes.capture] = {
		[EventStateOwnershipModel.Owners.playerProfile] = false,
		[EventStateOwnershipModel.Owners.realmProfile] = false,
		[EventStateOwnershipModel.Owners.sessionRuntime] = true,
		sessionAction = "apply_capture_runtime",
	},
	[EventStateOwnershipModel.Outcomes.escape] = {
		[EventStateOwnershipModel.Owners.playerProfile] = false,
		[EventStateOwnershipModel.Owners.realmProfile] = false,
		[EventStateOwnershipModel.Owners.sessionRuntime] = true,
		sessionAction = "apply_escape_runtime",
	},
	[EventStateOwnershipModel.Outcomes.defense] = {
		[EventStateOwnershipModel.Owners.playerProfile] = false,
		[EventStateOwnershipModel.Owners.realmProfile] = true,
		[EventStateOwnershipModel.Owners.sessionRuntime] = true,
		sessionAction = "apply_defense_runtime",
	},
	[EventStateOwnershipModel.Outcomes.returnToRealm] = {
		[EventStateOwnershipModel.Owners.playerProfile] = false,
		[EventStateOwnershipModel.Owners.realmProfile] = true,
		[EventStateOwnershipModel.Owners.sessionRuntime] = true,
		sessionAction = "apply_return_runtime",
	},
}

local validReconnectPhases = {
	none = true,
	active = true,
	resolved = true,
}

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local clone: any = {}
	for key, child in pairs(value) do
		clone[key] = cloneTable(child)
	end

	return clone
end

local function normalizeOwner(value: any): string?
	if type(value) ~= "string" then
		return nil
	end

	if value == EventStateOwnershipModel.Owners.playerProfile then
		return value
	end
	if value == EventStateOwnershipModel.Owners.realmProfile then
		return value
	end
	if value == EventStateOwnershipModel.Owners.sessionRuntime then
		return value
	end

	return nil
end

local function resolveOwnerKey(owner: string): string
	if owner == EventStateOwnershipModel.Owners.playerProfile then
		return "playerProfile"
	end
	if owner == EventStateOwnershipModel.Owners.realmProfile then
		return "realmProfile"
	end

	return "sessionRuntime"
end

function EventStateOwnershipModel.GetNamespaceOwners(): { [string]: string }
	return cloneTable(ownersByNamespace)
end

function EventStateOwnershipModel.GetNamespaceOwner(namespace: any): string?
	if type(namespace) ~= "string" or namespace == "" then
		return nil
	end

	local owner = ownersByNamespace[namespace]
	if type(owner) ~= "string" then
		return nil
	end

	return owner
end

function EventStateOwnershipModel.ValidateStatePartitions(partitions: any): (boolean, string?)
	if type(partitions) ~= "table" then
		return false, "state_partitions_invalid"
	end

	for namespace, _value in pairs(partitions) do
		local namespaceOwner = EventStateOwnershipModel.GetNamespaceOwner(namespace)
		if namespaceOwner == nil then
			return false, "state_partition_namespace_unknown"
		end

		local explicitOwner = normalizeOwner(partitions[namespace])
		if explicitOwner == nil then
			return false, "state_partition_owner_invalid"
		end

		if explicitOwner ~= namespaceOwner then
			return false, "state_partition_owner_mismatch"
		end
	end

	return true, nil
end

function EventStateOwnershipModel.ResolveWriteBackPlan(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "write_back_input_invalid",
		}
	end

	local outcome = input.outcome
	if type(outcome) ~= "string" or outcome == "" then
		return {
			accepted = false,
			reason = "write_back_outcome_invalid",
		}
	end

	local plan = writeBackPlanByOutcome[outcome]
	if type(plan) ~= "table" then
		return {
			accepted = false,
			reason = "write_back_outcome_unknown",
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		outcome = outcome,
		sessionAction = plan.sessionAction,
		scopes = {
			playerProfile = plan[EventStateOwnershipModel.Owners.playerProfile] == true,
			realmProfile = plan[EventStateOwnershipModel.Owners.realmProfile] == true,
			sessionRuntime = plan[EventStateOwnershipModel.Owners.sessionRuntime] == true,
		},
	}
end

function EventStateOwnershipModel.ResolveReconnectRestore(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "reconnect_input_invalid",
		}
	end

	local phase = input.phase
	if type(phase) ~= "string" or validReconnectPhases[phase] ~= true then
		return {
			accepted = false,
			reason = "reconnect_phase_invalid",
		}
	end

	if phase == "none" then
		return {
			accepted = true,
			reason = "clear_no_active_session",
			action = "clear_session_runtime",
			reapplySessionRuntime = false,
			clearSessionRuntime = true,
		}
	end

	local expectedSessionId = input.expectedSessionId
	local activeSessionId = input.activeSessionId
	if type(expectedSessionId) ~= "string" or expectedSessionId == "" then
		return {
			accepted = false,
			reason = "reconnect_expected_session_id_invalid",
		}
	end
	if type(activeSessionId) ~= "string" or activeSessionId == "" then
		return {
			accepted = false,
			reason = "reconnect_active_session_id_invalid",
		}
	end

	if expectedSessionId ~= activeSessionId then
		return {
			accepted = true,
			reason = "clear_mismatched_session",
			action = "clear_session_runtime",
			reapplySessionRuntime = false,
			clearSessionRuntime = true,
		}
	end

	if phase == "resolved" then
		return {
			accepted = true,
			reason = "clear_resolved_session",
			action = "clear_session_runtime",
			reapplySessionRuntime = false,
			clearSessionRuntime = true,
		}
	end

	if input.hasSessionRuntime == true then
		return {
			accepted = true,
			reason = "reapply_active_session",
			action = "reapply_session_runtime",
			reapplySessionRuntime = true,
			clearSessionRuntime = false,
		}
	end

	return {
		accepted = true,
		reason = "active_session_without_runtime",
		action = "skip_session_runtime",
		reapplySessionRuntime = false,
		clearSessionRuntime = false,
	}
end

function EventStateOwnershipModel.GetOwnerPartitionKey(owner: any): string?
	local normalized = normalizeOwner(owner)
	if normalized == nil then
		return nil
	end

	return resolveOwnerKey(normalized)
end

return EventStateOwnershipModel
