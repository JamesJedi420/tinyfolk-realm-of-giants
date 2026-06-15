--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local CustodyTransferConfig = require(Config:WaitForChild("CustodyTransferConfig"))
local ModerationReportConfig = require(Config:WaitForChild("ModerationReportConfig"))
local RansomBoardConfig = require(Config:WaitForChild("RansomBoardConfig"))
local RescueContractConfig = require(Config:WaitForChild("RescueContractConfig"))
local RepeatedTargetingAbuseConfig = require(Config:WaitForChild("RepeatedTargetingAbuseConfig"))
local ModerationReportState = require(GiantRealm:WaitForChild("ModerationReportState"))

local REMOTES_FOLDER_NAME = "Remotes"
local globalEnv: any = getfenv()

local state = ModerationReportState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local lastAffordanceRefreshAt = 0
local exportRemote: RemoteEvent? = nil

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

local function getGlobalApi(apiName: string): any?
	local queryApi = globalEnv[apiName]
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)[apiName]) == "table" then
		return (_G :: any)[apiName]
	end
	return nil
end

local function getSessionId(): string
	local sessionId = game.JobId
	if type(sessionId) ~= "string" or sessionId == "" then
		return "local_session"
	end
	return sessionId
end

local function readRealmId(player: Player?): string
	if player == nil then
		return "unknown_realm"
	end

	local attributeName = ModerationReportConfig.TargetRealmIdAttribute
	if type(attributeName) == "string" and attributeName ~= "" then
		local value = player:GetAttribute(attributeName)
		if type(value) == "string" and value ~= "" then
			return value
		end
	end

	local ownerAttribute = ModerationReportConfig.TargetRealmOwnerUserIdAttribute
	if type(ownerAttribute) == "string" and ownerAttribute ~= "" then
		local ownerUserId = player:GetAttribute(ownerAttribute)
		if type(ownerUserId) == "number" and ownerUserId > 0 then
			return string.format("giant_realm_%d", ownerUserId)
		end
	end

	return "unknown_realm"
end

local function getRecentModerationEvents(limit: number?): { any }
	local eventLogApi = getGlobalApi("_EventLogService_QueryAPI")
	if type(eventLogApi) ~= "table" or type(eventLogApi.GetRecentEvents) ~= "function" then
		return {}
	end

	local ok, events = pcall(eventLogApi.GetRecentEvents, limit or ModerationReportConfig.MaxRecentEvents)
	if not ok or type(events) ~= "table" then
		return {}
	end
	return events
end

local function logReportExport(context: any)
	local eventLogApi = getGlobalApi("_EventLogService_QueryAPI")
	if type(eventLogApi) ~= "table" then
		return
	end

	local payload = {
		category = ModerationReportConfig.EventLogCategory,
		message = "Moderation report context exported",
		severity = "info",
		timestamp = context.generatedAt,
		metadata = {
			reportId = context.reportId,
			surfaceKind = context.surfaceKind,
			realmId = context.realmId,
			sessionId = context.sessionId,
			reporterUserId = context.reporterUserId,
			capturingUserId = context.capturingUserId,
			capturedUserId = context.capturedUserId,
		},
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

local function resolveCaptureContext(reporterUserId: number, at: number): (number?, number?, any?)
	local captureApi = getGlobalApi("_CaptureService_QueryAPI")
	if type(captureApi) ~= "table" or type(captureApi.GetTargetCapture) ~= "function" then
		return nil, nil, nil
	end

	local capture = captureApi.GetTargetCapture(reporterUserId, at)
	if type(capture) == "table" then
		return capture.custodianUserId,
			capture.targetUserId,
			{
				startedAt = capture.startedAt,
				expiresAt = capture.expiresAt,
				containmentPhase = capture.containmentPhase,
				containedAt = capture.containedAt,
			}
	end

	if type(captureApi.GetCustodianCapture) == "function" then
		local custodianCapture = captureApi.GetCustodianCapture(reporterUserId, at)
		if type(custodianCapture) == "table" then
			return custodianCapture.custodianUserId,
				custodianCapture.targetUserId,
				{
					startedAt = custodianCapture.startedAt,
					expiresAt = custodianCapture.expiresAt,
					containmentPhase = custodianCapture.containmentPhase,
					containedAt = custodianCapture.containedAt,
					reporterRole = "custodian",
				}
		end
	end

	return nil, nil, nil
end

local function resolveCustodyTransferContext(reporterUserId: number, at: number): any?
	local transferApi = getGlobalApi("_CustodyTransferService_QueryAPI")
	if type(transferApi) ~= "table" or type(transferApi.GetPendingTransferForTarget) ~= "function" then
		return nil
	end

	local pending = transferApi.GetPendingTransferForTarget(reporterUserId, at)
	if type(pending) == "table" then
		return {
			requestId = pending.requestId,
			terms = pending.terms,
		}
	end

	if type(transferApi.GetPendingTransferByRequestId) ~= "function" then
		return nil
	end

	local attrs = CustodyTransferConfig.StateAttributes
	local reporter = getPlayerByUserId(reporterUserId)
	if reporter == nil then
		return nil
	end

	local requestId = reporter:GetAttribute(attrs.PendingRequestId)
	if type(requestId) ~= "string" or requestId == "" then
		return nil
	end

	local byRequest = transferApi.GetPendingTransferByRequestId(requestId, at)
	if type(byRequest) == "table" then
		return {
			requestId = byRequest.requestId,
			terms = byRequest.terms,
		}
	end

	return nil
end

local function resolveRansomContext(reporterUserId: number, at: number): any?
	local ransomApi = getGlobalApi("_RansomBoardService_QueryAPI")
	if type(ransomApi) ~= "table" or type(ransomApi.GetActiveOfferForTarget) ~= "function" then
		return nil
	end

	local offer = ransomApi.GetActiveOfferForTarget(reporterUserId, at)
	if type(offer) == "table" then
		return {
			offerId = offer.offerId,
			terms = offer.terms,
		}
	end

	if type(ransomApi.GetBoardEntries) ~= "function" then
		return nil
	end

	local boardEntries = ransomApi.GetBoardEntries(at)
	if type(boardEntries) ~= "table" then
		return nil
	end

	for _, entry in ipairs(boardEntries) do
		if type(entry) == "table" and entry.targetUserId == reporterUserId then
			return {
				offerId = entry.offerId,
				terms = entry.terms,
			}
		end
	end

	return nil
end

local function resolveAbuseSignals(reporterUserId: number, at: number): any?
	local abuseApi = getGlobalApi("_RepeatedTargetingAbuseService_QueryAPI")
	if type(abuseApi) ~= "table" then
		return nil
	end

	local output: any = {}
	if type(abuseApi.GetTargetSnapshot) == "function" then
		local ok, snapshot = pcall(abuseApi.GetTargetSnapshot, reporterUserId, at)
		if ok and type(snapshot) == "table" then
			output.targetSnapshot = snapshot
		end
	end

	if type(abuseApi.GetRecentSuspiciousLoops) == "function" then
		local ok, loops = pcall(abuseApi.GetRecentSuspiciousLoops, 10)
		if ok and type(loops) == "table" then
			local filtered = {}
			for _, loop in ipairs(loops) do
				if type(loop) == "table" then
					if
						loop.targetUserId == reporterUserId
						or loop.custodianUserId == reporterUserId
						or loop.outgoingCustodianUserId == reporterUserId
						or loop.incomingCustodianUserId == reporterUserId
					then
						table.insert(filtered, loop)
					end
				end
			end
			if #filtered > 0 then
				output.recentSuspiciousLoops = filtered
			end
		end
	end

	if next(output) == nil then
		return nil
	end
	return output
end

local function resolveAffordanceInput(player: Player): any
	local captureAttrs = CaptureConfig.StateAttributes
	local rescueAttrs = RescueContractConfig.StateAttributes
	local abuseAttrs = RepeatedTargetingAbuseConfig.StateAttributes
	local ransomAttrs = RansomBoardConfig.StateAttributes
	local transferAttrs = CustodyTransferConfig.StateAttributes

	local captureActive = player:GetAttribute(captureAttrs.CaptureActive) == true
	local custodyTransferPending = player:GetAttribute(transferAttrs.PendingRequestId) ~= nil
		or player:GetAttribute(transferAttrs.PendingTargetUserId) ~= nil
	local ransomOfferActive = player:GetAttribute(ransomAttrs.ActiveOfferId) ~= nil
	local repeatedBlockingFlagged = player:GetAttribute(abuseAttrs.AbuseFlag) == true
	local rescueBlocked = player:GetAttribute(rescueAttrs.RescueLastReason)
		== ModerationReportConfig.RescueBlockedReason

	if not captureActive then
		local captureApi = getGlobalApi("_CaptureService_QueryAPI")
		if type(captureApi) == "table" and type(captureApi.GetTargetCapture) == "function" then
			captureActive = type(captureApi.GetTargetCapture(player.UserId, now())) == "table"
		end
	end

	if not custodyTransferPending then
		custodyTransferPending = resolveCustodyTransferContext(player.UserId, now()) ~= nil
	end

	if not ransomOfferActive then
		ransomOfferActive = resolveRansomContext(player.UserId, now()) ~= nil
	end

	return {
		captureActive = captureActive,
		custodyTransferPending = custodyTransferPending,
		ransomOfferActive = ransomOfferActive,
		repeatedBlockingFlagged = repeatedBlockingFlagged,
		rescueBlocked = rescueBlocked,
	}
end

local function projectAffordanceAttributes(player: Player)
	local attrs = ModerationReportConfig.StateAttributes
	local surfaces = ModerationReportState.ResolveAffordanceSurfaces(resolveAffordanceInput(player))
	local available = #surfaces > 0
	player:SetAttribute(attrs.AffordanceAvailable, available)
	player:SetAttribute(attrs.AffordanceSurfaces, ModerationReportState.SerializeAffordanceSurfaces(surfaces))
end

local function refreshAffordanceAttributes(at: number)
	lastAffordanceRefreshAt = at
	for _, player in Players:GetPlayers() do
		projectAffordanceAttributes(player)
	end
end

local function resolveSurfaceDetails(surfaceKind: string, reporterUserId: number, at: number): any?
	local kinds = ModerationReportConfig.SurfaceKinds
	if surfaceKind == kinds.Capture then
		local _, _, details = resolveCaptureContext(reporterUserId, at)
		return details
	end
	if surfaceKind == kinds.CustodyTransfer then
		return resolveCustodyTransferContext(reporterUserId, at)
	end
	if surfaceKind == kinds.Ransom then
		return resolveRansomContext(reporterUserId, at)
	end
	if surfaceKind == kinds.RepeatedBlocking then
		return resolveAbuseSignals(reporterUserId, at)
	end
	if surfaceKind == kinds.RescueBlocking then
		local rescueAttrs = RescueContractConfig.StateAttributes
		local reporter = getPlayerByUserId(reporterUserId)
		if reporter == nil then
			return nil
		end
		return {
			rescueLastReason = reporter:GetAttribute(rescueAttrs.RescueLastReason),
			rescueActive = reporter:GetAttribute(rescueAttrs.RescueActive) == true,
			rescueTargetUserId = reporter:GetAttribute(rescueAttrs.RescueTargetUserId),
			rescueRescuerUserId = reporter:GetAttribute(rescueAttrs.RescueRescuerUserId),
		}
	end
	return nil
end

local function buildReportContext(reporterUserId: number, surfaceKind: string, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	local reporter = getPlayerByUserId(reporterUserId)
	if reporter == nil then
		return { accepted = false, reason = "reporter_not_found", context = nil, summary = nil }
	end

	local capturingUserId, capturedUserId, captureDetails = resolveCaptureContext(reporterUserId, resolvedNow)
	local surfaceDetails = resolveSurfaceDetails(surfaceKind, reporterUserId, resolvedNow)
	if
		surfaceDetails == nil
		and captureDetails ~= nil
		and surfaceKind == ModerationReportConfig.SurfaceKinds.Capture
	then
		surfaceDetails = captureDetails
	end

	if capturingUserId == nil and type(surfaceDetails) == "table" and type(surfaceDetails.terms) == "table" then
		capturingUserId = surfaceDetails.terms.outgoingCustodianUserId or surfaceDetails.terms.custodianUserId
		capturedUserId = surfaceDetails.terms.targetUserId
	end
	if capturingUserId == nil and type(surfaceDetails) == "table" and type(surfaceDetails.terms) == "table" then
		capturingUserId = surfaceDetails.terms.custodianUserId
		capturedUserId = surfaceDetails.terms.targetUserId
	end

	local transitionState, buildResult = ModerationReportState.BuildReportContext(state, {
		now = resolvedNow,
		reporterUserId = reporterUserId,
		surfaceKind = surfaceKind,
		realmId = readRealmId(reporter),
		sessionId = getSessionId(),
		capturingUserId = capturingUserId,
		capturedUserId = capturedUserId or reporterUserId,
		recentEvents = getRecentModerationEvents(),
		surfaceDetails = surfaceDetails,
		abuseSignals = resolveAbuseSignals(reporterUserId, resolvedNow),
	})
	state = transitionState

	if buildResult.accepted ~= true or buildResult.context == nil then
		return {
			accepted = false,
			reason = buildResult.reason,
			context = nil,
			summary = nil,
		}
	end

	return {
		accepted = true,
		reason = buildResult.reason,
		context = buildResult.context,
		summary = ModerationReportState.ExportSummary(buildResult.context),
	}
end

local function requestReportExport(reporterUserId: number, surfaceKind: string?, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	local lastRequestAt = lastRequestAtByUserId[reporterUserId]
	if
		type(lastRequestAt) == "number"
		and resolvedNow - lastRequestAt < ModerationReportConfig.RequestCooldownSeconds
	then
		return { accepted = false, reason = "request_cooldown", summary = nil }
	end
	lastRequestAtByUserId[reporterUserId] = resolvedNow

	local reporter = getPlayerByUserId(reporterUserId)
	if reporter == nil then
		return { accepted = false, reason = "reporter_not_found", summary = nil }
	end

	projectAffordanceAttributes(reporter)
	local surfaces = ModerationReportState.ParseAffordanceSurfaces(
		reporter:GetAttribute(ModerationReportConfig.StateAttributes.AffordanceSurfaces)
	)
	if #surfaces == 0 then
		return { accepted = false, reason = "affordance_unavailable", summary = nil }
	end

	local resolvedSurfaceKind = surfaceKind
	if type(resolvedSurfaceKind) ~= "string" or resolvedSurfaceKind == "" then
		resolvedSurfaceKind = surfaces[1]
	end

	local surfaceAllowed = false
	for _, allowedSurface in ipairs(surfaces) do
		if allowedSurface == resolvedSurfaceKind then
			surfaceAllowed = true
			break
		end
	end
	if not surfaceAllowed then
		return { accepted = false, reason = "surface_not_available", summary = nil }
	end

	local built = buildReportContext(reporterUserId, resolvedSurfaceKind :: string, resolvedNow)
	if built.accepted ~= true or built.summary == nil then
		return { accepted = false, reason = built.reason, summary = nil }
	end

	logReportExport(built.summary)
	local attrs = ModerationReportConfig.StateAttributes
	reporter:SetAttribute(attrs.LastExportAt, resolvedNow)
	reporter:SetAttribute(attrs.LastExportReportId, built.summary.reportId)

	return {
		accepted = true,
		reason = "accepted",
		summary = built.summary,
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
exportRemote = ensureRemoteEvent(remotesFolder, ModerationReportConfig.Remotes.RequestExport)

exportRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local surfaceKind = nil
	if type(payload) == "table" then
		surfaceKind = (payload :: any).surfaceKind
	elseif type(payload) == "string" then
		surfaceKind = payload
	end
	local result = requestReportExport(player.UserId, surfaceKind, nil)
	exportRemote:FireClient(player, result)
end)

Players.PlayerAdded:Connect(function(player: Player)
	projectAffordanceAttributes(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	local attrs = ModerationReportConfig.StateAttributes
	player:SetAttribute(attrs.AffordanceAvailable, false)
	player:SetAttribute(attrs.AffordanceSurfaces, "")
end)

RunService.Heartbeat:Connect(function()
	local at = now()
	if at - lastAffordanceRefreshAt < ModerationReportConfig.AffordanceRefreshSeconds then
		return
	end
	refreshAffordanceAttributes(at)
end)

globalEnv._ModerationReportService_QueryAPI = {
	BuildReportContext = function(reporterUserId: number, surfaceKind: string, at: number?): any
		return buildReportContext(reporterUserId, surfaceKind, at)
	end,
	ExportReportSummary = function(reporterUserId: number, surfaceKind: string?, at: number?): any
		return requestReportExport(reporterUserId, surfaceKind, at)
	end,
	GetAffordanceSurfaces = function(reporterUserId: number, _at: number?): any
		local reporter = getPlayerByUserId(reporterUserId)
		if reporter == nil then
			return { available = false, surfaces = {} }
		end
		projectAffordanceAttributes(reporter)
		local surfaces = ModerationReportState.ParseAffordanceSurfaces(
			reporter:GetAttribute(ModerationReportConfig.StateAttributes.AffordanceSurfaces)
		)
		return {
			available = #surfaces > 0,
			surfaces = surfaces,
		}
	end,
	RefreshAffordanceForPlayer = function(reporterUserId: number): any
		local reporter = getPlayerByUserId(reporterUserId)
		if reporter == nil then
			return { available = false, surfaces = {} }
		end
		projectAffordanceAttributes(reporter)
		local surfaces = ModerationReportState.ParseAffordanceSurfaces(
			reporter:GetAttribute(ModerationReportConfig.StateAttributes.AffordanceSurfaces)
		)
		return {
			available = #surfaces > 0,
			surfaces = surfaces,
		}
	end,
	ResetForTests = function()
		state = ModerationReportState.NewState()
		lastRequestAtByUserId = {}
		lastAffordanceRefreshAt = 0
	end,
}

if type(_G) == "table" then
	rawset(_G, "_ModerationReportService_QueryAPI", globalEnv._ModerationReportService_QueryAPI)
end

return globalEnv._ModerationReportService_QueryAPI
