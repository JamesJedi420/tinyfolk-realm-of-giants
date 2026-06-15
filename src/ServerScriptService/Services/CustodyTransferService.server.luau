--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local CustodyTransferConfig = require(Config:WaitForChild("CustodyTransferConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local CustodyTransferState = require(GiantRealm:WaitForChild("CustodyTransferState"))
local VillageWorksiteUpgradeState = require(GiantRealm:WaitForChild("VillageWorksiteUpgradeState"))

local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_ATTRIBUTE = "Role"
local globalEnv: any = getfenv()

local state = CustodyTransferState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local transferSequenceByTargetUserId: { [number]: number? } = {}
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

local function getRuntimeEventLogQueryApi(): any?
	local queryApi = globalEnv._RuntimeEventLogService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._RuntimeEventLogService_QueryAPI) == "table" then
		return (_G :: any)._RuntimeEventLogService_QueryAPI
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

local function notifyAbuseCustodyTransfer(
	outgoingCustodianUserId: number,
	incomingCustodianUserId: number,
	targetUserId: number,
	at: number,
	requestId: string?
)
	local abuseApi = getRepeatedTargetingAbuseQueryApi()
	if abuseApi == nil or type(abuseApi.RecordCustodyTransfer) ~= "function" then
		return
	end
	pcall(abuseApi.RecordCustodyTransfer, outgoingCustodianUserId, incomingCustodianUserId, targetUserId, at, requestId)
end

local function resolveAbuseCustodyBlock(
	custodianUserId: number,
	targetUserId: number,
	at: number,
	interactionKind: string,
	outgoingCustodianUserId: number?,
	incomingCustodianUserId: number?
): any
	local abuseApi = getRepeatedTargetingAbuseQueryApi()
	if abuseApi == nil or type(abuseApi.IsCustodyInteractionBlocked) ~= "function" then
		return { blocked = false, reason = "accepted" }
	end
	local ok, result = pcall(abuseApi.IsCustodyInteractionBlocked, {
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
		now = at,
		interactionKind = interactionKind,
		outgoingCustodianUserId = outgoingCustodianUserId,
		incomingCustodianUserId = incomingCustodianUserId,
	})
	if not ok or type(result) ~= "table" then
		return { blocked = false, reason = "accepted" }
	end
	return result
end

local function resolveMaxConcurrentCapturesPerCustodian(): number
	local upgradeApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
	if type(upgradeApi) ~= "table" and type(_G) == "table" then
		upgradeApi = (_G :: any)._VillageWorksiteUpgradeService_QueryAPI
	end

	local heldCapacityMultiplier = 1
	if type(upgradeApi) == "table" and type(upgradeApi.GetHeldCapacityMultiplier) == "function" then
		local resolvedMultiplier = upgradeApi.GetHeldCapacityMultiplier(StationConfig.DefaultPenId)
		if type(resolvedMultiplier) == "number" and resolvedMultiplier > 0 then
			heldCapacityMultiplier = resolvedMultiplier
		end
	end

	return VillageWorksiteUpgradeState.ResolveMaxConcurrentCaptures(
		CaptureConfig.BaseMaxConcurrentCapturesPerCustodian,
		heldCapacityMultiplier
	)
end

local function incomingCustodianHasCapacity(incomingCustodianUserId: number, at: number): boolean
	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.GetAllCaptures) ~= "function" then
		return true
	end

	local captures = captureApi.GetAllCaptures(at)
	local activeCaptures = 0
	if type(captures) == "table" then
		for _, record in ipairs(captures) do
			if type(record) == "table" and record.custodianUserId == incomingCustodianUserId then
				activeCaptures += 1
			end
		end
	end

	return activeCaptures < resolveMaxConcurrentCapturesPerCustodian()
end

local function setTransferLastReason(player: Player?, reason: string)
	if player == nil then
		return
	end
	player:SetAttribute(CustodyTransferConfig.StateAttributes.LastReason, reason)
end

local function clearTransferAttributes(player: Player?)
	if player == nil then
		return
	end

	local attrs = CustodyTransferConfig.StateAttributes
	player:SetAttribute(attrs.PendingRequestId, nil)
	player:SetAttribute(attrs.PendingOutgoingCustodianUserId, nil)
	player:SetAttribute(attrs.PendingIncomingCustodianUserId, nil)
	player:SetAttribute(attrs.PendingTargetUserId, nil)
	player:SetAttribute(attrs.PendingExpiresAt, nil)
	player:SetAttribute(attrs.TermsCustodyExpiresAt, nil)
	player:SetAttribute(attrs.TermsAbsoluteDeadlineAt, nil)
	player:SetAttribute(attrs.TermsCaptivityAnchorAt, nil)
	player:SetAttribute(attrs.TermsContainmentPhase, nil)
	player:SetAttribute(attrs.TermsRemainingSeconds, nil)
	player:SetAttribute(attrs.NotifiedAt, nil)
end

local function applyPendingTransferAttributes(request: any)
	if type(request) ~= "table" or type(request.terms) ~= "table" then
		return
	end

	local terms = request.terms
	local attrs = CustodyTransferConfig.StateAttributes
	local outgoing = getPlayerByUserId(terms.outgoingCustodianUserId)
	local incoming = getPlayerByUserId(terms.incomingCustodianUserId)
	local target = getPlayerByUserId(terms.targetUserId)

	local function applyToPlayer(player: Player?)
		if player == nil then
			return
		end
		player:SetAttribute(attrs.PendingRequestId, request.requestId)
		player:SetAttribute(attrs.PendingOutgoingCustodianUserId, terms.outgoingCustodianUserId)
		player:SetAttribute(attrs.PendingIncomingCustodianUserId, terms.incomingCustodianUserId)
		player:SetAttribute(attrs.PendingTargetUserId, terms.targetUserId)
		player:SetAttribute(attrs.PendingExpiresAt, request.requestExpiresAt)
		player:SetAttribute(attrs.TermsCustodyExpiresAt, terms.custodyExpiresAt)
		player:SetAttribute(attrs.TermsAbsoluteDeadlineAt, terms.absoluteDeadlineAt)
		player:SetAttribute(attrs.TermsCaptivityAnchorAt, terms.captivityAnchorAt)
		player:SetAttribute(attrs.TermsContainmentPhase, terms.containmentPhase)
		player:SetAttribute(attrs.TermsRemainingSeconds, terms.remainingSeconds)
	end

	applyToPlayer(outgoing)
	applyToPlayer(incoming)
	applyToPlayer(target)
end

local function notifyTinyfolkTransfer(request: any, at: number)
	if type(request) ~= "table" or type(request.terms) ~= "table" then
		return
	end

	local target = getPlayerByUserId(request.terms.targetUserId)
	if target == nil then
		return
	end

	target:SetAttribute(CustodyTransferConfig.StateAttributes.NotifiedAt, at)
	if notifyRemote ~= nil then
		notifyRemote:FireClient(target, {
			requestId = request.requestId,
			outgoingCustodianUserId = request.terms.outgoingCustodianUserId,
			incomingCustodianUserId = request.terms.incomingCustodianUserId,
			targetUserId = request.terms.targetUserId,
			terms = request.terms,
			notifiedAt = at,
		})
	end
end

local function clearPendingTransferAttributesForRequest(request: any)
	if type(request) ~= "table" or type(request.terms) ~= "table" then
		return
	end

	clearTransferAttributes(getPlayerByUserId(request.terms.outgoingCustodianUserId))
	clearTransferAttributes(getPlayerByUserId(request.terms.incomingCustodianUserId))
	clearTransferAttributes(getPlayerByUserId(request.terms.targetUserId))
end

local function logTransferEvent(category: string, message: string, metadata: any?)
	local eventLogApi = getRuntimeEventLogQueryApi()
	if eventLogApi == nil or type(eventLogApi.RecordEvent) ~= "function" then
		return
	end

	pcall(eventLogApi.RecordEvent, {
		category = category,
		message = message,
		severity = "info",
		metadata = metadata,
	})
end

local function makeRequestId(
	targetUserId: number,
	outgoingCustodianUserId: number,
	incomingCustodianUserId: number,
	at: number
): string
	local sequence = (transferSequenceByTargetUserId[targetUserId] or 0) + 1
	transferSequenceByTargetUserId[targetUserId] = sequence
	return string.format(
		"transfer_%d_%d_%d_%d_%d",
		targetUserId,
		outgoingCustodianUserId,
		incomingCustodianUserId,
		math.floor(at * 1000),
		sequence
	)
end

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end
	return (at - last) < CustodyTransferConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number)
	lastRequestAtByUserId[userId] = at
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

local function requestCustodyTransfer(
	outgoingCustodianUserId: number,
	targetUserId: number,
	incomingCustodianUserId: number,
	at: number?
): any
	local resolvedNow = if type(at) == "number" then at else now()
	state = CustodyTransferState.PruneExpired(state, resolvedNow)

	local outgoing = getPlayerByUserId(outgoingCustodianUserId)
	if outgoing == nil then
		return { accepted = false, reason = "outgoing_custodian_not_found" }
	end
	local incoming = getPlayerByUserId(incomingCustodianUserId)
	if incoming == nil then
		return { accepted = false, reason = "incoming_custodian_not_found" }
	end
	local target = getPlayerByUserId(targetUserId)
	if target == nil then
		return { accepted = false, reason = "target_not_found" }
	end

	local outgoingValidation = validateGiantActor(outgoing, resolvedNow)
	if outgoingValidation ~= nil then
		setTransferLastReason(outgoing, outgoingValidation)
		return { accepted = false, reason = outgoingValidation }
	end
	if incoming:GetAttribute(ROLE_ATTRIBUTE) ~= "Giant" then
		setTransferLastReason(outgoing, "incoming_not_giant")
		setTransferLastReason(incoming, "incoming_not_giant")
		return { accepted = false, reason = "incoming_not_giant" }
	end
	if not isPlayerAlive(incoming) then
		setTransferLastReason(outgoing, "incoming_not_alive")
		return { accepted = false, reason = "incoming_not_alive" }
	end
	if target:GetAttribute(ROLE_ATTRIBUTE) ~= "Tinyfolk" then
		setTransferLastReason(outgoing, "target_not_tinyfolk")
		return { accepted = false, reason = "target_not_tinyfolk" }
	end

	local record = getCaptureRecord(targetUserId, resolvedNow)
	if record == nil then
		setTransferLastReason(outgoing, "capture_missing")
		return { accepted = false, reason = "capture_missing" }
	end
	if record.custodianUserId ~= outgoingCustodianUserId then
		setTransferLastReason(outgoing, "custodian_mismatch")
		return { accepted = false, reason = "custodian_mismatch" }
	end
	if not isInRangeOfTarget(outgoing, target, CustodyTransferConfig.ConfirmRadiusStuds) then
		setTransferLastReason(outgoing, "outgoing_out_of_range")
		return { accepted = false, reason = "outgoing_out_of_range" }
	end
	if not incomingCustodianHasCapacity(incomingCustodianUserId, resolvedNow) then
		setTransferLastReason(outgoing, "incoming_capacity_reached")
		setTransferLastReason(incoming, "incoming_capacity_reached")
		return { accepted = false, reason = "incoming_capacity_reached" }
	end

	local abuseBlock = resolveAbuseCustodyBlock(
		outgoingCustodianUserId,
		targetUserId,
		resolvedNow,
		"transfer",
		outgoingCustodianUserId,
		incomingCustodianUserId
	)
	if abuseBlock.blocked == true then
		setTransferLastReason(outgoing, abuseBlock.reason)
		setTransferLastReason(incoming, abuseBlock.reason)
		setTransferLastReason(target, abuseBlock.reason)
		return { accepted = false, reason = abuseBlock.reason }
	end

	local transition = CustodyTransferState.ResolveRequest(state, {
		now = resolvedNow,
		outgoingCustodianUserId = outgoingCustodianUserId,
		incomingCustodianUserId = incomingCustodianUserId,
		targetUserId = targetUserId,
		record = record,
		requestExpirySeconds = CustodyTransferConfig.RequestExpirySeconds,
		requestId = makeRequestId(targetUserId, outgoingCustodianUserId, incomingCustodianUserId, resolvedNow),
	}, CaptureConfig)

	state = transition.state
	setTransferLastReason(outgoing, transition.reason)
	setTransferLastReason(incoming, transition.reason)
	setTransferLastReason(target, transition.reason)

	if transition.accepted ~= true or transition.request == nil then
		return {
			accepted = false,
			reason = transition.reason,
			request = nil,
			terms = transition.terms,
		}
	end

	markRequest(outgoingCustodianUserId, resolvedNow)
	applyPendingTransferAttributes(transition.request)
	notifyTinyfolkTransfer(transition.request, resolvedNow)

	logTransferEvent("custody_transfer", "transfer_requested", {
		requestId = transition.request.requestId,
		targetUserId = targetUserId,
		outgoingCustodianUserId = outgoingCustodianUserId,
		incomingCustodianUserId = incomingCustodianUserId,
		terms = transition.terms,
	})

	return {
		accepted = true,
		reason = transition.reason,
		request = transition.request,
		terms = transition.terms,
	}
end

local function confirmCustodyTransfer(incomingCustodianUserId: number, requestId: string, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	state = CustodyTransferState.PruneExpired(state, resolvedNow)

	local incoming = getPlayerByUserId(incomingCustodianUserId)
	if incoming == nil then
		return { accepted = false, reason = "incoming_custodian_not_found" }
	end

	local incomingValidation = validateGiantActor(incoming, resolvedNow)
	if incomingValidation ~= nil then
		setTransferLastReason(incoming, incomingValidation)
		return { accepted = false, reason = incomingValidation }
	end

	local pending = CustodyTransferState.GetPendingByRequestId(state, requestId)
	if pending == nil then
		setTransferLastReason(incoming, "transfer_request_missing")
		return { accepted = false, reason = "transfer_request_missing" }
	end

	local target = getPlayerByUserId(pending.terms.targetUserId)
	if target == nil then
		setTransferLastReason(incoming, "target_not_found")
		return { accepted = false, reason = "target_not_found" }
	end
	if not isInRangeOfTarget(incoming, target, CustodyTransferConfig.ConfirmRadiusStuds) then
		setTransferLastReason(incoming, "incoming_out_of_range")
		return { accepted = false, reason = "incoming_out_of_range" }
	end

	local record = getCaptureRecord(pending.terms.targetUserId, resolvedNow)
	if record == nil then
		setTransferLastReason(incoming, "capture_missing")
		return { accepted = false, reason = "capture_missing" }
	end
	if not incomingCustodianHasCapacity(incomingCustodianUserId, resolvedNow) then
		setTransferLastReason(incoming, "incoming_capacity_reached")
		return { accepted = false, reason = "incoming_capacity_reached" }
	end

	local abuseBlock = resolveAbuseCustodyBlock(
		incomingCustodianUserId,
		pending.terms.targetUserId,
		resolvedNow,
		"transfer",
		pending.terms.outgoingCustodianUserId,
		incomingCustodianUserId
	)
	if abuseBlock.blocked == true then
		setTransferLastReason(incoming, abuseBlock.reason)
		setTransferLastReason(target, abuseBlock.reason)
		return { accepted = false, reason = abuseBlock.reason }
	end

	local transition = CustodyTransferState.ResolveConfirm(state, {
		now = resolvedNow,
		incomingCustodianUserId = incomingCustodianUserId,
		requestId = requestId,
		record = record,
	}, CaptureConfig)

	state = transition.state
	setTransferLastReason(incoming, transition.reason)

	if transition.accepted ~= true or transition.request == nil then
		return {
			accepted = false,
			reason = transition.reason,
			request = nil,
			terms = transition.terms,
		}
	end

	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.TransferTargetCustody) ~= "function" then
		setTransferLastReason(incoming, "capture_transfer_unavailable")
		return { accepted = false, reason = "capture_transfer_unavailable" }
	end

	local transferResult =
		captureApi.TransferTargetCustody(pending.terms.targetUserId, incomingCustodianUserId, resolvedNow)
	if transferResult.accepted ~= true then
		setTransferLastReason(incoming, transferResult.reason or "capture_transfer_failed")
		return {
			accepted = false,
			reason = transferResult.reason or "capture_transfer_failed",
			request = transition.request,
			terms = transition.terms,
		}
	end

	markRequest(incomingCustodianUserId, resolvedNow)
	clearPendingTransferAttributesForRequest(transition.request)
	notifyTinyfolkTransfer(transition.request, resolvedNow)

	local outgoing = getPlayerByUserId(pending.terms.outgoingCustodianUserId)
	setTransferLastReason(outgoing, "custody_transferred")
	setTransferLastReason(target, "custody_transferred")

	logTransferEvent("custody_transfer", "transfer_settled", {
		requestId = transition.request.requestId,
		targetUserId = pending.terms.targetUserId,
		outgoingCustodianUserId = pending.terms.outgoingCustodianUserId,
		incomingCustodianUserId = incomingCustodianUserId,
		terms = transition.terms,
		record = transferResult.record,
	})
	notifyAbuseCustodyTransfer(
		pending.terms.outgoingCustodianUserId,
		incomingCustodianUserId,
		pending.terms.targetUserId,
		resolvedNow,
		transition.request.requestId
	)

	return {
		accepted = true,
		reason = "custody_transferred",
		request = transition.request,
		terms = transition.terms,
		record = transferResult.record,
	}
end

local function cancelCustodyTransfer(actorUserId: number, requestId: string, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	state = CustodyTransferState.PruneExpired(state, resolvedNow)

	local transition = CustodyTransferState.ResolveCancel(state, {
		now = resolvedNow,
		requestId = requestId,
		actorUserId = actorUserId,
	})

	state = transition.state
	local actor = getPlayerByUserId(actorUserId)
	setTransferLastReason(actor, transition.reason)

	if transition.accepted ~= true or transition.request == nil then
		return {
			accepted = false,
			reason = transition.reason,
			request = nil,
			terms = nil,
		}
	end

	clearPendingTransferAttributesForRequest(transition.request)
	logTransferEvent("custody_transfer", "transfer_cancelled", {
		requestId = requestId,
		actorUserId = actorUserId,
		terms = transition.terms,
	})

	return {
		accepted = true,
		reason = transition.reason,
		request = transition.request,
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
local requestRemote = ensureRemoteEvent(remotesFolder, CustodyTransferConfig.Remotes.Request)
local confirmRemote = ensureRemoteEvent(remotesFolder, CustodyTransferConfig.Remotes.Confirm)
local cancelRemote = ensureRemoteEvent(remotesFolder, CustodyTransferConfig.Remotes.Cancel)
notifyRemote = ensureRemoteEvent(remotesFolder, CustodyTransferConfig.Remotes.Notify)

requestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local targetUserId = nil
	local incomingCustodianUserId = nil
	if type(payload) == "table" then
		targetUserId = (payload :: any).targetUserId
		incomingCustodianUserId = (payload :: any).incomingCustodianUserId
	end
	local result = requestCustodyTransfer(player.UserId, targetUserId, incomingCustodianUserId, nil)
	requestRemote:FireClient(player, result)
end)

confirmRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local requestId = nil
	if type(payload) == "table" then
		requestId = (payload :: any).requestId
	elseif type(payload) == "string" then
		requestId = payload
	end
	local result = confirmCustodyTransfer(player.UserId, requestId, nil)
	confirmRemote:FireClient(player, result)
end)

cancelRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local requestId = nil
	if type(payload) == "table" then
		requestId = (payload :: any).requestId
	elseif type(payload) == "string" then
		requestId = payload
	end
	local result = cancelCustodyTransfer(player.UserId, requestId, nil)
	cancelRemote:FireClient(player, result)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	state = CustodyTransferState.RemovePlayer(state, player.UserId)
	clearTransferAttributes(player)
end)

_G._CustodyTransferService_QueryAPI = {
	RequestCustodyTransfer = function(
		outgoingCustodianUserId: number,
		targetUserId: number,
		incomingCustodianUserId: number,
		at: number?
	): any
		return requestCustodyTransfer(outgoingCustodianUserId, targetUserId, incomingCustodianUserId, at)
	end,
	ConfirmCustodyTransfer = function(incomingCustodianUserId: number, requestId: string, at: number?): any
		return confirmCustodyTransfer(incomingCustodianUserId, requestId, at)
	end,
	CancelCustodyTransfer = function(actorUserId: number, requestId: string, at: number?): any
		return cancelCustodyTransfer(actorUserId, requestId, at)
	end,
	GetPendingTransferForTarget = function(targetUserId: number, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		state = CustodyTransferState.PruneExpired(state, resolvedNow)
		return CustodyTransferState.GetPendingByTargetUserId(state, targetUserId)
	end,
	GetPendingTransferByRequestId = function(requestId: string, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		state = CustodyTransferState.PruneExpired(state, resolvedNow)
		return CustodyTransferState.GetPendingByRequestId(state, requestId)
	end,
	BuildTransferTerms = function(record: any, incomingCustodianUserId: number, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		return CustodyTransferState.BuildTerms({
			record = record,
			incomingCustodianUserId = incomingCustodianUserId,
			now = resolvedNow,
		}, CaptureConfig)
	end,
	ResetForTests = function()
		state = CustodyTransferState.NewState()
		lastRequestAtByUserId = {}
		transferSequenceByTargetUserId = {}
	end,
}
