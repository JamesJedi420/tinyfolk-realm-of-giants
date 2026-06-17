--!strict

local RealmEntryPortalConfig: any = {}

RealmEntryPortalConfig.RequestCooldownSeconds = 0.5
RealmEntryPortalConfig.RefreshCoalesceSeconds = 1.0
RealmEntryPortalConfig.DefaultListLimit = 20
RealmEntryPortalConfig.MaxListLimit = 50
RealmEntryPortalConfig.OwnerDisplayNameCacheMax = 64
RealmEntryPortalConfig.PartyIdPrefix = "realm_portal:"

RealmEntryPortalConfig.PortalNamePrefix = "RealmPortalHub_"
RealmEntryPortalConfig.DefaultPortalId = "RealmPortalHub_A"
RealmEntryPortalConfig.InteractionRangeStuds = 16
RealmEntryPortalConfig.OpenRequestAttribute = "RealmEntryPortalOpenRequested"

RealmEntryPortalConfig.EntryMethods = {
	Portal = "portal",
	Contract = "contract",
	Raid = "raid",
	Invitation = "invitation",
}

RealmEntryPortalConfig.EntryRoles = {
	Guest = "guest",
	Raider = "raider",
	Worker = "worker",
	Scout = "scout",
	PrisonerTransfer = "prisoner_transfer",
}

RealmEntryPortalConfig.Remotes = {
	ListRequest = "RealmEntryPortalListRequest",
	ListResponse = "RealmEntryPortalListResponse",
	EnterRequest = "RealmEntryPortalEnterRequest",
	EnterResponse = "RealmEntryPortalEnterResponse",
	Notify = "RealmEntryPortalNotify",
}

RealmEntryPortalConfig.EntryMethodLabels = {
	portal = "Portal",
	contract = "Contract",
	raid = "Raid",
	invitation = "Invitation",
}

RealmEntryPortalConfig.EntryRoleLabels = {
	guest = "Guest",
	raider = "Raider",
	worker = "Worker",
	scout = "Scout",
	prisoner_transfer = "Prisoner Transfer",
}

RealmEntryPortalConfig.AccessModeLabels = {
	public = "Open Visit",
	raid_enabled = "Raid Entry",
	invite_only = "Invitation",
}

RealmEntryPortalConfig.DebugOpenKeyName = "P"

return RealmEntryPortalConfig
