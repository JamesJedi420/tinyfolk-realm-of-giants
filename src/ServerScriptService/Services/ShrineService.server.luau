--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local ConstructionFolder = Shared:WaitForChild("Construction")
local ContextualTaskProgressLogic = require(ConstructionFolder:WaitForChild("ContextualTaskProgressLogic"))
local TaskQteTimingLogic = require(ConstructionFolder:WaitForChild("TaskQteTimingLogic"))
local GiantEssenceSession = require(script.Parent:WaitForChild("GiantEssenceSession"))

local REMOTES_FOLDER_NAME = "Remotes"
local ACTIVATE_REMOTE_NAME = "ShrineActivateRequest"
local DEBUG_REQUEST_REMOTE_NAME = "ShrineDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "ShrineDebugStateResponse"

local ATTRIBUTE_IS_ACTIVE = "IsActive"
local ATTRIBUTE_ESSENCE_TOTAL = "EssenceTotal"
local ATTRIBUTE_TICK_COUNT = "EssenceTickCount"
local ATTRIBUTE_LAST_TICK_AT = "LastTickAt"
local ATTRIBUTE_ACTIVATED_BY = "ActivatedByUserId"

local SHRINE_FOLDER_PATH = { "Map", "Stations" }
local globalEnv: any = getfenv()

type ShrineState = {
	shrineId: string,
	part: BasePart,
	isActive: boolean,
	essenceTotal: number,
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
	accumulatorSeconds: number,
}

local shrineStateById: { [string]: ShrineState } = {}
local lastRequestAtByUserId: { [number]: number? } = {}
local taskStateByShrineId: { [string]: any } = {}

type ShrinePersistenceRecord = {
	shrineId: string,
	isActive: boolean,
	essenceTotal: number,
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
}

type ShrinePersistenceState = {
	shrines: { ShrinePersistenceRecord },
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

local function isWholeNumber(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end

	return value % 1 == 0
end

local function isPositiveUserId(value: any): boolean
	if not isWholeNumber(value) then
		return false
	end

	return value > 0
end

local function debugLog(message: string)
	print(string.format("[ShrineService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[ShrineService] %s", message))
end

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
	if not last then
		return false
	end
	local lastAt = last :: number

	if type(at) == "number" then
		return (at - lastAt) < ShrineConfig.RequestCooldownSeconds
	end

	return (os.clock() - lastAt) < ShrineConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number?)
	lastRequestAtByUserId[userId] = if type(at) == "number" then at else os.clock()
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
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
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	return (humanoid :: Humanoid).Health > 0
end

local function isPlayerTinyfolkWorshipper(player: Player): boolean
	local role = player:GetAttribute("Role")
	if role ~= RoleConfig.Roles.Tinyfolk then
		return false
	end

	local specialistRole = player:GetAttribute("SpecialistRole")
	return specialistRole == SpecialistConfig.SpecialistRoles.Worshipper
end

local function getSpecialistAssignmentQueryApi(): any?
	-- selene: allow(global_usage)
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._SpecialistAssignmentService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function applyDebugAttributes(state: ShrineState)
	state.part:SetAttribute(ATTRIBUTE_IS_ACTIVE, state.isActive)
	state.part:SetAttribute(ATTRIBUTE_ESSENCE_TOTAL, state.essenceTotal)
	state.part:SetAttribute(ATTRIBUTE_TICK_COUNT, state.tickCount)
	state.part:SetAttribute(ATTRIBUTE_LAST_TICK_AT, state.lastTickAt)
	state.part:SetAttribute(ATTRIBUTE_ACTIVATED_BY, state.activatedByUserId)
end

local function findShrinesRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in SHRINE_FOLDER_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function magnitudeBetweenPositions(a: any, b: any): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function shouldTrackShrinePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. ShrineConfig.ShrineNamePrefix) ~= nil
end

local function registerShrinePart(part: BasePart)
	local shrineId = part.Name
	if shrineStateById[shrineId] then
		debugWarn(string.format("Duplicate shrine id ignored: %s", shrineId))
		return
	end

	local state: ShrineState = {
		shrineId = shrineId,
		part = part,
		isActive = false,
		essenceTotal = 0,
		tickCount = 0,
		lastTickAt = 0,
		activatedByUserId = nil,
		accumulatorSeconds = 0,
	}

	shrineStateById[shrineId] = state
	applyDebugAttributes(state)

	debugLog(string.format("Registered shrine id=%s", shrineId))
end

local function registerShrinesFromWorkspace()
	local shrinesRoot = findShrinesRoot()
	if not shrinesRoot then
		debugWarn("No shrine root found at Workspace.Map.Stations")
		return
	end

	for _, descendant in ((shrinesRoot :: any):GetDescendants()) do
		if descendant:IsA("BasePart") and shouldTrackShrinePart(descendant) then
			registerShrinePart(descendant)
		end
	end

	if next(shrineStateById) == nil then
		debugWarn("No shrine parts registered under Workspace.Map.Stations")
	end
end

local function rejectActivate(player: Player, reason: string)
	debugWarn(string.format("Rejected ShrineActivateRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected ShrineDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local function deactivateShrine(state: ShrineState, reason: string)
	state.isActive = false
	state.accumulatorSeconds = 0
	applyDebugAttributes(state)
	debugLog(
		string.format("Shrine deactivated id=%s reason=%s essenceTotal=%d", state.shrineId, reason, state.essenceTotal)
	)
end

local function buildPersistenceState(): ShrinePersistenceState
	local shrineIds = {}
	for shrineId in shrineStateById do
		table.insert(shrineIds, shrineId)
	end
	table.sort(shrineIds)

	local shrines = {}
	for _, shrineId in ipairs(shrineIds) do
		local state = shrineStateById[shrineId]
		table.insert(shrines, {
			shrineId = shrineId,
			isActive = state.isActive == true,
			essenceTotal = state.essenceTotal,
			tickCount = state.tickCount,
			lastTickAt = state.lastTickAt,
			activatedByUserId = state.activatedByUserId,
		})
	end

	return {
		shrines = shrines,
	}
end

local function resetShrineStateForPersistence(state: ShrineState)
	state.isActive = false
	state.essenceTotal = 0
	state.tickCount = 0
	state.lastTickAt = 0
	state.activatedByUserId = nil
	state.accumulatorSeconds = 0
	applyDebugAttributes(state)
end

local function validatePersistenceRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "shrine_persistence_record_invalid"
	end
	if type(record.shrineId) ~= "string" or record.shrineId == "" then
		return false, "shrine_persistence_record_shrine_id_invalid"
	end
	if type(record.isActive) ~= "boolean" then
		return false, "shrine_persistence_record_is_active_invalid"
	end
	if not isFiniteNumber(record.essenceTotal) or record.essenceTotal < 0 then
		return false, "shrine_persistence_record_essence_total_invalid"
	end
	if record.essenceTotal > ShrineConfig.MaxEssenceTotal then
		return false, "shrine_persistence_record_essence_total_out_of_bounds"
	end
	if not isWholeNumber(record.tickCount) or record.tickCount < 0 then
		return false, "shrine_persistence_record_tick_count_invalid"
	end
	if not isFiniteNumber(record.lastTickAt) or record.lastTickAt < 0 then
		return false, "shrine_persistence_record_last_tick_at_invalid"
	end
	if record.activatedByUserId ~= nil and not isPositiveUserId(record.activatedByUserId) then
		return false, "shrine_persistence_record_activated_by_user_id_invalid"
	end
	if record.isActive == true and record.activatedByUserId == nil then
		return false, "shrine_persistence_record_activated_by_user_id_missing"
	end

	return true, nil
end

local function applyPersistenceState(persistedState: any): (boolean, string?)
	if persistedState == nil then
		for _, state in shrineStateById do
			resetShrineStateForPersistence(state)
		end
		return true, nil
	end

	if type(persistedState) ~= "table" then
		return false, "shrine_persistence_invalid"
	end
	if type(persistedState.shrines) ~= "table" then
		return false, "shrine_persistence_shrines_invalid"
	end

	local recordsByShrineId: { [string]: ShrinePersistenceRecord } = {}
	for index, record in ipairs(persistedState.shrines) do
		local valid, reason = validatePersistenceRecord(record)
		if not valid then
			return false, string.format("%s index=%d", reason or "shrine_persistence_record_invalid", index)
		end

		local shrineId = record.shrineId
		if recordsByShrineId[shrineId] ~= nil then
			return false, string.format("shrine_persistence_record_duplicate index=%d", index)
		end
		if shrineStateById[shrineId] == nil then
			return false, string.format("shrine_persistence_record_unknown_shrine index=%d", index)
		end

		recordsByShrineId[shrineId] = record
	end

	for shrineId, state in shrineStateById do
		local record = recordsByShrineId[shrineId]
		if record == nil then
			resetShrineStateForPersistence(state)
		else
			state.isActive = record.isActive
			state.essenceTotal = math.max(0, math.min(record.essenceTotal, ShrineConfig.MaxEssenceTotal))
			state.tickCount = record.tickCount
			state.lastTickAt = record.lastTickAt
			state.activatedByUserId = record.activatedByUserId
			state.accumulatorSeconds = 0
			applyDebugAttributes(state)
		end
	end

	return true, nil
end

local function applyTaskAttributes(player: Player, taskSnapshot: any)
	player:SetAttribute(ShrineConfig.TaskActiveShrineIdAttribute, taskSnapshot.activeTaskId)
	player:SetAttribute(ShrineConfig.TaskProgressRatioAttribute, taskSnapshot.progressRatio)
	player:SetAttribute(ShrineConfig.TaskStartedAtAttribute, taskSnapshot.startedAt)
	player:SetAttribute(ShrineConfig.TaskEndsAtAttribute, taskSnapshot.endsAt)
	player:SetAttribute(ShrineConfig.TaskLastReasonAttribute, taskSnapshot.lastReason)
	player:SetAttribute(ShrineConfig.TaskObjectiveStateAttribute, taskSnapshot.objectiveState)
	player:SetAttribute(ShrineConfig.TaskProgressSecondsAttribute, taskSnapshot.progressSeconds)
	player:SetAttribute(ShrineConfig.TaskRegressionCountAttribute, taskSnapshot.majorRegressionEvents)
	player:SetAttribute(ShrineConfig.TaskRegressingUntilAttribute, taskSnapshot.regressingUntil)
end

local function setTaskQteResultAttribute(player: Player, result: string?)
	player:SetAttribute(ShrineConfig.TaskQteResultAttribute, result)
end

local function getTaskStateForShrine(shrineId: string): any
	local existing = taskStateByShrineId[shrineId]
	if existing ~= nil then
		return existing
	end

	local created = ContextualTaskProgressLogic.New()
	taskStateByShrineId[shrineId] = created
	return created
end

local function validateActivationRequest(
	player: Player,
	shrineState: ShrineState,
	skipWorshipperRoleCheck: boolean?
): (boolean, string?)
	if not isPlayerAlive(player) then
		return false, "player_not_alive"
	end

	local root = getHumanoidRootPart(player)
	if not root then
		return false, "humanoid_root_missing"
	end
	local rootPart = root :: BasePart

	local distance = magnitudeBetweenPositions(shrineState.part.Position :: any, rootPart.Position :: any)
	if distance > ShrineConfig.ActivationRangeStuds then
		return false, string.format("out_of_range distance=%.2f max=%.2f", distance, ShrineConfig.ActivationRangeStuds)
	end

	if skipWorshipperRoleCheck ~= true and not isPlayerTinyfolkWorshipper(player) then
		return false, "worshipper_role_required"
	end

	return true, nil
end

local function ensureInteractionWorshipperAssignment(player: Player, shrineState: ShrineState): (boolean, string?)
	local allowed, reason = validateActivationRequest(player, shrineState, true)
	if not allowed then
		return false, reason
	end

	if
		player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
		and player:GetAttribute("SpecialistRole") == SpecialistConfig.SpecialistRoles.Worshipper
		and player:GetAttribute("SpecialistAssignedStationId") == shrineState.shrineId
	then
		return true, nil
	end

	local queryApi = getSpecialistAssignmentQueryApi()
	if queryApi == nil or type(queryApi.AssignForInteraction) ~= "function" then
		if isPlayerTinyfolkWorshipper(player) then
			return true, nil
		end

		return false, "specialist_assignment_api_missing"
	end

	local assigned, assignReason =
		queryApi.AssignForInteraction(player, SpecialistConfig.SpecialistRoles.Worshipper, shrineState.shrineId)
	if assigned ~= true then
		return false, string.format("specialist_assignment_rejected detail=%s", tostring(assignReason))
	end

	debugLog(
		string.format(
			"Ensured shrine worshipper assignment userId=%d shrineId=%s reason=%s",
			player.UserId,
			shrineState.shrineId,
			tostring(assignReason)
		)
	)
	return true, nil
end

local remotesFolder = ensureRemotesFolder()
local shrineActivateRequestRemote = ensureRemoteEvent(remotesFolder, ACTIVATE_REMOTE_NAME)
local shrineDebugStateRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local shrineDebugStateResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

registerShrinesFromWorkspace()

shrineActivateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local shrineId: string? = nil
	local requestMode = "legacy"
	local requestNow: number? = nil
	local requestQteTapAt: number? = nil

	if type(payload) == "string" then
		shrineId = payload
	elseif type(payload) == "table" then
		local payloadAny = payload :: any
		if type(payloadAny.shrineId) ~= "string" or payloadAny.shrineId == "" then
			rejectActivate(player, "malformed_payload")
			return
		end
		if type(payloadAny.mode) ~= "string" then
			rejectActivate(player, "malformed_payload")
			return
		end

		shrineId = payloadAny.shrineId
		requestMode = payloadAny.mode
		if type(payloadAny.now) == "number" then
			requestNow = payloadAny.now
		end
		if type(payloadAny.qteTapAt) == "number" then
			requestQteTapAt = payloadAny.qteTapAt
		end
	else
		rejectActivate(player, "malformed_payload")
		return
	end

	local bypassCooldown = requestMode == "cancel"
	if not bypassCooldown and isCoolingDown(player.UserId, requestNow) then
		rejectActivate(player, "request_cooldown")
		return
	end

	if not bypassCooldown then
		markRequest(player.UserId, requestNow)
	end

	local shrineIdValue = shrineId :: string
	local shrineState = shrineStateById[shrineIdValue]
	if not shrineState then
		rejectActivate(player, "shrine_not_found")
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
		if requestMode == "begin" and ShrineConfig.TaskQteEnabled == true then
			setTaskQteResultAttribute(player, nil)
		end

		if requestMode ~= "cancel" and requestMode ~= "unblock" and requestMode ~= "block" then
			local allowed, reason = validateActivationRequest(player, shrineState)
			if not allowed then
				rejectActivate(player, reason :: string)
				return
			end
		end

		local taskState = getTaskStateForShrine(shrineIdValue)
		local resolvedNow = if type(requestNow) == "number" then requestNow else os.clock()

		if requestMode == "complete" and ShrineConfig.TaskQteEnabled == true then
			local qteAttemptAt = if type(requestQteTapAt) == "number" then requestQteTapAt else resolvedNow
			local qteResult = TaskQteTimingLogic.Evaluate({
				now = qteAttemptAt,
				targetAt = taskState.endsAt,
				windowSeconds = ShrineConfig.TaskQteWindowSeconds,
				bonusSeconds = ShrineConfig.TaskQteBonusSeconds,
			})

			if qteResult.success then
				setTaskQteResultAttribute(player, "success")
				resolvedNow = qteResult.effectiveNow
			else
				setTaskQteResultAttribute(player, "failed")
				if ShrineConfig.TaskQteFailureDisrupts == true then
					local disruptResult = ContextualTaskProgressLogic.Resolve(taskState, {
						eventType = "disrupt",
						taskId = shrineIdValue,
						now = resolvedNow,
						durationSeconds = ShrineConfig.TaskDurationSeconds,
						regressionPerSecond = ShrineConfig.TaskRegressionPerSecond,
						stabilizationThresholdSeconds = ShrineConfig.TaskStabilizationThresholdSeconds,
						majorRegressionStepSeconds = ShrineConfig.TaskMajorRegressionStepSeconds,
						majorRegressionMaxEvents = ShrineConfig.TaskMajorRegressionMaxEvents,
						regressionWindowSeconds = ShrineConfig.TaskRegressionWindowSeconds,
					})
					applyTaskAttributes(player, disruptResult.snapshot)
				end

				rejectActivate(player, "task_qte_failed")
				return
			end
		end

		local taskResult = ContextualTaskProgressLogic.Resolve(taskState, {
			eventType = requestMode,
			taskId = shrineIdValue,
			now = resolvedNow,
			durationSeconds = ShrineConfig.TaskDurationSeconds,
			regressionPerSecond = ShrineConfig.TaskRegressionPerSecond,
			stabilizationThresholdSeconds = ShrineConfig.TaskStabilizationThresholdSeconds,
			majorRegressionStepSeconds = ShrineConfig.TaskMajorRegressionStepSeconds,
			majorRegressionMaxEvents = ShrineConfig.TaskMajorRegressionMaxEvents,
			regressionWindowSeconds = ShrineConfig.TaskRegressionWindowSeconds,
		})
		applyTaskAttributes(player, taskResult.snapshot)

		if not taskResult.accepted then
			rejectActivate(player, string.format("task_%s", taskResult.reason))
			return
		end

		if requestMode ~= "complete" then
			return
		end
	elseif requestMode ~= "legacy" then
		rejectActivate(player, "invalid_mode")
		return
	end

	local assigned, assignReason = ensureInteractionWorshipperAssignment(player, shrineState)
	if not assigned then
		rejectActivate(player, assignReason :: string)
		return
	end

	local allowed, reason = validateActivationRequest(player, shrineState)
	if not allowed then
		rejectActivate(player, reason :: string)
		return
	end

	if shrineState.isActive then
		rejectActivate(player, "already_active")
		return
	end

	shrineState.isActive = true
	shrineState.activatedByUserId = player.UserId
	shrineState.lastTickAt = os.clock()
	shrineState.accumulatorSeconds = 0
	applyDebugAttributes(shrineState)

	debugLog(string.format("Accepted ShrineActivateRequest userId=%d shrineId=%s", player.UserId, shrineIdValue))
end)

shrineDebugStateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil and type(payload) ~= "string" then
		rejectDebug(player, "malformed_payload")
		return
	end

	local requestedShrineId = payload :: string?
	if requestedShrineId then
		local shrineState = shrineStateById[requestedShrineId]
		if not shrineState then
			rejectDebug(player, "shrine_not_found")
			return
		end

		shrineDebugStateResponseRemote:FireClient(player, {
			shrineId = shrineState.shrineId,
			isActive = shrineState.isActive,
			essenceTotal = shrineState.essenceTotal,
			tickCount = shrineState.tickCount,
			activatedByUserId = shrineState.activatedByUserId,
		})
		debugLog(string.format("Sent shrine debug state userId=%d shrineId=%s", player.UserId, shrineState.shrineId))
		return
	end

	local snapshot = {}
	for shrineId, shrineState in shrineStateById do
		table.insert(snapshot, {
			shrineId = shrineId,
			isActive = shrineState.isActive,
			essenceTotal = shrineState.essenceTotal,
			tickCount = shrineState.tickCount,
			activatedByUserId = shrineState.activatedByUserId,
		})
	end

	shrineDebugStateResponseRemote:FireClient(player, snapshot)
	debugLog(string.format("Sent shrine debug state snapshot userId=%d shrineCount=%d", player.UserId, #snapshot))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil

	for _, shrineState in shrineStateById do
		if shrineState.activatedByUserId == player.UserId and shrineState.isActive then
			debugLog(string.format("Activation owner left; shrine remains active id=%s", shrineState.shrineId))
		end
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	for _, shrineState in shrineStateById do
		if not shrineState.isActive then
			continue
		end

		shrineState.accumulatorSeconds += deltaTime

		while shrineState.accumulatorSeconds >= ShrineConfig.GenerationIntervalSeconds and shrineState.isActive do
			local activatingPlayer: Player? = nil
			if shrineState.activatedByUserId ~= nil then
				activatingPlayer = Players:GetPlayerByUserId(shrineState.activatedByUserId)
			end
			if not activatingPlayer or not isPlayerTinyfolkWorshipper(activatingPlayer) then
				applyDebugAttributes(shrineState)
				deactivateShrine(shrineState, "worshipper_role_lost")
				break
			end
			if activatingPlayer:GetAttribute("SpecialistAssignedStationId") ~= shrineState.shrineId then
				applyDebugAttributes(shrineState)
				deactivateShrine(shrineState, "worshipper_assignment_target_lost")
				break
			end
			local activePlayer = activatingPlayer :: Player

			shrineState.accumulatorSeconds -= ShrineConfig.GenerationIntervalSeconds
			shrineState.tickCount += 1
			shrineState.lastTickAt = os.clock()

			local remainingCapacity = ShrineConfig.MaxEssenceTotal - shrineState.essenceTotal
			local generatedAmount = math.min(ShrineConfig.EssencePerTick, math.max(0, remainingCapacity))
			if generatedAmount <= 0 then
				applyDebugAttributes(shrineState)
				deactivateShrine(shrineState, "max_essence_reached")
				break
			end

			shrineState.essenceTotal += generatedAmount
			local sessionSnapshot = GiantEssenceSession.AddGenerated(
				activePlayer.UserId,
				"Shrine:" .. shrineState.shrineId,
				generatedAmount
			)

			if shrineState.essenceTotal >= ShrineConfig.MaxEssenceTotal then
				shrineState.essenceTotal = ShrineConfig.MaxEssenceTotal
				applyDebugAttributes(shrineState)
				debugLog(
					string.format(
						"Shrine Essence tick id=%s tick=%d generated=%.0f total=%d giantSessionTotal=%.0f",
						shrineState.shrineId,
						shrineState.tickCount,
						generatedAmount,
						shrineState.essenceTotal,
						sessionSnapshot.total
					)
				)
				deactivateShrine(shrineState, "max_essence_reached")
				break
			end

			applyDebugAttributes(shrineState)
			if shrineState.tickCount % ShrineConfig.DebugLogEveryTicks == 0 then
				debugLog(
					string.format(
						"Shrine Essence tick id=%s tick=%d generated=%.0f total=%d giantSessionTotal=%.0f",
						shrineState.shrineId,
						shrineState.tickCount,
						generatedAmount,
						shrineState.essenceTotal,
						sessionSnapshot.total
					)
				)
			end
		end
	end
end)

debugLog("ShrineService initialized")

globalEnv._ShrineService_QueryAPI = {
	BuildPersistenceState = buildPersistenceState,
	ApplyPersistenceState = applyPersistenceState,
}

-- Test-only exports for runtime proof slices.
globalEnv._ShrineService_ShrineState = shrineStateById
globalEnv._ShrineService_TaskState = taskStateByShrineId
