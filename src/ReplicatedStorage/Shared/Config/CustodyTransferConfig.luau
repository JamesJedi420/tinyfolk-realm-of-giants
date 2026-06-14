--!strict

local CustodyTransferConfig: any = {}

CustodyTransferConfig.RequestExpirySeconds = 20
CustodyTransferConfig.ConfirmRadiusStuds = 14
CustodyTransferConfig.RequestCooldownSeconds = 0.5

CustodyTransferConfig.Remotes = {
	Request = "CustodyTransferRequest",
	Confirm = "CustodyTransferConfirm",
	Cancel = "CustodyTransferCancel",
	Notify = "CustodyTransferNotify",
}

CustodyTransferConfig.StateAttributes = {
	PendingRequestId = "CustodyTransferPendingRequestId",
	PendingOutgoingCustodianUserId = "CustodyTransferPendingOutgoingCustodianUserId",
	PendingIncomingCustodianUserId = "CustodyTransferPendingIncomingCustodianUserId",
	PendingTargetUserId = "CustodyTransferPendingTargetUserId",
	PendingExpiresAt = "CustodyTransferPendingExpiresAt",
	TermsCustodyExpiresAt = "CustodyTransferTermsCustodyExpiresAt",
	TermsAbsoluteDeadlineAt = "CustodyTransferTermsAbsoluteDeadlineAt",
	TermsCaptivityAnchorAt = "CustodyTransferTermsCaptivityAnchorAt",
	TermsContainmentPhase = "CustodyTransferTermsContainmentPhase",
	TermsRemainingSeconds = "CustodyTransferTermsRemainingSeconds",
	LastReason = "CustodyTransferLastReason",
	NotifiedAt = "CustodyTransferNotifiedAt",
}

return CustodyTransferConfig
