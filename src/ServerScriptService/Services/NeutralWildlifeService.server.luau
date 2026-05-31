--!nocheck

local NeutralWildlifeConfig = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Config")
			:WaitForChild("NeutralWildlifeConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/NeutralWildlifeConfig")

local WildlifeState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("WildlifeState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/WildlifeState")

local RealmMetadataRegistry = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("RealmAssembly")
			:WaitForChild("RealmMetadataRegistry")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/RealmAssembly/RealmMetadataRegistry")

local NeutralWildlifeService: any = {}
local globalEnv: any = getfenv()

type Diagnostics = {
	spawnAttempts: number,
	spawnSucceeded: number,
	spawnFailed: number,
	disturbanceAttempts: number,
	disturbanceSucceeded: number,
	disturbanceFailed: number,
	interactionAttempts: number,
	interactionSucceeded: number,
	interactionFailed: number,
	interactionFeedAccepted: number,
	interactionFeedDenied: number,
	interactionDispersed: number,
	feedGrantAttempts: number,
	feedGrantSucceeded: number,
	feedGrantCapped: number,
	disturbanceRangeChecks: number,
	disturbanceRangeRejected: number,
	disturbanceMissingPositionRejected: number,
	expiryCount: number,
	despawnCount: number,
	clueEventsAttempted: number,
	clueEventsSucceeded: number,
	lastReason: string,
	lastWildlifeId: string?,
	lastRealmTemplateId: string?,
	lastHabitatGroupId: string?,
	lastSpeciesId: string?,
	lastClueTag: string?,
	lastTickAt: number?,
	habitatSource: string,
	habitatNodeCount: number,
	habitatGroupCount: number,
	anchorResolvedCount: number,
	anchorFallbackCount: number,
	lastAnchorZoneId: string?,
	lastAnchorBucketId: string?,
	lastInteractionOutcome: string?,
}

local runtimeConfig: any = nil
local recordsById: { [string]: any } = {}
local habitatDescriptorsByGroup: { [string]: any } = {}
local feedGrantStateByUserId: { [number]: any } = {}
local nextWildlifeId = 0
local lastSpawnAt = 0
local diagnostics: Diagnostics = {
	spawnAttempts = 0,
	spawnSucceeded = 0,
	spawnFailed = 0,
	disturbanceAttempts = 0,
	disturbanceSucceeded = 0,
	disturbanceFailed = 0,
	interactionAttempts = 0,
	interactionSucceeded = 0,
	interactionFailed = 0,
	interactionFeedAccepted = 0,
	interactionFeedDenied = 0,
	interactionDispersed = 0,
	feedGrantAttempts = 0,
	feedGrantSucceeded = 0,
	feedGrantCapped = 0,
	disturbanceRangeChecks = 0,
	disturbanceRangeRejected = 0,
	disturbanceMissingPositionRejected = 0,
	expiryCount = 0,
	despawnCount = 0,
	clueEventsAttempted = 0,
	clueEventsSucceeded = 0,
	lastReason = "not_started",
	lastWildlifeId = nil,
	lastRealmTemplateId = nil,
	lastHabitatGroupId = nil,
	lastSpeciesId = nil,
	lastClueTag = nil,
	lastTickAt = nil,
	habitatSource = "config",
	habitatNodeCount = 0,
	habitatGroupCount = 0,
	anchorResolvedCount = 0,
	anchorFallbackCount = 0,
	lastAnchorZoneId = nil,
	lastAnchorBucketId = nil,
	lastInteractionOutcome = nil,
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

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local clone: any = {}
	for key, child in pairs(value) do
		clone[key] = cloneTable(child)
	end
	return clone
end

local function resetState(reason: string)
	recordsById = {}
	habitatDescriptorsByGroup = {}
	feedGrantStateByUserId = {}
	nextWildlifeId = 0
	lastSpawnAt = 0
	diagnostics = {
		spawnAttempts = 0,
		spawnSucceeded = 0,
		spawnFailed = 0,
		disturbanceAttempts = 0,
		disturbanceSucceeded = 0,
		disturbanceFailed = 0,
		interactionAttempts = 0,
		interactionSucceeded = 0,
		interactionFailed = 0,
		interactionFeedAccepted = 0,
		interactionFeedDenied = 0,
		interactionDispersed = 0,
		feedGrantAttempts = 0,
		feedGrantSucceeded = 0,
		feedGrantCapped = 0,
		disturbanceRangeChecks = 0,
		disturbanceRangeRejected = 0,
		disturbanceMissingPositionRejected = 0,
		expiryCount = 0,
		despawnCount = 0,
		clueEventsAttempted = 0,
		clueEventsSucceeded = 0,
		lastReason = reason,
		lastWildlifeId = nil,
		lastRealmTemplateId = nil,
		lastHabitatGroupId = nil,
		lastSpeciesId = nil,
		lastClueTag = nil,
		lastTickAt = nil,
		habitatSource = "config",
		habitatNodeCount = 0,
		habitatGroupCount = 0,
		anchorResolvedCount = 0,
		anchorFallbackCount = 0,
		lastAnchorZoneId = nil,
		lastAnchorBucketId = nil,
		lastInteractionOutcome = nil,
	}
end

resetState("not_started")

local function resolveNow(): number
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.now) == "function" then
		local nowValue = configAny.now()
		if isFiniteNumber(nowValue) then
			return nowValue
		end
	end
	return os.clock()
end

local function getConfigNumber(key: string): number
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and isFiniteNumber(configAny[key]) then
		return configAny[key]
	end
	return NeutralWildlifeConfig[key]
end

local function getConfigValue(key: string): any
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and configAny[key] ~= nil then
		return configAny[key]
	end
	return NeutralWildlifeConfig[key]
end

local function resolveRealmMetadataApi(): any
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.realmMetadataApi) == "table" then
		return configAny.realmMetadataApi
	end
	return {
		BuildRealmMetadataSnapshot = function(): any
			return RealmMetadataRegistry.BuildRealmMetadataSnapshot(nil)
		end,
	}
end

local function resolveEventLogApi(): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.eventLogApi) == "table" then
		return configAny.eventLogApi
	end
	local fromEnv = rawget(globalEnv, "_EventLogService_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_EventLogService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function resolveScoreServiceApi(): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.scoreServiceApi) == "table" then
		return configAny.scoreServiceApi
	end
	local fromEnv = rawget(globalEnv, "_ScoreService_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_ScoreService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function resolveRoleServiceApi(): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.roleServiceApi) == "table" then
		return configAny.roleServiceApi
	end
	local fromEnv = rawget(globalEnv, "_RoleService_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_RoleService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function preserveWildlifeMetadata(sourceRecord: any, targetRecord: any)
	if type(sourceRecord) ~= "table" or type(targetRecord) ~= "table" then
		return
	end
	targetRecord.clueTag = sourceRecord.clueTag
	targetRecord.anchorZoneId = sourceRecord.anchorZoneId
	targetRecord.anchorBucketId = sourceRecord.anchorBucketId
	targetRecord.anchorX = sourceRecord.anchorX
	targetRecord.anchorZ = sourceRecord.anchorZ
end

local function updateLastRecordDiagnostics(record: any)
	if type(record) ~= "table" then
		return
	end
	diagnostics.lastWildlifeId = record.wildlifeId
	diagnostics.lastRealmTemplateId = record.realmTemplateId
	diagnostics.lastHabitatGroupId = record.habitatGroupId
	diagnostics.lastSpeciesId = record.speciesId
	diagnostics.lastAnchorZoneId = record.anchorZoneId
	diagnostics.lastAnchorBucketId = record.anchorBucketId
end

local function isRecordInteractionEligible(record: any, at: number): boolean
	if type(record) ~= "table" then
		return false
	end
	if WildlifeState.IsTerminalStatus(record.status) then
		return false
	end
	return at < record.expiresAt
end

local function resolveActorRole(input: any): string?
	if type(input) == "table" and isNonEmptyString(input.actorRole) then
		return input.actorRole
	end
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.roleResolver) == "function" then
		local ok, resolvedRole = pcall(function()
			return configAny.roleResolver(input.actorUserId)
		end)
		if ok and isNonEmptyString(resolvedRole) then
			return resolvedRole
		end
	end
	return nil
end

local function reserveFeedGrant(actorUserId: number, at: number): (boolean, string)
	diagnostics.feedGrantAttempts += 1
	local maxGrants = math.max(0, math.floor(getConfigNumber("MaxFeedGrantsPerWindow")))
	if maxGrants <= 0 then
		diagnostics.feedGrantCapped += 1
		return false, "feed_cap_reached"
	end

	local windowSeconds = math.max(1, math.floor(getConfigNumber("FeedGrantWindowSeconds")))
	local state = feedGrantStateByUserId[actorUserId]
	if type(state) ~= "table" or not isFiniteNumber(state.windowStartedAt) then
		state = {
			windowStartedAt = at,
			grantsUsed = 0,
		}
		feedGrantStateByUserId[actorUserId] = state
	end

	if (at - state.windowStartedAt) >= windowSeconds then
		state.windowStartedAt = at
		state.grantsUsed = 0
	end

	if state.grantsUsed >= maxGrants then
		diagnostics.feedGrantCapped += 1
		return false, "feed_cap_reached"
	end

	state.grantsUsed += 1
	diagnostics.feedGrantSucceeded += 1
	return true, "accepted"
end

local function bestEffortGrantFeedProgression(actorUserId: number, at: number, record: any, outcome: string)
	local scoreServiceApi = resolveScoreServiceApi()
	if type(scoreServiceApi) ~= "table" or type((scoreServiceApi :: any).RequestScoreEvent) ~= "function" then
		return
	end

	local scoreEventId = getConfigValue("FeedScoreEventId")
	if not isNonEmptyString(scoreEventId) then
		scoreEventId = "wildlife_feed"
	end

	pcall(function()
		(scoreServiceApi :: any).RequestScoreEvent(actorUserId, scoreEventId, at, {
			outcome = outcome,
			wildlifeId = record.wildlifeId,
			realmTemplateId = record.realmTemplateId,
			habitatGroupId = record.habitatGroupId,
			anchorZoneId = record.anchorZoneId,
			anchorBucketId = record.anchorBucketId,
		})
	end)
end

local function emitClue(clueTag: string, record: any)
	diagnostics.clueEventsAttempted += 1
	diagnostics.lastClueTag = clueTag

	local eventLogApi = resolveEventLogApi()
	if type(eventLogApi) ~= "table" or type((eventLogApi :: any).RecordEvent) ~= "function" then
		return
	end

	local at = resolveNow()
	local ok = pcall(function()
		(eventLogApi :: any).RecordEvent(
			NeutralWildlifeConfig.ClueCategory,
			"wildlife clue emitted",
			NeutralWildlifeConfig.ClueSeverity,
			at,
			{
				clueTag = clueTag,
				realmTemplateId = record.realmTemplateId,
				habitatGroupId = record.habitatGroupId,
				speciesId = record.speciesId,
				wildlifeId = record.wildlifeId,
				anchorZoneId = record.anchorZoneId,
				anchorBucketId = record.anchorBucketId,
			}
		)
	end)
	if ok then
		diagnostics.clueEventsSucceeded += 1
	end
end

local function activeRecordCount(): number
	local count = 0
	local at = resolveNow()
	for _, record in pairs(recordsById) do
		if WildlifeState.IsActive(record, at) then
			count += 1
		end
	end
	return count
end

local function activeCountByRealmAndHabitat(realmTemplateId: string, habitatGroupId: string): number
	local count = 0
	local at = resolveNow()
	for _, record in pairs(recordsById) do
		if
			record.realmTemplateId == realmTemplateId
			and record.habitatGroupId == habitatGroupId
			and WildlifeState.IsActive(record, at)
		then
			count += 1
		end
	end
	return count
end

local function chooseRealmTemplateIds(): { string }
	local explicitRealmTemplateIds = getConfigValue("realmTemplateIds")
	if type(explicitRealmTemplateIds) == "table" and #explicitRealmTemplateIds > 0 then
		local output = {}
		for _, realmTemplateId in ipairs(explicitRealmTemplateIds) do
			if isNonEmptyString(realmTemplateId) then
				table.insert(output, realmTemplateId)
			end
		end
		if #output > 0 then
			return output
		end
	end

	local realmMetadataApi = resolveRealmMetadataApi()
	if
		type(realmMetadataApi) == "table"
		and type((realmMetadataApi :: any).BuildRealmMetadataSnapshot) == "function"
	then
		local ok, snapshot = pcall(function()
			return (realmMetadataApi :: any).BuildRealmMetadataSnapshot(nil)
		end)
		if ok and type(snapshot) == "table" then
			local realmIds = {}
			for _, entry in ipairs(snapshot) do
				if type(entry) == "table" and isNonEmptyString(entry.realmTemplateId) then
					table.insert(realmIds, entry.realmTemplateId)
				end
			end
			if #realmIds > 0 then
				return realmIds
			end
		end
	end

	return { NeutralWildlifeConfig.DefaultRealmTemplateId }
end

local function getNodeAttribute(node: any, attributeName: string): any
	if type(node) == "table" and type(node.GetAttribute) == "function" then
		local ok, value = pcall(function()
			return node:GetAttribute(attributeName)
		end)
		if ok then
			return value
		end
	end
	if type(node) == "table" then
		return node[attributeName]
	end
	return nil
end

local function parseCommaSeparatedValues(raw: any): { string }
	local output = {}
	if type(raw) ~= "string" or raw == "" then
		return output
	end
	for token in string.gmatch(raw, "[^,]+") do
		local value = string.gsub(token, "^%s*(.-)%s*$", "%1")
		if value ~= "" then
			table.insert(output, value)
		end
	end
	return output
end

local function getNodePosition(node: any): (number?, number?)
	local position = nil
	if type(node) == "table" then
		position = node.Position
	end
	if type(position) == "table" and isFiniteNumber(position.X) and isFiniteNumber(position.Z) then
		return position.X, position.Z
	end

	local anchorX = getNodeAttribute(node, "WildlifeAnchorX")
	local anchorZ = getNodeAttribute(node, "WildlifeAnchorZ")
	if isFiniteNumber(anchorX) and isFiniteNumber(anchorZ) then
		return anchorX, anchorZ
	end

	return nil, nil
end

local function getPositionXZ(positionLike: any): (number?, number?)
	if type(positionLike) ~= "table" then
		return nil, nil
	end
	local x = positionLike.X
	local z = positionLike.Z
	if isFiniteNumber(x) and isFiniteNumber(z) then
		return x, z
	end
	x = positionLike.x
	z = positionLike.z
	if isFiniteNumber(x) and isFiniteNumber(z) then
		return x, z
	end
	return nil, nil
end

local function toAnchorBucketId(anchorX: number, anchorZ: number): string
	local bucketSize = math.max(1, math.floor(getConfigNumber("WildlifeAnchorBucketSize")))
	local bucketX = math.floor(anchorX / bucketSize)
	local bucketZ = math.floor(anchorZ / bucketSize)
	return string.format("%d_%d", bucketX, bucketZ)
end

local function resolveHabitatNodes(): { any }
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.habitatNodes) == "table" then
		return configAny.habitatNodes
	end
	if type(configAny) == "table" and type(configAny.habitatNodeResolver) == "function" then
		local ok, resolved = pcall(function()
			return configAny.habitatNodeResolver()
		end)
		if ok and type(resolved) == "table" then
			return resolved
		end
	end

	local workspaceInstance = nil
	if type(configAny) == "table" and configAny.workspace ~= nil then
		workspaceInstance = configAny.workspace
	else
		local ok, resolvedWorkspace = pcall(function()
			return game:GetService("Workspace")
		end)
		if ok then
			workspaceInstance = resolvedWorkspace
		end
	end
	if workspaceInstance == nil then
		return {}
	end

	local habitatRoot = workspaceInstance
	if type(configAny) == "table" and type(configAny.habitatNodePath) == "table" then
		for _, childName in ipairs(configAny.habitatNodePath) do
			if type(habitatRoot.FindFirstChild) ~= "function" then
				return {}
			end
			local nextNode = habitatRoot:FindFirstChild(childName)
			if nextNode == nil then
				return {}
			end
			habitatRoot = nextNode
		end
	else
		if type(habitatRoot.FindFirstChild) == "function" then
			local map = habitatRoot:FindFirstChild("Map")
			if map ~= nil and type(map.FindFirstChild) == "function" then
				local habitats = map:FindFirstChild("WildlifeHabitats")
				if habitats ~= nil then
					habitatRoot = habitats
				end
			end
		end
	end

	if type(habitatRoot.GetDescendants) ~= "function" then
		return {}
	end

	local ok, descendants = pcall(function()
		return habitatRoot:GetDescendants()
	end)
	if not ok or type(descendants) ~= "table" then
		return {}
	end
	return descendants
end

local function resolveHabitatGroups(): { any }
	local configured = getConfigValue("HabitatGroups")
	if type(configured) ~= "table" then
		diagnostics.habitatSource = "invalid"
		diagnostics.habitatNodeCount = 0
		diagnostics.habitatGroupCount = 0
		return {}
	end

	local configuredByGroup: { [string]: any } = {}
	for _, habitat in ipairs(configured) do
		if type(habitat) == "table" and isNonEmptyString(habitat.habitatGroupId) then
			configuredByGroup[habitat.habitatGroupId] = habitat
		end
	end

	local habitatNodes = resolveHabitatNodes()
	local nodeCount = 0
	local fromNodesByGroup: { [string]: any } = {}
	for _, node in ipairs(habitatNodes) do
		local isBasePart = true
		if type(node) == "table" and type(node.IsA) == "function" then
			local ok, basePartResult = pcall(function()
				return node:IsA("BasePart")
			end)
			isBasePart = ok and basePartResult == true
		end
		if not isBasePart then
			continue
		end

		local habitatGroupId = getNodeAttribute(node, "WildlifeHabitatGroupId")
		if not isNonEmptyString(habitatGroupId) then
			habitatGroupId = getNodeAttribute(node, "HabitatGroupId")
		end
		if not isNonEmptyString(habitatGroupId) and isNonEmptyString(node.Name) then
			habitatGroupId = node.Name
		end
		if not isNonEmptyString(habitatGroupId) then
			continue
		end

		nodeCount += 1
		local entry = fromNodesByGroup[habitatGroupId]
		if entry == nil then
			entry = {
				realmTemplateIds = {},
				realmTemplateSet = {},
				speciesIds = {},
				speciesSet = {},
				targetActive = nil,
				clueTag = nil,
				anchorXTotal = 0,
				anchorZTotal = 0,
				anchorSamples = 0,
				anchorZoneId = nil,
			}
			fromNodesByGroup[habitatGroupId] = entry
		end

		local realmTemplateId = getNodeAttribute(node, "RealmTemplateId")
		if isNonEmptyString(realmTemplateId) and entry.realmTemplateSet[realmTemplateId] ~= true then
			entry.realmTemplateSet[realmTemplateId] = true
			table.insert(entry.realmTemplateIds, realmTemplateId)
		end

		local targetActive = getNodeAttribute(node, "WildlifeTargetActive")
		if isFiniteNumber(targetActive) then
			entry.targetActive = math.max(1, math.floor(targetActive))
		end

		local nodeClueTag = getNodeAttribute(node, "WildlifeClueTag")
		if isNonEmptyString(nodeClueTag) then
			entry.clueTag = nodeClueTag
		end

		local anchorZoneId = getNodeAttribute(node, "WildlifeZoneId")
		if not isNonEmptyString(anchorZoneId) then
			anchorZoneId = getNodeAttribute(node, "ZoneId")
		end
		if isNonEmptyString(anchorZoneId) then
			entry.anchorZoneId = anchorZoneId
		end

		local nodeX, nodeZ = getNodePosition(node)
		if isFiniteNumber(nodeX) and isFiniteNumber(nodeZ) then
			entry.anchorSamples += 1
			entry.anchorXTotal += nodeX
			entry.anchorZTotal += nodeZ
		end

		local speciesFromNode = parseCommaSeparatedValues(getNodeAttribute(node, "WildlifeSpeciesIds"))
		for _, speciesId in ipairs(speciesFromNode) do
			if entry.speciesSet[speciesId] ~= true then
				entry.speciesSet[speciesId] = true
				table.insert(entry.speciesIds, speciesId)
			end
		end
	end

	if nodeCount == 0 then
		diagnostics.habitatSource = "config"
		diagnostics.habitatNodeCount = 0
		diagnostics.habitatGroupCount = #configured
		diagnostics.anchorResolvedCount = 0
		diagnostics.anchorFallbackCount = #configured
		return configured
	end

	local merged = {}
	local resolvedAnchors = 0
	local fallbackAnchors = 0
	for habitatGroupId, nodeEntry in pairs(fromNodesByGroup) do
		local configuredEntry = configuredByGroup[habitatGroupId]
		local realmTemplateIds = {}
		local realmTemplateSet = {}
		if type(configuredEntry) == "table" and type(configuredEntry.realmTemplateIds) == "table" then
			for _, realmTemplateId in ipairs(configuredEntry.realmTemplateIds) do
				if isNonEmptyString(realmTemplateId) and realmTemplateSet[realmTemplateId] ~= true then
					realmTemplateSet[realmTemplateId] = true
					table.insert(realmTemplateIds, realmTemplateId)
				end
			end
		end
		for _, realmTemplateId in ipairs(nodeEntry.realmTemplateIds) do
			if isNonEmptyString(realmTemplateId) and realmTemplateSet[realmTemplateId] ~= true then
				realmTemplateSet[realmTemplateId] = true
				table.insert(realmTemplateIds, realmTemplateId)
			end
		end

		local speciesIds = if type(configuredEntry) == "table" and type(configuredEntry.speciesIds) == "table"
			then configuredEntry.speciesIds
			else nodeEntry.speciesIds
		if #speciesIds == 0 then
			speciesIds = { "wildlife" }
		end

		local anchorX = nil
		local anchorZ = nil
		if nodeEntry.anchorSamples > 0 then
			anchorX = nodeEntry.anchorXTotal / nodeEntry.anchorSamples
			anchorZ = nodeEntry.anchorZTotal / nodeEntry.anchorSamples
			resolvedAnchors += 1
		else
			fallbackAnchors += 1
		end

		local anchorZoneId = if isNonEmptyString(nodeEntry.anchorZoneId)
			then nodeEntry.anchorZoneId
			else string.format("zone_%s", habitatGroupId)
		local anchorBucketId = if isFiniteNumber(anchorX) and isFiniteNumber(anchorZ)
			then toAnchorBucketId(anchorX, anchorZ)
			else string.format("fallback_%s", habitatGroupId)

		table.insert(merged, {
			habitatGroupId = habitatGroupId,
			realmTemplateIds = realmTemplateIds,
			targetActive = if type(configuredEntry) == "table" and isFiniteNumber(configuredEntry.targetActive)
				then configuredEntry.targetActive
				else (nodeEntry.targetActive or 1),
			speciesIds = speciesIds,
			clueTag = if type(configuredEntry) == "table" and isNonEmptyString(configuredEntry.clueTag)
				then configuredEntry.clueTag
				else (nodeEntry.clueTag or string.format("disturbed_%s", habitatGroupId)),
			anchorZoneId = anchorZoneId,
			anchorBucketId = anchorBucketId,
			anchorX = anchorX,
			anchorZ = anchorZ,
		})

		habitatDescriptorsByGroup[habitatGroupId] = {
			anchorZoneId = anchorZoneId,
			anchorBucketId = anchorBucketId,
			anchorX = anchorX,
			anchorZ = anchorZ,
		}
	end

	table.sort(merged, function(a: any, b: any)
		return tostring(a.habitatGroupId) < tostring(b.habitatGroupId)
	end)

	if #merged == 0 then
		diagnostics.habitatSource = "config_fallback"
		diagnostics.habitatNodeCount = nodeCount
		diagnostics.habitatGroupCount = #configured
		diagnostics.anchorResolvedCount = 0
		diagnostics.anchorFallbackCount = #configured
		return configured
	end

	diagnostics.habitatSource = "workspace_nodes"
	diagnostics.habitatNodeCount = nodeCount
	diagnostics.habitatGroupCount = #merged
	diagnostics.anchorResolvedCount = resolvedAnchors
	diagnostics.anchorFallbackCount = fallbackAnchors
	return merged
end

local function habitatSupportsRealm(habitat: any, realmTemplateId: string): boolean
	if type(habitat) ~= "table" then
		return false
	end
	local realms = habitat.realmTemplateIds
	if type(realms) ~= "table" or #realms == 0 then
		return true
	end
	for _, value in ipairs(realms) do
		if value == realmTemplateId then
			return true
		end
	end
	return false
end

local function nextSpeciesId(habitat: any): string
	local speciesIds = if type(habitat.speciesIds) == "table" then habitat.speciesIds else { "wildlife" }
	if #speciesIds == 0 then
		return "wildlife"
	end
	local index = (nextWildlifeId % #speciesIds) + 1
	local speciesId = speciesIds[index]
	if not isNonEmptyString(speciesId) then
		return "wildlife"
	end
	return speciesId
end

local function buildWildlifeId(realmTemplateId: string): string
	nextWildlifeId += 1
	return string.format("wildlife_%s_%d", realmTemplateId, nextWildlifeId)
end

local function spawnRecord(realmTemplateId: string, habitat: any): boolean
	diagnostics.spawnAttempts += 1
	local at = resolveNow()
	local wildlifeId = buildWildlifeId(realmTemplateId)
	local speciesId = nextSpeciesId(habitat)
	local accepted, reason, record = WildlifeState.NewRecord({
		wildlifeId = wildlifeId,
		realmTemplateId = realmTemplateId,
		habitatGroupId = habitat.habitatGroupId,
		speciesId = speciesId,
		spawnedAt = at,
		expiresAt = at + getConfigNumber("WildlifeLifetimeSeconds"),
	})
	if not accepted or record == nil then
		diagnostics.spawnFailed += 1
		diagnostics.lastReason = reason
		diagnostics.lastWildlifeId = wildlifeId
		diagnostics.lastRealmTemplateId = realmTemplateId
		diagnostics.lastHabitatGroupId = habitat.habitatGroupId
		diagnostics.lastSpeciesId = speciesId
		return false
	end

	recordsById[record.wildlifeId] = record
	record.clueTag = habitat.clueTag
	record.anchorZoneId = habitat.anchorZoneId
	record.anchorBucketId = habitat.anchorBucketId
	record.anchorX = habitat.anchorX
	record.anchorZ = habitat.anchorZ
	diagnostics.spawnSucceeded += 1
	diagnostics.lastReason = "accepted"
	updateLastRecordDiagnostics(record)
	return true
end

local function maintainPopulation(): any
	local habitats = resolveHabitatGroups()
	if type(habitats) ~= "table" or #habitats == 0 then
		diagnostics.lastReason = "habitat_groups_invalid"
		return { accepted = false, reason = "habitat_groups_invalid" }
	end

	local maxActive = math.floor(getConfigNumber("MaxActiveWildlifeTotal"))
	local targetActive = math.floor(getConfigNumber("TargetActiveWildlifeTotal"))
	if targetActive > maxActive then
		targetActive = maxActive
	end

	if activeRecordCount() >= targetActive then
		diagnostics.lastReason = "population_target_met"
		return { accepted = true, reason = "population_target_met" }
	end

	local spawned = 0
	local realmTemplateIds = chooseRealmTemplateIds()
	for _, realmTemplateId in ipairs(realmTemplateIds) do
		for _, habitat in ipairs(habitats) do
			if not habitatSupportsRealm(habitat, realmTemplateId) then
				continue
			end
			if not isNonEmptyString(habitat.habitatGroupId) then
				continue
			end

			local targetPerHabitat = if isFiniteNumber(habitat.targetActive)
				then math.max(1, math.floor(habitat.targetActive))
				else 1
			local currentPerHabitat = activeCountByRealmAndHabitat(realmTemplateId, habitat.habitatGroupId)
			while currentPerHabitat < targetPerHabitat and activeRecordCount() < maxActive do
				if spawnRecord(realmTemplateId, habitat) then
					spawned += 1
					currentPerHabitat += 1
				end
				if activeRecordCount() >= targetActive then
					break
				end
			end
			if activeRecordCount() >= targetActive then
				break
			end
		end
		if activeRecordCount() >= targetActive then
			break
		end
	end

	if spawned == 0 then
		diagnostics.lastReason = "spawn_capacity_reached"
		return { accepted = true, reason = "spawn_capacity_reached" }
	end

	lastSpawnAt = resolveNow()
	diagnostics.lastReason = "accepted"
	return { accepted = true, reason = "accepted", spawned = spawned }
end

local function resolveExpiryAndRespawn(at: number)
	local changed = false
	for wildlifeId, record in pairs(recordsById) do
		local expired, reason, nextRecord = WildlifeState.ResolveExpiry(record, at)
		if expired and nextRecord ~= nil then
			preserveWildlifeMetadata(record, nextRecord)
			recordsById[wildlifeId] = nextRecord
			diagnostics.expiryCount += 1
			diagnostics.lastReason = reason
			emitClue("wildlife_missing", nextRecord)
			changed = true
		end
	end

	if changed or (at - lastSpawnAt) >= getConfigNumber("RespawnIntervalSeconds") then
		maintainPopulation()
	end
end

function NeutralWildlifeService.Tick(input: any?): any
	local at = if type(input) == "table" and isFiniteNumber(input.at) then input.at else resolveNow()
	diagnostics.lastTickAt = at
	resolveExpiryAndRespawn(at)
	return {
		accepted = true,
		reason = "accepted",
		at = at,
	}
end

function NeutralWildlifeService.GetWildlifeSnapshot(_input: any?): any
	local at = resolveNow()
	local records = {}
	for _, record in pairs(recordsById) do
		table.insert(records, WildlifeState.BuildSnapshot(record, at))
	end
	table.sort(records, function(a: any, b: any)
		return tostring(a.wildlifeId) < tostring(b.wildlifeId)
	end)

	return {
		accepted = true,
		reason = "accepted",
		at = at,
		records = records,
		activeCount = activeRecordCount(),
	}
end

function NeutralWildlifeService.GetWildlifeDiagnostics(): Diagnostics
	return cloneTable(diagnostics)
end

function NeutralWildlifeService.RequestWildlifeDisturbance(input: any): any
	diagnostics.disturbanceAttempts += 1
	if type(input) ~= "table" then
		diagnostics.disturbanceFailed += 1
		diagnostics.lastReason = "request_invalid"
		return {
			accepted = false,
			reason = "request_invalid",
		}
	end
	if not isNonEmptyString(input.wildlifeId) then
		diagnostics.disturbanceFailed += 1
		diagnostics.lastReason = "wildlife_id_invalid"
		return {
			accepted = false,
			reason = "wildlife_id_invalid",
		}
	end
	if not isPositiveInteger(input.userId) then
		diagnostics.disturbanceFailed += 1
		diagnostics.lastReason = "user_id_invalid"
		return {
			accepted = false,
			reason = "user_id_invalid",
		}
	end

	local record = recordsById[input.wildlifeId]
	if record == nil then
		diagnostics.disturbanceFailed += 1
		diagnostics.lastReason = "wildlife_not_found"
		return {
			accepted = false,
			reason = "wildlife_not_found",
		}
	end

	local maxDisturbanceDistance = getConfigNumber("DisturbanceMaxDistance")
	if maxDisturbanceDistance > 0 and isFiniteNumber(record.anchorX) and isFiniteNumber(record.anchorZ) then
		diagnostics.disturbanceRangeChecks += 1
		local requestPosition = input.position
		if requestPosition == nil then
			requestPosition = input.worldPosition
		end
		local requestX, requestZ = getPositionXZ(requestPosition)
		if not isFiniteNumber(requestX) or not isFiniteNumber(requestZ) then
			diagnostics.disturbanceFailed += 1
			diagnostics.disturbanceMissingPositionRejected += 1
			diagnostics.lastReason = "disturbance_position_required"
			return {
				accepted = false,
				reason = "disturbance_position_required",
			}
		end

		local dx = requestX - record.anchorX
		local dz = requestZ - record.anchorZ
		local distance = math.sqrt((dx * dx) + (dz * dz))
		if distance > maxDisturbanceDistance then
			diagnostics.disturbanceFailed += 1
			diagnostics.disturbanceRangeRejected += 1
			diagnostics.lastReason = "disturbance_out_of_range"
			return {
				accepted = false,
				reason = "disturbance_out_of_range",
			}
		end
	end

	local at = resolveNow()
	local accepted, reason, nextRecord = WildlifeState.ResolveDisturbance(record, at)
	if not accepted or nextRecord == nil then
		diagnostics.disturbanceFailed += 1
		diagnostics.lastReason = reason
		if nextRecord ~= nil then
			recordsById[input.wildlifeId] = nextRecord
		end
		return {
			accepted = false,
			reason = reason,
		}
	end

	preserveWildlifeMetadata(record, nextRecord)

	recordsById[input.wildlifeId] = nextRecord
	diagnostics.disturbanceSucceeded += 1
	diagnostics.lastReason = reason
	updateLastRecordDiagnostics(nextRecord)

	emitClue("wildlife_disturbed", nextRecord)

	return {
		accepted = true,
		reason = reason,
		snapshot = WildlifeState.BuildSnapshot(nextRecord, at),
	}
end

function NeutralWildlifeService.RequestWildlifeInteraction(input: any): any
	diagnostics.interactionAttempts += 1
	if type(input) ~= "table" then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "request_invalid"
		return {
			accepted = false,
			reason = "request_invalid",
		}
	end
	if not isNonEmptyString(input.wildlifeId) then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "wildlife_id_invalid"
		return {
			accepted = false,
			reason = "wildlife_id_invalid",
		}
	end
	if not isPositiveInteger(input.actorUserId) then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "actor_user_id_invalid"
		return {
			accepted = false,
			reason = "actor_user_id_invalid",
		}
	end

	local outcome = input.outcome
	if outcome ~= "feed_accepted" and outcome ~= "feed_denied" and outcome ~= "wildlife_dispersed" then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "interaction_outcome_invalid"
		return {
			accepted = false,
			reason = "interaction_outcome_invalid",
		}
	end

	local role = resolveActorRole(input)
	if role ~= "Giant" then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "actor_role_forbidden"
		return {
			accepted = false,
			reason = "actor_role_forbidden",
		}
	end

	local roleServiceApi = resolveRoleServiceApi()
	if
		type(roleServiceApi) == "table"
		and type((roleServiceApi :: any).CanPlayerPerformInteraction) == "function"
		and (roleServiceApi :: any).CanPlayerPerformInteraction(input.actorUserId, "wildlifeInteraction") ~= true
	then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "actor_role_forbidden"
		return {
			accepted = false,
			reason = "actor_role_forbidden",
		}
	end

	local record = recordsById[input.wildlifeId]
	if record == nil then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "wildlife_not_found"
		return {
			accepted = false,
			reason = "wildlife_not_found",
		}
	end

	local at = resolveNow()
	if not isRecordInteractionEligible(record, at) then
		diagnostics.interactionFailed += 1
		diagnostics.lastReason = "wildlife_ineligible"
		return {
			accepted = false,
			reason = "wildlife_ineligible",
		}
	end

	if outcome == "feed_denied" then
		diagnostics.interactionSucceeded += 1
		diagnostics.interactionFeedDenied += 1
		diagnostics.lastReason = "feed_denied"
		diagnostics.lastInteractionOutcome = "feed_denied"
		updateLastRecordDiagnostics(record)
		emitClue("wildlife_feed_denied", record)
		return {
			accepted = true,
			reason = "feed_denied",
			snapshot = WildlifeState.BuildSnapshot(record, at),
		}
	end

	local nextRecord = nil
	if outcome == "feed_accepted" then
		local grantAccepted, grantReason = reserveFeedGrant(input.actorUserId, at)
		if not grantAccepted then
			diagnostics.interactionFailed += 1
			diagnostics.lastReason = grantReason
			return {
				accepted = false,
				reason = grantReason,
			}
		end

		local despawnAccepted, _, despawnRecord = WildlifeState.ResolveDespawn(record, "feed_accepted", at)
		if not despawnAccepted or despawnRecord == nil then
			diagnostics.interactionFailed += 1
			diagnostics.lastReason = "wildlife_ineligible"
			return {
				accepted = false,
				reason = "wildlife_ineligible",
			}
		end
		nextRecord = despawnRecord
		preserveWildlifeMetadata(record, nextRecord)
		diagnostics.interactionFeedAccepted += 1
		diagnostics.lastInteractionOutcome = "feed_accepted"
		bestEffortGrantFeedProgression(input.actorUserId, at, nextRecord, "feed_accepted")
		emitClue("wildlife_feed", nextRecord)
	else
		local despawnAccepted, _, despawnRecord = WildlifeState.ResolveDespawn(record, "wildlife_dispersed", at)
		if not despawnAccepted or despawnRecord == nil then
			diagnostics.interactionFailed += 1
			diagnostics.lastReason = "wildlife_ineligible"
			return {
				accepted = false,
				reason = "wildlife_ineligible",
			}
		end
		nextRecord = despawnRecord
		preserveWildlifeMetadata(record, nextRecord)
		diagnostics.interactionDispersed += 1
		diagnostics.lastInteractionOutcome = "wildlife_dispersed"
		emitClue("wildlife_dispersed", nextRecord)
	end
	recordsById[input.wildlifeId] = nextRecord
	diagnostics.interactionSucceeded += 1
	diagnostics.despawnCount += 1
	diagnostics.lastReason = nextRecord.lastReason
	updateLastRecordDiagnostics(nextRecord)

	return {
		accepted = true,
		reason = nextRecord.lastReason,
		snapshot = WildlifeState.BuildSnapshot(nextRecord, at),
	}
end

function NeutralWildlifeService.Start(config: any?): any
	runtimeConfig = if type(config) == "table" then config else {}
	resetState("started")
	lastSpawnAt = resolveNow()
	maintainPopulation()
	return {
		ok = true,
		reason = nil,
	}
end

function NeutralWildlifeService.ConfigureForTests(config: any): any
	return NeutralWildlifeService.Start(config)
end

function NeutralWildlifeService.ResetForTests()
	runtimeConfig = nil
	resetState("reset")
end

NeutralWildlifeService.Start({})

globalEnv._NeutralWildlifeService_QueryAPI = {
	Start = function(config: any?): any
		return NeutralWildlifeService.Start(config)
	end,
	Tick = function(input: any?): any
		return NeutralWildlifeService.Tick(input)
	end,
	GetWildlifeSnapshot = function(input: any?): any
		return NeutralWildlifeService.GetWildlifeSnapshot(input)
	end,
	GetWildlifeDiagnostics = function(): any
		return NeutralWildlifeService.GetWildlifeDiagnostics()
	end,
	RequestWildlifeDisturbance = function(input: any): any
		return NeutralWildlifeService.RequestWildlifeDisturbance(input)
	end,
	RequestWildlifeInteraction = function(input: any): any
		return NeutralWildlifeService.RequestWildlifeInteraction(input)
	end,
	ConfigureForTests = function(config: any): any
		return NeutralWildlifeService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		return NeutralWildlifeService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_NeutralWildlifeService_QueryAPI", globalEnv._NeutralWildlifeService_QueryAPI)
end

return NeutralWildlifeService
