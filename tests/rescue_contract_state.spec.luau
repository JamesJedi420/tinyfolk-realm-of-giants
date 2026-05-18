--!strict

local RescueContractState = require("../src/ReplicatedStorage/Shared/GiantRealm/RescueContractState")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function makeRequestInput(overrides: any?): any
	local input = {
		now = 100,
		rescuerUserId = 1,
		targetUserId = 2,
		rescuerRole = "Tinyfolk",
		targetRole = "Tinyfolk",
		rescuerAlive = true,
		targetDowned = true,
		targetCarried = false,
		targetProtected = false,
		inRange = true,
		maxConcurrentContractsPerRescuer = 1,
		rescueWindowSeconds = 12,
	}

	if overrides ~= nil then
		for key, value in overrides do
			input[key] = value
		end
	end

	return input
end

do
	local state = RescueContractState.NewState()
	local rejected = RescueContractState.ResolveRequest(state, makeRequestInput({ rescuerRole = "Giant" }))

	assertFalse(rejected.accepted, "rescuer role gate rejects non-tinyfolk")
	assertEqual(rejected.reason, "rescuer_not_tinyfolk", "rescuer role rejection reason")
end

do
	local state = RescueContractState.NewState()
	local rejected = RescueContractState.ResolveRequest(state, makeRequestInput({ targetDowned = false }))

	assertFalse(rejected.accepted, "target must be downed")
	assertEqual(rejected.reason, "target_not_downed", "target downed rejection reason")
end

do
	local state = RescueContractState.NewState()
	local accepted = RescueContractState.ResolveRequest(state, makeRequestInput())

	assertTrue(accepted.accepted, "valid request accepted")
	assertEqual(accepted.reason, "accepted", "accepted reason")
	assertEqual(accepted.contract.rescuerUserId, 1, "accepted contract stores rescuer")
	assertEqual(accepted.contract.targetUserId, 2, "accepted contract stores target")

	local second = RescueContractState.ResolveRequest(accepted.state, makeRequestInput({ now = 101 }))
	assertFalse(second.accepted, "rescuer cannot hold multiple contracts")
	assertEqual(second.reason, "rescuer_contract_active", "second request rejection reason")

	local complete = RescueContractState.ResolveComplete(accepted.state, {
		now = 102,
		rescuerUserId = 1,
		targetUserId = 2,
	})
	assertTrue(complete.accepted, "complete resolves active contract")
	assertEqual(complete.reason, "rescued", "complete reason")
	assertEqual(RescueContractState.GetRescuerContract(complete.state, 1), nil, "contract removed after completion")
end

print("rescue_contract_state: all checks passed")
