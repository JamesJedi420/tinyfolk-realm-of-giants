--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local PenRationingConfig = require(Config:WaitForChild("PenRationingConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local CaptureState = require(GiantRealm:WaitForChild("CaptureState"))
local CapturePersistenceRules = require(GiantRealm:WaitForChild("CapturePersistenceRules"))
local DisconnectResolutionState = require(GiantRealm:WaitForChild("DisconnectResolutionState"))
local CaptivityDurationState = require(GiantRealm:WaitForChild("CaptivityDurationState"))
local PostRescueProtectionState = require(GiantRealm:WaitForChild("PostRescueProtectionState"))
local PenRationingState = require(GiantRealm:WaitForChild("PenRationingState"))
local VillageWorksiteUpgradeState = require(GiantRealm:WaitForChild("VillageWorksiteUpgradeState"))
local ContainmentRewardResolver = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ContainmentRewardResolver"))
	else (require :: any)("./ContainmentRewardResolver")
local MemoryStoreAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreAdapter"))
	else (require :: any)("./MemoryStoreAdapter")
local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")
local QueueProcessingIdempotencyStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("QueueProcessingIdempotencyStore"))
	else (require :: any)("./QueueProcessingIdempotencyStore")
local CaptivitySafeReturnCaller = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("CaptivitySafeReturnCaller"))
	else (require :: any)("./CaptivitySafeReturnCaller")
local DisconnectSafeReturnCaller = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("DisconnectSafeReturnCaller"))
	else (require :: any)("./DisconnectSafeReturnCaller")

local ROLE_ATTRIBUTE = "Role"
local POST_RESCUE_PROTECTED_ATTRIBUTE = "PostRescueProtected"
local POST_RESCUE_PROTECTION_EXPIRES_AT_ATTRIBUTE = "PostRescueProtectionExpiresAt"
local ANTI_GUARDING_REPEAT_TARGET_COOLDOWN_SECONDS = 12
local globalEnv: any = getfenv()

local state = CaptureState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local lastRejectedRequestAtByUserId: { [number]: number? } = {}
local lastCaptureAtByCustodianTargetKey: { [string]: number? } = {}
local containmentRewardResolver: any = nil
local containmentRewardIdempotencyStore: any = nil
local applyCaptureAttributesFromState: () -> ()

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

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	return nil
end

local function isPlayerAlive(player: Player): boolean
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return false
	end

	return humanoid.Health > 0
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

local function getRoleServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RoleService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getContainmentStructureQueryApi(): any?
	local queryApi = globalEnv._ContainmentStructureService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._ContainmentStructureService_QueryAPI) == "table" then
		return (_G :: any)._ContainmentStructureService_QueryAPI
	end
	return nil
end

local function makeLocalIdempotencyAdapter(): any
	local mapsByName: { [string]: { [string]: any } } = {}
	return {
		HashMapUpdateAsync = function(mapName: string, key: string, transform: (any) -> any, _ttlSeconds: number?): any
			local map = mapsByName[mapName]
			if map == nil then
				map = {}
				mapsByName[mapName] = map
			end
			local nextValue = transform(map[key])
			map[key] = nextValue
			return nextValue
		end,
	}
end

local function getMemoryStoreAdapter(): any
	local globalValue: any = _G
	if type(globalValue) == "table" and type(globalValue._MemoryStoreAdapter_QueryAPI) == "table" then
		return globalValue._MemoryStoreAdapter_QueryAPI
	end

	if type(MemoryStoreAdapter) == "table" and type(MemoryStoreAdapter.CreateDefault) == "function" then
		local ok, adapter = pcall(function()
			return MemoryStoreAdapter.CreateDefault({
				activeRealmCapacityMapName = MemoryStoreStructurePolicy.GetPolicy("activeRealmCapacity").name,
			})
		end)
		if ok and type(adapter) == "table" then
			return adapter
		end
	end

	return makeLocalIdempotencyAdapter()
end

local function getContainmentRewardResolver(): any?
	if containmentRewardResolver ~= nil then
		return containmentRewardResolver
	end
	if type(ContainmentRewardResolver) ~= "table" or type(ContainmentRewardResolver.Create) ~= "function" then
		return nil
	end
	if containmentRewardIdempotencyStore == nil and type(QueueProcessingIdempotencyStore) == "table" then
		containmentRewardIdempotencyStore = QueueProcessingIdempotencyStore.Create({
			adapter = getMemoryStoreAdapter(),
			structurePolicy = MemoryStoreStructurePolicy,
			structureId = "containmentRewardIdempotency",
			now = now,
		})
	end
	containmentRewardResolver = ContainmentRewardResolver.Create({
		now = now,
		idempotencyStore = containmentRewardIdempotencyStore,
		pairRetentionSeconds = CaptureConfig.ContainmentRewardPairCooldownSeconds,
	})
	return containmentRewardResolver
end

local function isValidCustodyEndReason(endReason: any): boolean
	return CapturePersistenceRules.ValidateCustodyEndReason(endReason).accepted == true
end
local function getDownedState(target: Player): boolean
	local roleQueryApi = getRoleServiceQueryApi()
	if roleQueryApi ~= nil and type(roleQueryApi.IsPlayerDowned) == "function" then
		return roleQueryApi.IsPlayerDowned(target.UserId) == true
	end

	return target:GetAttribute("DownedIsDowned") == true
end

local function getRescueContractQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RescueContractService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function clearPostRescueProtection(target: Player)
	target:SetAttribute(POST_RESCUE_PROTECTED_ATTRIBUTE, false)
	target:SetAttribute(POST_RESCUE_PROTECTION_EXPIRES_AT_ATTRIBUTE, nil)
	target:SetAttribute("PostRescueMovementSpeedMultiplier", nil)
end

local function isPostRescueProtected(target: Player, at: number): boolean
	local rescueApi = getRescueContractQueryApi()
	if rescueApi ~= nil and type(rescueApi.IsTargetPostRescueProtected) == "function" then
		return rescueApi.IsTargetPostRescueProtected(target.UserId, at) == true
	end

	local evaluation = PostRescueProtectionState.Evaluate({
		protected = target:GetAttribute(POST_RESCUE_PROTECTED_ATTRIBUTE),
		expiresAt = target:GetAttribute(POST_RESCUE_PROTECTION_EXPIRES_AT_ATTRIBUTE),
		at = at,
		isDowned = getDownedState(target),
		breakingAction = nil,
	})
	if evaluation.shouldClear == true then
		clearPostRescueProtection(target)
	end

	return evaluation.active == true
end

local function isInRange(custodian: Player, target: Player): boolean
	local custodianRoot = getHumanoidRootPart(custodian)
	local targetRoot = getHumanoidRootPart(target)
	if custodianRoot == nil or targetRoot == nil then
		return false
	end
	local custodianRootPart = custodianRoot :: BasePart
	local targetRootPart = targetRoot :: BasePart

	local delta = (custodianRootPart.Position - targetRootPart.Position)
	if delta == nil then
		return false
	end

	local magnitude = nil
	local magnitudeValue = (delta :: any).Magnitude
	if type(magnitudeValue) == "number" then
		magnitude = magnitudeValue
	elseif type(magnitudeValue) == "function" then
		magnitude = (delta :: any):Magnitude()
	end

	if type(magnitude) ~= "number" then
		return false
	end

	return magnitude <= CaptureConfig.TriggerRadiusStuds
end

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end

	return (at - last) < CaptureConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number)
	lastRequestAtByUserId[userId] = at
end

local function isRejectCoolingDown(userId: number, at: number): boolean
	local rejectCooldown = CaptureConfig.RejectRequestCooldownSeconds
	if type(rejectCooldown) ~= "number" or rejectCooldown <= 0 then
		return false
	end

	local last = lastRejectedRequestAtByUserId[userId]
	if last == nil then
		return false
	end

	return (at - last) < rejectCooldown
end

local function markRejectedRequest(userId: number, at: number)
	lastRejectedRequestAtByUserId[userId] = at
end

local function getCustodianTargetKey(custodianUserId: number, targetUserId: number): string
	return string.format("%d|%d", custodianUserId, targetUserId)
end

local function clearAntiGuardingHistoryForUser(userId: number)
	for key, _ in pairs(lastCaptureAtByCustodianTargetKey) do
		local separatorIndex = string.find(key, "|", 1, true)
		if separatorIndex ~= nil then
			local custodianPart = string.sub(key, 1, separatorIndex - 1)
			local targetPart = string.sub(key, separatorIndex + 1)
			local custodianId = tonumber(custodianPart)
			local targetId = tonumber(targetPart)
			if custodianId == userId or targetId == userId then
				lastCaptureAtByCustodianTargetKey[key] = nil
			end
		end
	end
end

local function setCaptureLastReason(player: Player?, reason: string)
	if player == nil then
		return
	end

	local attrs = CaptureConfig.StateAttributes
	player:SetAttribute(attrs.CaptureLastReason, reason)
end

local function resolveContainmentRewardForRecord(
	record: any,
	endReason: string,
	endedAt: number,
	operationId: string?
): any
	local resolver = getContainmentRewardResolver()
	if resolver == nil or type(resolver.Resolve) ~= "function" then
		return {
			accepted = false,
			reason = "containment_reward_resolver_unavailable",
		}
	end

	local ok, result = pcall(function()
		return resolver.Resolve({
			operationId = operationId,
			custodianUserId = record.custodianUserId,
			custodianPlayer = getPlayerByUserId(record.custodianUserId),
			targetUserId = record.targetUserId,
			captureStartedAt = record.startedAt,
			captureExpiresAt = record.expiresAt,
			endedAt = endedAt,
			endReason = endReason,
			custodyWindowSeconds = CaptureConfig.CustodyWindowSeconds,
		})
	end)
	if not ok or type(result) ~= "table" then
		return {
			accepted = false,
			reason = "containment_reward_resolver_fault",
		}
	end
	return result
end

local function projectCustodyEndReason(record: any, endReason: string)
	setCaptureLastReason(getPlayerByUserId(record.custodianUserId), endReason)
	setCaptureLastReason(getPlayerByUserId(record.targetUserId), endReason)
end

local function applyCaptivitySafeReturnFallback(record: any, at: number, returnReason: string)
	local target = getPlayerByUserId(record.targetUserId)
	if target ~= nil then
		target:SetAttribute("CaptivitySafeReturnPending", true)
		target:SetAttribute("CaptivitySafeReturnReason", returnReason)
		target:SetAttribute("CaptivitySafeReturnAt", at)
	end

	CaptivitySafeReturnCaller.Apply(record.targetUserId, at, returnReason)
end

local function pruneExpiredCaptures(at: number)
	for _, record in ipairs(CaptureState.GetAllCaptures(state)) do
		local timeout = CaptivityDurationState.ResolveTimeout(record, at, CaptureConfig)
		if timeout.accepted == true and timeout.shouldEnd == true then
			local endReason = timeout.custodyEndReason or CapturePersistenceRules.CustodyEndReasons.timeout
			resolveContainmentRewardForRecord(record, endReason, record.expiresAt, nil)
			projectCustodyEndReason(record, endReason)
			local fallbackReason = timeout.fallbackEndReason or CapturePersistenceRules.CustodyEndReasons.safe_return
			applyCaptivitySafeReturnFallback(record, at, fallbackReason)
		end
	end
	state = CaptureState.PruneExpired(state, at)
	applyCaptureAttributesFromState()
end

applyCaptureAttributesFromState = function()
	local attrs = CaptureConfig.StateAttributes

	for _, player in Players:GetPlayers() do
		player:SetAttribute(attrs.CaptureActive, false)
		player:SetAttribute(attrs.CaptureCustodianUserId, nil)
		player:SetAttribute(attrs.CaptureExpiresAt, nil)
		player:SetAttribute(attrs.CaptureContainmentPhase, nil)
	end

	local captures = CaptureState.GetAllCaptures(state)
	for _, record in ipairs(captures) do
		local custodian = getPlayerByUserId(record.custodianUserId)
		if custodian ~= nil then
			custodian:SetAttribute(attrs.CaptureActive, true)
			custodian:SetAttribute(attrs.CaptureExpiresAt, record.expiresAt)
		end

		local target = getPlayerByUserId(record.targetUserId)
		if target ~= nil then
			target:SetAttribute(attrs.CaptureActive, true)
			target:SetAttribute(attrs.CaptureCustodianUserId, record.custodianUserId)
			target:SetAttribute(attrs.CaptureExpiresAt, record.expiresAt)
			target:SetAttribute(attrs.CaptureContainmentPhase, record.containmentPhase)
		end
	end
end

local function getScoreServiceQueryApi(): any?
	local globalValue = globalEnv
	if type(globalValue._ScoreService_QueryAPI) == "table" then
		return globalValue._ScoreService_QueryAPI
	end
	if type(_G) == "table" and type((_G :: any)._ScoreService_QueryAPI) == "table" then
		return (_G :: any)._ScoreService_QueryAPI
	end
	return nil
end

local function getTrophyServiceQueryApi(): any?
	local globalValue = globalEnv
	if type(globalValue._TrophyService_QueryAPI) == "table" then
		return globalValue._TrophyService_QueryAPI
	end
	if type(_G) == "table" and type((_G :: any)._TrophyService_QueryAPI) == "table" then
		return (_G :: any)._TrophyService_QueryAPI
	end
	return nil
end

local function getGiantLevelServiceQueryApi(): any?
	local globalValue = globalEnv
	if type(globalValue._GiantLevelService_QueryAPI) == "table" then
		return globalValue._GiantLevelService_QueryAPI
	end
	if type(_G) == "table" and type((_G :: any)._GiantLevelService_QueryAPI) == "table" then
		return (_G :: any)._GiantLevelService_QueryAPI
	end
	return nil
end

local function getPenRationingServiceQueryApi(): any?
	local queryApi = globalEnv._PenRationingService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._PenRationingService_QueryAPI) == "table" then
		return (_G :: any)._PenRationingService_QueryAPI
	end
	return nil
end

local function resolveMoraleCaptureGate(custodianUserId: number, targetUserId: number, at: number): any
	local rationingApi = getPenRationingServiceQueryApi()
	if type(rationingApi) ~= "table" or type(rationingApi.GetCustodianMorale) ~= "function" then
		return { allowed = true, reason = "accepted" }
	end

	local morale = rationingApi.GetCustodianMorale(custodianUserId)
	return PenRationingState.ResolveCaptureMoraleCheck(
		morale,
		custodianUserId,
		targetUserId,
		at,
		PenRationingConfig.MoraleCaptureSureThreshold
	)
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

local function requestCapture(custodian: Player, targetUserId: any, at: number?): any
	local resolvedNow = now()
	if type(at) == "number" then
		resolvedNow = at
	end
	pruneExpiredCaptures(resolvedNow)

	if isCoolingDown(custodian.UserId, resolvedNow) then
		setCaptureLastReason(custodian, "request_cooldown")
		return { accepted = false, reason = "request_cooldown" }
	end

	if isRejectCoolingDown(custodian.UserId, resolvedNow) then
		setCaptureLastReason(custodian, "request_cooldown")
		return { accepted = false, reason = "request_cooldown" }
	end

	if type(targetUserId) ~= "number" then
		markRejectedRequest(custodian.UserId, resolvedNow)
		setCaptureLastReason(custodian, "target_user_id_invalid")
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	local target = getPlayerByUserId(targetUserId)
	if target == nil then
		markRejectedRequest(custodian.UserId, resolvedNow)
		setCaptureLastReason(custodian, "target_not_found")
		return { accepted = false, reason = "target_not_found" }
	end

	if isPostRescueProtected(target, resolvedNow) then
		setCaptureLastReason(custodian, "target_post_rescue_protected")
		setCaptureLastReason(target, "target_post_rescue_protected")
		return { accepted = false, reason = "target_post_rescue_protected" }
	end

	local activeTargetCapture = CaptureState.GetTargetCapture(state, targetUserId)
	if activeTargetCapture == nil then
		local antiGuardingKey = getCustodianTargetKey(custodian.UserId, target.UserId)
		local lastAt = lastCaptureAtByCustodianTargetKey[antiGuardingKey]
		if type(lastAt) == "number" then
			local elapsedSeconds = resolvedNow - (lastAt :: number)
			if elapsedSeconds < ANTI_GUARDING_REPEAT_TARGET_COOLDOWN_SECONDS then
				setCaptureLastReason(custodian, "anti_guarding_repeat_target_cooldown")
				setCaptureLastReason(target, "anti_guarding_repeat_target_cooldown")
				return { accepted = false, reason = "anti_guarding_repeat_target_cooldown" }
			end
		end
	end

	local moraleGate = resolveMoraleCaptureGate(custodian.UserId, targetUserId, resolvedNow)
	if moraleGate.allowed ~= true then
		markRejectedRequest(custodian.UserId, resolvedNow)
		setCaptureLastReason(custodian, moraleGate.reason)
		setCaptureLastReason(target, moraleGate.reason)
		return { accepted = false, reason = moraleGate.reason }
	end

	local transition = CaptureState.ResolveRequest(state, {
		now = resolvedNow,
		custodianUserId = custodian.UserId,
		targetUserId = targetUserId,
		custodianRole = custodian:GetAttribute(ROLE_ATTRIBUTE),
		targetRole = target:GetAttribute(ROLE_ATTRIBUTE),
		custodianAlive = isPlayerAlive(custodian),
		targetDowned = getDownedState(target),
		inRange = isInRange(custodian, target),
		custodyWindowSeconds = CaptureConfig.CustodyWindowSeconds,
		maxConcurrentCapturesPerCustodian = resolveMaxConcurrentCapturesPerCustodian(),
	})

	if transition.accepted and transition.record ~= nil then
		local recordValidation = CapturePersistenceRules.ValidateCaptureRecord(transition.record, resolvedNow)
		if recordValidation.accepted ~= true then
			setCaptureLastReason(custodian, recordValidation.reason)
			setCaptureLastReason(target, recordValidation.reason)
			markRejectedRequest(custodian.UserId, resolvedNow)
			applyCaptureAttributesFromState()
			return {
				accepted = false,
				reason = recordValidation.reason,
				record = nil,
			}
		end
		local captivityValidation = CaptivityDurationState.ValidateRecordBounds(transition.record, CaptureConfig)
		if captivityValidation.accepted ~= true then
			setCaptureLastReason(custodian, captivityValidation.reason)
			setCaptureLastReason(target, captivityValidation.reason)
			markRejectedRequest(custodian.UserId, resolvedNow)
			applyCaptureAttributesFromState()
			return {
				accepted = false,
				reason = captivityValidation.reason,
				record = nil,
			}
		end
	end

	state = transition.state
	setCaptureLastReason(custodian, transition.reason)
	setCaptureLastReason(target, transition.reason)
	if transition.accepted then
		local antiGuardingKey = getCustodianTargetKey(custodian.UserId, target.UserId)
		lastCaptureAtByCustodianTargetKey[antiGuardingKey] = resolvedNow
		markRequest(custodian.UserId, resolvedNow)
		local scoreApi = getScoreServiceQueryApi()
		if scoreApi ~= nil and type(scoreApi.RequestScoreEvent) == "function" then
			scoreApi.RequestScoreEvent(
				custodian.UserId,
				"capture_success",
				resolvedNow,
				{ targetUserId = target.UserId }
			)
		end
		local trophyApi = getTrophyServiceQueryApi()
		if trophyApi ~= nil and type(trophyApi.RecordCaptureSuccess) == "function" then
			trophyApi.RecordCaptureSuccess(custodian.UserId, target.UserId, resolvedNow)
		end
		local giantLevelApi = getGiantLevelServiceQueryApi()
		if giantLevelApi ~= nil and type(giantLevelApi.RecordCaptureSuccess) == "function" then
			giantLevelApi.RecordCaptureSuccess(custodian.UserId, target.UserId, resolvedNow)
		end
	else
		markRejectedRequest(custodian.UserId, resolvedNow)
	end
	applyCaptureAttributesFromState()

	return {
		accepted = transition.accepted,
		reason = transition.reason,
		record = transition.record,
	}
end

local function resolveCustodyEnd(targetUserId: any, endReason: any, at: number?, operationId: string?): any
	local resolvedNow = if type(at) == "number" then at else now()
	if type(targetUserId) ~= "number" then
		return { accepted = false, reason = "target_user_id_invalid" }
	end
	if not isValidCustodyEndReason(endReason) then
		return { accepted = false, reason = "end_reason_invalid" }
	end

	local record = CaptureState.GetTargetCapture(state, targetUserId)
	if record == nil then
		return { accepted = false, reason = "capture_missing" }
	end

	local transition = CaptureState.ResolveRelease(state, {
		now = resolvedNow,
		targetUserId = targetUserId,
	})
	if transition.accepted ~= true or transition.record == nil then
		return {
			accepted = false,
			reason = transition.reason,
		}
	end

	state = transition.state
	projectCustodyEndReason(transition.record, endReason)
	local reward = resolveContainmentRewardForRecord(transition.record, endReason, resolvedNow, operationId)
	local structureApi = getContainmentStructureQueryApi()
	if structureApi ~= nil and type(structureApi.RemoveOccupantByTargetUserId) == "function" then
		pcall(structureApi.RemoveOccupantByTargetUserId, targetUserId)
	end
	applyCaptureAttributesFromState()

	return {
		accepted = true,
		reason = endReason,
		record = transition.record,
		reward = reward,
	}
end

local function releaseCapture(custodianUserId: any, targetUserId: any, at: number?): any
	if type(custodianUserId) ~= "number" then
		return { accepted = false, reason = "custodian_user_id_invalid" }
	end
	if type(targetUserId) ~= "number" then
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	local record = CaptureState.GetTargetCapture(state, targetUserId)
	if record == nil then
		return { accepted = false, reason = "capture_missing" }
	end
	if record.custodianUserId ~= custodianUserId then
		return { accepted = false, reason = "custodian_mismatch" }
	end

	return resolveCustodyEnd(targetUserId, "released", at, nil)
end

local function promoteTargetToContained(targetUserId: any, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	pruneExpiredCaptures(resolvedNow)
	if type(targetUserId) ~= "number" then
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	local record = CaptureState.GetTargetCapture(state, targetUserId)
	if record == nil then
		return { accepted = false, reason = "capture_missing" }
	end

	local structureApi = getContainmentStructureQueryApi()
	local structureAssignment = nil
	if structureApi ~= nil and type(structureApi.ResolveAssignOccupantForCapture) == "function" then
		local custodian = getPlayerByUserId(record.custodianUserId)
		local target = getPlayerByUserId(targetUserId)
		local custodianPosition = nil
		local targetPosition = nil
		if custodian ~= nil then
			local custodianRoot = getHumanoidRootPart(custodian)
			if custodianRoot ~= nil then
				custodianPosition = custodianRoot.Position
			end
		end
		if target ~= nil then
			local targetRoot = getHumanoidRootPart(target)
			if targetRoot ~= nil then
				targetPosition = targetRoot.Position
			end
		end
		structureAssignment = structureApi.ResolveAssignOccupantForCapture({
			targetUserId = targetUserId,
			custodianUserId = record.custodianUserId,
			custodianPosition = custodianPosition,
			targetPosition = targetPosition,
		})
		if structureAssignment.accepted ~= true and structureAssignment.skipped ~= true then
			return {
				accepted = false,
				reason = structureAssignment.reason,
				structureId = structureAssignment.structureId,
			}
		end
	end

	local transition = CaptureState.ResolvePromoteToContained(state, {
		now = resolvedNow,
		targetUserId = targetUserId,
	})
	if transition.accepted ~= true and structureAssignment ~= nil and structureAssignment.skipped ~= true then
		if structureApi ~= nil and type(structureApi.RemoveOccupantByTargetUserId) == "function" then
			pcall(structureApi.RemoveOccupantByTargetUserId, targetUserId)
		end
	end
	state = transition.state
	applyCaptureAttributesFromState()
	return {
		accepted = transition.accepted,
		reason = transition.reason,
		record = transition.record,
		structureId = if structureAssignment ~= nil then structureAssignment.structureId else nil,
	}
end

local function transferTargetCustody(targetUserId: any, newCustodianUserId: any, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	pruneExpiredCaptures(resolvedNow)
	if type(targetUserId) ~= "number" then
		return { accepted = false, reason = "target_user_id_invalid" }
	end
	if type(newCustodianUserId) ~= "number" then
		return { accepted = false, reason = "custodian_user_id_invalid" }
	end

	local transition = CaptureState.ResolveTransferCustody(state, {
		now = resolvedNow,
		targetUserId = targetUserId,
		newCustodianUserId = newCustodianUserId,
	})
	if transition.accepted ~= true or transition.record == nil then
		return {
			accepted = false,
			reason = transition.reason,
		}
	end

	state = transition.state
	applyCaptureAttributesFromState()
	return {
		accepted = true,
		reason = transition.reason,
		record = transition.record,
	}
end

Players.PlayerRemoving:Connect(function(player: Player)
	local resolvedNow = now()
	local logoutPlan = DisconnectResolutionState.ResolveLogout({
		userId = player.UserId,
		records = CaptureState.GetAllCaptures(state),
	})
	if logoutPlan.accepted == true and type(logoutPlan.recordsToClear) == "table" then
		local endReason = logoutPlan.endReason or CapturePersistenceRules.CustodyEndReasons.logout
		for _, record in ipairs(logoutPlan.recordsToClear) do
			resolveContainmentRewardForRecord(record, endReason, resolvedNow, nil)
			projectCustodyEndReason(record, endReason)
		end
	end

	if logoutPlan.accepted == true and logoutPlan.persistReturnPendingForDisconnectingUser == true then
		DisconnectSafeReturnCaller.PersistDisconnectReturnPending(player.UserId, resolvedNow, {
			sourceId = "capture_disconnect",
		})
	end

	if logoutPlan.accepted == true and type(logoutPlan.targetsToSafeReturn) == "table" then
		for _, targetUserId in ipairs(logoutPlan.targetsToSafeReturn) do
			if getPlayerByUserId(targetUserId) ~= nil then
				DisconnectSafeReturnCaller.ApplyOnlineSafeReturn(
					targetUserId,
					resolvedNow,
					CapturePersistenceRules.CustodyEndReasons.safe_return
				)
			end
		end
	end

	lastRequestAtByUserId[player.UserId] = nil
	lastRejectedRequestAtByUserId[player.UserId] = nil
	clearAntiGuardingHistoryForUser(player.UserId)
	state = CaptureState.RemovePlayer(state, player.UserId)
	applyCaptureAttributesFromState()
end)

_G._CaptureService_QueryAPI = {
	RequestCapture = function(custodianUserId: number, targetUserId: number, at: number?): any
		local custodian = getPlayerByUserId(custodianUserId)
		if custodian == nil then
			return { accepted = false, reason = "custodian_not_found" }
		end
		return requestCapture(custodian, targetUserId, at)
	end,
	GetTargetCapture = function(targetUserId: number, at: number?): any
		if type(at) == "number" then
			pruneExpiredCaptures(at)
		end
		return CaptureState.GetTargetCapture(state, targetUserId)
	end,
	GetCustodianCapture = function(custodianUserId: number, at: number?): any
		if type(at) == "number" then
			pruneExpiredCaptures(at)
		end
		return CaptureState.GetCustodianCapture(state, custodianUserId)
	end,
	GetAllCaptures = function(at: number?): { any }
		if type(at) == "number" then
			pruneExpiredCaptures(at)
		end
		return CaptureState.GetAllCaptures(state)
	end,
	ResolveCustodyEnd = function(targetUserId: number, endReason: string, at: number?, operationId: string?): any
		return resolveCustodyEnd(targetUserId, endReason, at, operationId)
	end,
	ReleaseCapture = function(custodianUserId: number, targetUserId: number, at: number?): any
		return releaseCapture(custodianUserId, targetUserId, at)
	end,
	ValidateCustodyEndReason = function(endReason: string): any
		return CapturePersistenceRules.ValidateCustodyEndReason(endReason)
	end,
	ValidateCaptureRecord = function(record: any, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		return CapturePersistenceRules.ValidateCaptureRecord(record, resolvedNow)
	end,
	CanTargetPerformEscapeAction = function(action: string): boolean
		return CapturePersistenceRules.CanTargetPerformEscapeAction(action)
	end,
	ResolveReconnectCaptureRestore = function(input: any?): any
		return CapturePersistenceRules.ResolveReconnectRestore(input)
	end,
	ResolveProfileCaptureHydration = function(input: any): any
		return CapturePersistenceRules.ResolveProfileHydration(input)
	end,
	GetCapturePersistenceRules = function(): any
		return CapturePersistenceRules
	end,
	GetCaptivityDurationRules = function(): any
		return CaptivityDurationState
	end,
	PromoteTargetToContained = function(targetUserId: number, at: number?): any
		return promoteTargetToContained(targetUserId, at)
	end,
	TransferTargetCustody = function(targetUserId: number, newCustodianUserId: number, at: number?): any
		return transferTargetCustody(targetUserId, newCustodianUserId, at)
	end,
	ResetForTests = function()
		state = CaptureState.NewState()
		lastRequestAtByUserId = {}
		lastRejectedRequestAtByUserId = {}
		lastCaptureAtByCustodianTargetKey = {}
		containmentRewardResolver = nil
		containmentRewardIdempotencyStore = nil
		applyCaptureAttributesFromState()
	end,
}
