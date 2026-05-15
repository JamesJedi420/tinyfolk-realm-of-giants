--!strict

local RoleConfig: any = {}

RoleConfig.Roles = {
	Giant = "Giant",
	Tinyfolk = "Tinyfolk",
}

RoleConfig.DefaultRole = RoleConfig.Roles.Tinyfolk

RoleConfig.ScaleByRole = {
	[RoleConfig.Roles.Giant] = 2.25,
	[RoleConfig.Roles.Tinyfolk] = 0.85,
}

RoleConfig.HumanoidBaseByRole = {
	[RoleConfig.Roles.Giant] = {
		maxHealth = 100,
		walkSpeed = 16,
	},
	[RoleConfig.Roles.Tinyfolk] = {
		maxHealth = 100,
		walkSpeed = 16,
	},
}

RoleConfig.RoleChangeCooldownSeconds = 0.75

RoleConfig.DownedState = {
	DefaultDurationSeconds = 30,
	MaxDurationSeconds = 60,
	SelfRecoveryCap = 0.5,
	MovementMultiplier = 0.35,
	ValidSources = {
		giant_pressure = true,
		server_test = true,
	},
	InteractionMask = {
		escapeAttempt = false,
		objectiveInteraction = false,
		toolUse = false,
		routeTraversal = false,
		throughGapReach = false,
		rescueAction = false,
		debugInspect = true,
	},
}

return RoleConfig
