--!nocheck

local LaborActionState = require("../src/ReplicatedStorage/Shared/GiantRealm/LaborActionState")
local LaborActionConfig = require("../src/ReplicatedStorage/Shared/Config/LaborActionConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

assertEqual(
	LaborActionState.ResolveActionForSpecialistRole("Woodcutter"),
	LaborActionConfig.Actions.Chop,
	"woodcutter maps to chop"
)
assertEqual(
	LaborActionState.ResolveActionForSpecialistRole("Miner"),
	LaborActionConfig.Actions.Mine,
	"miner maps to mine"
)
assertEqual(
	LaborActionState.ResolveActionForSpecialistRole("Farmer"),
	LaborActionConfig.Actions.Farm,
	"farmer maps to farm"
)
assertEqual(
	LaborActionState.ResolveActionForSpecialistRole("Worshipper"),
	LaborActionConfig.Actions.Sermon,
	"worshipper maps to sermon"
)
assertEqual(LaborActionState.ResolveActionForSpecialistRole("None"), nil, "none has no labor action")

local chopValidation = LaborActionState.ValidateWorkAction("Woodcutter", "Woodcutter")
assertTrue(chopValidation.accepted, "matching woodcutter action accepted")
assertEqual(chopValidation.laborAction, LaborActionConfig.Actions.Chop, "woodcutter validation exposes chop")

local mismatchValidation = LaborActionState.ValidateWorkAction("Miner", "Woodcutter")
assertTrue(not mismatchValidation.accepted, "miner at wood station rejected")
assertTrue(
	string.find(mismatchValidation.reason or "", "labor_action_role_mismatch", 1, true) ~= nil,
	"mismatch reason names labor_action_role_mismatch"
)

print("labor_action_state: all checks passed")
