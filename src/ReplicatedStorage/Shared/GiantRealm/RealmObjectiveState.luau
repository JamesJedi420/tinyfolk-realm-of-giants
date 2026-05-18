--!strict

local RealmObjectiveState = {}

export type ObjectiveSite = {
	siteId: string,
	siteType: string,
	completed: boolean,
	completedAt: number?,
	completedByUserId: number?,
}

export type State = {
	sitesById: { [string]: ObjectiveSite },
	baseRequiredCompletions: number,
	minimumRequiredCompletions: number,
	requiredCompletions: number,
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
	}
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
		lastReason = state.lastReason,
		lastAlert = state.lastAlert,
	}
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
	local site = nextState.sitesById[siteId]
	if site == nil then
		nextState.lastReason = "site_not_found"
		return { accepted = false, reason = "site_not_found", state = nextState, alert = nil }
	end

	if site.completed == true then
		nextState.lastReason = "site_already_completed"
		return { accepted = false, reason = "site_already_completed", state = nextState, alert = nil }
	end

	site.completed = true
	site.completedAt = if type(at) == "number" then at else nil
	site.completedByUserId = if type(completedByUserId) == "number" then completedByUserId else nil
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
	nextState.lastAlert = alert
	return { accepted = true, reason = "accepted", state = nextState, alert = alert }
end

function RealmObjectiveState.GetSnapshot(state: State): any
	local siteIds = sortedSiteIds(state)
	local unresolvedSiteIds: { string } = {}
	local completedSiteIds: { string } = {}

	for _, siteId in ipairs(siteIds) do
		local site = state.sitesById[siteId]
		if site ~= nil then
			if site.completed == true then
				table.insert(completedSiteIds, siteId)
			else
				table.insert(unresolvedSiteIds, siteId)
			end
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
		lastReason = state.lastReason,
		lastAlert = state.lastAlert,
	}
end

return RealmObjectiveState
