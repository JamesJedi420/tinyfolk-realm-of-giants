--!strict

local RoleConfig = {}

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

return RoleConfig
