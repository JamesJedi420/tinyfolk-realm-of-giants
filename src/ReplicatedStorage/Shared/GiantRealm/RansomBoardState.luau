--!strict

local CaptivityDurationState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("CaptivityDurationState"))
	else (require :: any)("./CaptivityDurationState")

local CapturePersistenceRules = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("CapturePersistenceRules"))
	else (require :: any)("./CapturePersistenceRules")

local RansomBoardConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("RansomBoardConfig"))
	else (require :: any)("../Config/RansomBoardConfig")

local RansomBoardState: any = {}

export type RansomTerms = {
	targetUserId: number,
	custodianUserId: number,
	settlementKind: string,
	foodCost: number,
	captivityAnchorAt: number,
	custodyExpiresAt: number,
	absoluteDeadlineAt: number,
	containmentPhase: string,
	containedAt: number?,
	remainingSeconds: number,
	offerExpiresAt: number,
	endConditions: { string },
}

export type RansomOffer = {
	offerId: string,
	terms: RansomTerms,
	postedAt: number,
}

export type State = {
	activeByOfferId: { [string]: RansomOffer? },
	activeOfferIdByTargetUserId: { [number]: string? },
	activeOfferCountByCustodianUserId: { [number]: number? },
	lastReason: string?,
}

export type TransitionResult = {
	accepted: boolean,
	reason: string,
	state: State,
	offer: RansomOffer?,
	terms: RansomTerms?,
}

local END_CONDITIONS: { string } = {
	CapturePersistenceRules.CustodyEndReasons.escaped,
	CapturePersistenceRules.CustodyEndReasons.rescued,
	CapturePersistenceRules.CustodyEndReasons.released,
	CapturePersistenceRules.CustodyEndReasons.timeout,
	CapturePersistenceRules.CustodyEndReasons.safe_return,
}

local VALID_SETTLEMENT_KINDS = {
	[RansomBoardConfig.SettlementKinds.PaymentFood] = true,
	[RansomBoardConfig.SettlementKinds.ObjectiveEscapeReady] = true,
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	return value % 1 == 0
end

local function validNow(now: any): boolean
	return isFiniteNumber(now) and (now :: number) >= 0
end

local function positiveNumber(value: any, fallback: number): number
	if not isFiniteNumber(value) or (value :: number) <= 0 then
		return fallback
	end
	return value :: number
end

local function cloneTerms(terms: RansomTerms): RansomTerms
	local endConditions: { string } = {}
	for _, endCondition in ipairs(terms.endConditions) do
		table.insert(endConditions, endCondition)
	end

	return {
		targetUserId = terms.targetUserId,
		custodianUserId = terms.custodianUserId,
		settlementKind = terms.settlementKind,
		foodCost = terms.foodCost,
		captivityAnchorAt = terms.captivityAnchorAt,
		custodyExpiresAt = terms.custodyExpiresAt,
		absoluteDeadlineAt = terms.absoluteDeadlineAt,
		containmentPhase = terms.containmentPhase,
		containedAt = terms.containedAt,
		remainingSeconds = terms.remainingSeconds,
		offerExpiresAt = terms.offerExpiresAt,
		endConditions = endConditions,
	}
end

local function cloneOffer(offer: RansomOffer): RansomOffer
	return {
		offerId = offer.offerId,
		terms = cloneTerms(offer.terms),
		postedAt = offer.postedAt,
	}
end

local function cloneState(state: State): State
	local activeByOfferId: { [string]: RansomOffer? } = {}
	for offerId, offer in pairs(state.activeByOfferId) do
		if offer ~= nil then
			activeByOfferId[offerId] = cloneOffer(offer)
		end
	end

	return {
		activeByOfferId = activeByOfferId,
		activeOfferIdByTargetUserId = table.clone(state.activeOfferIdByTargetUserId),
		activeOfferCountByCustodianUserId = table.clone(state.activeOfferCountByCustodianUserId),
		lastReason = state.lastReason,
	}
end

local function incrementCustodianCount(state: State, custodianUserId: number)
	local count = state.activeOfferCountByCustodianUserId[custodianUserId] or 0
	state.activeOfferCountByCustodianUserId[custodianUserId] = count + 1
end

local function decrementCustodianCount(state: State, custodianUserId: number)
	local count = state.activeOfferCountByCustodianUserId[custodianUserId] or 0
	if count <= 1 then
		state.activeOfferCountByCustodianUserId[custodianUserId] = nil
	else
		state.activeOfferCountByCustodianUserId[custodianUserId] = count - 1
	end
end

local function removeOfferInPlace(state: State, offer: RansomOffer)
	state.activeByOfferId[offer.offerId] = nil
	state.activeOfferIdByTargetUserId[offer.terms.targetUserId] = nil
	decrementCustodianCount(state, offer.terms.custodianUserId)
end

function RansomBoardState.NewState(): State
	return {
		activeByOfferId = {},
		activeOfferIdByTargetUserId = {},
		activeOfferCountByCustodianUserId = {},
		lastReason = nil,
	}
end

local function pruneExpiredInPlace(nextState: State, now: number)
	local expiredOfferIds: { string } = {}

	for offerId, offer in pairs(nextState.activeByOfferId) do
		if offer ~= nil and offer.terms.offerExpiresAt <= now then
			table.insert(expiredOfferIds, offerId)
		end
	end

	for _, offerId in ipairs(expiredOfferIds) do
		local offer = nextState.activeByOfferId[offerId]
		if offer ~= nil then
			removeOfferInPlace(nextState, offer)
		end
	end
end

function RansomBoardState.PruneExpired(state: State, now: number): State
	if not validNow(now) then
		return cloneState(state)
	end

	local nextState = cloneState(state)
	pruneExpiredInPlace(nextState, now)
	return nextState
end

function RansomBoardState.GetEndConditions(): { string }
	local endConditions: { string } = {}
	for _, endCondition in ipairs(END_CONDITIONS) do
		table.insert(endConditions, endCondition)
	end
	return endConditions
end

function RansomBoardState.BuildTerms(input: any, config: any?): RansomTerms?
	if type(input) ~= "table" then
		return nil
	end

	local record = input.record
	local now = input.now
	local settlementKind = input.settlementKind
	local foodCost = input.foodCost
	if type(record) ~= "table" or not validNow(now) or type(settlementKind) ~= "string" then
		return nil
	end
	if VALID_SETTLEMENT_KINDS[settlementKind] ~= true then
		return nil
	end

	local resolvedFoodCost = if isFiniteNumber(foodCost) then math.floor(foodCost) else 0
	if settlementKind == RansomBoardConfig.SettlementKinds.PaymentFood then
		local minCost =
			positiveNumber(if config ~= nil then (config :: any).MinFoodCost else nil, RansomBoardConfig.MinFoodCost)
		local maxCost =
			positiveNumber(if config ~= nil then (config :: any).MaxFoodCost else nil, RansomBoardConfig.MaxFoodCost)
		if resolvedFoodCost < minCost or resolvedFoodCost > maxCost then
			return nil
		end
	else
		resolvedFoodCost = 0
	end

	local anchorAt = if isFiniteNumber(record.captivityAnchorAt) then record.captivityAnchorAt else record.startedAt
	if not isFiniteNumber(anchorAt) or not isFiniteNumber(record.expiresAt) then
		return nil
	end

	local absoluteDeadlineAt = CaptivityDurationState.ResolveAbsoluteDeadline(record, config)
	if not isFiniteNumber(absoluteDeadlineAt) then
		return nil
	end

	local remainingSeconds = math.max(0, (absoluteDeadlineAt :: number) - (now :: number))
	if remainingSeconds <= 0 then
		return nil
	end

	local maxOfferDuration = positiveNumber(
		if config ~= nil then (config :: any).MaxOfferDurationSeconds else nil,
		RansomBoardConfig.MaxOfferDurationSeconds
	)
	local offerExpiresAt = math.min((now :: number) + maxOfferDuration, absoluteDeadlineAt :: number)
	local containmentPhase = if type(record.containmentPhase) == "string"
		then record.containmentPhase
		else CaptivityDurationState.Phases.captured

	return {
		targetUserId = record.targetUserId,
		custodianUserId = record.custodianUserId,
		settlementKind = settlementKind,
		foodCost = resolvedFoodCost,
		captivityAnchorAt = anchorAt :: number,
		custodyExpiresAt = record.expiresAt,
		absoluteDeadlineAt = absoluteDeadlineAt :: number,
		containmentPhase = containmentPhase,
		containedAt = if isFiniteNumber(record.containedAt) then record.containedAt else nil,
		remainingSeconds = remainingSeconds,
		offerExpiresAt = offerExpiresAt,
		endConditions = RansomBoardState.GetEndConditions(),
	}
end

function RansomBoardState.TermsMatchCaptureRecord(terms: any, record: any): boolean
	if type(terms) ~= "table" or type(record) ~= "table" then
		return false
	end

	if terms.targetUserId ~= record.targetUserId then
		return false
	end
	if terms.custodianUserId ~= record.custodianUserId then
		return false
	end

	local anchorAt = if isFiniteNumber(record.captivityAnchorAt) then record.captivityAnchorAt else record.startedAt
	if terms.captivityAnchorAt ~= anchorAt then
		return false
	end
	if terms.custodyExpiresAt ~= record.expiresAt then
		return false
	end

	local containmentPhase = if type(record.containmentPhase) == "string"
		then record.containmentPhase
		else CaptivityDurationState.Phases.captured
	if terms.containmentPhase ~= containmentPhase then
		return false
	end

	local containedAt = if isFiniteNumber(record.containedAt) then record.containedAt else nil
	if terms.containedAt ~= containedAt then
		return false
	end

	return true
end

function RansomBoardState.GetActiveOfferByTargetUserId(state: State, targetUserId: number): RansomOffer?
	local offerId = state.activeOfferIdByTargetUserId[targetUserId]
	if type(offerId) ~= "string" then
		return nil
	end
	local offer = state.activeByOfferId[offerId]
	if offer == nil then
		return nil
	end
	return cloneOffer(offer)
end

function RansomBoardState.GetActiveOfferByOfferId(state: State, offerId: string): RansomOffer?
	local offer = state.activeByOfferId[offerId]
	if offer == nil then
		return nil
	end
	return cloneOffer(offer)
end

function RansomBoardState.GetBoardEntries(state: State, now: number): { RansomOffer }
	local entries: { RansomOffer } = {}
	if not validNow(now) then
		return entries
	end

	for _, offer in pairs(state.activeByOfferId) do
		if offer ~= nil and offer.terms.offerExpiresAt > now then
			table.insert(entries, cloneOffer(offer))
		end
	end

	table.sort(entries, function(a: RansomOffer, b: RansomOffer): boolean
		if a.terms.offerExpiresAt ~= b.terms.offerExpiresAt then
			return a.terms.offerExpiresAt < b.terms.offerExpiresAt
		end
		return a.offerId < b.offerId
	end)

	return entries
end

function RansomBoardState.ResolvePost(state: State, input: any, config: any?): TransitionResult
	local nextState = cloneState(state)

	if type(input) ~= "table" then
		nextState.lastReason = "ransom_input_invalid"
		return { accepted = false, reason = "ransom_input_invalid", state = nextState, offer = nil, terms = nil }
	end

	local now = input.now
	local custodianUserId = input.custodianUserId
	local targetUserId = input.targetUserId
	local record = input.record
	local settlementKind = input.settlementKind
	local foodCost = input.foodCost
	local offerId = input.offerId
	local maxOffersPerCustodian = positiveNumber(
		if config ~= nil then (config :: any).MaxActiveOffersPerCustodian else nil,
		RansomBoardConfig.MaxActiveOffersPerCustodian
	)

	if not validNow(now) then
		nextState.lastReason = "ransom_now_invalid"
		return { accepted = false, reason = "ransom_now_invalid", state = nextState, offer = nil, terms = nil }
	end
	if not isPositiveInteger(custodianUserId) then
		nextState.lastReason = "custodian_user_id_invalid"
		return { accepted = false, reason = "custodian_user_id_invalid", state = nextState, offer = nil, terms = nil }
	end
	if not isPositiveInteger(targetUserId) then
		nextState.lastReason = "target_user_id_invalid"
		return { accepted = false, reason = "target_user_id_invalid", state = nextState, offer = nil, terms = nil }
	end
	if type(record) ~= "table" then
		nextState.lastReason = "capture_record_invalid"
		return { accepted = false, reason = "capture_record_invalid", state = nextState, offer = nil, terms = nil }
	end
	if record.targetUserId ~= targetUserId or record.custodianUserId ~= custodianUserId then
		nextState.lastReason = "capture_record_mismatch"
		return { accepted = false, reason = "capture_record_mismatch", state = nextState, offer = nil, terms = nil }
	end
	if type(offerId) ~= "string" or offerId == "" then
		nextState.lastReason = "offer_id_invalid"
		return { accepted = false, reason = "offer_id_invalid", state = nextState, offer = nil, terms = nil }
	end
	if VALID_SETTLEMENT_KINDS[settlementKind] ~= true then
		nextState.lastReason = "settlement_kind_invalid"
		return { accepted = false, reason = "settlement_kind_invalid", state = nextState, offer = nil, terms = nil }
	end

	pruneExpiredInPlace(nextState, now)

	if nextState.activeOfferIdByTargetUserId[targetUserId] ~= nil then
		nextState.lastReason = "ransom_offer_already_active"
		return {
			accepted = false,
			reason = "ransom_offer_already_active",
			state = nextState,
			offer = nil,
			terms = nil,
		}
	end

	local custodianOfferCount = nextState.activeOfferCountByCustodianUserId[custodianUserId] or 0
	if custodianOfferCount >= maxOffersPerCustodian then
		nextState.lastReason = "custodian_offer_cap_reached"
		return {
			accepted = false,
			reason = "custodian_offer_cap_reached",
			state = nextState,
			offer = nil,
			terms = nil,
		}
	end

	local terms = RansomBoardState.BuildTerms({
		record = record,
		now = now,
		settlementKind = settlementKind,
		foodCost = foodCost,
	}, config)
	if terms == nil then
		nextState.lastReason = "ransom_terms_invalid"
		return { accepted = false, reason = "ransom_terms_invalid", state = nextState, offer = nil, terms = nil }
	end

	local offer: RansomOffer = {
		offerId = offerId,
		terms = terms,
		postedAt = now,
	}

	nextState.activeByOfferId[offerId] = offer
	nextState.activeOfferIdByTargetUserId[targetUserId] = offerId
	incrementCustodianCount(nextState, custodianUserId)
	nextState.lastReason = "ransom_posted"

	return {
		accepted = true,
		reason = "ransom_posted",
		state = nextState,
		offer = cloneOffer(offer),
		terms = cloneTerms(terms),
	}
end

function RansomBoardState.ResolveSettle(state: State, input: any): TransitionResult
	local nextState = cloneState(state)

	if type(input) ~= "table" then
		nextState.lastReason = "ransom_input_invalid"
		return { accepted = false, reason = "ransom_input_invalid", state = nextState, offer = nil, terms = nil }
	end

	local now = input.now
	local offerId = input.offerId
	local payerUserId = input.payerUserId
	local record = input.record
	local settlementReady = input.settlementReady == true
	local canAffordFood = input.canAffordFood == true

	if not validNow(now) then
		nextState.lastReason = "ransom_now_invalid"
		return { accepted = false, reason = "ransom_now_invalid", state = nextState, offer = nil, terms = nil }
	end
	if type(offerId) ~= "string" or offerId == "" then
		nextState.lastReason = "offer_id_invalid"
		return { accepted = false, reason = "offer_id_invalid", state = nextState, offer = nil, terms = nil }
	end
	if not isPositiveInteger(payerUserId) then
		nextState.lastReason = "payer_user_id_invalid"
		return { accepted = false, reason = "payer_user_id_invalid", state = nextState, offer = nil, terms = nil }
	end
	if type(record) ~= "table" then
		nextState.lastReason = "capture_record_invalid"
		return { accepted = false, reason = "capture_record_invalid", state = nextState, offer = nil, terms = nil }
	end

	pruneExpiredInPlace(nextState, now)

	local offer = nextState.activeByOfferId[offerId]
	if offer == nil then
		nextState.lastReason = "ransom_offer_missing"
		return { accepted = false, reason = "ransom_offer_missing", state = nextState, offer = nil, terms = nil }
	end
	if offer.terms.offerExpiresAt <= now then
		removeOfferInPlace(nextState, offer)
		nextState.lastReason = "ransom_offer_expired"
		return { accepted = false, reason = "ransom_offer_expired", state = nextState, offer = nil, terms = nil }
	end
	if payerUserId == offer.terms.custodianUserId then
		nextState.lastReason = "custodian_cannot_settle_own_offer"
		return {
			accepted = false,
			reason = "custodian_cannot_settle_own_offer",
			state = nextState,
			offer = nil,
			terms = nil,
		}
	end
	if payerUserId == offer.terms.targetUserId then
		nextState.lastReason = "target_cannot_settle_own_offer"
		return {
			accepted = false,
			reason = "target_cannot_settle_own_offer",
			state = nextState,
			offer = nil,
			terms = nil,
		}
	end
	if not RansomBoardState.TermsMatchCaptureRecord(offer.terms, record) then
		nextState.lastReason = "ransom_terms_changed"
		return { accepted = false, reason = "ransom_terms_changed", state = nextState, offer = nil, terms = nil }
	end

	if offer.terms.settlementKind == RansomBoardConfig.SettlementKinds.PaymentFood then
		if not canAffordFood then
			nextState.lastReason = "insufficient_food"
			return { accepted = false, reason = "insufficient_food", state = nextState, offer = nil, terms = nil }
		end
	elseif offer.terms.settlementKind == RansomBoardConfig.SettlementKinds.ObjectiveEscapeReady then
		if not settlementReady then
			nextState.lastReason = "objective_threshold_not_met"
			return {
				accepted = false,
				reason = "objective_threshold_not_met",
				state = nextState,
				offer = nil,
				terms = nil,
			}
		end
	else
		nextState.lastReason = "settlement_kind_invalid"
		return { accepted = false, reason = "settlement_kind_invalid", state = nextState, offer = nil, terms = nil }
	end

	local settledOffer = cloneOffer(offer)
	removeOfferInPlace(nextState, offer)
	nextState.lastReason = "ransom_settled"

	return {
		accepted = true,
		reason = "ransom_settled",
		state = nextState,
		offer = settledOffer,
		terms = cloneTerms(settledOffer.terms),
	}
end

function RansomBoardState.ResolveCancel(state: State, input: any): TransitionResult
	local nextState = cloneState(state)

	if type(input) ~= "table" then
		nextState.lastReason = "ransom_input_invalid"
		return { accepted = false, reason = "ransom_input_invalid", state = nextState, offer = nil, terms = nil }
	end

	local now = input.now
	local offerId = input.offerId
	local actorUserId = input.actorUserId

	if not validNow(now) then
		nextState.lastReason = "ransom_now_invalid"
		return { accepted = false, reason = "ransom_now_invalid", state = nextState, offer = nil, terms = nil }
	end
	if type(offerId) ~= "string" or offerId == "" then
		nextState.lastReason = "offer_id_invalid"
		return { accepted = false, reason = "offer_id_invalid", state = nextState, offer = nil, terms = nil }
	end
	if not isPositiveInteger(actorUserId) then
		nextState.lastReason = "actor_user_id_invalid"
		return { accepted = false, reason = "actor_user_id_invalid", state = nextState, offer = nil, terms = nil }
	end

	pruneExpiredInPlace(nextState, now)

	local offer = nextState.activeByOfferId[offerId]
	if offer == nil then
		nextState.lastReason = "ransom_offer_missing"
		return { accepted = false, reason = "ransom_offer_missing", state = nextState, offer = nil, terms = nil }
	end
	if actorUserId ~= offer.terms.custodianUserId then
		nextState.lastReason = "ransom_cancel_unauthorized"
		return { accepted = false, reason = "ransom_cancel_unauthorized", state = nextState, offer = nil, terms = nil }
	end

	local cancelledOffer = cloneOffer(offer)
	removeOfferInPlace(nextState, offer)
	nextState.lastReason = "ransom_cancelled"

	return {
		accepted = true,
		reason = "ransom_cancelled",
		state = nextState,
		offer = cancelledOffer,
		terms = cloneTerms(cancelledOffer.terms),
	}
end

function RansomBoardState.RemovePlayer(state: State, userId: number): State
	local nextState = cloneState(state)
	local removedOfferIds: { string } = {}

	for offerId, offer in pairs(nextState.activeByOfferId) do
		if offer ~= nil then
			if offer.terms.custodianUserId == userId or offer.terms.targetUserId == userId then
				table.insert(removedOfferIds, offerId)
			end
		end
	end

	for _, offerId in ipairs(removedOfferIds) do
		local offer = nextState.activeByOfferId[offerId]
		if offer ~= nil then
			removeOfferInPlace(nextState, offer)
		end
	end

	return nextState
end

return RansomBoardState
