--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local RansomBoardConfig = require(Config:WaitForChild("RansomBoardConfig"))
local RansomBoardState = require(GiantRealm:WaitForChild("RansomBoardState"))
local ResourceFlowState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ResourceFlowState"))
	else (require :: any)("./ResourceFlowState")

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_ATTRIBUTE = "Role"
local globalEnv: any = getfenv()

local state = RansomBoardState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local offerSequenceByTargetUserId: { [number]: number? } = {}
local notifyRemote: RemoteEvent? = nil

local function now(): number
	return os.clock()
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return false
	end
	return humanoid.Health > 0
end

local function resolveMagnitude(delta: any): number?
	if delta == nil then
		return nil
	end
	local magnitudeValue = (delta :: any).Magnitude
	if type(magnitudeValue) == "number" then
		return magnitudeValue
	end
	if type(magnitudeValue) == "function" then
		return (delta :: any):Magnitude()
	end
	return nil
end

local function getDistanceBetweenPlayers(a: Player, b: Player): number?
	local aRoot = getHumanoidRootPart(a)
	local bRoot = getHumanoidRootPart(b)
	if aRoot == nil or bRoot == nil then
		return nil
	end
	return resolveMagnitude((aRoot :: BasePart).Position - (bRoot :: BasePart).Position)
end

local function isInRangeOfTarget(actor: Player, target: Player, radiusStuds: number): boolean
	local distance = getDistanceBetweenPlayers(actor, target)
	if distance == nil then
		return false
	end
	return distance <= radiusStuds
end

local function getCaptureServiceQueryApi(): any?
	local queryApi = globalEnv._CaptureService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._CaptureService_QueryAPI) == "table" then
		return (_G :: any)._CaptureService_QueryAPI
	end
	return nil
end

local function getRealmObjectiveQueryApi(): any?
	local queryApi = globalEnv._RealmObjectiveService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._RealmObjectiveService_QueryAPI) == "table" then
		return (_G :: any)._RealmObjectiveService_QueryAPI
	end
	return nil
end

local function getRuntimeEventLogQueryApi(): any?
	local queryApi = globalEnv._RuntimeEventLogService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	queryApi = globalEnv._EventLogService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._RuntimeEventLogService_QueryAPI) == "table" then
		return (_G :: any)._RuntimeEventLogService_QueryAPI
	end
	if type(_G) == "table" and type((_G :: any)._EventLogService_QueryAPI) == "table" then
		return (_G :: any)._EventLogService_QueryAPI
	end
	return nil
end

local function getRepeatedTargetingAbuseQueryApi(): any?
	local queryApi = globalEnv._RepeatedTargetingAbuseService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._RepeatedTargetingAbuseService_QueryAPI) == "table" then
		return (_G :: any)._RepeatedTargetingAbuseService_QueryAPI
	end
	return nil
end

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end
	return (at - last) < RansomBoardConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number)
	lastRequestAtByUserId[userId] = at
end

local function setRansomLastReason(player: Player?, reason: string)
	if player == nil then
		return
	end
	player:SetAttribute(RansomBoardConfig.StateAttributes.LastReason, reason)
end

local function clearRansomAttributes(player: Player?)
	if player == nil then
		return
	end

	local attrs = RansomBoardConfig.StateAttributes
	player:SetAttribute(attrs.ActiveOfferId, nil)
	player:SetAttribute(attrs.ActiveTargetUserId, nil)
	player:SetAttribute(attrs.ActiveCustodianUserId, nil)
	player:SetAttribute(attrs.TermsSettlementKind, nil)
	player:SetAttribute(attrs.TermsFoodCost, nil)
	player:SetAttribute(attrs.TermsOfferExpiresAt, nil)
	player:SetAttribute(attrs.TermsCustodyExpiresAt, nil)
	player:SetAttribute(attrs.TermsAbsoluteDeadlineAt, nil)
	player:SetAttribute(attrs.TermsCaptivityAnchorAt, nil)
	player:SetAttribute(attrs.TermsContainmentPhase, nil)
	player:SetAttribute(attrs.TermsRemainingSeconds, nil)
	player:SetAttribute(attrs.NotifiedAt, nil)
end

local function projectOfferAttributes(offer: any)
	if type(offer) ~= "table" or type(offer.terms) ~= "table" then
		return
	end

	local terms = offer.terms
	local attrs = RansomBoardConfig.StateAttributes
	local players = {
		getPlayerByUserId(terms.targetUserId),
		getPlayerByUserId(terms.custodianUserId),
	}

	for _, player in ipairs(players) do
		if player ~= nil then
			player:SetAttribute(attrs.ActiveOfferId, offer.offerId)
			player:SetAttribute(attrs.ActiveTargetUserId, terms.targetUserId)
			player:SetAttribute(attrs.ActiveCustodianUserId, terms.custodianUserId)
			player:SetAttribute(attrs.TermsSettlementKind, terms.settlementKind)
			player:SetAttribute(attrs.TermsFoodCost, terms.foodCost)
			player:SetAttribute(attrs.TermsOfferExpiresAt, terms.offerExpiresAt)
			player:SetAttribute(attrs.TermsCustodyExpiresAt, terms.custodyExpiresAt)
			player:SetAttribute(attrs.TermsAbsoluteDeadlineAt, terms.absoluteDeadlineAt)
			player:SetAttribute(attrs.TermsCaptivityAnchorAt, terms.captivityAnchorAt)
			player:SetAttribute(attrs.TermsContainmentPhase, terms.containmentPhase)
			player:SetAttribute(attrs.TermsRemainingSeconds, terms.remainingSeconds)
		end
	end
end

local function clearOfferAttributesForOffer(offer: any)
	if type(offer) ~= "table" or type(offer.terms) ~= "table" then
		return
	end

	clearRansomAttributes(getPlayerByUserId(offer.terms.targetUserId))
	clearRansomAttributes(getPlayerByUserId(offer.terms.custodianUserId))
end

local function logRansomEvent(category: string, message: string, metadata: any?)
	local eventLogApi = getRuntimeEventLogQueryApi()
	if eventLogApi == nil then
		return
	end

	local payload = {
		category = category,
		message = message,
		severity = "info",
		timestamp = if type(metadata) == "table" and type(metadata.at) == "number" then metadata.at else now(),
		metadata = metadata,
	}

	if type(eventLogApi.RecordEventFromPayload) == "function" then
		pcall(eventLogApi.RecordEventFromPayload, payload)
		return
	end
	if type(eventLogApi.RecordEvent) == "function" then
		pcall(
			eventLogApi.RecordEvent,
			payload.category,
			payload.message,
			payload.severity,
			payload.timestamp,
			payload.metadata
		)
	end
end

local function notifyTinyfolkRansom(offer: any, at: number, eventKind: string)
	if notifyRemote == nil or type(offer) ~= "table" or type(offer.terms) ~= "table" then
		return
	end

	local target = getPlayerByUserId(offer.terms.targetUserId)
	if target == nil then
		return
	end

	target:SetAttribute(RansomBoardConfig.StateAttributes.NotifiedAt, at)
	notifyRemote:FireClient(target, {
		eventKind = eventKind,
		offerId = offer.offerId,
		terms = offer.terms,
		at = at,
	})
end

local function makeOfferId(targetUserId: number, custodianUserId: number, at: number): string
	local sequence = (offerSequenceByTargetUserId[targetUserId] or 0) + 1
	offerSequenceByTargetUserId[targetUserId] = sequence
	return string.format("ransom_%d_%d_%d_%d", targetUserId, custodianUserId, math.floor(at * 1000), sequence)
end

local function getCaptureRecord(targetUserId: number, at: number): any?
	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.GetTargetCapture) ~= "function" then
		return nil
	end
	return captureApi.GetTargetCapture(targetUserId, at)
end

local function validateGiantActor(player: Player, at: number): string?
	if player:GetAttribute(ROLE_ATTRIBUTE) ~= "Giant" then
		return "actor_not_giant"
	end
	if not isPlayerAlive(player) then
		return "actor_not_alive"
	end
	if isCoolingDown(player.UserId, at) then
		return "request_cooldown"
	end
	return nil
end

local function validateTinyfolkActor(player: Player, at: number): string?
	if player:GetAttribute(ROLE_ATTRIBUTE) ~= "Tinyfolk" then
		return "actor_not_tinyfolk"
	end
	if not isPlayerAlive(player) then
		return "actor_not_alive"
	end
	if isCoolingDown(player.UserId, at) then
		return "request_cooldown"
	end
	return nil
end

local function resolveObjectiveReady(): boolean
	local objectiveApi = getRealmObjectiveQueryApi()
	if objectiveApi == nil or type(objectiveApi.IsEscapeObjectiveThresholdMet) ~= "function" then
		return false
	end
	local ok, ready = pcall(objectiveApi.IsEscapeObjectiveThresholdMet)
	if not ok then
		return false
	end
	return ready == true
end

local function canAffordFoodCost(foodCost: number): boolean
	if foodCost <= 0 then
		return true
	end
	local snapshot = ResourceFlowState.GetSnapshot()
	return snapshot.Food.stored >= foodCost
end

local function spendFoodCost(foodCost: number, offerId: string): (boolean, string?)
	if foodCost <= 0 then
		return true, nil
	end
	local spent, _, reason =
		ResourceFlowState.SpendStoredAtomic(0, 0, string.format("RansomBoard:%s", offerId), foodCost)
	return spent, reason
end

local function notifyAbuseCustodyEnd(custodianUserId: number, targetUserId: number, at: number, offerId: string?)
	local abuseApi = getRepeatedTargetingAbuseQueryApi()
	if abuseApi == nil or type(abuseApi.RecordCustodyEnd) ~= "function" then
		return
	end
	pcall(abuseApi.RecordCustodyEnd, custodianUserId, targetUserId, "released", at, offerId)
end

local function postRansomOffer(
	custodianUserId: number,
	targetUserId: any,
	settlementKind: any,
	foodCost: any,
	at: number?
): any
	local resolvedNow = if type(at) == "number" then at else now()
	state = RansomBoardState.PruneExpired(state, resolvedNow)

	local custodian = getPlayerByUserId(custodianUserId)
	if custodian == nil then
		return { accepted = false, reason = "custodian_not_found" }
	end

	local validation = validateGiantActor(custodian, resolvedNow)
	if validation ~= nil then
		setRansomLastReason(custodian, validation)
		return { accepted = false, reason = validation }
	end

	if type(targetUserId) ~= "number" then
		setRansomLastReason(custodian, "target_user_id_invalid")
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	local target = getPlayerByUserId(targetUserId)
	if target == nil then
		setRansomLastReason(custodian, "target_not_found")
		return { accepted = false, reason = "target_not_found" }
	end

	local record = getCaptureRecord(targetUserId, resolvedNow)
	if record == nil then
		setRansomLastReason(custodian, "capture_missing")
		return { accepted = false, reason = "capture_missing" }
	end
	if record.custodianUserId ~= custodianUserId then
		setRansomLastReason(custodian, "custodian_mismatch")
		return { accepted = false, reason = "custodian_mismatch" }
	end

	local resolvedSettlementKind = if type(settlementKind) == "string"
		then settlementKind
		else RansomBoardConfig.SettlementKinds.PaymentFood
	local resolvedFoodCost = if type(foodCost) == "number" then foodCost else RansomBoardConfig.DefaultFoodCost

	local transition = RansomBoardState.ResolvePost(state, {
		now = resolvedNow,
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
		record = record,
		settlementKind = resolvedSettlementKind,
		foodCost = resolvedFoodCost,
		offerId = makeOfferId(targetUserId, custodianUserId, resolvedNow),
	}, RansomBoardConfig)

	state = transition.state
	setRansomLastReason(custodian, transition.reason)
	setRansomLastReason(target, transition.reason)

	if transition.accepted ~= true or transition.offer == nil then
		return {
			accepted = false,
			reason = transition.reason,
			offer = nil,
			terms = transition.terms,
		}
	end

	markRequest(custodianUserId, resolvedNow)
	projectOfferAttributes(transition.offer)
	notifyTinyfolkRansom(transition.offer, resolvedNow, "ransom_posted")

	logRansomEvent("ransom_board", "ransom_posted", {
		at = resolvedNow,
		offerId = transition.offer.offerId,
		targetUserId = targetUserId,
		custodianUserId = custodianUserId,
		settlementKind = resolvedSettlementKind,
		foodCost = transition.offer.terms.foodCost,
		terms = transition.offer.terms,
	})

	return {
		accepted = true,
		reason = transition.reason,
		offer = transition.offer,
		terms = transition.terms,
	}
end

local function settleRansomOffer(payerUserId: number, offerId: string, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	state = RansomBoardState.PruneExpired(state, resolvedNow)

	local payer = getPlayerByUserId(payerUserId)
	if payer == nil then
		return { accepted = false, reason = "payer_not_found" }
	end

	local validation = validateTinyfolkActor(payer, resolvedNow)
	if validation ~= nil then
		setRansomLastReason(payer, validation)
		return { accepted = false, reason = validation }
	end

	local pending = RansomBoardState.GetActiveOfferByOfferId(state, offerId)
	if pending == nil then
		setRansomLastReason(payer, "ransom_offer_missing")
		return { accepted = false, reason = "ransom_offer_missing" }
	end

	local target = getPlayerByUserId(pending.terms.targetUserId)
	if target == nil then
		setRansomLastReason(payer, "target_not_found")
		return { accepted = false, reason = "target_not_found" }
	end
	if not isInRangeOfTarget(payer, target, RansomBoardConfig.SettleRadiusStuds) then
		setRansomLastReason(payer, "payer_out_of_range")
		return { accepted = false, reason = "payer_out_of_range" }
	end

	local record = getCaptureRecord(pending.terms.targetUserId, resolvedNow)
	if record == nil then
		setRansomLastReason(payer, "capture_missing")
		return { accepted = false, reason = "capture_missing" }
	end

	local transition = RansomBoardState.ResolveSettle(state, {
		now = resolvedNow,
		offerId = offerId,
		payerUserId = payerUserId,
		record = record,
		canAffordFood = canAffordFoodCost(pending.terms.foodCost),
		settlementReady = resolveObjectiveReady(),
	})

	if transition.accepted ~= true or transition.offer == nil then
		setRansomLastReason(payer, transition.reason)
		return {
			accepted = false,
			reason = transition.reason,
			offer = nil,
			terms = transition.terms,
		}
	end

	if transition.offer.terms.settlementKind == RansomBoardConfig.SettlementKinds.PaymentFood then
		local spent, spendReason = spendFoodCost(transition.offer.terms.foodCost, offerId)
		if not spent then
			setRansomLastReason(payer, spendReason or "insufficient_food")
			return {
				accepted = false,
				reason = spendReason or "insufficient_food",
				offer = nil,
				terms = transition.terms,
			}
		end
	end

	markRequest(payerUserId, resolvedNow)

	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.ResolveCustodyEnd) ~= "function" then
		if transition.offer.terms.settlementKind == RansomBoardConfig.SettlementKinds.PaymentFood then
			ResourceFlowState.AddStoredAtomic(
				0,
				0,
				string.format("RansomBoardRollback:%s", offerId),
				transition.offer.terms.foodCost
			)
		end
		setRansomLastReason(payer, "capture_release_unavailable")
		return { accepted = false, reason = "capture_release_unavailable" }
	end

	local releaseResult = captureApi.ResolveCustodyEnd(pending.terms.targetUserId, "released", resolvedNow, offerId)
	if releaseResult.accepted ~= true then
		if transition.offer.terms.settlementKind == RansomBoardConfig.SettlementKinds.PaymentFood then
			ResourceFlowState.AddStoredAtomic(
				0,
				0,
				string.format("RansomBoardRollback:%s", offerId),
				transition.offer.terms.foodCost
			)
		end
		setRansomLastReason(payer, releaseResult.reason or "capture_release_failed")
		return {
			accepted = false,
			reason = releaseResult.reason or "capture_release_failed",
			offer = transition.offer,
			terms = transition.terms,
		}
	end

	state = transition.state

	clearOfferAttributesForOffer(transition.offer)
	notifyTinyfolkRansom(transition.offer, resolvedNow, "ransom_settled")

	local custodian = getPlayerByUserId(pending.terms.custodianUserId)
	setRansomLastReason(custodian, "ransom_settled")
	setRansomLastReason(target, "ransom_settled")
	setRansomLastReason(payer, "ransom_settled")

	notifyAbuseCustodyEnd(pending.terms.custodianUserId, pending.terms.targetUserId, resolvedNow, offerId)

	logRansomEvent("ransom_board", "ransom_settled", {
		at = resolvedNow,
		offerId = offerId,
		payerUserId = payerUserId,
		targetUserId = pending.terms.targetUserId,
		custodianUserId = pending.terms.custodianUserId,
		settlementKind = transition.offer.terms.settlementKind,
		foodCost = transition.offer.terms.foodCost,
		release = releaseResult,
	})

	return {
		accepted = true,
		reason = "ransom_settled",
		offer = transition.offer,
		terms = transition.terms,
		release = releaseResult,
	}
end

local function cancelRansomOffer(actorUserId: number, offerId: string, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	state = RansomBoardState.PruneExpired(state, resolvedNow)

	local transition = RansomBoardState.ResolveCancel(state, {
		now = resolvedNow,
		offerId = offerId,
		actorUserId = actorUserId,
	})

	state = transition.state
	local actor = getPlayerByUserId(actorUserId)
	setRansomLastReason(actor, transition.reason)

	if transition.accepted ~= true or transition.offer == nil then
		return {
			accepted = false,
			reason = transition.reason,
			offer = nil,
			terms = transition.terms,
		}
	end

	clearOfferAttributesForOffer(transition.offer)
	notifyTinyfolkRansom(transition.offer, resolvedNow, "ransom_cancelled")

	logRansomEvent("ransom_board", "ransom_cancelled", {
		at = resolvedNow,
		offerId = offerId,
		actorUserId = actorUserId,
		terms = transition.terms,
	})

	return {
		accepted = true,
		reason = transition.reason,
		offer = transition.offer,
		terms = transition.terms,
	}
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	return remote
end

local remotesFolder = ensureRemotesFolder()
local postRemote = ensureRemoteEvent(remotesFolder, RansomBoardConfig.Remotes.Post)
local settleRemote = ensureRemoteEvent(remotesFolder, RansomBoardConfig.Remotes.Settle)
local cancelRemote = ensureRemoteEvent(remotesFolder, RansomBoardConfig.Remotes.Cancel)
notifyRemote = ensureRemoteEvent(remotesFolder, RansomBoardConfig.Remotes.Notify)

postRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local targetUserId = nil
	local settlementKind = nil
	local foodCost = nil
	if type(payload) == "table" then
		targetUserId = (payload :: any).targetUserId
		settlementKind = (payload :: any).settlementKind
		foodCost = (payload :: any).foodCost
	end
	local result = postRansomOffer(player.UserId, targetUserId, settlementKind, foodCost, nil)
	postRemote:FireClient(player, result)
end)

settleRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local offerId = nil
	if type(payload) == "table" then
		offerId = (payload :: any).offerId
	elseif type(payload) == "string" then
		offerId = payload
	end
	local result = settleRansomOffer(player.UserId, offerId, nil)
	settleRemote:FireClient(player, result)
end)

cancelRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local offerId = nil
	if type(payload) == "table" then
		offerId = (payload :: any).offerId
	elseif type(payload) == "string" then
		offerId = payload
	end
	local result = cancelRansomOffer(player.UserId, offerId, nil)
	cancelRemote:FireClient(player, result)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	state = RansomBoardState.RemovePlayer(state, player.UserId)
	clearRansomAttributes(player)
end)

globalEnv._RansomBoardService_QueryAPI = {
	PostRansomOffer = function(
		custodianUserId: number,
		targetUserId: number,
		settlementKind: string?,
		foodCost: number?,
		at: number?
	): any
		return postRansomOffer(custodianUserId, targetUserId, settlementKind, foodCost, at)
	end,
	SettleRansomOffer = function(payerUserId: number, offerId: string, at: number?): any
		return settleRansomOffer(payerUserId, offerId, at)
	end,
	CancelRansomOffer = function(actorUserId: number, offerId: string, at: number?): any
		return cancelRansomOffer(actorUserId, offerId, at)
	end,
	GetActiveOfferForTarget = function(targetUserId: number, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		state = RansomBoardState.PruneExpired(state, resolvedNow)
		return RansomBoardState.GetActiveOfferByTargetUserId(state, targetUserId)
	end,
	GetActiveOfferByOfferId = function(offerId: string, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		state = RansomBoardState.PruneExpired(state, resolvedNow)
		return RansomBoardState.GetActiveOfferByOfferId(state, offerId)
	end,
	GetBoardEntries = function(at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		state = RansomBoardState.PruneExpired(state, resolvedNow)
		return RansomBoardState.GetBoardEntries(state, resolvedNow)
	end,
	BuildRansomTerms = function(record: any, settlementKind: string, foodCost: number?, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		return RansomBoardState.BuildTerms({
			record = record,
			now = resolvedNow,
			settlementKind = settlementKind,
			foodCost = foodCost,
		}, RansomBoardConfig)
	end,
	ResetForTests = function()
		state = RansomBoardState.NewState()
		lastRequestAtByUserId = {}
		offerSequenceByTargetUserId = {}
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RansomBoardService_QueryAPI", globalEnv._RansomBoardService_QueryAPI)
end

return globalEnv._RansomBoardService_QueryAPI
