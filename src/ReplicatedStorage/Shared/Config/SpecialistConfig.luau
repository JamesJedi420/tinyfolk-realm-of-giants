--!strict

local SpecialistConfig = {}

SpecialistConfig.RequestCooldownSeconds = 0.2

SpecialistConfig.SpecialistRoles = {
	None = "None",
	Woodcutter = "Woodcutter",
	Miner = "Miner",
	Farmer = "Farmer",
	Worshipper = "Worshipper",
}

SpecialistConfig.AssignmentReasons = {
	Initial = "Initial",
	Assigned = "Assigned",
	ClearedManual = "ClearedManual",
	ClearedRoleChange = "ClearedRoleChange",
	JobScheduled = "JobScheduled",
}

return SpecialistConfig
