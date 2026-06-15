--!strict

local RansomBoardConfig: any = {}

RansomBoardConfig.MaxOfferDurationSeconds = 45
RansomBoardConfig.MinFoodCost = 1
RansomBoardConfig.MaxFoodCost = 25
RansomBoardConfig.DefaultFoodCost = 5
RansomBoardConfig.MaxActiveOffersPerCustodian = 3
RansomBoardConfig.RequestCooldownSeconds = 0.5
RansomBoardConfig.SettleRadiusStuds = 14

RansomBoardConfig.SettlementKinds = {
	PaymentFood = "payment_food",
	ObjectiveEscapeReady = "objective_escape_ready",
}

RansomBoardConfig.Remotes = {
	Post = "RansomBoardPost",
	Settle = "RansomBoardSettle",
	Cancel = "RansomBoardCancel",
	Notify = "RansomBoardNotify",
}

RansomBoardConfig.StateAttributes = {
	ActiveOfferId = "RansomBoardActiveOfferId",
	ActiveTargetUserId = "RansomBoardActiveTargetUserId",
	ActiveCustodianUserId = "RansomBoardActiveCustodianUserId",
	TermsSettlementKind = "RansomBoardTermsSettlementKind",
	TermsFoodCost = "RansomBoardTermsFoodCost",
	TermsOfferExpiresAt = "RansomBoardTermsOfferExpiresAt",
	TermsCustodyExpiresAt = "RansomBoardTermsCustodyExpiresAt",
	TermsAbsoluteDeadlineAt = "RansomBoardTermsAbsoluteDeadlineAt",
	TermsCaptivityAnchorAt = "RansomBoardTermsCaptivityAnchorAt",
	TermsContainmentPhase = "RansomBoardTermsContainmentPhase",
	TermsRemainingSeconds = "RansomBoardTermsRemainingSeconds",
	LastReason = "RansomBoardLastReason",
	NotifiedAt = "RansomBoardNotifiedAt",
}

return RansomBoardConfig
