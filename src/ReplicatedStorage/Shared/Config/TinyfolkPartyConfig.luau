--!strict

local TinyfolkPartyConfig: any = {}

TinyfolkPartyConfig.RequestCooldownSeconds = 0.25
TinyfolkPartyConfig.MaxPartySize = 4
TinyfolkPartyConfig.PartyIdPrefix = "tinyfolk_party:"
TinyfolkPartyConfig.DebugOpenKeyName = "P"
TinyfolkPartyConfig.DisconnectGraceSeconds = 30

TinyfolkPartyConfig.Actions = {
	Create = "create",
	Invite = "invite",
	AcceptInvite = "accept_invite",
	DeclineInvite = "decline_invite",
	Leave = "leave",
	SetReady = "set_ready",
}

TinyfolkPartyConfig.Remotes = {
	ActionRequest = "TinyfolkPartyActionRequest",
	ActionResponse = "TinyfolkPartyActionResponse",
	Notify = "TinyfolkPartyNotify",
}

TinyfolkPartyConfig.StateAttributes = {
	PartyId = "RealmAdmissionPartyId",
	IsLeader = "TinyfolkPartyIsLeader",
	IsReady = "TinyfolkPartyIsReady",
	LastReason = "TinyfolkPartyLastReason",
}

return TinyfolkPartyConfig
