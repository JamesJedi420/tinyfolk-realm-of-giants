--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local TinyfolkHaulLogisticsConfig = require(Config:WaitForChild("TinyfolkHaulLogisticsConfig"))
local TinyfolkJobSchedulingConfig = require(Config:WaitForChild("TinyfolkJobSchedulingConfig"))
local TinyfolkHaulLogisticsState = require(GiantRealm:WaitForChild("TinyfolkHaulLogisticsState"))

local REMOTES_FOLDER_NAME = "Remotes"

type ProcessScheduler = {
	schedule: (delaySeconds: number, callback: () -> ()) -> any,
	cancel: (token: any) -> (),
}

local globalEnv: any = getfenv()

local lastDebugSnapshot: any = nil
local runtimeProcessScheduler: ProcessScheduler? = nil
local runtimeProcessToken: any = nil
local started = false

local playersServiceOverride: any = nil
local stationQueryApiOverride: any = nil
local warehousingQueryApiOverride: any = nil
local jobSchedulingQueryApiOverride: any = nil
local laborUpgradeQueryApiOverride: any = nil
local flowSnapshotProviderOverride: (() -> any)? = nil
local lastHaulRequestAtProviderOverride: ((userId: number) -> number?)? = nil
local nowFnOverride: (() -> number)? = nil
local giantRealmActiveOverride: boolean? = nil

local diagnostics = {
	tickAttempts = 0,
	tickSucceeded = 0,
	tickFailed = 0,
	lastTickAt = 0,
	lastReason = "none",
	actionsApplied = 0,
	actionsSkipped = 0,
	jobsCleared = 0,
}

local function debugLog(message: string)
	print(string.format("[TinyfolkHaulLogisticsService] %s", message))
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

local function getWarehousingQueryApi(): any?
	if warehousingQueryApiOverride ~= nil then
		return warehousingQueryApiOverride
	end
	return getGlobalTable("_WarehousingService_QueryAPI")
end

local function getJobSchedulingQueryApi(): any?
	if jobSchedulingQueryApiOverride ~= nil then
		return jobSchedulingQueryApiOverride
	end
	return getGlobalTable("_TinyfolkJobSchedulingService_QueryAPI")
end

local function getLaborUpgradeQueryApi(): any?
	if laborUpgradeQueryApiOverride ~= nil then
		return laborUpgradeQueryApiOverride
	end
	return getGlobalTable("_TinyfolkLaborUpgradeService_QueryAPI")
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

local function getLastHaulRequestAt(userId: number): number?
	if type(lastHaulRequestAtProviderOverride) == "function" then
		return lastHaulRequestAtProviderOverride(userId)
	end
	local lastHaulTable = getGlobalTable("_StationService_LastHaulRequestAt")
	if type(lastHaulTable) == "table" then
		return lastHaulTable[userId]
	end
	return nil
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

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	return humanoid.Health > 0
end

local function getPlayerPosition(player: Player): any?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = root.Position
		return {
			x = position.X,
			y = position.Y,
			z = position.Z,
		}
	end

	return nil
end

local function applyLogisticsAttributes(player: Player, route: any, phase: string, reason: string, movedAmount: number?)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.PhaseAttribute, phase)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.RouteSourceIdAttribute, route.sourceStationId)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.RouteDeliveryIdAttribute, route.deliveryId)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.MaterialAttribute, route.material)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.LastReasonAttribute, reason)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.UpdatedAtAttribute, now())
	if type(movedAmount) == "number" then
		player:SetAttribute(TinyfolkHaulLogisticsConfig.LastMovedAmountAttribute, movedAmount)
	end
end

local function clearLogisticsAttributes(player: Player, reason: string)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.PhaseAttribute, TinyfolkHaulLogisticsConfig.Phases.None)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.RouteSourceIdAttribute, nil)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.RouteDeliveryIdAttribute, nil)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.MaterialAttribute, nil)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.LastReasonAttribute, reason)
	player:SetAttribute(TinyfolkHaulLogisticsConfig.UpdatedAtAttribute, now())
	player:SetAttribute(TinyfolkHaulLogisticsConfig.LastMovedAmountAttribute, nil)
end

local function buildWorkerSnapshot(player: Player): any
	return {
		userId = player.UserId,
		role = player:GetAttribute("Role"),
		scheduledJobKind = player:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobKindAttribute),
		scheduledMaterial = player:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobMaterialAttribute),
		scheduledSourceStationId = player:GetAttribute(TinyfolkJobSchedulingConfig.ScheduledJobStationIdAttribute),
		captureActive = player:GetAttribute(CaptureConfig.StateAttributes.CaptureActive) == true,
		haulInteractionActive = player:GetAttribute(StationConfig.HaulInteractionActiveAttribute) == true,
		position = getPlayerPosition(player),
	}
end

local function collectHaulWorkers(): { any }
	local workers: { any } = {}
	local playersService = getPlayersService()
	if playersService == nil or type(playersService.GetPlayers) ~= "function" then
		return workers
	end

	for _, player in ipairs(playersService:GetPlayers()) do
		if type(player) == "table" and type(player.GetAttribute) == "function" then
			local snapshot = buildWorkerSnapshot(player)
			if snapshot.scheduledJobKind == TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
				table.insert(workers, snapshot)
			end
		end
	end

	return TinyfolkHaulLogisticsState.SortWorkersByUserId(workers)
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

local function clearScheduledHaulJob(userId: number, reason: string): boolean
	local schedulingApi = getJobSchedulingQueryApi()
	if schedulingApi == nil or type(schedulingApi.ClearScheduledJobForUser) ~= "function" then
		return false
	end
	local cleared = schedulingApi.ClearScheduledJobForUser(userId, reason)
	if cleared then
		diagnostics.jobsCleared += 1
	end
	return cleared
end

local function resolveHaulYieldMultiplier(userId: number): number?
	local upgradeApi = getLaborUpgradeQueryApi()
	if type(upgradeApi) == "table" and type(upgradeApi.GetHaulYieldMultiplier) == "function" then
		return upgradeApi.GetHaulYieldMultiplier(userId)
	end
	return nil
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

local function processWorkerLogistics(worker: any, flowSnapshot: any, tickAt: number): any?
	local eligible, eligibleReason = TinyfolkHaulLogisticsState.IsWorkerEligible(worker)
	if not eligible then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = eligibleReason or "worker_ineligible",
		}
	end

	local deferManual, deferReason = TinyfolkHaulLogisticsState.ShouldDeferToManualHaul(worker, {
		lastHaulRequestAt = getLastHaulRequestAt(worker.userId),
		now = tickAt,
		cooldownSeconds = StationConfig.HaulIntervalSeconds,
	})
	if deferManual then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "deferred",
			reason = deferReason,
		}
	end

	local material = worker.scheduledMaterial
	local route, routeReason = TinyfolkHaulLogisticsState.ResolveHaulRoute(material, worker.scheduledSourceStationId)
	if route == nil then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = routeReason or "route_unresolved",
		}
	end

	local materialSnapshot = if type(flowSnapshot) == "table" then flowSnapshot[material] else nil
	if type(materialSnapshot) ~= "table" then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = "material_snapshot_missing",
		}
	end

	if TinyfolkHaulLogisticsState.IsHaulComplete(materialSnapshot) then
		local player = findPlayerByUserId(worker.userId)
		if player ~= nil then
			clearLogisticsAttributes(player, "haul_logistics_stale")
			clearScheduledHaulJob(worker.userId, "haul_logistics_stale")
		end
		return {
			userId = worker.userId,
			action = "cleared",
			reason = "haul_logistics_stale",
		}
	end

	local player = findPlayerByUserId(worker.userId)
	if player == nil then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = "player_not_found",
		}
	end

	if not isPlayerAlive(player) then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = "player_not_alive",
		}
	end

	local phase = TinyfolkHaulLogisticsState.ResolveHaulPhase(materialSnapshot)
	if phase == TinyfolkHaulLogisticsConfig.Phases.None then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = "no_haul_phase",
		}
	end

	applyLogisticsAttributes(player, route, phase, "tick_active", nil)

	if phase == TinyfolkHaulLogisticsConfig.Phases.Pickup then
		local stationApi = getStationQueryApi()
		if stationApi == nil or type(stationApi.GetStationHaulSnapshot) ~= "function" then
			diagnostics.actionsSkipped += 1
			return {
				userId = worker.userId,
				action = "skipped",
				reason = "station_query_api_missing",
			}
		end

		local stationSnapshot = stationApi.GetStationHaulSnapshot(route.sourceStationId)
		if stationSnapshot == nil or type(stationSnapshot.position) ~= "table" then
			diagnostics.actionsSkipped += 1
			return {
				userId = worker.userId,
				action = "skipped",
				reason = "source_station_missing",
			}
		end

		if
			not TinyfolkHaulLogisticsState.IsWithinRange(
				worker.position,
				stationSnapshot.position,
				StationConfig.ActivationRangeStuds
			)
		then
			diagnostics.actionsSkipped += 1
			return {
				userId = worker.userId,
				action = "waiting",
				reason = "out_of_range_source",
				phase = phase,
			}
		end

		if type(stationApi.ApplyScheduledPickup) ~= "function" then
			diagnostics.actionsSkipped += 1
			return {
				userId = worker.userId,
				action = "skipped",
				reason = "station_pickup_api_missing",
			}
		end

		local baseAmount = StationConfig.HaulTransferPerStepByMaterial[material]
		local pickupAmount = TinyfolkHaulLogisticsState.ResolvePickupAmount(
			if type(baseAmount) == "number" then baseAmount else 2,
			resolveHaulYieldMultiplier(worker.userId)
		)
		local pickupResult = stationApi.ApplyScheduledPickup(player, route.sourceStationId, pickupAmount)
		if type(pickupResult) ~= "table" or pickupResult.accepted ~= true then
			diagnostics.actionsSkipped += 1
			return {
				userId = worker.userId,
				action = "skipped",
				reason = if type(pickupResult) == "table" then pickupResult.reason else "pickup_failed",
			}
		end

		diagnostics.actionsApplied += 1
		applyLogisticsAttributes(
			player,
			route,
			TinyfolkHaulLogisticsConfig.Phases.Deliver,
			"pickup_applied",
			pickupResult.movedAmount
		)
		debugLog(
			string.format(
				"Pickup userId=%d material=%s stationId=%s moved=%.0f",
				worker.userId,
				material,
				route.sourceStationId,
				pickupResult.movedAmount
			)
		)
		return {
			userId = worker.userId,
			action = "pickup",
			reason = "pickup_applied",
			movedAmount = pickupResult.movedAmount,
			phase = TinyfolkHaulLogisticsConfig.Phases.Deliver,
		}
	end

	local warehousingApi = getWarehousingQueryApi()
	if warehousingApi == nil or type(warehousingApi.GetDeliverySnapshot) ~= "function" then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = "warehousing_query_api_missing",
		}
	end

	local deliverySnapshot = warehousingApi.GetDeliverySnapshot(material)
	if deliverySnapshot == nil or type(deliverySnapshot.position) ~= "table" then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = "delivery_point_missing",
		}
	end

	if
		not TinyfolkHaulLogisticsState.IsWithinRange(
			worker.position,
			deliverySnapshot.position,
			StationConfig.ActivationRangeStuds
		)
	then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "waiting",
			reason = "out_of_range_delivery",
			phase = phase,
		}
	end

	if type(warehousingApi.ApplyScheduledDelivery) ~= "function" then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = "warehousing_delivery_api_missing",
		}
	end

	local inTransitAmount = if type(materialSnapshot.inTransit) == "number" then materialSnapshot.inTransit else 0
	local deliveryAmount = TinyfolkHaulLogisticsState.ResolveDeliveryAmount(
		material,
		inTransitAmount,
		StationConfig.HaulTransferPerStepByMaterial
	)
	local deliveryResult = warehousingApi.ApplyScheduledDelivery(player, material, deliveryAmount)
	if type(deliveryResult) ~= "table" or deliveryResult.accepted ~= true then
		diagnostics.actionsSkipped += 1
		return {
			userId = worker.userId,
			action = "skipped",
			reason = if type(deliveryResult) == "table" then deliveryResult.reason else "delivery_failed",
		}
	end

	diagnostics.actionsApplied += 1
	local refreshedSnapshot = getFlowSnapshot()
	local refreshedMaterialSnapshot = if type(refreshedSnapshot) == "table"
		then refreshedSnapshot[material]
		else nil
	local nextPhase = TinyfolkHaulLogisticsConfig.Phases.Pickup
	if type(refreshedMaterialSnapshot) == "table" then
		nextPhase = TinyfolkHaulLogisticsState.ResolveHaulPhase(refreshedMaterialSnapshot)
	end

	if type(refreshedMaterialSnapshot) == "table" and TinyfolkHaulLogisticsState.IsHaulComplete(refreshedMaterialSnapshot) then
		clearLogisticsAttributes(player, "haul_logistics_complete")
		clearScheduledHaulJob(worker.userId, "haul_logistics_complete")
		debugLog(
			string.format(
				"Deliver complete userId=%d material=%s deliveryId=%s moved=%.0f",
				worker.userId,
				material,
				route.deliveryId,
				deliveryResult.movedAmount
			)
		)
		return {
			userId = worker.userId,
			action = "deliver_complete",
			reason = "haul_logistics_complete",
			movedAmount = deliveryResult.movedAmount,
			phase = TinyfolkHaulLogisticsConfig.Phases.None,
		}
	end

	applyLogisticsAttributes(player, route, nextPhase, "deliver_applied", deliveryResult.movedAmount)
	debugLog(
		string.format(
			"Deliver userId=%d material=%s deliveryId=%s moved=%.0f nextPhase=%s",
			worker.userId,
			material,
			route.deliveryId,
			deliveryResult.movedAmount,
			nextPhase
		)
	)
	return {
		userId = worker.userId,
		action = "deliver",
		reason = "deliver_applied",
		movedAmount = deliveryResult.movedAmount,
		phase = nextPhase,
	}
end

local function processLogisticsTick(): any
	diagnostics.tickAttempts += 1
	local tickAt = now()

	if not isGiantRealmServerActive() then
		diagnostics.lastReason = "hub_or_inactive_giant_realm"
		diagnostics.tickSucceeded += 1
		diagnostics.lastTickAt = tickAt
		lastDebugSnapshot = TinyfolkHaulLogisticsState.BuildDebugSnapshot({
			lastTickAt = tickAt,
			lastReason = diagnostics.lastReason,
		})
		return lastDebugSnapshot
	end

	local workers = collectHaulWorkers()
	if #workers == 0 then
		diagnostics.lastReason = "no_scheduled_haul_workers"
		diagnostics.tickSucceeded += 1
		diagnostics.lastTickAt = tickAt
		lastDebugSnapshot = TinyfolkHaulLogisticsState.BuildDebugSnapshot({
			workers = workers,
			actions = {},
			lastTickAt = tickAt,
			lastReason = diagnostics.lastReason,
		})
		return lastDebugSnapshot
	end

	local flowSnapshot = getFlowSnapshot()
	local actions: { any } = {}
	local limit = TinyfolkHaulLogisticsConfig.MaxWorkersPerTick

	for index, worker in ipairs(workers) do
		if index > limit then
			table.insert(actions, {
				userId = worker.userId,
				action = "skipped",
				reason = "worker_limit_reached",
			})
			continue
		end

		local actionResult = processWorkerLogistics(worker, flowSnapshot, tickAt)
		if actionResult ~= nil then
			table.insert(actions, actionResult)
		end
	end

	diagnostics.lastReason = "tick_completed"
	diagnostics.tickSucceeded += 1
	diagnostics.lastTickAt = tickAt
	lastDebugSnapshot = TinyfolkHaulLogisticsState.BuildDebugSnapshot({
		workers = workers,
		actions = actions,
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

	local disableAutoStart = getGlobalTable("_TinyfolkHaulLogisticsService_DisableAutoStart") == true
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

	local intervalSeconds = TinyfolkHaulLogisticsConfig.ProcessIntervalSeconds
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
				local tickOk = pcall(processLogisticsTick)
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
local debugRequestRemote = ensureRemoteEvent(remotesFolder, TinyfolkHaulLogisticsConfig.DebugRequestRemoteName)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, TinyfolkHaulLogisticsConfig.DebugResponseRemoteName)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil then
		return
	end
	if lastDebugSnapshot == nil then
		lastDebugSnapshot = TinyfolkHaulLogisticsState.BuildDebugSnapshot({
			lastReason = "no_tick_yet",
		})
	end
	debugResponseRemote:FireClient(player, lastDebugSnapshot)
	debugLog(string.format("Sent haul logistics debug state userId=%d", player.UserId))
end)

-- selene: allow(global_usage)
_G._TinyfolkHaulLogisticsService_QueryAPI = {
	ProcessTick = processLogisticsTick,
	GetDebugSnapshot = function(): any
		if lastDebugSnapshot == nil then
			return TinyfolkHaulLogisticsState.BuildDebugSnapshot({
				lastReason = "no_tick_yet",
			})
		end
		return lastDebugSnapshot
	end,
	GetDiagnostics = function(): any
		return table.clone(diagnostics)
	end,
}

-- selene: allow(global_usage)
_G._TinyfolkHaulLogisticsService_TestHooks = {
	SetPlayersService = function(service: any?)
		playersServiceOverride = service
	end,
	SetStationQueryApi = function(api: any?)
		stationQueryApiOverride = api
	end,
	SetWarehousingQueryApi = function(api: any?)
		warehousingQueryApiOverride = api
	end,
	SetJobSchedulingQueryApi = function(api: any?)
		jobSchedulingQueryApiOverride = api
	end,
	SetLaborUpgradeQueryApi = function(api: any?)
		laborUpgradeQueryApiOverride = api
	end,
	SetFlowSnapshotProvider = function(provider: (() -> any)?)
		flowSnapshotProviderOverride = provider
	end,
	SetLastHaulRequestAtProvider = function(provider: ((userId: number) -> number?)?)
		lastHaulRequestAtProviderOverride = provider
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
		warehousingQueryApiOverride = nil
		jobSchedulingQueryApiOverride = nil
		laborUpgradeQueryApiOverride = nil
		flowSnapshotProviderOverride = nil
		lastHaulRequestAtProviderOverride = nil
		nowFnOverride = nil
		giantRealmActiveOverride = nil
		lastDebugSnapshot = nil
	end,
}

startProcessingLoop(getGlobalTable("_TinyfolkHaulLogisticsService_StartConfig"))

debugLog("TinyfolkHaulLogisticsService initialized")
