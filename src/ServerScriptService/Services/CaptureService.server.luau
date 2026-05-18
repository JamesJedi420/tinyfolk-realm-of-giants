--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local CaptureState = require(GiantRealm:WaitForChild("CaptureState"))

local ROLE_ATTRIBUTE = "Role"
local POST_RESCUE_PROTECTED_ATTRIBUTE = "PostRescueProtected"
local POST_RESCUE_PROTECTION_EXPIRES_AT_ATTRIBUTE = "PostRescueProtectionExpiresAt"
local ANTI_GUARDING_REPEAT_TARGET_COOLDOWN_SECONDS = 12

local state = CaptureState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local lastRejectedRequestAtByUserId: { [number]: number? } = {}
local lastCaptureAtByCustodianTargetKey: { [string]: number? } = {}
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
local function getScoreServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._ScoreService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end
local function getDownedState(target: Player): boolean
	local roleQueryApi = getRoleServiceQueryApi()
	if roleQueryApi ~= nil and type(roleQueryApi.IsPlayerDowned) == "function" then
		return roleQueryApi.IsPlayerDowned(target.UserId) == true
	end

	return target:GetAttribute("DownedIsDowned") == true
end

local function clearPostRescueProtection(target: Player)
	target:SetAttribute(POST_RESCUE_PROTECTED_ATTRIBUTE, false)
	target:SetAttribute(POST_RESCUE_PROTECTION_EXPIRES_AT_ATTRIBUTE, nil)
end

local function isPostRescueProtected(target: Player, at: number): boolean
	if target:GetAttribute(POST_RESCUE_PROTECTED_ATTRIBUTE) ~= true then
		return false
	end

	-- Phase 3 bounded cancellation: once target is downed again, protection ends.
	if getDownedState(target) then
		clearPostRescueProtection(target)
		return false
	end

	local expiresAt = target:GetAttribute(POST_RESCUE_PROTECTION_EXPIRES_AT_ATTRIBUTE)
	if type(expiresAt) ~= "number" then
		clearPostRescueProtection(target)
		return false
	end

	if expiresAt <= at then
		clearPostRescueProtection(target)
		return false
	end

	return true
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

local function pruneExpiredCaptures(at: number)
	state = CaptureState.PruneExpired(state, at)
	applyCaptureAttributesFromState()
end

applyCaptureAttributesFromState = function()
	local attrs = CaptureConfig.StateAttributes

	for _, player in Players:GetPlayers() do
		player:SetAttribute(attrs.CaptureActive, false)
		player:SetAttribute(attrs.CaptureCustodianUserId, nil)
		player:SetAttribute(attrs.CaptureExpiresAt, nil)
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
	})

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

Players.PlayerRemoving:Connect(function(player: Player)
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
	ResetForTests = function()
		state = CaptureState.NewState()
		lastRequestAtByUserId = {}
		lastRejectedRequestAtByUserId = {}
		lastCaptureAtByCustodianTargetKey = {}
		applyCaptureAttributesFromState()
	end,
}
