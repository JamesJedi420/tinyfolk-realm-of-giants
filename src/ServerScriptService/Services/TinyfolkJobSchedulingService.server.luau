--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local SocialEconomyConfig = require(Config:WaitForChild("SocialEconomyConfig"))
local TinyfolkJobSchedulingConfig = require(Config:WaitForChild("TinyfolkJobSchedulingConfig"))
local TinyfolkJobSchedulingState = require(GiantRealm:WaitForChild("TinyfolkJobSchedulingState"))

local REMOTES_FOLDER_NAME = "Remotes"

type ProcessScheduler = {
	schedule: (delaySeconds: number, callback: () -> ()) -> any,
	cancel: (token: any) -> (),
}

local globalEnv: any = getfenv()

local scheduledJobByUserId: { [number]: any } = {}
local lastDebugSnapshot: any = nil
local runtimeProcessScheduler: ProcessScheduler? = nil
local runtimeProcessToken: any = nil
local started = false

local playersServiceOverride: any = nil
local stationQueryApiOverride: any = nil
local specialistQueryApiOverride: any = nil
local flowSnapshotProviderOverride: (() -> any)? = nil
local shrineDemandProviderOverride: (() -> { any })? = nil
local nowFnOverride: (() -> number)? = nil
local giantRealmActiveOverride: boolean? = nil

local diagnostics = {
	tickAttempts = 0,
	tickSucceeded = 0,
	tickFailed = 0,
	lastTickAt = 0,
	lastReason = "none",
	assignmentsApplied = 0,
	assignmentsRejected = 0,
}

local function debugLog(message: string)
	print(string.format("[TinyfolkJobSchedulingService] %s", message))
end

local function now(): number
	if type(nowFnOverride) == "function" then
		local at = nowFnOverride()
		if type(at) == "number" and at == at then
			return at
		end
	end
	return os.clock()
end

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function getPlayersService(): any
	if playersServiceOverride ~= nil then
		return playersServiceOverride
	end
	return Players
end

local function getStationQueryApi(): any?
	if stationQueryApiOverride ~= nil then
		return stationQueryApiOverride
	end
	return getGlobalTable("_StationService_QueryAPI")
end

local function getSpecialistQueryApi(): any?
	if specialistQueryApiOverride ~= nil then
		return specialistQueryApiOverride
	end
	return getGlobalTable("_SpecialistAssignmentService_QueryAPI")
end

local function getFlowSnapshot(): any?
	if type(flowSnapshotProviderOverride) == "function" then
		return flowSnapshotProviderOverride()
	end
	local resourceFlowStateModule = script.Parent:FindFirstChild("ResourceFlowState")
	if resourceFlowStateModule == nil then
		return nil
	end
	local resourceFlowState = require(resourceFlowStateModule)
	if type(resourceFlowState.GetSnapshot) == "function" then
		return resourceFlowState.GetSnapshot()
	end
	return nil
end

local function getShrineDemandSnapshots(): { any }
	if type(shrineDemandProviderOverride) == "function" then
		return shrineDemandProviderOverride()
	end
	return TinyfolkJobSchedulingConfig.ShrineSpecialistDemands
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

local function clearScheduledJobAttributes(player: Player, reason: string)
	player:SetAttribute(
		TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute,
		TinyfolkJobSchedulingConfig.JobKinds.None
	)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobDemandIdAttribute, nil)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute, nil)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute, nil)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobLastReasonAttribute, reason)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobUpdatedAtAttribute, now())
	scheduledJobByUserId[player.UserId] = nil
end

local function applyScheduledJobAttributes(player: Player, assignment: any, reason: string)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute, assignment.kind)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobDemandIdAttribute, assignment.demandId)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute, assignment.stationId)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute, assignment.material)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobLastReasonAttribute, reason)
	player:SetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobUpdatedAtAttribute, now())
	scheduledJobByUserId[player.UserId] = table.clone(assignment)
end

local function buildWorkerSnapshot(player: Player): any
	local scheduled = scheduledJobByUserId[player.UserId]
	local scheduledJobKind = player:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute)
	local scheduledMaterial = player:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute)
	if type(scheduled) == "table" and type(scheduled.kind) == "string" then
		scheduledJobKind = scheduled.kind
		if type(scheduled.material) == "string" then
			scheduledMaterial = scheduled.material
		end
	end

	return {
		userId = player.UserId,
		role = player:GetAttribute("Role"),
		specialistRole = player:GetAttribute("SpecialistRole"),
		assignedStationId = player:GetAttribute("SpecialistAssignedStationId"),
		scheduledJobKind = scheduledJobKind,
		scheduledMaterial = scheduledMaterial,
		captureActive = player:GetAttribute(CaptureConfig.StateAttributes.CaptureActive) == true,
		dyadicFavor = player:GetAttribute(SocialEconomyConfig.DyadicAttributes.Favor),
		dyadicControl = player:GetAttribute(SocialEconomyConfig.DyadicAttributes.Control),
	}
end

local function collectWorkerSnapshots(): { any }
	local workers: { any } = {}
	local playersService = getPlayersService()
	if playersService == nil or type(playersService.GetPlayers) ~= "function" then
		return workers
	end

	for _, player in ipairs(playersService:GetPlayers()) do
		if type(player) == "table" and type(player.GetAttribute) == "function" then
			table.insert(workers, buildWorkerSnapshot(player))
		end
	end

	return workers
end

local function collectStationDemandSnapshots(): { any }
	local queryApi = getStationQueryApi()
	if queryApi == nil or type(queryApi.ListStationDemandSnapshots) ~= "function" then
		return {}
	end
	return queryApi.ListStationDemandSnapshots()
end

local function resolveScheduledHaulMaterials(workers: { any }): { [string]: boolean }
	local scheduled: { [string]: boolean } = {}
	for _, worker in ipairs(workers) do
		if worker.scheduledJobKind == TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
			local material = worker.scheduledMaterial
			if type(material) == "string" and material ~= "" then
				scheduled[material] = true
			end
		end
	end
	return scheduled
end

local function findPlayerByUserId(userId: number): Player?
	local playersService = getPlayersService()
	if playersService == nil or type(playersService.GetPlayers) ~= "function" then
		return nil
	end
	for _, player in ipairs(playersService:GetPlayers()) do
		if type(player) == "table" and player.UserId == userId then
			return player
		end
	end
	return nil
end

local function applySpecialistAssignment(player: Player, assignment: any): (boolean, string)
	local specialistApi = getSpecialistQueryApi()
	if specialistApi == nil or type(specialistApi.AssignForJobScheduling) ~= "function" then
		return false, "specialist_assignment_api_missing"
	end
	return specialistApi.AssignForJobScheduling(player, assignment.specialistRole, assignment.stationId)
end

local function isGiantRealmServerActive(): boolean
	if type(giantRealmActiveOverride) == "boolean" then
		return giantRealmActiveOverride
	end

	local roleApi = getGlobalTable("_RoleService_QueryAPI")
	if type(roleApi) == "table" and type(roleApi.GetActiveGiantRealmOwnerUserId) == "function" then
		local ownerUserId = roleApi.GetActiveGiantRealmOwnerUserId()
		return type(ownerUserId) == "number" and ownerUserId > 0
	end

	return false
end

local function processSchedulingTick(): any
	diagnostics.tickAttempts += 1
	local tickAt = now()

	if not isGiantRealmServerActive() then
		diagnostics.lastReason = "hub_or_inactive_giant_realm"
		diagnostics.tickSucceeded += 1
		diagnostics.lastTickAt = tickAt
		lastDebugSnapshot = TinyfolkJobSchedulingState.BuildDebugSnapshot({
			lastTickAt = tickAt,
			lastReason = diagnostics.lastReason,
		})
		return lastDebugSnapshot
	end

	local workers = collectWorkerSnapshots()
	local stationSnapshots = collectStationDemandSnapshots()
	if #stationSnapshots == 0 and #getShrineDemandSnapshots() == 0 then
		diagnostics.lastReason = "no_giant_realm_station_demands"
		diagnostics.tickSucceeded += 1
		diagnostics.lastTickAt = tickAt
		lastDebugSnapshot = TinyfolkJobSchedulingState.BuildDebugSnapshot({
			demands = {},
			assignments = {},
			rejections = {},
			workers = workers,
			lastTickAt = tickAt,
			lastReason = diagnostics.lastReason,
		})
		return lastDebugSnapshot
	end

	local filledTargets = TinyfolkJobSchedulingState.ResolveFilledSpecialistTargets(workers)
	local specialistDemands =
		TinyfolkJobSchedulingState.BuildSpecialistDemands(stationSnapshots, getShrineDemandSnapshots(), filledTargets)
	local haulDemands =
		TinyfolkJobSchedulingState.BuildHaulDemands(getFlowSnapshot(), resolveScheduledHaulMaterials(workers))

	local demands = {}
	for _, demand in ipairs(specialistDemands) do
		table.insert(demands, demand)
	end
	for _, demand in ipairs(haulDemands) do
		table.insert(demands, demand)
	end

	local matchResult = TinyfolkJobSchedulingState.SelectAssignments(demands, workers)
	local appliedAssignments: { any } = {}

	for _, assignment in ipairs(matchResult.assignments) do
		local player = findPlayerByUserId(assignment.userId)
		if player == nil then
			diagnostics.assignmentsRejected += 1
			table.insert(matchResult.rejections, {
				demandId = assignment.demandId,
				userId = assignment.userId,
				reason = "player_not_found",
			})
			continue
		end

		if assignment.kind == TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction then
			local assigned, assignReason = applySpecialistAssignment(player, assignment)
			if not assigned then
				diagnostics.assignmentsRejected += 1
				table.insert(matchResult.rejections, {
					demandId = assignment.demandId,
					userId = assignment.userId,
					reason = assignReason or "specialist_assignment_rejected",
				})
				continue
			end
			applyScheduledJobAttributes(player, assignment, "specialist_job_scheduled")
			diagnostics.assignmentsApplied += 1
			table.insert(appliedAssignments, assignment)
			debugLog(
				string.format(
					"Scheduled specialist job userId=%d stationId=%s role=%s demandId=%s",
					assignment.userId,
					tostring(assignment.stationId),
					tostring(assignment.specialistRole),
					assignment.demandId
				)
			)
		elseif assignment.kind == TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
			applyScheduledJobAttributes(player, assignment, "haul_job_scheduled")
			diagnostics.assignmentsApplied += 1
			table.insert(appliedAssignments, assignment)
			debugLog(
				string.format(
					"Scheduled haul job userId=%d material=%s demandId=%s",
					assignment.userId,
					tostring(assignment.material),
					assignment.demandId
				)
			)
		end
	end

	diagnostics.lastReason = "tick_completed"
	diagnostics.tickSucceeded += 1
	diagnostics.lastTickAt = tickAt
	lastDebugSnapshot = TinyfolkJobSchedulingState.BuildDebugSnapshot({
		demands = demands,
		assignments = appliedAssignments,
		rejections = matchResult.rejections,
		workers = workers,
		lastTickAt = tickAt,
		lastReason = diagnostics.lastReason,
	})
	return lastDebugSnapshot
end

local function defaultProcessSchedule(delaySeconds: number, callback: () -> ())
	task.delay(delaySeconds, callback)
	return {}
end

local function defaultProcessCancel(_token: any)
	return
end

local function _stopProcessingLoop()
	local scheduler = runtimeProcessScheduler
	if scheduler ~= nil and runtimeProcessToken ~= nil and type(scheduler.cancel) == "function" then
		pcall(scheduler.cancel, runtimeProcessToken)
	end
	runtimeProcessToken = nil
end

local scheduleNextTick: (() -> ())? = nil

local function startProcessingLoop(configAny: any?)
	if started then
		return
	end
	started = true

	local disableAutoStart = getGlobalTable("_TinyfolkJobSchedulingService_DisableAutoStart") == true
	if disableAutoStart then
		return
	end

	local requestedScheduler = if type(configAny) == "table" then configAny.processScheduler else nil
	runtimeProcessScheduler = if type(requestedScheduler) == "table"
			and type(requestedScheduler.schedule) == "function"
		then requestedScheduler
		else {
			schedule = defaultProcessSchedule,
			cancel = defaultProcessCancel,
		}

	local intervalSeconds = TinyfolkJobSchedulingConfig.ProcessIntervalSeconds
	if
		type(configAny) == "table"
		and type(configAny.processIntervalSeconds) == "number"
		and configAny.processIntervalSeconds > 0
	then
		intervalSeconds = configAny.processIntervalSeconds
	end

	scheduleNextTick = function()
		local activeScheduler = runtimeProcessScheduler
		if activeScheduler == nil then
			return
		end

		local scheduleOk, scheduleToken = pcall(function()
			return activeScheduler.schedule(intervalSeconds, function()
				runtimeProcessToken = nil
				local tickOk = pcall(processSchedulingTick)
				if not tickOk then
					diagnostics.tickFailed += 1
					diagnostics.lastReason = "tick_threw"
				end
				if scheduleNextTick ~= nil then
					scheduleNextTick()
				end
			end)
		end)

		if scheduleOk then
			runtimeProcessToken = scheduleToken
		end
	end

	scheduleNextTick()
end

local remotesFolder = ensureRemotesFolder()
local debugRequestRemote = ensureRemoteEvent(remotesFolder, TinyfolkJobSchedulingConfig.DebugRequestRemoteName)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, TinyfolkJobSchedulingConfig.DebugResponseRemoteName)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil then
		return
	end
	if lastDebugSnapshot == nil then
		lastDebugSnapshot = TinyfolkJobSchedulingState.BuildDebugSnapshot({
			lastReason = "no_tick_yet",
		})
	end
	debugResponseRemote:FireClient(player, lastDebugSnapshot)
	debugLog(string.format("Sent job scheduling debug state userId=%d", player.UserId))
end)

local playersService = getPlayersService()
if playersService ~= nil and type(playersService.PlayerRemoving) == "table" then
	playersService.PlayerRemoving:Connect(function(player: Player)
		scheduledJobByUserId[player.UserId] = nil
	end)
end

-- selene: allow(global_usage)
_G._TinyfolkJobSchedulingService_QueryAPI = {
	ProcessTick = processSchedulingTick,
	GetDebugSnapshot = function(): any
		if lastDebugSnapshot == nil then
			return TinyfolkJobSchedulingState.BuildDebugSnapshot({
				lastReason = "no_tick_yet",
			})
		end
		return lastDebugSnapshot
	end,
	GetDiagnostics = function(): any
		return table.clone(diagnostics)
	end,
	GetScheduledJobForUser = function(userId: number): any?
		return scheduledJobByUserId[userId]
	end,
	ClearScheduledJobForUser = function(userId: number, reason: string?): boolean
		local player = findPlayerByUserId(userId)
		if player == nil then
			scheduledJobByUserId[userId] = nil
			return false
		end
		clearScheduledJobAttributes(player, reason or "cleared")
		return true
	end,
}

-- selene: allow(global_usage)
_G._TinyfolkJobSchedulingService_TestHooks = {
	SetPlayersService = function(service: any?)
		playersServiceOverride = service
	end,
	SetStationQueryApi = function(api: any?)
		stationQueryApiOverride = api
	end,
	SetSpecialistQueryApi = function(api: any?)
		specialistQueryApiOverride = api
	end,
	SetFlowSnapshotProvider = function(provider: (() -> any)?)
		flowSnapshotProviderOverride = provider
	end,
	SetShrineDemandProvider = function(provider: (() -> { any })?)
		shrineDemandProviderOverride = provider
	end,
	SetNowFn = function(provider: (() -> number)?)
		nowFnOverride = provider
	end,
	SetGiantRealmActive = function(active: boolean?)
		giantRealmActiveOverride = active
	end,
	Reset = function()
		playersServiceOverride = nil
		stationQueryApiOverride = nil
		specialistQueryApiOverride = nil
		flowSnapshotProviderOverride = nil
		shrineDemandProviderOverride = nil
		nowFnOverride = nil
		giantRealmActiveOverride = nil
		scheduledJobByUserId = {}
		lastDebugSnapshot = nil
	end,
}

startProcessingLoop(getGlobalTable("_TinyfolkJobSchedulingService_StartConfig"))

debugLog("TinyfolkJobSchedulingService initialized")
