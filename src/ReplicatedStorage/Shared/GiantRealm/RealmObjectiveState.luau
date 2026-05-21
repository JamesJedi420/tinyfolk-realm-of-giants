--!strict

local RealmObjectiveState = {}

export type ObjectiveSite = {
	siteId: string,
	siteType: string,
	completed: boolean,
	completedAt: number?,
	completedByUserId: number?,
	objectiveState: string,
	progress: number,
	activeUserId: number?,
	lastProgressAt: number?,
	blockedUntil: number?,
	blockedByUserId: number?,
	regressionEventsUsed: number,
	regressingUntil: number?,
	ruleLocked: boolean,
}

export type State = {
	sitesById: { [string]: ObjectiveSite },
	baseRequiredCompletions: number,
	minimumRequiredCompletions: number,
	requiredCompletions: number,
	completionProgress: number,
	disruptionDamage: number,
	regressionPerSecond: number,
	stabilizationProgress: number,
	majorRegressionMaxEvents: number,
	defaultBlockDurationSeconds: number,
	lastReason: string?,
	lastAlert: any?,
}

export type Transition = {
	accepted: boolean,
	reason: string,
	state: State,
	alert: any?,
}

local function cloneSite(site: ObjectiveSite): ObjectiveSite
	return {
		siteId = site.siteId,
		siteType = site.siteType,
		completed = site.completed,
		completedAt = site.completedAt,
		completedByUserId = site.completedByUserId,
		objectiveState = site.objectiveState,
		progress = site.progress,
		activeUserId = site.activeUserId,
		lastProgressAt = site.lastProgressAt,
		blockedUntil = site.blockedUntil,
		blockedByUserId = site.blockedByUserId,
		regressionEventsUsed = site.regressionEventsUsed,
		regressingUntil = site.regressingUntil,
		ruleLocked = site.ruleLocked,
	}
end

local function cloneAlert(alert: any?): any?
	if type(alert) ~= "table" then
		return alert
	end

	local copied = {}
	for key, value in pairs(alert) do
		copied[key] = value
	end
	return copied
end

local function cloneState(state: State): State
	local sitesById: { [string]: ObjectiveSite } = {}
	for siteId, site in pairs(state.sitesById) do
		sitesById[siteId] = cloneSite(site)
	end

	return {
		sitesById = sitesById,
		baseRequiredCompletions = state.baseRequiredCompletions,
		minimumRequiredCompletions = state.minimumRequiredCompletions,
		requiredCompletions = state.requiredCompletions,
		completionProgress = state.completionProgress,
		disruptionDamage = state.disruptionDamage,
		regressionPerSecond = state.regressionPerSecond,
		stabilizationProgress = state.stabilizationProgress,
		majorRegressionMaxEvents = state.majorRegressionMaxEvents,
		defaultBlockDurationSeconds = state.defaultBlockDurationSeconds,
		lastReason = state.lastReason,
		lastAlert = cloneAlert(state.lastAlert),
	}
end

local function finiteNumber(value: any, fallback: number): number
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end
	return fallback
end

local function nonNegativeNumber(value: any, fallback: number): number
	local resolved = finiteNumber(value, fallback)
	if resolved < 0 then
		return 0
	end
	return resolved
end

local function positiveNumber(value: any, fallback: number): number
	local resolved = finiteNumber(value, fallback)
	if resolved <= 0 then
		return fallback
	end
	return resolved
end

local function positiveInteger(value: any, fallback: number): number
	return math.max(0, math.floor(nonNegativeNumber(value, fallback)))
end

local function resolveAt(at: number?): number
	return finiteNumber(at, 0)
end

local function clampProgress(value: number, completionProgress: number): number
	if value < 0 then
		return 0
	end
	if value > completionProgress then
		return completionProgress
	end
	return value
end

local function getSiteOrReject(nextState: State, siteId: string): (ObjectiveSite?, Transition?)
	if type(siteId) ~= "string" or string.len(siteId) == 0 then
		nextState.lastReason = "site_id_invalid"
		return nil, { accepted = false, reason = "site_id_invalid", state = nextState, alert = nil }
	end

	local site = nextState.sitesById[siteId]
	if site == nil then
		nextState.lastReason = "site_not_found"
		return nil, { accepted = false, reason = "site_not_found", state = nextState, alert = nil }
	end
	return site, nil
end

local function ensureSiteRuntimeDefaults(site: ObjectiveSite, state: State): ObjectiveSite
	site.objectiveState = if type((site :: any).objectiveState) == "string" then site.objectiveState else "idle"
	site.progress = clampProgress(nonNegativeNumber((site :: any).progress, 0), state.completionProgress)
	site.regressionEventsUsed = positiveInteger((site :: any).regressionEventsUsed, 0)
	site.ruleLocked = (site :: any).ruleLocked == true
	if site.completed == true then
		site.objectiveState = "completed"
		site.progress = state.completionProgress
	end
	return site
end

local function makeObjectiveAlert(kind: string, site: ObjectiveSite, state: State): any
	return {
		kind = kind,
		siteId = site.siteId,
		objectiveState = site.objectiveState,
		progress = site.progress,
		progressRatio = if state.completionProgress > 0 then site.progress / state.completionProgress else 0,
		regressionEventsUsed = site.regressionEventsUsed,
		blockedUntil = site.blockedUntil,
	}
end

local function refreshSiteTimedState(site: ObjectiveSite, state: State, at: number): ObjectiveSite
	site = ensureSiteRuntimeDefaults(site, state)

	if site.completed == true or site.ruleLocked == true then
		return site
	end

	if site.objectiveState == "blocked" and site.blockedUntil ~= nil and at >= (site.blockedUntil :: number) then
		site.objectiveState = if site.progress > 0 then "contested" else "idle"
		site.blockedUntil = nil
		site.blockedByUserId = nil
	end

	if site.objectiveState == "regressing" then
		local lastProgressAt = if site.lastProgressAt ~= nil then site.lastProgressAt else at
		local elapsed = math.max(0, at - lastProgressAt)
		if elapsed > 0 then
			site.progress =
				clampProgress(site.progress - (elapsed * state.regressionPerSecond), state.completionProgress)
			site.lastProgressAt = at
		end

		local shouldStabilize = site.progress <= state.stabilizationProgress
			or (site.regressingUntil ~= nil and at >= (site.regressingUntil :: number))
		if shouldStabilize then
			site.progress = math.max(site.progress, math.min(state.stabilizationProgress, state.completionProgress))
			site.objectiveState = if site.progress > 0 then "contested" else "idle"
			site.regressingUntil = nil
		end
	end

	return site
end

local function countTotalSites(state: State): number
	local count = 0
	for _, _ in pairs(state.sitesById) do
		count += 1
	end
	return count
end

local function countCompletedSites(state: State): number
	local count = 0
	for _, site in pairs(state.sitesById) do
		if site.completed == true then
			count += 1
		end
	end
	return count
end

local function computeRequiredCompletions(state: State, activeTinyfolkCount: number): number
	local siteCount = countTotalSites(state)
	if siteCount <= 0 then
		return 0
	end

	local tinyfolkCount = if activeTinyfolkCount > 0 then activeTinyfolkCount else 0
	local scaledRequired = state.baseRequiredCompletions + math.floor(math.max(0, tinyfolkCount - 1) / 2)

	local maxRequired = if siteCount > 1 then siteCount - 1 else siteCount
	local minimumRequired = if state.minimumRequiredCompletions > 0 then state.minimumRequiredCompletions else 1
	if minimumRequired > maxRequired then
		minimumRequired = maxRequired
	end

	if scaledRequired < minimumRequired then
		scaledRequired = minimumRequired
	end
	if scaledRequired > maxRequired then
		scaledRequired = maxRequired
	end

	return scaledRequired
end

local function sortedSiteIds(state: State): { string }
	local siteIds: { string } = {}
	for siteId, _ in pairs(state.sitesById) do
		table.insert(siteIds, siteId)
	end
	table.sort(siteIds)
	return siteIds
end

function RealmObjectiveState.NewState(config: any?): State
	local configAny = config
	local baseRequired = if type(configAny) == "table" and type(configAny.BaseRequiredCompletions) == "number"
		then math.max(1, math.floor(configAny.BaseRequiredCompletions))
		else 1
	local minimumRequired = if type(configAny) == "table"
			and type(configAny.MinimumRequiredCompletions) == "number"
		then math.max(1, math.floor(configAny.MinimumRequiredCompletions))
		else 1

	return {
		sitesById = {},
		baseRequiredCompletions = baseRequired,
		minimumRequiredCompletions = minimumRequired,
		requiredCompletions = 0,
		completionProgress = positiveNumber(
			if type(configAny) == "table" then configAny.CompletionProgress else nil,
			100
		),
		disruptionDamage = nonNegativeNumber(
			if type(configAny) == "table" then configAny.DisruptionDamage else nil,
			35
		),
		regressionPerSecond = nonNegativeNumber(
			if type(configAny) == "table" then configAny.RegressionPerSecond else nil,
			5
		),
		stabilizationProgress = nonNegativeNumber(
			if type(configAny) == "table" then configAny.StabilizationProgress else nil,
			20
		),
		majorRegressionMaxEvents = positiveInteger(
			if type(configAny) == "table" then configAny.MajorRegressionMaxEvents else nil,
			2
		),
		defaultBlockDurationSeconds = nonNegativeNumber(
			if type(configAny) == "table" then configAny.DefaultBlockDurationSeconds else nil,
			3
		),
		lastReason = nil,
		lastAlert = nil,
	}
end

function RealmObjectiveState.RegisterSite(
	state: State,
	siteId: string,
	siteType: string?,
	activeTinyfolkCount: number?
): Transition
	local nextState = cloneState(state)
	if type(siteId) ~= "string" or string.len(siteId) == 0 then
		nextState.lastReason = "site_id_invalid"
		return { accepted = false, reason = "site_id_invalid", state = nextState, alert = nil }
	end

	if nextState.sitesById[siteId] ~= nil then
		nextState.lastReason = "site_already_registered"
		return { accepted = false, reason = "site_already_registered", state = nextState, alert = nil }
	end

	local resolvedSiteType: string = "generic"
	if type(siteType) == "string" and string.len(siteType) > 0 then
		resolvedSiteType = siteType
	end

	nextState.sitesById[siteId] = {
		siteId = siteId,
		siteType = resolvedSiteType,
		completed = false,
		completedAt = nil,
		completedByUserId = nil,
		objectiveState = "idle",
		progress = 0,
		activeUserId = nil,
		lastProgressAt = nil,
		blockedUntil = nil,
		blockedByUserId = nil,
		regressionEventsUsed = 0,
		regressingUntil = nil,
		ruleLocked = false,
	}

	local tinyfolkCount = if type(activeTinyfolkCount) == "number" then activeTinyfolkCount else 0
	nextState.requiredCompletions = computeRequiredCompletions(nextState, tinyfolkCount)
	nextState.lastReason = "site_registered"

	return { accepted = true, reason = "site_registered", state = nextState, alert = nil }
end

function RealmObjectiveState.RecomputeRequiredCompletions(state: State, activeTinyfolkCount: number): State
	local nextState = cloneState(state)
	nextState.requiredCompletions = computeRequiredCompletions(nextState, activeTinyfolkCount)
	nextState.lastReason = "required_recomputed"
	return nextState
end

function RealmObjectiveState.RecordCompletion(
	state: State,
	siteId: string,
	completedByUserId: number?,
	at: number?
): Transition
	local nextState = cloneState(state)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolveAt(at))

	if site.completed == true then
		nextState.lastReason = "site_already_completed"
		return { accepted = false, reason = "site_already_completed", state = nextState, alert = nil }
	end

	if site.ruleLocked == true then
		nextState.lastReason = "rule_locked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "rule_locked", state = nextState, alert = nil }
	end

	if site.objectiveState == "blocked" then
		nextState.lastReason = "blocked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "blocked", state = nextState, alert = nil }
	end

	site.completed = true
	site.completedAt = if type(at) == "number" then at else nil
	site.completedByUserId = if type(completedByUserId) == "number" then completedByUserId else nil
	site.objectiveState = "completed"
	site.progress = nextState.completionProgress
	site.activeUserId = nil
	site.blockedUntil = nil
	site.blockedByUserId = nil
	site.regressingUntil = nil
	nextState.sitesById[siteId] = site

	local completedCount = countCompletedSites(nextState)
	local escapeReady = nextState.requiredCompletions > 0 and completedCount >= nextState.requiredCompletions
	local alert = {
		kind = "objective_completed",
		siteId = siteId,
		completedCount = completedCount,
		requiredCompletions = nextState.requiredCompletions,
		escapeReady = escapeReady,
	}

	nextState.lastReason = "accepted"
	nextState.lastAlert = cloneAlert(alert)
	return { accepted = true, reason = "accepted", state = nextState, alert = alert }
end

function RealmObjectiveState.BeginProgress(state: State, siteId: string, userId: number?, at: number?): Transition
	local nextState = cloneState(state)
	local resolvedAt = resolveAt(at)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolvedAt)

	if site.completed == true then
		nextState.lastReason = "site_already_completed"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "site_already_completed", state = nextState, alert = nil }
	end
	if site.ruleLocked == true then
		nextState.lastReason = "rule_locked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "rule_locked", state = nextState, alert = nil }
	end
	if site.objectiveState == "blocked" then
		nextState.lastReason = "blocked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "blocked", state = nextState, alert = nil }
	end
	if site.objectiveState == "progressing" then
		nextState.lastReason = "already_progressing"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "already_progressing", state = nextState, alert = nil }
	end

	site.objectiveState = "progressing"
	site.activeUserId = if type(userId) == "number" then userId else nil
	site.lastProgressAt = resolvedAt
	site.regressingUntil = nil
	nextState.sitesById[siteId] = site

	local alert = makeObjectiveAlert("objective_progress_began", site, nextState)
	nextState.lastReason = "progress_began"
	nextState.lastAlert = cloneAlert(alert)
	return { accepted = true, reason = "progress_began", state = nextState, alert = alert }
end

function RealmObjectiveState.ApplyProgress(
	state: State,
	siteId: string,
	progressAmount: number,
	userId: number?,
	at: number?
): Transition
	local nextState = cloneState(state)
	local resolvedAt = resolveAt(at)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolvedAt)

	if site.completed == true then
		nextState.lastReason = "site_already_completed"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "site_already_completed", state = nextState, alert = nil }
	end
	if site.ruleLocked == true then
		nextState.lastReason = "rule_locked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "rule_locked", state = nextState, alert = nil }
	end
	if site.objectiveState == "blocked" then
		nextState.lastReason = "blocked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "blocked", state = nextState, alert = nil }
	end

	local amount = nonNegativeNumber(progressAmount, 0)
	if amount <= 0 then
		nextState.lastReason = "invalid_progress"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "invalid_progress", state = nextState, alert = nil }
	end

	site.progress = clampProgress(site.progress + amount, nextState.completionProgress)
	site.activeUserId = if type(userId) == "number" then userId else site.activeUserId
	site.lastProgressAt = resolvedAt
	site.regressingUntil = nil

	if site.progress >= nextState.completionProgress then
		site.completed = true
		site.completedAt = resolvedAt
		site.completedByUserId = if type(userId) == "number" then userId else nil
		site.objectiveState = "completed"
		site.activeUserId = nil
	else
		site.objectiveState = "progressing"
	end

	nextState.sitesById[siteId] = site
	if site.completed == true then
		local completedCount = countCompletedSites(nextState)
		local escapeReady = nextState.requiredCompletions > 0 and completedCount >= nextState.requiredCompletions
		local completedAlert = {
			kind = "objective_completed",
			siteId = siteId,
			completedCount = completedCount,
			requiredCompletions = nextState.requiredCompletions,
			escapeReady = escapeReady,
			objectiveState = site.objectiveState,
			progress = site.progress,
			progressRatio = 1,
		}
		nextState.lastReason = "completed"
		nextState.lastAlert = cloneAlert(completedAlert)
		return { accepted = true, reason = "completed", state = nextState, alert = completedAlert }
	end

	local alert = makeObjectiveAlert("objective_progressed", site, nextState)
	nextState.lastReason = "progress_applied"
	nextState.lastAlert = cloneAlert(alert)
	return { accepted = true, reason = "progress_applied", state = nextState, alert = alert }
end

function RealmObjectiveState.CancelProgress(state: State, siteId: string, at: number?): Transition
	local nextState = cloneState(state)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolveAt(at))

	if site.objectiveState ~= "progressing" then
		nextState.lastReason = "not_progressing"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "not_progressing", state = nextState, alert = nil }
	end

	site.objectiveState = if site.progress > 0 then "contested" else "idle"
	site.activeUserId = nil
	nextState.sitesById[siteId] = site

	local alert = makeObjectiveAlert("objective_progress_canceled", site, nextState)
	nextState.lastReason = "progress_canceled"
	nextState.lastAlert = cloneAlert(alert)
	return { accepted = true, reason = "progress_canceled", state = nextState, alert = alert }
end

function RealmObjectiveState.DisruptProgress(
	state: State,
	siteId: string,
	userId: number?,
	at: number?,
	regressionWindowSeconds: number?
): Transition
	local nextState = cloneState(state)
	local resolvedAt = resolveAt(at)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolvedAt)

	if site.completed == true then
		nextState.lastReason = "site_already_completed"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "site_already_completed", state = nextState, alert = nil }
	end
	if site.ruleLocked == true then
		nextState.lastReason = "rule_locked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "rule_locked", state = nextState, alert = nil }
	end
	if site.objectiveState == "blocked" then
		nextState.lastReason = "blocked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "blocked", state = nextState, alert = nil }
	end
	if site.progress <= 0 then
		nextState.lastReason = "no_progress"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "no_progress", state = nextState, alert = nil }
	end
	if site.regressionEventsUsed >= nextState.majorRegressionMaxEvents then
		nextState.lastReason = "regression_cap_reached"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "regression_cap_reached", state = nextState, alert = nil }
	end

	site.progress = clampProgress(
		math.max(nextState.stabilizationProgress, site.progress - nextState.disruptionDamage),
		nextState.completionProgress
	)
	site.activeUserId = nil
	site.blockedUntil = nil
	site.blockedByUserId = nil
	site.regressionEventsUsed += 1
	site.lastProgressAt = resolvedAt
	local regressionWindow = nonNegativeNumber(regressionWindowSeconds, 3)
	site.regressingUntil = if regressionWindow > 0 then resolvedAt + regressionWindow else nil
	site.objectiveState = "regressing"
	nextState.sitesById[siteId] = site

	local alert = makeObjectiveAlert("objective_disrupted", site, nextState)
	alert.disruptedByUserId = if type(userId) == "number" then userId else nil
	nextState.lastReason = "disrupted"
	nextState.lastAlert = cloneAlert(alert)
	return { accepted = true, reason = "disrupted", state = nextState, alert = alert }
end

function RealmObjectiveState.TickRegression(state: State, siteId: string, at: number): Transition
	local nextState = cloneState(state)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolveAt(at))
	nextState.sitesById[siteId] = site

	local alert = makeObjectiveAlert("objective_tick", site, nextState)
	nextState.lastReason = "tick"
	nextState.lastAlert = cloneAlert(alert)
	return { accepted = true, reason = "tick", state = nextState, alert = alert }
end

function RealmObjectiveState.BlockObjective(
	state: State,
	siteId: string,
	userId: number?,
	at: number?,
	durationSeconds: number?
): Transition
	local nextState = cloneState(state)
	local resolvedAt = resolveAt(at)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolvedAt)

	if site.completed == true then
		nextState.lastReason = "site_already_completed"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "site_already_completed", state = nextState, alert = nil }
	end
	if site.ruleLocked == true then
		nextState.lastReason = "rule_locked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "rule_locked", state = nextState, alert = nil }
	end

	local duration = positiveNumber(durationSeconds, nextState.defaultBlockDurationSeconds)
	site.objectiveState = "blocked"
	site.activeUserId = nil
	site.regressingUntil = nil
	site.blockedUntil = resolvedAt + duration
	site.blockedByUserId = if type(userId) == "number" then userId else nil
	nextState.sitesById[siteId] = site

	local alert = makeObjectiveAlert("objective_blocked", site, nextState)
	nextState.lastReason = "blocked"
	nextState.lastAlert = alert
	return { accepted = true, reason = "blocked", state = nextState, alert = alert }
end

function RealmObjectiveState.UnlockObjective(state: State, siteId: string, at: number?): Transition
	local nextState = cloneState(state)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolveAt(at))

	if site.objectiveState ~= "blocked" and site.ruleLocked ~= true then
		nextState.lastReason = "not_locked"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "not_locked", state = nextState, alert = nil }
	end

	site.ruleLocked = false
	site.blockedUntil = nil
	site.blockedByUserId = nil
	site.objectiveState = if site.progress > 0 then "contested" else "idle"
	nextState.sitesById[siteId] = site

	local alert = makeObjectiveAlert("objective_unlocked", site, nextState)
	nextState.lastReason = "unlocked"
	nextState.lastAlert = alert
	return { accepted = true, reason = "unlocked", state = nextState, alert = alert }
end

function RealmObjectiveState.SetRuleLocked(state: State, siteId: string, locked: boolean, at: number?): Transition
	local nextState = cloneState(state)
	local siteValue, reject = getSiteOrReject(nextState, siteId)
	if reject ~= nil then
		return reject
	end
	local site: ObjectiveSite = refreshSiteTimedState(siteValue :: ObjectiveSite, nextState, resolveAt(at))

	if site.completed == true then
		nextState.lastReason = "site_already_completed"
		nextState.sitesById[siteId] = site
		return { accepted = false, reason = "site_already_completed", state = nextState, alert = nil }
	end

	site.ruleLocked = locked == true
	if site.ruleLocked then
		site.objectiveState = "rule_locked"
		site.activeUserId = nil
		site.regressingUntil = nil
		site.blockedUntil = nil
	else
		site.objectiveState = if site.progress > 0 then "contested" else "idle"
	end
	nextState.sitesById[siteId] = site

	local reason = if site.ruleLocked then "rule_locked" else "unlocked"
	local alert =
		makeObjectiveAlert(if site.ruleLocked then "objective_rule_locked" else "objective_unlocked", site, nextState)
	nextState.lastReason = reason
	nextState.lastAlert = alert
	return { accepted = true, reason = reason, state = nextState, alert = alert }
end

function RealmObjectiveState.GetSnapshot(state: State): any
	local siteIds = sortedSiteIds(state)
	local unresolvedSiteIds: { string } = {}
	local completedSiteIds: { string } = {}
	local sitesById: { [string]: any } = {}

	for _, siteId in ipairs(siteIds) do
		local site = state.sitesById[siteId]
		if site ~= nil then
			if site.completed == true then
				table.insert(completedSiteIds, siteId)
			else
				table.insert(unresolvedSiteIds, siteId)
			end
			local progress = clampProgress(nonNegativeNumber((site :: any).progress, 0), state.completionProgress)
			local objectiveState = if type((site :: any).objectiveState) == "string"
				then (site :: any).objectiveState
				else "idle"
			if site.completed == true then
				objectiveState = "completed"
				progress = state.completionProgress
			end
			sitesById[siteId] = {
				siteId = site.siteId,
				siteType = site.siteType,
				completed = site.completed,
				completedAt = site.completedAt,
				completedByUserId = site.completedByUserId,
				objectiveState = objectiveState,
				progress = progress,
				progressRatio = if state.completionProgress > 0 then progress / state.completionProgress else 0,
				activeUserId = site.activeUserId,
				lastProgressAt = site.lastProgressAt,
				blockedUntil = site.blockedUntil,
				blockedByUserId = site.blockedByUserId,
				regressionEventsUsed = positiveInteger((site :: any).regressionEventsUsed, 0),
				regressingUntil = site.regressingUntil,
				ruleLocked = site.ruleLocked == true,
			}
		end
	end

	local completedCount = #completedSiteIds
	local totalSiteCount = #siteIds
	local escapeReady = state.requiredCompletions > 0 and completedCount >= state.requiredCompletions

	return {
		totalSiteCount = totalSiteCount,
		completedCount = completedCount,
		unresolvedCount = #unresolvedSiteIds,
		requiredCompletions = state.requiredCompletions,
		escapeReady = escapeReady,
		siteIds = siteIds,
		completedSiteIds = completedSiteIds,
		unresolvedSiteIds = unresolvedSiteIds,
		sitesById = sitesById,
		lastReason = state.lastReason,
		lastAlert = state.lastAlert,
	}
end

return RealmObjectiveState
