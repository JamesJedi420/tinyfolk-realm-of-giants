--!strict

local LaborActionConfig: any = {}

LaborActionConfig.Actions = {
	Chop = "chop",
	Mine = "mine",
	Farm = "farm",
	Sermon = "sermon",
	Refine = "refine",
}

LaborActionConfig.ActionBySpecialistRole = {
	Woodcutter = LaborActionConfig.Actions.Chop,
	Miner = LaborActionConfig.Actions.Mine,
	Farmer = LaborActionConfig.Actions.Farm,
	Worshipper = LaborActionConfig.Actions.Sermon,
}

LaborActionConfig.SpecialistRoleByAction = {
	[LaborActionConfig.Actions.Chop] = "Woodcutter",
	[LaborActionConfig.Actions.Mine] = "Miner",
	[LaborActionConfig.Actions.Farm] = "Farmer",
	[LaborActionConfig.Actions.Sermon] = "Worshipper",
	[LaborActionConfig.Actions.Refine] = "Miner",
}

LaborActionConfig.LaborActionAttribute = "LaborAction"
LaborActionConfig.LaborActionStateAttribute = "LaborActionState"
LaborActionConfig.LaborActionTargetIdAttribute = "LaborActionTargetId"
LaborActionConfig.LaborActionLastReasonAttribute = "LaborActionLastReason"

return LaborActionConfig
