--!nocheck

local globalEnv: any = getfenv()

local SystemAnnouncementService: any = {}

local ATTR_ACTIVE = "SystemAnnouncementActive"
local ATTR_ID = "SystemAnnouncementId"
local ATTR_MESSAGE = "SystemAnnouncementMessage"
local ATTR_SEVERITY = "SystemAnnouncementSeverity"
local ATTR_STARTS_AT = "SystemAnnouncementStartsAt"
local ATTR_ENDS_AT = "SystemAnnouncementEndsAt"
local ATTR_ISSUED_BY = "SystemAnnouncementIssuedByUserId"
local ATTR_UPDATED_AT = "SystemAnnouncementUpdatedAt"

local SEVERITY_ALLOWED = {
	info = true,
	warning = true,
	critical = true,
}

type AnnouncementRecord = {
	announcementId: string,
	message: string,
	severity: string,
	startsAt: number,
	endsAt: number?,
	issuedByUserId: number?,
	createdAt: number,
	updatedAt: number,
}

type Diagnostics = {
	publishAttempts: number,
	publishSucceeded: number,
	publishFailed: number,
	clearAttempts: number,
	clearSucceeded: number,
	clearFailed: number,
	queryAttempts: number,
	lastAnnouncementId: string?,
	lastReason: string,
}

local nowFnOverride: (() -> number)? = nil
local projectionSinkOverride: ((any) -> ())? = nil
local activeAnnouncement: AnnouncementRecord? = nil
local diagnostics: Diagnostics = {
	publishAttempts = 0,
	publishSucceeded = 0,
	publishFailed = 0,
	clearAttempts = 0,
	clearSucceeded = 0,
	clearFailed = 0,
	queryAttempts = 0,
	lastAnnouncementId = nil,
	lastReason = "not_started",
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0 and value == value
end

local function cloneTable(source: any): any
	if type(source) ~= "table" then
		return source
	end

	local clone: any = {}
	for key, value in pairs(source) do
		clone[key] = cloneTable(value)
	end
	return clone
end

local function resolveNow(): number
	if type(nowFnOverride) == "function" then
		local at = nowFnOverride()
		if isFiniteNumber(at) then
			return at
		end
	end
	return os.clock()
end

local function resolveQueryNow(input: any?): number
	if type(input) == "table" and isFiniteNumber(input.at) then
		return input.at
	end
	return resolveNow()
end

local function validatePublishRequest(input: any, at: number): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "request_invalid" }
	end

	if not isNonEmptyString(input.announcementId) then
		return { accepted = false, reason = "announcement_id_invalid" }
	end
	if not isNonEmptyString(input.message) then
		return { accepted = false, reason = "announcement_message_invalid" }
	end
	if type(input.message) == "string" and string.len(input.message) > 512 then
		return { accepted = false, reason = "announcement_message_invalid" }
	end
	if not isNonEmptyString(input.severity) or SEVERITY_ALLOWED[input.severity] ~= true then
		return { accepted = false, reason = "announcement_severity_invalid" }
	end

	local startsAt = if isFiniteNumber(input.startsAt) then input.startsAt else at
	if not isFiniteNumber(startsAt) then
		return { accepted = false, reason = "announcement_starts_at_invalid" }
	end

	local endsAt = input.endsAt
	if endsAt ~= nil and not isFiniteNumber(endsAt) then
		return { accepted = false, reason = "announcement_ends_at_invalid" }
	end
	if endsAt ~= nil and endsAt <= startsAt then
		return { accepted = false, reason = "announcement_window_invalid" }
	end

	local issuedByUserId = input.issuedByUserId
	if issuedByUserId ~= nil and not isPositiveInteger(issuedByUserId) then
		return { accepted = false, reason = "issued_by_user_id_invalid" }
	end

	return {
		accepted = true,
		reason = "accepted",
		record = {
			announcementId = input.announcementId,
			message = input.message,
			severity = input.severity,
			startsAt = startsAt,
			endsAt = endsAt,
			issuedByUserId = issuedByUserId,
			createdAt = if activeAnnouncement ~= nil
					and activeAnnouncement.announcementId == input.announcementId
				then activeAnnouncement.createdAt
				else at,
			updatedAt = at,
		},
	}
end

local function isAnnouncementActive(record: AnnouncementRecord, at: number): boolean
	if at < record.startsAt then
		return false
	end
	if record.endsAt ~= nil and at >= (record.endsAt :: number) then
		return false
	end
	return true
end

local function resolvePlayersService(): any?
	if game == nil or type((game :: any).GetService) ~= "function" then
		return nil
	end

	local ok, players = pcall(function()
		return (game :: any):GetService("Players")
	end)
	if not ok then
		return nil
	end
	if players == nil then
		return nil
	end
	if type((players :: any).GetPlayers) ~= "function" then
		return nil
	end

	return players
end

local function buildProjectionSnapshot(at: number): any
	local record = activeAnnouncement
	if record == nil then
		return {
			active = false,
			announcementId = nil,
			message = nil,
			severity = nil,
			startsAt = nil,
			endsAt = nil,
			issuedByUserId = nil,
			updatedAt = nil,
			at = at,
		}
	end

	return {
		active = isAnnouncementActive(record, at),
		announcementId = record.announcementId,
		message = record.message,
		severity = record.severity,
		startsAt = record.startsAt,
		endsAt = record.endsAt,
		issuedByUserId = record.issuedByUserId,
		updatedAt = record.updatedAt,
		at = at,
	}
end

local function applyProjectionToPlayer(player: any, projection: any)
	if player == nil or type((player :: any).SetAttribute) ~= "function" then
		return
	end
	local playerAny: any = player

	playerAny:SetAttribute(ATTR_ACTIVE, projection.active == true)
	playerAny:SetAttribute(ATTR_ID, projection.announcementId)
	playerAny:SetAttribute(ATTR_MESSAGE, projection.message)
	playerAny:SetAttribute(ATTR_SEVERITY, projection.severity)
	playerAny:SetAttribute(ATTR_STARTS_AT, projection.startsAt)
	playerAny:SetAttribute(ATTR_ENDS_AT, projection.endsAt)
	playerAny:SetAttribute(ATTR_ISSUED_BY, projection.issuedByUserId)
	playerAny:SetAttribute(ATTR_UPDATED_AT, projection.updatedAt)
end

local function applyProjection(projection: any)
	if type(projectionSinkOverride) == "function" then
		projectionSinkOverride(projection)
		return
	end

	local players = resolvePlayersService()
	if players == nil then
		return
	end

	for _, player in ipairs((players :: any):GetPlayers()) do
		applyProjectionToPlayer(player, projection)
	end
end

local function refreshProjection()
	applyProjection(buildProjectionSnapshot(resolveNow()))
end

function SystemAnnouncementService.PublishAnnouncement(input: any): any
	local at = resolveNow()
	diagnostics.publishAttempts += 1

	local validation = validatePublishRequest(input, at)
	if validation.accepted ~= true then
		diagnostics.publishFailed += 1
		diagnostics.lastReason = validation.reason
		return {
			accepted = false,
			reason = validation.reason,
		}
	end

	local record = validation.record :: AnnouncementRecord
	activeAnnouncement = record
	diagnostics.publishSucceeded += 1
	diagnostics.lastAnnouncementId = record.announcementId
	diagnostics.lastReason = "accepted"
	refreshProjection()

	return {
		accepted = true,
		reason = "accepted",
		snapshot = cloneTable(record),
	}
end

function SystemAnnouncementService.ClearAnnouncement(input: any?): any
	diagnostics.clearAttempts += 1

	local targetAnnouncementId = nil
	if input ~= nil and type(input) ~= "table" then
		diagnostics.clearFailed += 1
		diagnostics.lastReason = "request_invalid"
		return {
			accepted = false,
			reason = "request_invalid",
		}
	end
	if type(input) == "table" and input.announcementId ~= nil then
		if not isNonEmptyString(input.announcementId) then
			diagnostics.clearFailed += 1
			diagnostics.lastReason = "announcement_id_invalid"
			return {
				accepted = false,
				reason = "announcement_id_invalid",
			}
		end
		targetAnnouncementId = input.announcementId
	end

	if activeAnnouncement == nil then
		diagnostics.clearFailed += 1
		diagnostics.lastReason = "announcement_not_found"
		return {
			accepted = false,
			reason = "announcement_not_found",
		}
	end

	if targetAnnouncementId ~= nil and activeAnnouncement.announcementId ~= targetAnnouncementId then
		diagnostics.clearFailed += 1
		diagnostics.lastReason = "announcement_not_found"
		return {
			accepted = false,
			reason = "announcement_not_found",
		}
	end

	local cleared = cloneTable(activeAnnouncement)
	activeAnnouncement = nil
	diagnostics.clearSucceeded += 1
	diagnostics.lastAnnouncementId = cleared.announcementId
	diagnostics.lastReason = "accepted"
	refreshProjection()

	return {
		accepted = true,
		reason = "accepted",
		snapshot = cleared,
	}
end

function SystemAnnouncementService.GetActiveAnnouncement(input: any?): any
	diagnostics.queryAttempts += 1
	local at = resolveQueryNow(input)

	if activeAnnouncement == nil then
		diagnostics.lastReason = "announcement_not_found"
		return {
			accepted = false,
			reason = "announcement_not_found",
			at = at,
			active = false,
			announcement = nil,
		}
	end

	local announcement = cloneTable(activeAnnouncement)
	local active = isAnnouncementActive(activeAnnouncement, at)
	diagnostics.lastAnnouncementId = announcement.announcementId
	diagnostics.lastReason = if active then "accepted" else "announcement_not_active"

	if not active then
		return {
			accepted = false,
			reason = "announcement_not_active",
			at = at,
			active = false,
			announcement = announcement,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		at = at,
		active = true,
		announcement = announcement,
	}
end

function SystemAnnouncementService.GetAnnouncementDiagnostics(): Diagnostics
	return cloneTable(diagnostics)
end

function SystemAnnouncementService.ConfigureForTests(config: any?)
	local configAny: any = config
	nowFnOverride = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
	projectionSinkOverride = if type(configAny) == "table" and type(configAny.projectionSink) == "function"
		then configAny.projectionSink
		else nil
end

function SystemAnnouncementService.ResetForTests()
	nowFnOverride = nil
	projectionSinkOverride = nil
	activeAnnouncement = nil
	diagnostics = {
		publishAttempts = 0,
		publishSucceeded = 0,
		publishFailed = 0,
		clearAttempts = 0,
		clearSucceeded = 0,
		clearFailed = 0,
		queryAttempts = 0,
		lastAnnouncementId = nil,
		lastReason = "not_started",
	}
end

globalEnv._SystemAnnouncementService_QueryAPI = {
	PublishAnnouncement = function(input: any): any
		return SystemAnnouncementService.PublishAnnouncement(input)
	end,
	ClearAnnouncement = function(input: any?): any
		return SystemAnnouncementService.ClearAnnouncement(input)
	end,
	GetActiveAnnouncement = function(input: any?): any
		return SystemAnnouncementService.GetActiveAnnouncement(input)
	end,
	GetAnnouncementDiagnostics = function(): Diagnostics
		return SystemAnnouncementService.GetAnnouncementDiagnostics()
	end,
	ConfigureForTests = function(config: any?)
		SystemAnnouncementService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		SystemAnnouncementService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_SystemAnnouncementService_QueryAPI", globalEnv._SystemAnnouncementService_QueryAPI)
end

return SystemAnnouncementService
