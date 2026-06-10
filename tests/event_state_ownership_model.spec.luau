--!strict

local EventStateOwnershipModel = require("../src/ReplicatedStorage/Shared/GiantRealm/EventStateOwnershipModel")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertFalse(value: boolean, label: string)
	if value then
		error("assertFalse failed [" .. label .. "]")
	end
end

local function run()
	assertEqual(EventStateOwnershipModel.SCHEMA_VERSION, 1, "schema version")

	do
		local namespaceOwners = EventStateOwnershipModel.GetNamespaceOwners()
		assertEqual(namespaceOwners.rolePreference, EventStateOwnershipModel.Owners.playerProfile, "role pref owner")
		assertEqual(
			namespaceOwners.specialistPreference,
			EventStateOwnershipModel.Owners.playerProfile,
			"specialist owner"
		)
		assertEqual(
			namespaceOwners.trophyDisplayPreference,
			EventStateOwnershipModel.Owners.playerProfile,
			"trophy display owner"
		)
		assertEqual(namespaceOwners.rescuePersistence, EventStateOwnershipModel.Owners.realmProfile, "rescue owner")
		assertEqual(namespaceOwners.captureRuntime, EventStateOwnershipModel.Owners.sessionRuntime, "capture owner")
		assertEqual(namespaceOwners.escapeRuntime, EventStateOwnershipModel.Owners.sessionRuntime, "escape owner")

		namespaceOwners.rolePreference = "mutated"
		assertEqual(
			EventStateOwnershipModel.GetNamespaceOwner("rolePreference"),
			EventStateOwnershipModel.Owners.playerProfile,
			"namespace owners cloned"
		)
	end

	do
		local valid, reason = EventStateOwnershipModel.ValidateStatePartitions({
			rolePreference = EventStateOwnershipModel.Owners.playerProfile,
			specialistPreference = EventStateOwnershipModel.Owners.playerProfile,
			trophyDisplayPreference = EventStateOwnershipModel.Owners.playerProfile,
			emergencyReinforcement = EventStateOwnershipModel.Owners.realmProfile,
			rescuePersistence = EventStateOwnershipModel.Owners.realmProfile,
			captureRuntime = EventStateOwnershipModel.Owners.sessionRuntime,
			escapeRuntime = EventStateOwnershipModel.Owners.sessionRuntime,
		})
		assertTrue(valid, "valid partition mapping")
		assertEqual(reason, nil, "valid partition reason")
	end

	do
		local unknownValid, unknownReason = EventStateOwnershipModel.ValidateStatePartitions({
			unknownNamespace = EventStateOwnershipModel.Owners.playerProfile,
		})
		assertFalse(unknownValid, "unknown namespace invalid")
		assertEqual(unknownReason, "state_partition_namespace_unknown", "unknown namespace reason")

		local mismatchValid, mismatchReason = EventStateOwnershipModel.ValidateStatePartitions({
			rescuePersistence = EventStateOwnershipModel.Owners.playerProfile,
		})
		assertFalse(mismatchValid, "owner mismatch invalid")
		assertEqual(mismatchReason, "state_partition_owner_mismatch", "owner mismatch reason")
	end

	do
		local outcomes = {
			EventStateOwnershipModel.Outcomes.capture,
			EventStateOwnershipModel.Outcomes.escape,
			EventStateOwnershipModel.Outcomes.defense,
			EventStateOwnershipModel.Outcomes.returnToRealm,
		}

		for _, outcome in ipairs(outcomes) do
			local plan = EventStateOwnershipModel.ResolveWriteBackPlan({ outcome = outcome })
			assertTrue(plan.accepted == true, "plan accepted " .. outcome)
			assertEqual(plan.reason, "accepted", "plan accepted reason " .. outcome)
			assertFalse(plan.scopes.playerProfile == true, "no player profile write for " .. outcome)
			assertTrue(plan.scopes.sessionRuntime == true, "session write for " .. outcome)
		end

		local capturePlan = EventStateOwnershipModel.ResolveWriteBackPlan({
			outcome = EventStateOwnershipModel.Outcomes.capture,
		})
		assertFalse(capturePlan.scopes.realmProfile == true, "capture excludes realm write")

		local escapePlan = EventStateOwnershipModel.ResolveWriteBackPlan({
			outcome = EventStateOwnershipModel.Outcomes.escape,
		})
		assertFalse(escapePlan.scopes.realmProfile == true, "escape excludes realm write")

		local defensePlan = EventStateOwnershipModel.ResolveWriteBackPlan({
			outcome = EventStateOwnershipModel.Outcomes.defense,
		})
		assertTrue(defensePlan.scopes.realmProfile == true, "defense includes realm write")

		local returnPlan = EventStateOwnershipModel.ResolveWriteBackPlan({
			outcome = EventStateOwnershipModel.Outcomes.returnToRealm,
		})
		assertTrue(returnPlan.scopes.realmProfile == true, "return includes realm write")

		local invalidPlan = EventStateOwnershipModel.ResolveWriteBackPlan({ outcome = "invalid" })
		assertFalse(invalidPlan.accepted == true, "invalid outcome rejected")
		assertEqual(invalidPlan.reason, "write_back_outcome_unknown", "invalid outcome reason")
	end

	do
		local activeRestore = EventStateOwnershipModel.ResolveReconnectRestore({
			phase = "active",
			expectedSessionId = "session_1",
			activeSessionId = "session_1",
			hasSessionRuntime = true,
		})
		assertTrue(activeRestore.accepted == true, "active restore accepted")
		assertEqual(activeRestore.reason, "reapply_active_session", "active restore reason")
		assertTrue(activeRestore.reapplySessionRuntime == true, "active restore reapplies")

		local resolvedRestore = EventStateOwnershipModel.ResolveReconnectRestore({
			phase = "resolved",
			expectedSessionId = "session_1",
			activeSessionId = "session_1",
			hasSessionRuntime = true,
		})
		assertTrue(resolvedRestore.accepted == true, "resolved restore accepted")
		assertEqual(resolvedRestore.reason, "clear_resolved_session", "resolved restore reason")
		assertTrue(resolvedRestore.clearSessionRuntime == true, "resolved restore clears")

		local mismatchRestore = EventStateOwnershipModel.ResolveReconnectRestore({
			phase = "active",
			expectedSessionId = "session_1",
			activeSessionId = "session_2",
			hasSessionRuntime = true,
		})
		assertTrue(mismatchRestore.accepted == true, "mismatch restore accepted")
		assertEqual(mismatchRestore.reason, "clear_mismatched_session", "mismatch restore reason")
		assertTrue(mismatchRestore.clearSessionRuntime == true, "mismatch restore clears")

		local noSessionRestore = EventStateOwnershipModel.ResolveReconnectRestore({ phase = "none" })
		assertTrue(noSessionRestore.accepted == true, "none restore accepted")
		assertEqual(noSessionRestore.reason, "clear_no_active_session", "none restore reason")
		assertTrue(noSessionRestore.clearSessionRuntime == true, "none restore clears")

		local invalidPhaseRestore = EventStateOwnershipModel.ResolveReconnectRestore({ phase = "bad" })
		assertFalse(invalidPhaseRestore.accepted == true, "invalid phase rejected")
		assertEqual(invalidPhaseRestore.reason, "reconnect_phase_invalid", "invalid phase reason")
	end

	do
		assertEqual(
			EventStateOwnershipModel.GetOwnerPartitionKey(EventStateOwnershipModel.Owners.playerProfile),
			"playerProfile",
			"owner partition key player"
		)
		assertEqual(
			EventStateOwnershipModel.GetOwnerPartitionKey(EventStateOwnershipModel.Owners.realmProfile),
			"realmProfile",
			"owner partition key realm"
		)
		assertEqual(
			EventStateOwnershipModel.GetOwnerPartitionKey(EventStateOwnershipModel.Owners.sessionRuntime),
			"sessionRuntime",
			"owner partition key session"
		)
		assertEqual(EventStateOwnershipModel.GetOwnerPartitionKey("invalid"), nil, "owner partition key invalid")
	end

	print("event_state_ownership_model: all checks passed")
end

run()
