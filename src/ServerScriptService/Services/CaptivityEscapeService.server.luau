--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RunService: any = nil
do
	local ok, service = pcall(function()
		return game:GetService("RunService")
	end)
	if ok then
		RunService = service
	end
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local CaptivityDurationState = require(GiantRealm:WaitForChild("CaptivityDurationState"))
local CapturePersistenceRules = require(GiantRealm:WaitForChild("CapturePersistenceRules"))
local CaptivityEscapeProgressState = require(GiantRealm:WaitForChild("CaptivityEscapeProgressState"))

local REMOTES_FOLDER_NAME = "Remotes"
local STRUGGLE_REMOTE_NAME = "CaptivityStruggleRequest"
local ALLY_ASSIST_REMOTE_NAME = "CaptivityAllyAssistRequest"

local ROLE_ATTRIBUTE = "Role"
local globalEnv: any = getfenv()

local progressByTargetUserId: { [number]: any? } = {}
local lastStruggleRequestAtByUserId: { [number]: number? } = {}
local lastAssistRequestAtByUserId: { [number]: number? } = {}
local lastContainmentScanAt = 0
local CONTAINMENT_SCAN_INTERVAL_SECONDS = 0.5

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

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return false
	end
	return humanoid.Health > 0
end

local function getCaptureServiceQueryApi(): any?
	local queryApi = globalEnv._CaptureService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._CaptureService_QueryAPI) == "table" then
		return (_G :: any)._CaptureService_QueryAPI
	end
	return nil
end

local function getRoleServiceQueryApi(): any?
	local queryApi = globalEnv._RoleService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	return nil
end

local function getDownedState(target: Player): boolean
	local roleQueryApi = getRoleServiceQueryApi()
	if roleQueryApi ~= nil and type(roleQueryApi.IsPlayerDowned) == "function" then
		return roleQueryApi.IsPlayerDowned(target.UserId) == true
	end
	return target:GetAttribute("DownedIsDowned") == true
end

local function resolveDistance(a: any, b: any): number?
	if a == nil or b == nil then
		return nil
	end
	if
		type(a) == "table"
		and type(b) == "table"
		and type(a.x) == "number"
		and type(a.y) == "number"
		and type(a.z) == "number"
		and type(b.x) == "number"
		and type(b.y) == "number"
		and type(b.z) == "number"
	then
		local dx = a.x - b.x
		local dy = a.y - b.y
		local dz = a.z - b.z
		return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
	end
	local ok, delta = pcall(function()
		return a - b
	end)
	if not ok then
		return nil
	end
	if type(delta) == "table" and type((delta :: any).Magnitude) == "number" then
		return (delta :: any).Magnitude
	end
	if type(delta) == "table" and type((delta :: any).Magnitude) == "function" then
		return (delta :: any):Magnitude()
	end
	return nil
end

local function isPositionInsidePart(position: any, part: any): boolean
	if position == nil or part == nil then
		return false
	end
	if
		type(part.CFrame) == "userdata"
		or (type(part.CFrame) == "table" and type(part.CFrame.PointToObjectSpace) == "function")
	then
		local localPos = part.CFrame:PointToObjectSpace(position)
		local halfSize = part.Size / 2
		return math.abs(localPos.X) <= halfSize.X
			and math.abs(localPos.Y) <= halfSize.Y
			and math.abs(localPos.Z) <= halfSize.Z
	end
	if type(part.Position) == "table" and type(part.Size) == "table" then
		local pos = part.Position
		local size = part.Size
		return math.abs(position.x - pos.x) <= size.x / 2
			and math.abs(position.y - pos.y) <= size.y / 2
			and math.abs(position.z - pos.z) <= size.z / 2
	end
	return false
end

local function findContainmentZonesRoot(): Instance?
	local current: any = Workspace
	for _, childName in CaptureConfig.ContainmentZoneFolderPath do
		if type(current.FindFirstChild) ~= "function" then
			return nil
		end
		current = current:FindFirstChild(childName)
		if current == nil then
			return nil
		end
	end
	return current
end

local function isContainmentZonePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. CaptureConfig.ContainmentZoneNamePrefix) ~= nil
end

local function isPositionInContainmentZone(position: any): boolean
	local zonesRoot = findContainmentZonesRoot()
	if zonesRoot == nil or type(zonesRoot.GetDescendants) ~= "function" then
		return false
	end
	for _, descendant in zonesRoot:GetDescendants() do
		if descendant:IsA("BasePart") and isContainmentZonePart(descendant) then
			if isPositionInsidePart(position, descendant) then
				return true
			end
		end
	end
	return false
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

local function getTargetCaptureRecord(targetUserId: number, at: number): any?
	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.GetTargetCapture) ~= "function" then
		return nil
	end
	local ok, record = pcall(captureApi.GetTargetCapture, targetUserId, at)
	if ok then
		return record
	end
	return nil
end

local function clearProgressForTarget(targetUserId: number)
	progressByTargetUserId[targetUserId] = nil
	local target = getPlayerByUserId(targetUserId)
	if target ~= nil then
		local attrs = CaptureConfig.StateAttributes
		target:SetAttribute(attrs.CaptivityEscapeProgress, nil)
		target:SetAttribute(attrs.CaptivityEscapeProgressRequired, nil)
		target:SetAttribute(attrs.CaptivityEscapeSuppressed, false)
		target:SetAttribute(attrs.CaptivityEscapeLastReason, nil)
	end
end

local function applyProgressAttributes(target: Player, snapshot: any)
	local attrs = CaptureConfig.StateAttributes
	target:SetAttribute(attrs.CaptivityEscapeProgress, snapshot.progress)
	target:SetAttribute(attrs.CaptivityEscapeProgressRequired, snapshot.required)
	target:SetAttribute(attrs.CaptivityEscapeSuppressed, snapshot.suppressed == true)
	target:SetAttribute(attrs.CaptivityEscapeLastReason, snapshot.lastReason)
end

local function ensureProgressState(targetUserId: number, at: number): any?
	local existing = progressByTargetUserId[targetUserId]
	if existing ~= nil then
		return existing
	end
	local record = getTargetCaptureRecord(targetUserId, at)
	if record == nil then
		return nil
	end
	local created = CaptivityEscapeProgressState.NewState(CaptureConfig, at)
	progressByTargetUserId[targetUserId] = created
	return created
end

local function refreshDecayForTarget(targetUserId: number, at: number): any?
	local state = progressByTargetUserId[targetUserId]
	if state == nil then
		return nil
	end
	local decayed = CaptivityEscapeProgressState.ResolveDecay(state, at, CaptureConfig)
	progressByTargetUserId[targetUserId] = decayed.state
	local target = getPlayerByUserId(targetUserId)
	if target ~= nil then
		applyProgressAttributes(target, decayed.snapshot)
	end
	return decayed
end

local function countNearbyRescueAllies(target: Player, custodianUserId: number, _at: number): number
	local targetRoot = getHumanoidRootPart(target)
	if targetRoot == nil then
		return 0
	end
	local count = 0
	for _, candidate in Players:GetPlayers() do
		if
			candidate.UserId ~= target.UserId
			and candidate.UserId ~= custodianUserId
			and candidate:GetAttribute(ROLE_ATTRIBUTE) == RoleConfig.Roles.Tinyfolk
			and isPlayerAlive(candidate)
			and getDownedState(candidate) ~= true
		then
			local candidateRoot = getHumanoidRootPart(candidate)
			if candidateRoot ~= nil then
				local distance = resolveDistance((targetRoot :: any).Position, (candidateRoot :: any).Position)
				if type(distance) == "number" and distance <= CaptureConfig.StruggleAllyRadiusStuds then
					count += 1
				end
			end
		end
	end
	return count
end

local function resolveStruggleRelease(targetUserId: number, at: number): any?
	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.ResolveCustodyEnd) ~= "function" then
		return { accepted = false, reason = "capture_query_unavailable" }
	end
	local ok, result = pcall(captureApi.ResolveCustodyEnd, targetUserId, "released", at, nil)
	if not ok then
		return { accepted = false, reason = "capture_custody_end_fault" }
	end
	clearProgressForTarget(targetUserId)
	return result
end

local function requestStruggle(target: Player, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	refreshDecayForTarget(target.UserId, resolvedNow)

	local record = getTargetCaptureRecord(target.UserId, resolvedNow)
	if record == nil then
		clearProgressForTarget(target.UserId)
		return { accepted = false, reason = "capture_missing" }
	end

	if record.containmentPhase == CaptivityDurationState.Phases.contained then
		local state = ensureProgressState(target.UserId, resolvedNow)
		if state ~= nil then
			local suppressed = CaptivityEscapeProgressState.ResolveSuppression(state, resolvedNow)
			progressByTargetUserId[target.UserId] = suppressed.state
			applyProgressAttributes(target, suppressed.snapshot)
		end
		return { accepted = false, reason = "escape_suppressed_contained" }
	end

	if target:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Tinyfolk then
		return { accepted = false, reason = "actor_not_tinyfolk" }
	end
	if not isPlayerAlive(target) then
		return { accepted = false, reason = "actor_not_alive" }
	end

	local struggleAllowed, struggleReason = canPerformEscapeAction(CapturePersistenceRules.EscapeActions.struggle)
	if struggleAllowed ~= true then
		return { accepted = false, reason = struggleReason or "escape_action_blocked" }
	end

	local lastRequest = lastStruggleRequestAtByUserId[target.UserId]
	if type(lastRequest) == "number" and (resolvedNow - lastRequest) < CaptureConfig.StruggleActionCooldownSeconds then
		return { accepted = false, reason = "request_cooldown" }
	end

	local state = ensureProgressState(target.UserId, resolvedNow)
	if state == nil then
		return { accepted = false, reason = "progress_state_missing" }
	end

	local nearbyAllies = countNearbyRescueAllies(target, record.custodianUserId, resolvedNow)
	local transition = CaptivityEscapeProgressState.ResolveStruggle(state, {
		now = resolvedNow,
		nearbyAllyCount = nearbyAllies,
	}, CaptureConfig)
	progressByTargetUserId[target.UserId] = transition.state
	applyProgressAttributes(target, transition.snapshot)
	lastStruggleRequestAtByUserId[target.UserId] = resolvedNow

	if transition.completed == true then
		local release = resolveStruggleRelease(target.UserId, resolvedNow)
		return {
			accepted = true,
			reason = "struggle_escape_completed",
			snapshot = transition.snapshot,
			release = release,
		}
	end

	return {
		accepted = transition.accepted,
		reason = transition.reason,
		snapshot = transition.snapshot,
		nearbyAllyCount = nearbyAllies,
	}
end

local function requestAllyAssist(ally: Player, targetUserId: any, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	if type(targetUserId) ~= "number" then
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	refreshDecayForTarget(targetUserId, resolvedNow)

	local target = getPlayerByUserId(targetUserId)
	if target == nil then
		return { accepted = false, reason = "target_not_found" }
	end

	local record = getTargetCaptureRecord(targetUserId, resolvedNow)
	if record == nil then
		clearProgressForTarget(targetUserId)
		return { accepted = false, reason = "capture_missing" }
	end

	if record.containmentPhase == CaptivityDurationState.Phases.contained then
		return { accepted = false, reason = "escape_suppressed_contained" }
	end

	if ally:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Tinyfolk then
		return { accepted = false, reason = "ally_not_tinyfolk" }
	end
	if ally.UserId == targetUserId or ally.UserId == record.custodianUserId then
		return { accepted = false, reason = "ally_not_eligible" }
	end
	if not isPlayerAlive(ally) or getDownedState(ally) == true then
		return { accepted = false, reason = "ally_not_available" }
	end

	local allyRoot = getHumanoidRootPart(ally)
	local targetRoot = getHumanoidRootPart(target)
	if allyRoot == nil or targetRoot == nil then
		return { accepted = false, reason = "missing_character_root" }
	end
	local distance = resolveDistance((allyRoot :: any).Position, (targetRoot :: any).Position)
	if distance == nil or distance > CaptureConfig.StruggleAllyRadiusStuds then
		return { accepted = false, reason = "ally_out_of_range" }
	end

	local assistAllowed, assistReason = canPerformEscapeAction(CapturePersistenceRules.EscapeActions.ally_rescue_assist)
	if assistAllowed ~= true then
		return { accepted = false, reason = assistReason or "escape_action_blocked" }
	end

	local lastRequest = lastAssistRequestAtByUserId[ally.UserId]
	if type(lastRequest) == "number" and (resolvedNow - lastRequest) < CaptureConfig.AllyAssistCooldownSeconds then
		return { accepted = false, reason = "request_cooldown" }
	end

	local state = ensureProgressState(targetUserId, resolvedNow)
	if state == nil then
		return { accepted = false, reason = "progress_state_missing" }
	end

	local transition = CaptivityEscapeProgressState.ResolveAllyAssist(state, { now = resolvedNow }, CaptureConfig)
	progressByTargetUserId[targetUserId] = transition.state
	applyProgressAttributes(target, transition.snapshot)
	lastAssistRequestAtByUserId[ally.UserId] = resolvedNow

	if transition.completed == true then
		local release = resolveStruggleRelease(targetUserId, resolvedNow)
		return {
			accepted = true,
			reason = "ally_assist_escape_completed",
			snapshot = transition.snapshot,
			release = release,
		}
	end

	return {
		accepted = transition.accepted,
		reason = transition.reason,
		snapshot = transition.snapshot,
	}
end

local function tryApplyContainmentSuppression(targetUserId: number, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	local record = getTargetCaptureRecord(targetUserId, resolvedNow)
	if record == nil then
		clearProgressForTarget(targetUserId)
		return { accepted = false, reason = "capture_missing" }
	end
	if record.containmentPhase == CaptivityDurationState.Phases.contained then
		local state = ensureProgressState(targetUserId, resolvedNow)
		if state ~= nil and state.suppressed ~= true then
			local suppressed = CaptivityEscapeProgressState.ResolveSuppression(state, resolvedNow)
			progressByTargetUserId[targetUserId] = suppressed.state
			local target = getPlayerByUserId(targetUserId)
			if target ~= nil then
				applyProgressAttributes(target, suppressed.snapshot)
			end
		end
		return { accepted = false, reason = "already_contained" }
	end

	local custodian = getPlayerByUserId(record.custodianUserId)
	if custodian == nil then
		return { accepted = false, reason = "custodian_not_found" }
	end
	local custodianRoot = getHumanoidRootPart(custodian)
	if custodianRoot == nil then
		return { accepted = false, reason = "custodian_root_missing" }
	end
	if not isPositionInContainmentZone((custodianRoot :: any).Position) then
		return { accepted = false, reason = "containment_zone_not_reached" }
	end

	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.PromoteTargetToContained) ~= "function" then
		return { accepted = false, reason = "capture_query_unavailable" }
	end
	local promoteOk, promoteResult = pcall(captureApi.PromoteTargetToContained, targetUserId, resolvedNow)
	if not promoteOk or type(promoteResult) ~= "table" or promoteResult.accepted ~= true then
		local reason = if type(promoteResult) == "table" then promoteResult.reason else "containment_promote_failed"
		return { accepted = false, reason = reason }
	end

	local state = ensureProgressState(targetUserId, resolvedNow)
	if state == nil then
		state = CaptivityEscapeProgressState.NewState(CaptureConfig, resolvedNow)
	end
	local suppressed = CaptivityEscapeProgressState.ResolveSuppression(state, resolvedNow)
	progressByTargetUserId[targetUserId] = suppressed.state
	local target = getPlayerByUserId(targetUserId)
	if target ~= nil then
		applyProgressAttributes(target, suppressed.snapshot)
	end

	return {
		accepted = true,
		reason = "containment_suppressed",
		snapshot = suppressed.snapshot,
		record = promoteResult.record,
	}
end

local function getProgressSnapshot(targetUserId: number, at: number?): any?
	local resolvedNow = if type(at) == "number" then at else now()
	local record = getTargetCaptureRecord(targetUserId, resolvedNow)
	if record == nil then
		clearProgressForTarget(targetUserId)
		return nil
	end
	refreshDecayForTarget(targetUserId, resolvedNow)
	local state = ensureProgressState(targetUserId, resolvedNow)
	if state == nil then
		return nil
	end
	return CaptivityEscapeProgressState.Snapshot(state)
end

local function refreshContainmentSuppressionForActiveCaptures(at: number)
	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.GetAllCaptures) ~= "function" then
		return
	end

	local ok, captures = pcall(captureApi.GetAllCaptures, at)
	if not ok or type(captures) ~= "table" then
		return
	end

	for _, record in ipairs(captures) do
		if type(record) == "table" and type(record.targetUserId) == "number" then
			if record.containmentPhase ~= CaptivityDurationState.Phases.contained then
				tryApplyContainmentSuppression(record.targetUserId, at)
			end
		end
	end
end

local remotesFolder = ensureRemotesFolder()
local struggleRemote = ensureRemoteEvent(remotesFolder, STRUGGLE_REMOTE_NAME)
local allyAssistRemote = ensureRemoteEvent(remotesFolder, ALLY_ASSIST_REMOTE_NAME)

struggleRemote.OnServerEvent:Connect(function(player: Player, _payload: unknown)
	requestStruggle(player, nil)
end)

allyAssistRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local targetUserId = nil
	if type(payload) == "number" then
		targetUserId = payload
	elseif type(payload) == "table" then
		targetUserId = (payload :: any).targetUserId
	end
	requestAllyAssist(player, targetUserId, nil)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastStruggleRequestAtByUserId[player.UserId] = nil
	lastAssistRequestAtByUserId[player.UserId] = nil
end)

if
	type(RunService) == "table"
	and type(RunService.Heartbeat) == "table"
	and type(RunService.Heartbeat.Connect) == "function"
then
	RunService.Heartbeat:Connect(function()
		local at = now()
		if at - lastContainmentScanAt < CONTAINMENT_SCAN_INTERVAL_SECONDS then
			return
		end
		lastContainmentScanAt = at
		refreshContainmentSuppressionForActiveCaptures(at)
	end)
end

_G._CaptivityEscapeService_QueryAPI = {
	RequestStruggle = function(targetUserId: number, at: number?): any
		local target = getPlayerByUserId(targetUserId)
		if target == nil then
			return { accepted = false, reason = "target_not_found" }
		end
		return requestStruggle(target, at)
	end,
	RequestAllyAssist = function(allyUserId: number, targetUserId: number, at: number?): any
		local ally = getPlayerByUserId(allyUserId)
		if ally == nil then
			return { accepted = false, reason = "ally_not_found" }
		end
		return requestAllyAssist(ally, targetUserId, at)
	end,
	TryApplyContainmentSuppression = function(targetUserId: number, at: number?): any
		return tryApplyContainmentSuppression(targetUserId, at)
	end,
	GetProgressSnapshot = function(targetUserId: number, at: number?): any?
		return getProgressSnapshot(targetUserId, at)
	end,
	CountNearbyRescueAllies = function(targetUserId: number, at: number?): number
		local target = getPlayerByUserId(targetUserId)
		if target == nil then
			return 0
		end
		local record = getTargetCaptureRecord(targetUserId, if type(at) == "number" then at else now())
		if record == nil then
			return 0
		end
		return countNearbyRescueAllies(target, record.custodianUserId, if type(at) == "number" then at else now())
	end,
	ResetForTests = function()
		progressByTargetUserId = {}
		lastStruggleRequestAtByUserId = {}
		lastAssistRequestAtByUserId = {}
		for _, player in Players:GetPlayers() do
			clearProgressForTarget(player.UserId)
		end
	end,
}
