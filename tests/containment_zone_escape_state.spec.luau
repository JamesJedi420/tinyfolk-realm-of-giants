--!nocheck

local ContainmentZoneEscapeState = require("../src/ReplicatedStorage/Shared/GiantRealm/ContainmentZoneEscapeState")
local ContainmentStructureConfig = require("../src/ReplicatedStorage/Shared/Config/ContainmentStructureConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

do
	local state = ContainmentZoneEscapeState.NewState(ContainmentStructureConfig, 0)
	assertEqual(state.progress, 0, "new state progress")
	assertEqual(state.required, 5, "new state required")
end

do
	local state = ContainmentZoneEscapeState.NewState(ContainmentStructureConfig, 0)
	local first = ContainmentZoneEscapeState.ResolveEscapeAction(state, 1, ContainmentStructureConfig)
	assertTrue(first.accepted, "first escape action accepts")
	assertEqual(first.state.progress, 1, "first action increments progress")
	assertEqual(first.completed, false, "first action not complete")

	local cooled = ContainmentZoneEscapeState.ResolveEscapeAction(first.state, 1.1, ContainmentStructureConfig)
	assertEqual(cooled.reason, "request_cooldown", "cooldown rejects immediate repeat")

	local second = ContainmentZoneEscapeState.ResolveEscapeAction(first.state, 1.5, ContainmentStructureConfig)
	assertTrue(second.accepted, "second escape action accepts after cooldown")
	assertEqual(second.state.progress, 2, "second action increments progress")
end

do
	local state = ContainmentZoneEscapeState.NewState(ContainmentStructureConfig, 0)
	local current = state
	for step = 1, 4 do
		local result = ContainmentZoneEscapeState.ResolveEscapeAction(current, step, ContainmentStructureConfig)
		current = result.state
	end
	local complete = ContainmentZoneEscapeState.ResolveEscapeAction(current, 10, ContainmentStructureConfig)
	assertTrue(complete.completed, "fifth action completes escape progress")
	assertEqual(complete.reason, "contained_escape_completed", "completion reason")
end

print("containment_zone_escape_state: all checks passed")
