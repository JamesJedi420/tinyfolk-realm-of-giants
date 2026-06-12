--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local globalEnv: any = (getfenv and getfenv()) or _G
local RaycastParamsCtor: any = globalEnv and globalEnv.RaycastParams
local OverlapParamsCtor: any = globalEnv and globalEnv.OverlapParams

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local GrabConfig = require(Config:WaitForChild("GrabConfig"))
local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local SafeZonePolicy = require(GiantRealm:WaitForChild("SafeZonePolicy"))
local GrabState = require(GiantRealm:WaitForChild("GrabState"))
local CarryLoadState = require(GiantRealm:WaitForChild("CarryLoadState"))
local CapturePersistenceRules = require(GiantRealm:WaitForChild("CapturePersistenceRules"))

local ROLE_ATTRIBUTE = "Role"
local REMOTES_FOLDER_NAME = "Remotes"
local GRAB_REMOTE_NAME = "GrabRequest"
local PLACE_REMOTE_NAME = "PlaceRequest"
local COUNTERPLAY_REMOTE_NAME = "CarriedCounterplayRequest"
local STUDIO_DEBUG_REQUEST_REMOTE_NAME = "GrabStudioDebugRequest"
local STUDIO_DEBUG_RESPONSE_REMOTE_NAME = "GrabStudioDebugResponse"

local HELD_TARGET_ATTRIBUTE = "HeldTargetUserId"
local HELD_BY_ATTRIBUTE = "HeldByUserId"

local heldTargetByGiantUserId: { [number]: number } = {}
local heldByTargetUserId: { [number]: number } = {}
local carriedTargetsByGiantUserId: { [number]: { number } } = {}
local carriedStateByTargetUserId: { [number]: any } = {}
local preGrabCFrameByTargetUserId: { [number]: any } = {}
local lastRequestAtByUserId: { [number]: number } = {}

local function debugLog(message: string)
	print(string.format("[GrabService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GrabService] %s", message))
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
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
	debugLog("Created ReplicatedStorage.Remotes folder")
	return folder
end

local function ensureRemote(parentFolder: Folder, remoteName: string): RemoteEvent
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

local function isPlayerRole(player: Player, roleName: string): boolean
	return player:GetAttribute(ROLE_ATTRIBUTE) == roleName
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

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	return nil
end

local function isAlive(player: Player): boolean
	local humanoid = getHumanoid(player)
	if not humanoid then
		return false
	end

	return humanoid.Health > 0
end

local function now(): number
	return os.clock()
end

local function isCoolingDown(userId: number, at: number?): boolean
	local last = lastRequestAtByUserId[userId]
	if not last then
		return false
	end

	return ((if type(at) == "number" then at else now()) - last) < GrabConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number?)
	lastRequestAtByUserId[userId] = if type(at) == "number" then at else now()
end

local function getOrCreateCarriedState(userId: number): any
	local existing = carriedStateByTargetUserId[userId]
	if existing ~= nil then
		return existing
	end
	local created = GrabState.New(now())
	carriedStateByTargetUserId[userId] = created
	return created
end

local function getCarriedSnapshot(userId: number): any
	local state = carriedStateByTargetUserId[userId]
	if state == nil then
		return GrabState.Snapshot(GrabState.New(now()))
	end
	return GrabState.Snapshot(state)
end

local function isCarried(userId: number): boolean
	local state = carriedStateByTargetUserId[userId]
	if state ~= nil and GrabState.IsCarried(state) then
		return true
	end
	return heldByTargetUserId[userId] ~= nil
end

local function getGiantBaseWalkSpeed(): number
	local humanoidBaseByRole = RoleConfig.HumanoidBaseByRole
	if type(humanoidBaseByRole) == "table" then
		local giantBase = humanoidBaseByRole[RoleConfig.Roles.Giant]
		if type(giantBase) == "table" and type(giantBase.walkSpeed) == "number" then
			return giantBase.walkSpeed
		end
	end

	return 16
end

local function getCarrierTargetIds(giantUserId: number): { number }
	local targetIds = carriedTargetsByGiantUserId[giantUserId]
	if type(targetIds) == "table" then
		local copied: { number } = {}
		for _, targetUserId in targetIds do
			table.insert(copied, targetUserId)
		end
		return copied
	end

	local heldTargetUserId = heldTargetByGiantUserId[giantUserId]
	if type(heldTargetUserId) == "number" then
		return { heldTargetUserId }
	end

	return {}
end

local function getCarrierLoadSnapshot(giantUserId: number): any
	return CarryLoadState.Snapshot(GrabConfig, getCarrierTargetIds(giantUserId))
end

local function setCarrierLoadAttributes(
	giant: Player?,
	snapshot: any,
	lastRejectReason: string?,
	lastDropReason: string?
)
	if giant == nil then
		return
	end

	giant:SetAttribute(GrabConfig.CarrySlotsUsedAttribute, snapshot.slotsUsed)
	giant:SetAttribute(GrabConfig.CarryCapacityAttribute, snapshot.capacity)
	giant:SetAttribute(GrabConfig.CarryEncumbranceAttribute, snapshot.encumbrance)
	giant:SetAttribute(GrabConfig.CarrySpeedMultiplierAttribute, snapshot.speedMultiplier)
	giant:SetAttribute(GrabConfig.CarryAtCapacityAttribute, snapshot.isAtCapacity)
	giant:SetAttribute(GrabConfig.CarryOverloadedAttribute, snapshot.isOverloaded)
	giant:SetAttribute(GrabConfig.CarryLastRejectReasonAttribute, lastRejectReason)
	giant:SetAttribute(GrabConfig.CarryLastDropReasonAttribute, lastDropReason)
end

local function applyCarrierLoadState(giant: Player?, lastRejectReason: string?, lastDropReason: string?): any
	if giant == nil then
		return CarryLoadState.Snapshot(GrabConfig, {})
	end

	local snapshot = getCarrierLoadSnapshot(giant.UserId)
	setCarrierLoadAttributes(giant, snapshot, lastRejectReason, lastDropReason)

	local humanoid = getHumanoid(giant)
	if humanoid ~= nil then
		local baseWalkSpeed = getGiantBaseWalkSpeed()
		humanoid.WalkSpeed = baseWalkSpeed * snapshot.speedMultiplier
	end

	return snapshot
end

local function addCarrierTarget(giantUserId: number, targetUserId: number)
	carriedTargetsByGiantUserId[giantUserId] = { targetUserId }
end

local function removeCarrierTarget(giantUserId: number, targetUserId: number)
	local existingTargets = carriedTargetsByGiantUserId[giantUserId]
	if type(existingTargets) ~= "table" then
		carriedTargetsByGiantUserId[giantUserId] = nil
		return
	end

	local nextTargets: { number } = {}
	for _, existingTargetUserId in existingTargets do
		if existingTargetUserId ~= targetUserId then
			table.insert(nextTargets, existingTargetUserId)
		end
	end

	carriedTargetsByGiantUserId[giantUserId] = if #nextTargets > 0 then nextTargets else nil
end

local function evaluateTargetSafeZone(player: Player, at: number): any
	return SafeZonePolicy.EvaluateProtection(EscapeConfig, {
		safeZoneState = player:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
		safeZoneType = player:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
		safeZoneProtectionEndsAt = player:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute),
		now = at,
	})
end

local function resolveDistance(a: any, b: any): number?
	local ok, delta = pcall(function()
		return a - b
	end)
	if not ok or delta == nil then
		return nil
	end

	if typeof(delta) == "Vector3" then
		return (delta :: Vector3).Magnitude
	end

	if type(delta) == "table" then
		if type((delta :: any).Magnitude) == "function" then
			return (delta :: any):Magnitude()
		end
		if type((delta :: any).Magnitude) == "number" then
			return (delta :: any).Magnitude
		end
	end

	if type(delta) == "number" then
		return math.abs(delta)
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

local function getCaptureServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._CaptureService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

local function canPerformEscapeAction(action: string): (boolean, string?)
	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.CanTargetPerformEscapeAction) ~= "function" then
		return true, nil
	end

	local ok, allowed = pcall(captureApi.CanTargetPerformEscapeAction, action)
	if not ok then
		return false, "capture_query_fault"
	end
	if allowed ~= true then
		return false, "escape_action_blocked"
	end

	return true, nil
end

local function isTargetCarryCompatible(target: Player): (boolean, string?)
	local roleServiceQueryApi = getRoleServiceQueryApi()
	if roleServiceQueryApi == nil or type(roleServiceQueryApi.GetDownedSnapshot) ~= "function" then
		return true, nil
	end

	local snapshot = roleServiceQueryApi.GetDownedSnapshot(target.UserId)
	if type(snapshot) ~= "table" then
		return true, nil
	end

	if snapshot.isDowned == true or snapshot.carryEligibleMarker == true then
		return true, nil
	end

	return true, nil
end

local function setCarriedAttributes(target: Player?, snapshot: any)
	if target == nil then
		return
	end
	target:SetAttribute(GrabConfig.CarriedStateAttribute, snapshot.state)
	target:SetAttribute(GrabConfig.CarriedByUserIdAttribute, snapshot.carriedByUserId)
	target:SetAttribute(GrabConfig.CarriedGrabbedAtAttribute, snapshot.grabbedAt)
	target:SetAttribute(GrabConfig.CarriedCooldownEndsAtAttribute, snapshot.cooldownEndsAt)
	target:SetAttribute(GrabConfig.CarriedCounterplayProgressAttribute, snapshot.counterplayProgress)
	target:SetAttribute(GrabConfig.CarriedCounterplayRequiredAttribute, snapshot.counterplayRequired)
	target:SetAttribute(GrabConfig.CarriedReleaseReasonAttribute, snapshot.releaseReason)
	target:SetAttribute(GrabConfig.CarriedLastActionAttribute, snapshot.lastAction)
	target:SetAttribute(GrabConfig.CarriedLastRejectReasonAttribute, snapshot.lastRejectReason)
end

local function setGiantCarriedAttributes(giant: Player?, snapshot: any)
	if giant == nil then
		return
	end
	local giantCarriedState = snapshot.state
	if giantCarriedState == GrabState.States.Carried or giantCarriedState == GrabState.States.Counterplay then
		-- Carrier keeps Free; HeldTargetUserId drives CarryingGiant physics/collision refresh.
		giantCarriedState = GrabState.States.Free
	end
	giant:SetAttribute(GrabConfig.CarriedStateAttribute, giantCarriedState)
	giant:SetAttribute(GrabConfig.CarriedTargetUserIdAttribute, snapshot.targetUserId)
	giant:SetAttribute(GrabConfig.CarriedCooldownEndsAtAttribute, snapshot.cooldownEndsAt)
	giant:SetAttribute(GrabConfig.CarriedLastActionAttribute, snapshot.lastAction)
	giant:SetAttribute(GrabConfig.CarriedLastRejectReasonAttribute, snapshot.lastRejectReason)
end

local function setHeldAttributes(giant: Player?, target: Player?)
	if giant then
		if target then
			giant:SetAttribute(HELD_TARGET_ATTRIBUTE, target.UserId)
		else
			giant:SetAttribute(HELD_TARGET_ATTRIBUTE, nil)
		end
	end

	if target then
		if giant then
			target:SetAttribute(HELD_BY_ATTRIBUTE, giant.UserId)
		else
			target:SetAttribute(HELD_BY_ATTRIBUTE, nil)
		end
	end
end

local resolveSafeDropCFrame: any = nil

local function clearHoldByGiantUserId(giantUserId: number, reason: string, placeCFrame: CFrame?)
	local targetUserId = heldTargetByGiantUserId[giantUserId]
	if not targetUserId then
		return
	end

	local giant = getPlayerByUserId(giantUserId)
	local target = getPlayerByUserId(targetUserId)
	local state = carriedStateByTargetUserId[targetUserId]
	local releaseSnapshot: any = nil
	local safeDropCFrame, dropReason = resolveSafeDropCFrame(giant, target, placeCFrame)

	heldTargetByGiantUserId[giantUserId] = nil
	heldByTargetUserId[targetUserId] = nil
	removeCarrierTarget(giantUserId, targetUserId)
	if state ~= nil and GrabState.IsCarried(state) then
		local releaseResult = GrabState.Release(state, {
			now = now(),
			reason = reason,
		})
		releaseSnapshot = releaseResult.snapshot
	elseif state ~= nil then
		releaseSnapshot = GrabState.Snapshot(state)
	end

	if target then
		local targetCharacter = target.Character
		if targetCharacter then
			local targetRoot = getHumanoidRootPart(target)
			if targetRoot then
				targetRoot.Anchored = false
			end

			local targetHumanoid = getHumanoid(target)
			if targetHumanoid then
				targetHumanoid.AutoRotate = true
			end

			if safeDropCFrame ~= nil then
				targetCharacter:PivotTo(safeDropCFrame)
			end
		end
		target:SetAttribute(GrabConfig.CarryLastDropReasonAttribute, dropReason)
	end

	setHeldAttributes(giant, nil)
	setHeldAttributes(nil, target)
	if releaseSnapshot ~= nil then
		setCarriedAttributes(target, releaseSnapshot)
		setGiantCarriedAttributes(giant, releaseSnapshot)
	elseif target then
		setCarriedAttributes(target, GrabState.Snapshot(GrabState.New(now())))
	end
	if giant then
		giant:SetAttribute(GrabConfig.CarriedTargetUserIdAttribute, nil)
	end
	preGrabCFrameByTargetUserId[targetUserId] = nil
	applyCarrierLoadState(giant, nil, dropReason)

	debugLog(
		string.format(
			"Released hold giantUserId=%d targetUserId=%d reason=%s dropReason=%s",
			giantUserId,
			targetUserId,
			reason,
			dropReason
		)
	)
end

local function rejectGrab(player: Player, reason: string)
	debugWarn(string.format("Rejected GrabRequest giantUserId=%d reason=%s", player.UserId, reason))
end

local function rejectPlace(player: Player, reason: string)
	debugWarn(string.format("Rejected PlaceRequest giantUserId=%d reason=%s", player.UserId, reason))
end

local function resolveGrabTarget(payload: unknown): (Player?, string?)
	if type(payload) ~= "number" then
		return nil, "malformed_payload"
	end

	local targetUserId = payload
	if targetUserId % 1 ~= 0 then
		return nil, "target_user_id_not_integer"
	end

	local target = getPlayerByUserId(targetUserId)
	if not target then
		return nil, "target_not_found"
	end

	return target, nil
end

local function getDesiredPlacePosition(giantRoot: BasePart, payload: unknown): (Vector3?, string?)
	if payload == nil then
		return giantRoot.Position + giantRoot.CFrame.LookVector * GrabConfig.DefaultPlaceDistanceStuds, nil
	end

	if typeof(payload) ~= "Vector3" then
		return nil, "malformed_payload"
	end

	local desiredPosition = payload :: Vector3
	local delta = desiredPosition - giantRoot.Position
	local deltaMagnitude = delta.Magnitude

	if deltaMagnitude < 0.001 then
		return giantRoot.Position + giantRoot.CFrame.LookVector * GrabConfig.DefaultPlaceDistanceStuds, nil
	end

	if deltaMagnitude > GrabConfig.PlaceRangeStuds then
		desiredPosition = giantRoot.Position + delta.Unit * GrabConfig.PlaceRangeStuds
	end

	return desiredPosition, nil
end

local function validatePlacePosition(giant: Player, target: Player, desiredPosition: Vector3): (CFrame?, string?)
	local giantRoot = getHumanoidRootPart(giant)
	if not giantRoot then
		return nil, "giant_root_missing"
	end

	if (desiredPosition - giantRoot.Position).Magnitude > GrabConfig.PlaceRangeStuds then
		return nil, "place_out_of_range"
	end

	if type(RaycastParamsCtor) ~= "table" or type(RaycastParamsCtor.new) ~= "function" then
		return nil, "raycast_params_unavailable"
	end
	local raycastParams = RaycastParamsCtor.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {}

	local giantCharacter = giant.Character
	if giantCharacter then
		table.insert(raycastParams.FilterDescendantsInstances, giantCharacter)
	end

	local targetCharacter = target.Character
	if targetCharacter then
		table.insert(raycastParams.FilterDescendantsInstances, targetCharacter)
	end

	local rayOrigin = desiredPosition + Vector3.new(0, GrabConfig.PlaceProbeHeightStuds, 0)
	local rayDirection = Vector3.new(0, -GrabConfig.PlaceProbeDepthStuds, 0)
	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if not rayResult then
		return nil, "place_has_no_floor"
	end

	local finalPosition = rayResult.Position + Vector3.new(0, GrabConfig.PlaceYOffsetStuds, 0)

	if type(OverlapParamsCtor) ~= "table" or type(OverlapParamsCtor.new) ~= "function" then
		return nil, "overlap_params_unavailable"
	end
	local overlapParams = OverlapParamsCtor.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {}
	if giantCharacter then
		table.insert(overlapParams.FilterDescendantsInstances, giantCharacter)
	end
	if targetCharacter then
		table.insert(overlapParams.FilterDescendantsInstances, targetCharacter)
	end

	local overlapCenter = finalPosition + Vector3.new(0, GrabConfig.PlaceClearanceSize.Y * 0.5, 0)
	local overlaps =
		Workspace:GetPartBoundsInBox(CFrame.new(overlapCenter), GrabConfig.PlaceClearanceSize, overlapParams)
	for _, part in overlaps do
		if part.CanCollide then
			return nil, "place_blocked"
		end
	end

	return CFrame.new(finalPosition, finalPosition + giantRoot.CFrame.LookVector), nil
end

local function readRootCFrame(root: BasePart?): any?
	if root == nil then
		return nil
	end

	local ok, cframe = pcall(function()
		return (root :: any).CFrame
	end)
	if ok and cframe ~= nil then
		return cframe
	end

	local positionOk, position = pcall(function()
		return (root :: any).Position
	end)
	if positionOk and position ~= nil and CFrame ~= nil and type((CFrame :: any).new) == "function" then
		local createdOk, createdCFrame = pcall(function()
			return CFrame.new(position)
		end)
		if createdOk then
			return createdCFrame
		end
	end

	return nil
end

local function capturePreGrabCFrame(target: Player)
	preGrabCFrameByTargetUserId[target.UserId] = readRootCFrame(getHumanoidRootPart(target))
end

local function tryAddCandidate(candidates: { Vector3 }, callback: () -> any)
	local ok, value = pcall(callback)
	if ok and value ~= nil then
		table.insert(candidates, value :: Vector3)
	end
end

resolveSafeDropCFrame = function(giant: Player?, target: Player?, requestedCFrame: CFrame?): (any?, string)
	if requestedCFrame ~= nil then
		return requestedCFrame, "requested_place"
	end

	if giant ~= nil and target ~= nil then
		local giantRoot = getHumanoidRootPart(giant)
		if giantRoot ~= nil then
			local candidates: { Vector3 } = {}
			local defaultDistance = GrabConfig.DefaultPlaceDistanceStuds
			tryAddCandidate(candidates, function()
				return giantRoot.Position + giantRoot.CFrame.LookVector * defaultDistance
			end)
			tryAddCandidate(candidates, function()
				return giantRoot.Position - giantRoot.CFrame.LookVector * defaultDistance
			end)
			tryAddCandidate(candidates, function()
				return giantRoot.Position + giantRoot.CFrame.RightVector * defaultDistance
			end)
			tryAddCandidate(candidates, function()
				return giantRoot.Position - giantRoot.CFrame.RightVector * defaultDistance
			end)

			for _, candidatePosition in candidates do
				local ok, candidateCFrame = pcall(function()
					return validatePlacePosition(giant, target, candidatePosition)
				end)
				if ok and candidateCFrame ~= nil then
					return candidateCFrame, "nearby_valid_drop"
				end
			end
		end
	end

	if target ~= nil then
		local fallbackCFrame = preGrabCFrameByTargetUserId[target.UserId]
		if fallbackCFrame ~= nil then
			return fallbackCFrame, "pre_grab_fallback"
		end
	end

	return nil, "drop_position_unresolved"
end

local function updateHeldTarget(giant: Player, target: Player)
	local giantRoot = getHumanoidRootPart(giant)
	local targetCharacter = target.Character
	local targetRoot = getHumanoidRootPart(target)
	local targetHumanoid = getHumanoid(target)

	if not giantRoot or not targetCharacter or not targetRoot or not targetHumanoid then
		clearHoldByGiantUserId(giant.UserId, "missing_character_parts", nil)
		return
	end

	if not isPlayerRole(giant, RoleConfig.Roles.Giant) then
		clearHoldByGiantUserId(giant.UserId, "giant_role_invalid", nil)
		return
	end

	if not isPlayerRole(target, RoleConfig.Roles.Tinyfolk) then
		clearHoldByGiantUserId(giant.UserId, "target_role_invalid", nil)
		return
	end

	if not isAlive(giant) or not isAlive(target) then
		clearHoldByGiantUserId(giant.UserId, "actor_not_alive", nil)
		return
	end

	targetRoot.Anchored = true
	targetHumanoid.AutoRotate = false

	if type((targetCharacter :: any).PivotTo) ~= "function" then
		return
	end
	if giantRoot.CFrame == nil or CFrame == nil then
		return
	end

	local holdCFrame = giantRoot.CFrame * CFrame.new(GrabConfig.HoldOffset)
	targetCharacter:PivotTo(CFrame.new(holdCFrame.Position, holdCFrame.Position + giantRoot.CFrame.LookVector))
end

local remotesFolder = ensureRemotesFolder()
local grabRequestRemote = ensureRemote(remotesFolder, GRAB_REMOTE_NAME)
local placeRequestRemote = ensureRemote(remotesFolder, PLACE_REMOTE_NAME)
local counterplayRequestRemote = ensureRemote(remotesFolder, COUNTERPLAY_REMOTE_NAME)

local function requestGrab(player: Player, targetUserIdPayload: unknown, nowOverride: number?): any
	local requestTime = if type(nowOverride) == "number" then nowOverride else now()
	if isCoolingDown(player.UserId, requestTime) then
		return { accepted = false, reason = "request_cooldown" }
	end

	markRequest(player.UserId, requestTime)

	if not isPlayerRole(player, RoleConfig.Roles.Giant) then
		return { accepted = false, reason = "caller_not_giant" }
	end

	if heldByTargetUserId[player.UserId] then
		return { accepted = false, reason = "caller_currently_carried" }
	end

	local callerHumanoid = getHumanoid(player)
	if player.Character == nil then
		return { accepted = false, reason = "caller_character_missing" }
	end
	if getHumanoidRootPart(player) == nil then
		return { accepted = false, reason = "caller_root_missing" }
	end
	if callerHumanoid == nil then
		return { accepted = false, reason = "caller_humanoid_missing" }
	end
	if callerHumanoid.Health <= 0 then
		return { accepted = false, reason = "caller_not_alive" }
	end

	local target, payloadError = resolveGrabTarget(targetUserIdPayload)
	if not target then
		return { accepted = false, reason = payloadError or "invalid_target" }
	end

	if target == player then
		return { accepted = false, reason = "self_target" }
	end

	if not isPlayerRole(target, RoleConfig.Roles.Tinyfolk) then
		return { accepted = false, reason = "target_not_tinyfolk" }
	end

	if heldByTargetUserId[target.UserId] then
		return { accepted = false, reason = "target_already_carried" }
	end

	local capacityResult = CarryLoadState.CanAcceptTarget(GrabConfig, getCarrierTargetIds(player.UserId), target.UserId)
	if capacityResult.accepted ~= true then
		setCarrierLoadAttributes(player, capacityResult.snapshot, capacityResult.reason, nil)
		return capacityResult
	end

	if heldTargetByGiantUserId[player.UserId] then
		local loadSnapshot = getCarrierLoadSnapshot(player.UserId)
		setCarrierLoadAttributes(player, loadSnapshot, "carry_physical_slot_unavailable", nil)
		return { accepted = false, reason = "carry_physical_slot_unavailable", snapshot = loadSnapshot }
	end

	if target.Character == nil then
		return { accepted = false, reason = "target_character_missing" }
	end

	local targetHumanoid = getHumanoid(target)
	if targetHumanoid == nil then
		return { accepted = false, reason = "target_humanoid_missing" }
	end
	if targetHumanoid.Health <= 0 then
		return { accepted = false, reason = "target_not_alive" }
	end

	local giantRoot = getHumanoidRootPart(player)
	local targetRoot = getHumanoidRootPart(target)
	if not giantRoot or not targetRoot then
		return { accepted = false, reason = if not giantRoot then "caller_root_missing" else "target_root_missing" }
	end

	local distance = resolveDistance(targetRoot.Position, giantRoot.Position)
	if distance == nil then
		return { accepted = false, reason = "distance_unavailable" }
	end
	if distance > GrabConfig.GrabRangeStuds then
		return {
			accepted = false,
			reason = "target_out_of_range",
			distance = distance,
			maxDistance = GrabConfig.GrabRangeStuds,
		}
	end

	local at = requestTime
	local safeZoneDecision = evaluateTargetSafeZone(target, at)
	if safeZoneDecision.protected == true then
		return { accepted = false, reason = tostring(safeZoneDecision.reason or "target_in_safe_zone") }
	end

	local compatible, incompatibleReason = isTargetCarryCompatible(target)
	if not compatible then
		return { accepted = false, reason = incompatibleReason or "target_state_incompatible" }
	end

	local state = getOrCreateCarriedState(target.UserId)
	local attemptResult = GrabState.CanAttemptGrab(state, at)
	if attemptResult.accepted ~= true and attemptResult.reason ~= "accepted" then
		setCarriedAttributes(target, attemptResult.snapshot)
		setGiantCarriedAttributes(player, attemptResult.snapshot)
		return attemptResult
	end

	local carriedResult = GrabState.EnterCarried(state, {
		now = at,
		carriedByUserId = player.UserId,
		targetUserId = target.UserId,
		cooldownSeconds = GrabConfig.RequestCooldownSeconds,
		counterplayRequired = GrabConfig.CounterplayRequired,
		source = "giant_grab",
	})
	if carriedResult.accepted ~= true then
		setCarriedAttributes(target, carriedResult.snapshot)
		setGiantCarriedAttributes(player, carriedResult.snapshot)
		return carriedResult
	end

	heldTargetByGiantUserId[player.UserId] = target.UserId
	heldByTargetUserId[target.UserId] = player.UserId
	addCarrierTarget(player.UserId, target.UserId)
	capturePreGrabCFrame(target)
	setHeldAttributes(player, target)
	setCarriedAttributes(target, carriedResult.snapshot)
	setGiantCarriedAttributes(player, carriedResult.snapshot)
	local carrierLoadSnapshot = applyCarrierLoadState(player, nil, nil)

	updateHeldTarget(player, target)

	return {
		accepted = true,
		reason = "accepted",
		distance = distance,
		snapshot = carriedResult.snapshot,
		carrierLoadSnapshot = carrierLoadSnapshot,
	}
end

local function requestCounterplay(player: Player, nowOverride: number?): any
	local giantUserId = heldByTargetUserId[player.UserId]
	if giantUserId == nil then
		return { accepted = false, reason = "not_carried", snapshot = getCarriedSnapshot(player.UserId) }
	end

	local counterplayAllowed, counterplayReason =
		canPerformEscapeAction(CapturePersistenceRules.EscapeActions.counterplay)
	if counterplayAllowed ~= true then
		local snapshot = getCarriedSnapshot(player.UserId)
		setCarriedAttributes(player, snapshot)
		local giant = getPlayerByUserId(giantUserId)
		setGiantCarriedAttributes(giant, snapshot)
		return {
			accepted = false,
			reason = counterplayReason or "escape_action_blocked",
			snapshot = snapshot,
		}
	end

	local state = getOrCreateCarriedState(player.UserId)
	local result = GrabState.ApplyCounterplay(state, {
		now = if type(nowOverride) == "number" then nowOverride else now(),
		progressDelta = GrabConfig.CounterplayProgressPerAction,
		counterplayCooldownSeconds = GrabConfig.CounterplayActionCooldownSeconds,
	})

	local giant = getPlayerByUserId(giantUserId)
	setCarriedAttributes(player, result.snapshot)
	setGiantCarriedAttributes(giant, result.snapshot)

	if result.accepted == true and result.snapshot.state == GrabState.States.Released then
		clearHoldByGiantUserId(giantUserId, "counterplay_completed", nil)
		result.carrierLoadSnapshot = getCarrierLoadSnapshot(giantUserId)
		result.dropReason = player:GetAttribute(GrabConfig.CarryLastDropReasonAttribute)
	elseif giant ~= nil then
		result.carrierLoadSnapshot = getCarrierLoadSnapshot(giantUserId)
	end

	return result
end

grabRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local result = requestGrab(player, payload, nil)
	if result.accepted == true then
		debugLog(
			string.format(
				"Accepted GrabRequest giantUserId=%d targetUserId=%s distance=%.2f",
				player.UserId,
				tostring(payload),
				if type(result.distance) == "number" then result.distance else 0
			)
		)
	else
		rejectGrab(player, tostring(result.reason))
	end
end)

counterplayRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil then
		debugWarn(string.format("Rejected CarriedCounterplayRequest userId=%d reason=malformed_payload", player.UserId))
		return
	end

	local result = requestCounterplay(player, nil)
	if result.accepted == true then
		debugLog(string.format("Accepted CarriedCounterplayRequest userId=%d", player.UserId))
	else
		debugWarn(
			string.format(
				"Rejected CarriedCounterplayRequest userId=%d reason=%s",
				player.UserId,
				tostring(result.reason)
			)
		)
	end
end)

placeRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId, nil) then
		rejectPlace(player, "request_cooldown")
		return
	end

	markRequest(player.UserId, nil)

	if not isPlayerRole(player, RoleConfig.Roles.Giant) then
		rejectPlace(player, "requester_not_giant")
		return
	end

	local targetUserId = heldTargetByGiantUserId[player.UserId]
	if not targetUserId then
		rejectPlace(player, "giant_not_holding_target")
		return
	end

	local target = getPlayerByUserId(targetUserId)
	if not target then
		clearHoldByGiantUserId(player.UserId, "target_missing_on_place", nil)
		rejectPlace(player, "target_not_found")
		return
	end

	local giantRoot = getHumanoidRootPart(player)
	if not giantRoot then
		clearHoldByGiantUserId(player.UserId, "giant_root_missing_on_place", nil)
		rejectPlace(player, "giant_root_missing")
		return
	end

	local desiredPosition, placePayloadError = getDesiredPlacePosition(giantRoot, payload)
	if not desiredPosition then
		rejectPlace(player, placePayloadError or "malformed_payload")
		return
	end

	local placeCFrame, placeError = validatePlacePosition(player, target, desiredPosition)
	if not placeCFrame then
		rejectPlace(player, placeError or "invalid_place")
		return
	end

	clearHoldByGiantUserId(player.UserId, "placed", placeCFrame)

	debugLog(string.format("Accepted PlaceRequest giantUserId=%d targetUserId=%d", player.UserId, target.UserId))
end)

local isStudioEnvironment = type(RunService.IsStudio) == "function" and RunService:IsStudio() == true

if isStudioEnvironment then
	local studioDebugRequestRemote = ensureRemote(remotesFolder, STUDIO_DEBUG_REQUEST_REMOTE_NAME)
	local studioDebugResponseRemote = ensureRemote(remotesFolder, STUDIO_DEBUG_RESPONSE_REMOTE_NAME)

	studioDebugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			studioDebugResponseRemote:FireClient(player, { accepted = false, reason = "malformed_payload" })
			return
		end

		local action = payload.action
		if action == "applySharedHubSafeZone" then
			player:SetAttribute(EscapeConfig.SafeZoneAttribute, true)
			player:SetAttribute(EscapeConfig.SafeZoneTypeAttribute, EscapeConfig.SafeZoneTypes.SharedHub)
			debugLog(string.format("Studio safe zone applied userId=%d", player.UserId))
			studioDebugResponseRemote:FireClient(player, {
				accepted = true,
				action = action,
				inSafeZone = player:GetAttribute(EscapeConfig.SafeZoneAttribute),
				safeZoneType = player:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
			})
			return
		end

		if action == "probeGrab" then
			local targetUserId = payload.targetUserId
			if type(targetUserId) ~= "number" then
				studioDebugResponseRemote:FireClient(player, { accepted = false, reason = "malformed_target_user_id" })
				return
			end

			local result = requestGrab(player, targetUserId, os.clock())
			if result.accepted ~= true then
				rejectGrab(player, tostring(result.reason))
			end
			studioDebugResponseRemote:FireClient(player, {
				action = action,
				accepted = result.accepted == true,
				reason = result.reason,
			})
			return
		end

		studioDebugResponseRemote:FireClient(player, { accepted = false, reason = "unknown_action" })
	end)

	debugLog("GrabService studio debug remotes ready")
end

local function setupPlayer(player: Player)
	player:SetAttribute(HELD_TARGET_ATTRIBUTE, nil)
	player:SetAttribute(HELD_BY_ATTRIBUTE, nil)
	local freeSnapshot = GrabState.Snapshot(GrabState.New(now()))
	setCarriedAttributes(player, freeSnapshot)
	setGiantCarriedAttributes(player, freeSnapshot)
	setCarrierLoadAttributes(player, CarryLoadState.Snapshot(GrabConfig, {}), nil, nil)

	if
		type((player :: any).CharacterAdded) ~= "table"
		or type((player :: any).CharacterAdded.Connect) ~= "function"
	then
		return
	end

	player.CharacterAdded:Connect(function()
		local giantHolding = heldTargetByGiantUserId[player.UserId]
		if giantHolding then
			clearHoldByGiantUserId(player.UserId, "giant_character_reset", nil)
		end

		local heldByGiant = heldByTargetUserId[player.UserId]
		if heldByGiant then
			clearHoldByGiantUserId(heldByGiant, "target_character_reset", nil)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, existingPlayer in Players:GetPlayers() do
	setupPlayer(existingPlayer)
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil

	local giantHolding = heldTargetByGiantUserId[player.UserId]
	if giantHolding then
		clearHoldByGiantUserId(player.UserId, "giant_left_game", nil)
	end

	local heldByGiant = heldByTargetUserId[player.UserId]
	if heldByGiant then
		clearHoldByGiantUserId(heldByGiant, "target_left_game", nil)
	end

	carriedStateByTargetUserId[player.UserId] = nil
	carriedTargetsByGiantUserId[player.UserId] = nil
	preGrabCFrameByTargetUserId[player.UserId] = nil
end)

RunService.Heartbeat:Connect(function()
	for giantUserId, targetUserId in heldTargetByGiantUserId do
		local giant = getPlayerByUserId(giantUserId)
		local target = getPlayerByUserId(targetUserId)
		if not giant or not target then
			clearHoldByGiantUserId(giantUserId, "player_missing_during_hold", nil)
		else
			updateHeldTarget(giant, target)
		end
	end
end)

_G._GrabService_QueryAPI = {
	RequestGrab = function(giantUserId: number, targetUserId: number, nowOverride: number?): any
		local giant = getPlayerByUserId(giantUserId)
		if giant == nil then
			return { accepted = false, reason = "caller_not_found" }
		end
		return requestGrab(giant, targetUserId, nowOverride)
	end,
	RequestCounterplay = function(targetUserId: number, nowOverride: number?): any
		local target = getPlayerByUserId(targetUserId)
		if target == nil then
			return { accepted = false, reason = "target_not_found" }
		end
		return requestCounterplay(target, nowOverride)
	end,
	ReleaseCarriedByGiant = function(giantUserId: number, reason: string): any
		if heldTargetByGiantUserId[giantUserId] == nil then
			return { accepted = false, reason = "not_carrying" }
		end
		clearHoldByGiantUserId(giantUserId, reason, nil)
		return {
			accepted = true,
			reason = "accepted",
			carrierLoadSnapshot = getCarrierLoadSnapshot(giantUserId),
		}
	end,
	GetCarrySnapshot = function(userId: number): any
		return getCarriedSnapshot(userId)
	end,
	GetCarrierLoadSnapshot = function(giantUserId: number): any
		return getCarrierLoadSnapshot(giantUserId)
	end,
	IsPlayerCarried = function(userId: number): boolean
		return isCarried(userId)
	end,
	IsCarrierEncumbered = function(giantUserId: number): boolean
		return getCarrierLoadSnapshot(giantUserId).isEncumbered == true
	end,
	CanGiantPerformCarryInteraction = function(giantUserId: number, interactionName: string): any
		return CarryLoadState.CanPerformCarrierInteraction(
			GrabConfig,
			getCarrierTargetIds(giantUserId),
			interactionName
		)
	end,
	CanPlayerPerformInteraction = function(userId: number, interactionName: string): boolean
		local state = carriedStateByTargetUserId[userId]
		if state == nil then
			return true
		end
		return GrabState.CanPerformCarriedInteraction(state, interactionName)
	end,
}

debugLog("GrabService initialized")
