--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local STARTUP_WAIT_TIMEOUT_SECONDS = 10

local ConstructionConfig: any
local ResourceFlowState: any
local ContextualTaskProgressLogic: any
local TaskQteTimingLogic: any

local REMOTES_FOLDER_NAME = "Remotes"
local BUILD_REMOTE_NAME = "ConstructionBuildRequest"
local DEBUG_REQUEST_REMOTE_NAME = "ConstructionDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "ConstructionDebugStateResponse"

local CONSTRUCTION_ROOT_PATH = { "Map" }

local ATTRIBUTE_IS_BUILT = "IsBuilt"
local ATTRIBUTE_BUILD_COUNT = "BuildCount"
local ATTRIBUTE_LAST_BUILT_BY = "LastBuiltByUserId"
local ATTRIBUTE_COST_WOOD = "ConstructionCostWood"
local ATTRIBUTE_COST_STONE = "ConstructionCostStone"
local ATTRIBUTE_WOOD_STORED_TOTAL = "WoodStoredTotal"
local ATTRIBUTE_WOOD_USABLE_TOTAL = "WoodUsableTotal"
local ATTRIBUTE_STONE_STORED_TOTAL = "StoneStoredTotal"
local ATTRIBUTE_STONE_USABLE_TOTAL = "StoneUsableTotal"
local BUILT_COLOR = Color3.fromRGB(92, 168, 104)
local BUILT_MATERIAL = Enum.Material.Grass

type ConstructionSiteState = {
	siteId: string,
	part: BasePart,
	isBuilt: boolean,
	buildCount: number,
	lastBuiltByUserId: number?,
}

type DistrictBuildState = {
	districtId: string,
	placedByUserId: number,
	placedAt: number,
	isBuilt: boolean,
	buildCount: number,
	lastBuiltByUserId: number?,
	woodCost: number,
	stoneCost: number,
}

local siteStateById: { [string]: ConstructionSiteState } = {}
local districtBuildStateById: { [string]: DistrictBuildState } = {}
local lastRequestAtByUserId: { [number]: number? } = {}
local taskStateBySiteId: { [string]: any } = {}

local function debugLog(message: string)
	print(string.format("[ConstructionService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[ConstructionService] %s", message))
end

debugLog("Booting service")

local function requireChildModule(parent: Instance, childName: string): any
	debugLog(
		string.format(
			"Resolving dependency child=%s parent=%s timeout=%ds",
			childName,
			parent:GetFullName(),
			STARTUP_WAIT_TIMEOUT_SECONDS
		)
	)
	local child = parent:WaitForChild(childName, STARTUP_WAIT_TIMEOUT_SECONDS)
	if not child then
		error(string.format("startup_dependency_missing child=%s parent=%s", childName, parent:GetFullName()))
	end

	local ok, moduleOrError = pcall(function()
		return require(child)
	end)
	if not ok then
		error(string.format("startup_dependency_require_failed child=%s error=%s", childName, tostring(moduleOrError)))
	end

	debugLog(string.format("Resolved dependency child=%s", childName))
	return moduleOrError
end

local function resolveDependencies()
	local shared = ReplicatedStorage:WaitForChild("Shared", STARTUP_WAIT_TIMEOUT_SECONDS)
	if not shared then
		error("startup_dependency_missing child=Shared parent=ReplicatedStorage")
	end

	local config = shared:WaitForChild("Config", STARTUP_WAIT_TIMEOUT_SECONDS)
	if not config then
		error("startup_dependency_missing child=Config parent=ReplicatedStorage.Shared")
	end

	local construction = shared:WaitForChild("Construction", STARTUP_WAIT_TIMEOUT_SECONDS)
	if not construction then
		error("startup_dependency_missing child=Construction parent=ReplicatedStorage.Shared")
	end

	ConstructionConfig = requireChildModule(config, "ConstructionConfig")
	ResourceFlowState = requireChildModule(script.Parent, "ResourceFlowState")
	ContextualTaskProgressLogic = requireChildModule(construction, "ContextualTaskProgressLogic")
	TaskQteTimingLogic = requireChildModule(construction, "TaskQteTimingLogic")
end

local dependenciesReady, dependencyError = pcall(resolveDependencies)
if not dependenciesReady then
	debugWarn(string.format("Startup failed during dependency resolution error=%s", tostring(dependencyError)))
	return
end

debugLog("Dependency resolution complete")

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	debugLog("Created ReplicatedStorage.Remotes folder")
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		debugLog(string.format("Using existing ReplicatedStorage.Remotes.%s", remoteName))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	debugLog(string.format("Created ReplicatedStorage.Remotes.%s", remoteName))
	return remote
end

local function isCoolingDown(userId: number, at: number?): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end
	local lastAt = last :: number

	if type(at) == "number" then
		return (at - lastAt) < ConstructionConfig.RequestCooldownSeconds
	end

	return (os.clock() - lastAt) < ConstructionConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number?)
	lastRequestAtByUserId[userId] = if type(at) == "number" then at else os.clock()
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root :: BasePart
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

	return (humanoid :: Humanoid).Health > 0
end

local function findConstructionRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in CONSTRUCTION_ROOT_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function shouldTrackConstructionPart(part: BasePart): boolean
	return string.match(part.Name, "^" .. ConstructionConfig.ConstructionSiteNamePrefix) ~= nil
end

local function getSiteCost(siteId: string): (number?, number?)
	local configured = ConstructionConfig.CostBySiteId[siteId]
	if type(configured) ~= "table" then
		return nil
	end

	local woodCost = configured.wood
	local stoneCost = configured.stone
	if type(woodCost) ~= "number" or type(stoneCost) ~= "number" then
		return nil
	end

	if woodCost < 0 or stoneCost < 0 then
		return nil
	end

	return woodCost, stoneCost
end

local function applyDebugAttributes(state: ConstructionSiteState)
	local woodCost, stoneCost = getSiteCost(state.siteId)
	local flowSnapshot = ResourceFlowState.GetSnapshot()

	state.part:SetAttribute(ATTRIBUTE_IS_BUILT, state.isBuilt)
	state.part:SetAttribute(ATTRIBUTE_BUILD_COUNT, state.buildCount)
	state.part:SetAttribute(ATTRIBUTE_LAST_BUILT_BY, state.lastBuiltByUserId)
	state.part:SetAttribute(ATTRIBUTE_COST_WOOD, woodCost)
	state.part:SetAttribute(ATTRIBUTE_COST_STONE, stoneCost)
	state.part:SetAttribute(ATTRIBUTE_WOOD_STORED_TOTAL, flowSnapshot.Wood.stored)
	state.part:SetAttribute(ATTRIBUTE_WOOD_USABLE_TOTAL, flowSnapshot.Wood.usable)
	state.part:SetAttribute(ATTRIBUTE_STONE_STORED_TOTAL, flowSnapshot.Stone.stored)
	state.part:SetAttribute(ATTRIBUTE_STONE_USABLE_TOTAL, flowSnapshot.Stone.usable)
end

local function applyBuiltVisualState(state: ConstructionSiteState)
	if state.isBuilt then
		state.part.Color = BUILT_COLOR
		state.part.Material = BUILT_MATERIAL
	end
end

local function registerConstructionPart(part: BasePart)
	local siteId = part.Name
	if siteStateById[siteId] then
		debugWarn(string.format("Duplicate construction site id ignored: %s", siteId))
		return
	end

	local woodCost, stoneCost = getSiteCost(siteId)
	if not woodCost or not stoneCost then
		debugWarn(string.format("Construction site has invalid or missing cost config id=%s", siteId))
		return
	end

	local state: ConstructionSiteState = {
		siteId = siteId,
		part = part,
		isBuilt = false,
		buildCount = 0,
		lastBuiltByUserId = nil,
	}

	siteStateById[siteId] = state
	applyBuiltVisualState(state)
	applyDebugAttributes(state)
	debugLog(
		string.format("Registered construction site id=%s woodCost=%.0f stoneCost=%.0f", siteId, woodCost, stoneCost)
	)
end

local function registerConstructionSitesFromWorkspace()
	local root = findConstructionRoot()
	if root == nil then
		debugWarn("No construction root found at Workspace.Map")
		return
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackConstructionPart(descendant) then
			registerConstructionPart(descendant)
		end
	end

	if next(siteStateById) == nil then
		debugWarn("No construction sites registered under Workspace.Map")
	end
end

local function initializeDistrictBuildStateFromPlacementQueryAPI()
	local queryApi = _G._DistrictPlacementService_QueryAPI
	if type(queryApi) ~= "table" then
		debugWarn("District placement query API unavailable at startup; skipping district build-state discovery")
		return
	end

	local getAllPlacedDistricts = queryApi.GetAllPlacedDistricts
	if type(getAllPlacedDistricts) ~= "function" then
		debugWarn("District placement query API missing GetAllPlacedDistricts; skipping district build-state discovery")
		return
	end

	local ok, placedDistrictsOrError = pcall(getAllPlacedDistricts)
	if not ok then
		debugWarn(string.format("District placement discovery failed error=%s", tostring(placedDistrictsOrError)))
		return
	end

	if type(placedDistrictsOrError) ~= "table" then
		debugWarn("District placement discovery returned invalid snapshot; expected table")
		return
	end

	local discoveredCount = 0
	for districtId, placedState in pairs(placedDistrictsOrError) do
		local placedStateAny = placedState :: any
		local placedByUserIdAny = placedStateAny.placedByUserId
		local placedAtAny = placedStateAny.placedAt
		if
			type(districtId) == "string"
			and districtId ~= ""
			and type(placedStateAny) == "table"
			and type(placedByUserIdAny) == "number"
			and type(placedAtAny) == "number"
		then
			districtBuildStateById[districtId] = {
				districtId = districtId,
				placedByUserId = placedByUserIdAny,
				placedAt = placedAtAny,
				isBuilt = false,
				buildCount = 0,
				lastBuiltByUserId = nil,
				woodCost = ConstructionConfig.DistrictDefaultCost.wood,
				stoneCost = ConstructionConfig.DistrictDefaultCost.stone,
			}
			discoveredCount += 1
		end
	end

	debugLog(string.format("Initialized district build-state entries=%d", discoveredCount))
end

local function rejectBuild(player: Player, reason: string)
	debugWarn(string.format("Rejected ConstructionBuildRequest userId=%d reason=%s", player.UserId, reason))
end

local function logBuildOutcome(status: string, player: Player, siteId: string, reason: string?)
	local flowSnapshot = ResourceFlowState.GetSnapshot()
	debugLog(
		string.format(
			"BuildOutcome status=%s userId=%d siteId=%s reason=%s woodStored=%.0f stoneStored=%.0f",
			status,
			player.UserId,
			siteId,
			tostring(reason),
			flowSnapshot.Wood.stored,
			flowSnapshot.Stone.stored
		)
	)
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected ConstructionDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local function applyTaskAttributes(player: Player, taskSnapshot: any)
	local setAttribute = (player :: any).SetAttribute
	if type(setAttribute) ~= "function" then
		return
	end

	setAttribute(player, ConstructionConfig.TaskActiveSiteIdAttribute, taskSnapshot.activeTaskId)
	setAttribute(player, ConstructionConfig.TaskProgressRatioAttribute, taskSnapshot.progressRatio)
	setAttribute(player, ConstructionConfig.TaskStartedAtAttribute, taskSnapshot.startedAt)
	setAttribute(player, ConstructionConfig.TaskEndsAtAttribute, taskSnapshot.endsAt)
	setAttribute(player, ConstructionConfig.TaskLastReasonAttribute, taskSnapshot.lastReason)
	setAttribute(player, ConstructionConfig.TaskObjectiveStateAttribute, taskSnapshot.objectiveState)
	setAttribute(player, ConstructionConfig.TaskProgressSecondsAttribute, taskSnapshot.progressSeconds)
	setAttribute(player, ConstructionConfig.TaskRegressionCountAttribute, taskSnapshot.majorRegressionEvents)
	setAttribute(player, ConstructionConfig.TaskRegressingUntilAttribute, taskSnapshot.regressingUntil)
end

local function setTaskQteResultAttribute(player: Player, result: string?)
	local setAttribute = (player :: any).SetAttribute
	if type(setAttribute) ~= "function" then
		return
	end

	setAttribute(player, ConstructionConfig.TaskQteResultAttribute, result)
end

local function getTaskStateForSite(siteId: string): any
	local existing = taskStateBySiteId[siteId]
	if existing ~= nil then
		return existing
	end

	local created = ContextualTaskProgressLogic.New()
	taskStateBySiteId[siteId] = created
	return created
end

local function attemptSiteBuild(player: Player, siteId: string, siteState: ConstructionSiteState): (boolean, string?)
	if siteState.isBuilt then
		return false, "already_built"
	end

	if not isPlayerAlive(player) then
		return false, "player_not_alive"
	end

	local root = getHumanoidRootPart(player)
	if root == nil then
		return false, "humanoid_root_missing"
	end

	local distance = (siteState.part.Position - root.Position).Magnitude
	if distance > ConstructionConfig.InteractionRangeStuds then
		return false,
			string.format("out_of_range distance=%.2f max=%.2f", distance, ConstructionConfig.InteractionRangeStuds)
	end

	local woodCost, stoneCost = getSiteCost(siteId)
	if not woodCost or not stoneCost then
		return false, "invalid_site_cost_config"
	end

	local spent, flowSnapshot, spendError =
		ResourceFlowState.SpendStoredAtomic(woodCost, stoneCost, "Construction:" .. siteId)
	if not spent then
		applyDebugAttributes(siteState)
		return false, spendError or "insufficient_materials"
	end

	local previousIsBuilt = siteState.isBuilt
	local previousBuildCount = siteState.buildCount
	local previousLastBuiltByUserId = siteState.lastBuiltByUserId
	local previousColor = siteState.part.Color
	local previousMaterial = siteState.part.Material

	local appliedBuiltState, applyError = pcall(function()
		siteState.isBuilt = true
		siteState.buildCount += 1
		siteState.lastBuiltByUserId = player.UserId
		applyBuiltVisualState(siteState)
		applyDebugAttributes(siteState)
	end)

	if not appliedBuiltState then
		ResourceFlowState.AddStoredAtomic(woodCost, stoneCost, "ConstructionRollback:" .. siteId)

		siteState.isBuilt = previousIsBuilt
		siteState.buildCount = previousBuildCount
		siteState.lastBuiltByUserId = previousLastBuiltByUserId
		pcall(function()
			siteState.part.Color = previousColor
			siteState.part.Material = previousMaterial
			applyDebugAttributes(siteState)
		end)

		return false, string.format("build_state_apply_failed detail=%s", tostring(applyError))
	end

	debugLog(
		string.format(
			"Accepted ConstructionBuildRequest userId=%d siteId=%s woodCost=%.0f stoneCost=%.0f woodStored=%.0f stoneStored=%.0f",
			player.UserId,
			siteId,
			woodCost,
			stoneCost,
			flowSnapshot.Wood.stored,
			flowSnapshot.Stone.stored
		)
	)

	return true, nil
end

local remotesFolder = ensureRemotesFolder()
debugLog("Ensuring construction remotes")
local buildRemote = ensureRemoteEvent(remotesFolder, BUILD_REMOTE_NAME)
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)
debugLog("Construction remotes ready")

debugLog("Registering construction sites")
registerConstructionSitesFromWorkspace()
debugLog(string.format(
	"Construction site count=%d",
	(function()
		local count = 0
		for _ in siteStateById do
			count += 1
		end
		return count
	end)()
))

-- Startup-only district discovery from placement query API (TIN-193).
-- This initializes minimal district build-state entries without widening build mutation scope.
initializeDistrictBuildStateFromPlacementQueryAPI()

buildRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	debugLog(
		string.format("Received ConstructionBuildRequest userId=%d payloadType=%s", player.UserId, typeof(payload))
	)

	local requestSiteId: string? = nil
	local requestMode = "legacy"
	local requestNow: number? = nil
	local requestQteTapAt: number? = nil

	if type(payload) == "string" then
		requestSiteId = payload
	elseif type(payload) == "table" then
		local payloadAny = payload :: any
		if type(payloadAny.siteId) ~= "string" or payloadAny.siteId == "" then
			rejectBuild(player, "malformed_payload")
			logBuildOutcome("rejected", player, "<unknown>", "malformed_payload")
			return
		end
		if type(payloadAny.mode) ~= "string" then
			rejectBuild(player, "malformed_payload")
			logBuildOutcome("rejected", player, "<unknown>", "malformed_payload")
			return
		end

		requestSiteId = payloadAny.siteId
		requestMode = payloadAny.mode
		if type(payloadAny.now) == "number" then
			requestNow = payloadAny.now
		end
		if type(payloadAny.qteTapAt) == "number" then
			requestQteTapAt = payloadAny.qteTapAt
		end
	else
		rejectBuild(player, "malformed_payload")
		logBuildOutcome("rejected", player, "<unknown>", "malformed_payload")
		return
	end

	local bypassCooldown = requestMode == "cancel"
	if not bypassCooldown and isCoolingDown(player.UserId, requestNow) then
		rejectBuild(player, "request_cooldown")
		logBuildOutcome("rejected", player, "<unknown>", "request_cooldown")
		return
	end

	if not bypassCooldown then
		markRequest(player.UserId, requestNow)
	end

	local siteId = requestSiteId :: string
	local siteState = siteStateById[siteId]
	if not siteState then
		if requestMode ~= "legacy" then
			rejectBuild(player, "task_mode_site_only")
			logBuildOutcome("rejected", player, siteId, "task_mode_site_only")
			return
		end

		-- TIN-197: check district build-state table before falling to site_not_found.
		local districtState = districtBuildStateById[siteId]
		if not districtState then
			rejectBuild(player, "site_not_found")
			logBuildOutcome("rejected", player, siteId, "site_not_found")
			return
		end

		if districtState.isBuilt then
			rejectBuild(player, "already_built")
			logBuildOutcome("rejected", player, siteId, "already_built")
			return
		end

		if not isPlayerAlive(player) then
			rejectBuild(player, "player_not_alive")
			logBuildOutcome("rejected", player, siteId, "player_not_alive")
			return
		end

		-- Range check deferred: DistrictBuildState has no Workspace part reference in this slice.

		local districtSpent, districtFlowSnapshot, districtSpendError = ResourceFlowState.SpendStoredAtomic(
			districtState.woodCost,
			districtState.stoneCost,
			"Construction:" .. siteId
		)
		if not districtSpent then
			local spendReason = districtSpendError or "insufficient_materials"
			rejectBuild(player, spendReason)
			logBuildOutcome("rejected", player, siteId, spendReason)
			return
		end

		local previousDistrictIsBuilt = districtState.isBuilt
		local previousDistrictBuildCount = districtState.buildCount
		local previousDistrictLastBuiltByUserId = districtState.lastBuiltByUserId

		local appliedDistrictBuiltState, districtApplyError = pcall(function()
			districtState.isBuilt = true
			districtState.buildCount += 1
			districtState.lastBuiltByUserId = player.UserId
		end)

		if not appliedDistrictBuiltState then
			ResourceFlowState.AddStoredAtomic(
				districtState.woodCost,
				districtState.stoneCost,
				"ConstructionRollback:" .. siteId
			)
			districtState.isBuilt = previousDistrictIsBuilt
			districtState.buildCount = previousDistrictBuildCount
			districtState.lastBuiltByUserId = previousDistrictLastBuiltByUserId
			local applyFailureReason = string.format("build_state_apply_failed detail=%s", tostring(districtApplyError))
			rejectBuild(player, applyFailureReason)
			logBuildOutcome("rejected", player, siteId, applyFailureReason)
			return
		end

		debugLog(
			string.format(
				"Accepted district ConstructionBuildRequest userId=%d districtId=%s woodCost=%.0f stoneCost=%.0f woodStored=%.0f stoneStored=%.0f",
				player.UserId,
				siteId,
				districtState.woodCost,
				districtState.stoneCost,
				districtFlowSnapshot.Wood.stored,
				districtFlowSnapshot.Stone.stored
			)
		)
		logBuildOutcome("accepted", player, siteId, nil)
		return
	end

	if
		requestMode == "begin"
		or requestMode == "cancel"
		or requestMode == "complete"
		or requestMode == "block"
		or requestMode == "unblock"
		or requestMode == "disrupt"
	then
		local taskState = getTaskStateForSite(siteId)
		local resolvedNow = if type(requestNow) == "number" then requestNow else os.clock()

		if requestMode == "begin" and ConstructionConfig.TaskQteEnabled == true then
			setTaskQteResultAttribute(player, nil)
		end

		if requestMode == "complete" and ConstructionConfig.TaskQteEnabled == true then
			local qteAttemptAt = if type(requestQteTapAt) == "number" then requestQteTapAt else resolvedNow
			local qteResult = TaskQteTimingLogic.Evaluate({
				now = qteAttemptAt,
				targetAt = taskState.endsAt,
				windowSeconds = ConstructionConfig.TaskQteWindowSeconds,
				bonusSeconds = ConstructionConfig.TaskQteBonusSeconds,
			})

			if qteResult.success then
				setTaskQteResultAttribute(player, "success")
				resolvedNow = qteResult.effectiveNow
			else
				setTaskQteResultAttribute(player, "failed")
				if ConstructionConfig.TaskQteFailureDisrupts == true then
					local disruptResult = ContextualTaskProgressLogic.Resolve(taskState, {
						eventType = "disrupt",
						taskId = siteId,
						now = resolvedNow,
						durationSeconds = ConstructionConfig.TaskDurationSeconds,
						regressionPerSecond = ConstructionConfig.TaskRegressionPerSecond,
						stabilizationThresholdSeconds = ConstructionConfig.TaskStabilizationThresholdSeconds,
						majorRegressionStepSeconds = ConstructionConfig.TaskMajorRegressionStepSeconds,
						majorRegressionMaxEvents = ConstructionConfig.TaskMajorRegressionMaxEvents,
						regressionWindowSeconds = ConstructionConfig.TaskRegressionWindowSeconds,
					})
					applyTaskAttributes(player, disruptResult.snapshot)
				end

				rejectBuild(player, "task_qte_failed")
				logBuildOutcome("rejected", player, siteId, "task_qte_failed")
				return
			end
		end

		local taskResult = ContextualTaskProgressLogic.Resolve(taskState, {
			eventType = requestMode,
			taskId = siteId,
			now = resolvedNow,
			durationSeconds = ConstructionConfig.TaskDurationSeconds,
			regressionPerSecond = ConstructionConfig.TaskRegressionPerSecond,
			stabilizationThresholdSeconds = ConstructionConfig.TaskStabilizationThresholdSeconds,
			majorRegressionStepSeconds = ConstructionConfig.TaskMajorRegressionStepSeconds,
			majorRegressionMaxEvents = ConstructionConfig.TaskMajorRegressionMaxEvents,
			regressionWindowSeconds = ConstructionConfig.TaskRegressionWindowSeconds,
		})
		applyTaskAttributes(player, taskResult.snapshot)

		if not taskResult.accepted then
			local reason = string.format("task_%s", taskResult.reason)
			rejectBuild(player, reason)
			logBuildOutcome("rejected", player, siteId, reason)
			return
		end

		if requestMode ~= "complete" then
			logBuildOutcome("accepted", player, siteId, string.format("task_%s", taskResult.reason))
			return
		end
	elseif requestMode ~= "legacy" then
		rejectBuild(player, "invalid_mode")
		logBuildOutcome("rejected", player, siteId, "invalid_mode")
		return
	end

	local succeeded, failureReason = attemptSiteBuild(player, siteId, siteState)
	if not succeeded then
		rejectBuild(player, failureReason :: string)
		logBuildOutcome("rejected", player, siteId, failureReason)
		return
	end

	logBuildOutcome("accepted", player, siteId, nil)
end)

local function handleDebugRequest(player: Player, payload: unknown)
	debugLog(
		string.format("Received ConstructionDebugStateRequest userId=%d payloadType=%s", player.UserId, typeof(payload))
	)

	if payload ~= nil and type(payload) ~= "string" then
		rejectDebug(player, "malformed_payload")
		return
	end

	local requestedSiteId = payload :: string?
	if requestedSiteId then
		local siteState = siteStateById[requestedSiteId]
		if not siteState then
			-- TIN-199: check district build-state table before falling to site_not_found.
			local districtState = districtBuildStateById[requestedSiteId]
			if not districtState then
				rejectDebug(player, "site_not_found")
				return
			end

			local flowSnapshot = ResourceFlowState.GetSnapshot()
			debugResponseRemote:FireClient(player, {
				districtId = districtState.districtId,
				isBuilt = districtState.isBuilt,
				buildCount = districtState.buildCount,
				lastBuiltByUserId = districtState.lastBuiltByUserId,
				woodCost = districtState.woodCost,
				stoneCost = districtState.stoneCost,
				woodProduced = flowSnapshot.Wood.produced,
				woodInTransit = flowSnapshot.Wood.inTransit,
				woodStored = flowSnapshot.Wood.stored,
				woodUsable = flowSnapshot.Wood.usable,
				stoneProduced = flowSnapshot.Stone.produced,
				stoneInTransit = flowSnapshot.Stone.inTransit,
				stoneStored = flowSnapshot.Stone.stored,
				stoneUsable = flowSnapshot.Stone.usable,
			})
			debugLog(
				string.format(
					"Sent district construction debug state userId=%d districtId=%s",
					player.UserId,
					districtState.districtId
				)
			)
			return
		end

		local woodCost, stoneCost = getSiteCost(siteState.siteId)
		local flowSnapshot = ResourceFlowState.GetSnapshot()
		debugResponseRemote:FireClient(player, {
			siteId = siteState.siteId,
			isBuilt = siteState.isBuilt,
			buildCount = siteState.buildCount,
			lastBuiltByUserId = siteState.lastBuiltByUserId,
			costWood = woodCost,
			costStone = stoneCost,
			woodProduced = flowSnapshot.Wood.produced,
			woodInTransit = flowSnapshot.Wood.inTransit,
			woodStored = flowSnapshot.Wood.stored,
			woodUsable = flowSnapshot.Wood.usable,
			stoneProduced = flowSnapshot.Stone.produced,
			stoneInTransit = flowSnapshot.Stone.inTransit,
			stoneStored = flowSnapshot.Stone.stored,
			stoneUsable = flowSnapshot.Stone.usable,
		})
		debugLog(string.format("Sent construction debug state userId=%d siteId=%s", player.UserId, siteState.siteId))
		return
	end

	local snapshot = {}
	local flowSnapshot = ResourceFlowState.GetSnapshot()
	for siteId, siteState in siteStateById do
		local woodCost, stoneCost = getSiteCost(siteId)
		table.insert(snapshot, {
			siteId = siteState.siteId,
			isBuilt = siteState.isBuilt,
			buildCount = siteState.buildCount,
			lastBuiltByUserId = siteState.lastBuiltByUserId,
			costWood = woodCost,
			costStone = stoneCost,
			woodProduced = flowSnapshot.Wood.produced,
			woodInTransit = flowSnapshot.Wood.inTransit,
			woodStored = flowSnapshot.Wood.stored,
			woodUsable = flowSnapshot.Wood.usable,
			stoneProduced = flowSnapshot.Stone.produced,
			stoneInTransit = flowSnapshot.Stone.inTransit,
			stoneStored = flowSnapshot.Stone.stored,
			stoneUsable = flowSnapshot.Stone.usable,
		})
	end

	-- TIN-199: include district entries in snapshot-all.
	for _districtId, districtState in districtBuildStateById do
		table.insert(snapshot, {
			districtId = districtState.districtId,
			isBuilt = districtState.isBuilt,
			buildCount = districtState.buildCount,
			lastBuiltByUserId = districtState.lastBuiltByUserId,
			woodCost = districtState.woodCost,
			stoneCost = districtState.stoneCost,
			woodProduced = flowSnapshot.Wood.produced,
			woodInTransit = flowSnapshot.Wood.inTransit,
			woodStored = flowSnapshot.Wood.stored,
			woodUsable = flowSnapshot.Wood.usable,
			stoneProduced = flowSnapshot.Stone.produced,
			stoneInTransit = flowSnapshot.Stone.inTransit,
			stoneStored = flowSnapshot.Stone.stored,
			stoneUsable = flowSnapshot.Stone.usable,
		})
	end

	debugResponseRemote:FireClient(player, snapshot)
	debugLog(string.format("Sent construction debug state snapshot userId=%d entryCount=%d", player.UserId, #snapshot))
end

debugRequestRemote.OnServerEvent:Connect(handleDebugRequest)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
end)

-- Test-only exports for runtime proof slices.
_G._ConstructionService_SiteState = siteStateById
_G._ConstructionService_DistrictBuildState = districtBuildStateById

debugLog("ConstructionService initialized")
