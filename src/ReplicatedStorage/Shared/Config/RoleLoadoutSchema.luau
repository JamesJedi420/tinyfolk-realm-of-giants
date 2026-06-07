--!strict

local RoleConfig = require("./RoleConfig")

local RoleLoadoutSchema: any = {}

export type RoleName = "Giant" | "Tinyfolk"
export type SlotType = "primary" | "secondary" | "passive" | "active" | "support"
export type SlotDefinition = {
	slotId: string,
	slotType: SlotType,
	required: boolean,
}
export type LoadoutPatternType = "cooldown" | "exhaustion" | "token" | "active_channel"

RoleLoadoutSchema.Roles = {
	Giant = RoleConfig.Roles.Giant,
	Tinyfolk = RoleConfig.Roles.Tinyfolk,
}

RoleLoadoutSchema.PatternTypes = {
	Cooldown = "cooldown",
	Exhaustion = "exhaustion",
	Token = "token",
	ActiveChannel = "active_channel",
}

RoleLoadoutSchema.TierOrder = {
	starter = 1,
	common = 2,
	uncommon = 3,
	rare = 4,
	epic = 5,
	legendary = 6,
}

RoleLoadoutSchema.MaxSelectableTierByRole = {
	[RoleConfig.Roles.Giant] = "common",
	[RoleConfig.Roles.Tinyfolk] = "common",
}

RoleLoadoutSchema.StarterUnlockSources = {
	initial = true,
}

RoleLoadoutSchema.ProgressionUnlockSources = {
	account_mastery = true,
	role_mastery = true,
	reputation = true,
	milestone = true,
	quest = true,
	achievement = true,
}

RoleLoadoutSchema.RoleSlotDefinitions = {
	[RoleConfig.Roles.Giant] = {
		{ slotId = "primary", slotType = "primary", required = false },
		{ slotId = "secondary", slotType = "secondary", required = false },
		{ slotId = "passive_1", slotType = "passive", required = false },
		{ slotId = "passive_2", slotType = "passive", required = false },
		{ slotId = "active", slotType = "active", required = false },
		{ slotId = "support", slotType = "support", required = false },
	},
	[RoleConfig.Roles.Tinyfolk] = {
		{ slotId = "primary", slotType = "primary", required = false },
		{ slotId = "secondary", slotType = "secondary", required = false },
		{ slotId = "passive_1", slotType = "passive", required = false },
		{ slotId = "passive_2", slotType = "passive", required = false },
		{ slotId = "active", slotType = "active", required = false },
		{ slotId = "support", slotType = "support", required = false },
	},
}

local function cloneSlotDefinition(source: SlotDefinition): SlotDefinition
	return {
		slotId = source.slotId,
		slotType = source.slotType,
		required = source.required,
	}
end

function RoleLoadoutSchema.IsValidRole(role: any): boolean
	return role == RoleConfig.Roles.Giant or role == RoleConfig.Roles.Tinyfolk
end

function RoleLoadoutSchema.GetMaxSelectableTier(role: any): string?
	if not RoleLoadoutSchema.IsValidRole(role) then
		return nil
	end
	return RoleLoadoutSchema.MaxSelectableTierByRole[role]
end

function RoleLoadoutSchema.GetSlotDefinitions(role: any): { SlotDefinition }
	if not RoleLoadoutSchema.IsValidRole(role) then
		return {}
	end

	local copied = {}
	for _, definition in ipairs(RoleLoadoutSchema.RoleSlotDefinitions[role]) do
		table.insert(copied, cloneSlotDefinition(definition))
	end
	return copied
end

function RoleLoadoutSchema.GetSlotIdsByType(role: any): { [string]: { string } }
	local grouped: { [string]: { string } } = {}
	for _, definition in ipairs(RoleLoadoutSchema.GetSlotDefinitions(role)) do
		if grouped[definition.slotType] == nil then
			grouped[definition.slotType] = {}
		end
		table.insert(grouped[definition.slotType], definition.slotId)
	end
	return grouped
end

function RoleLoadoutSchema.GetDefaultSelectedSlots(role: any): { [string]: string }
	if not RoleLoadoutSchema.IsValidRole(role) then
		return {}
	end
	return {}
end

function RoleLoadoutSchema.IsStarterUnlockSource(unlockSource: any): boolean
	return RoleLoadoutSchema.StarterUnlockSources[unlockSource] == true
end

function RoleLoadoutSchema.IsProgressionUnlockSource(unlockSource: any): boolean
	return RoleLoadoutSchema.ProgressionUnlockSources[unlockSource] == true
end

return RoleLoadoutSchema
