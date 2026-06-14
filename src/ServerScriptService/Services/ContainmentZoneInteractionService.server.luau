--!nocheck
-- ContainmentZoneInteractionService: contained escape, structure rescue, and grab-place delivery for TIN-87.

local function resolveDependency(parent: any, childName: string, fallbackRequirePath: string): any
	if parent ~= nil and type(parent.WaitForChild) == "function" then
		local child = parent:WaitForChild(childName)
		if child ~= nil then
			local childAny = child :: any
			if type(childAny) == "table" then
				return childAny
			end
			local ok, requiredOrError = pcall(function()
				return require(childAny)
			end)
			if ok then
				return requiredOrError
			end
		end
	end
	return require(fallbackRequirePath)
end

local function getService(gameRef: any, serviceName: string): any
	local colonOk, colonValue = pcall(function()
		return gameRef:GetService(serviceName)
	end)
	if colonOk and colonValue ~= nil then
		return colonValue
	end
	local dotOk, dotValue = pcall(function()
		return gameRef.GetService(serviceName)
	end)
	if dotOk and dotValue ~= nil then
		return dotValue
	end
	return nil
end

local function createContainmentZoneInteractionService(runtimeGame: any?, options: any?)
	local globalEnv: any = getfenv()
	local gameRef = runtimeGame or game
	local Players = getService(gameRef, "Players")
	local ReplicatedStorage = getService(gameRef, "ReplicatedStorage")

	local Shared = if ReplicatedStorage ~= nil and type(ReplicatedStorage.WaitForChild) == "function"
		then ReplicatedStorage:WaitForChild("Shared")
		else nil
	local Config = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("Config")
		else nil
	local GiantRealm = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("GiantRealm")
		else nil

	local CaptureConfig =
		resolveDependency(Config, "CaptureConfig", "../../ReplicatedStorage/Shared/Config/CaptureConfig")
	local RoleConfig = resolveDependency(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	local ContainmentStructureConfig = resolveDependency(
		Config,
		"ContainmentStructureConfig",
		"../../ReplicatedStorage/Shared/Config/ContainmentStructureConfig"
	)
	local CaptivityDurationState = resolveDependency(
		GiantRealm,
		"CaptivityDurationState",
		"../../ReplicatedStorage/Shared/GiantRealm/CaptivityDurationState"
	)
	local CapturePersistenceRules = resolveDependency(
		GiantRealm,
		"CapturePersistenceRules",
		"../../ReplicatedStorage/Shared/GiantRealm/CapturePersistenceRules"
	)
	local ContainmentZoneEscapeState = resolveDependency(
		GiantRealm,
		"ContainmentZoneEscapeState",
		"../../ReplicatedStorage/Shared/GiantRealm/ContainmentZoneEscapeState"
	)

	local REMOTES_FOLDER_NAME = "Remotes"
	local ESCAPE_REMOTE_NAME = "ContainmentEscapeRequest"
	local RESCUE_REMOTE_NAME = "ContainmentRescueRequest"

	local escapeProgressByTargetUserId: { [number]: any? } = {}
	local lastEscapeRequestAtByUserId: { [number]: number? } = {}
	local lastRescueRequestAtByUserId: { [number]: number? } = {}

	local function now(): number
		if options ~= nil and type(options.now) == "function" then
			return options.now()
		end
		return os.clock()
	end

	local function getPlayerByUserId(userId: number): any?
		if Players == nil or type(Players.GetPlayers) ~= "function" then
			return nil
		end
		for _, player in Players:GetPlayers() do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end

	local function getHumanoidRootPart(player: any): any?
		local character = player.Character
		if character == nil then
			return nil
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root ~= nil then
			return root
		end
		return nil
	end

	local function isPlayerAlive(player: any): boolean
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

	local function getQueryApi(globalKey: string): any?
		local queryApi = globalEnv[globalKey]
		if type(queryApi) == "table" then
			return queryApi
		end
		if type(_G) == "table" and type((_G :: any)[globalKey]) == "table" then
			return (_G :: any)[globalKey]
		end
		return nil
	end

	local function getCaptureServiceQueryApi(): any?
		return getQueryApi("_CaptureService_QueryAPI")
	end

	local function getContainmentStructureQueryApi(): any?
		return getQueryApi("_ContainmentStructureService_QueryAPI")
	end

	local function getCaptivityEscapeServiceQueryApi(): any?
		return getQueryApi("_CaptivityEscapeService_QueryAPI")
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

	local function clearEscapeProgressForTarget(targetUserId: number)
		escapeProgressByTargetUserId[targetUserId] = nil
		lastEscapeRequestAtByUserId[targetUserId] = nil
		local target = getPlayerByUserId(targetUserId)
		if target ~= nil and type(target.SetAttribute) == "function" then
			local attrs = ContainmentStructureConfig.PlayerAttributes
			target:SetAttribute(attrs.EscapeProgress, nil)
			target:SetAttribute(attrs.EscapeProgressRequired, nil)
			target:SetAttribute(attrs.EscapeLastReason, nil)
			target:SetAttribute(attrs.StructureId, nil)
		end
	end

	local function applyEscapeProgressAttributes(target: any, snapshot: any?, structureId: string?)
		if target == nil or type(target.SetAttribute) ~= "function" then
			return
		end
		local attrs = ContainmentStructureConfig.PlayerAttributes
		if snapshot == nil then
			target:SetAttribute(attrs.EscapeProgress, nil)
			target:SetAttribute(attrs.EscapeProgressRequired, nil)
			target:SetAttribute(attrs.EscapeLastReason, nil)
			target:SetAttribute(attrs.StructureId, structureId)
			return
		end
		target:SetAttribute(attrs.EscapeProgress, snapshot.progress)
		target:SetAttribute(attrs.EscapeProgressRequired, snapshot.required)
		target:SetAttribute(attrs.EscapeLastReason, snapshot.lastReason)
		target:SetAttribute(attrs.StructureId, structureId)
	end

	local function ensureEscapeProgressState(targetUserId: number, at: number): any?
		local state = escapeProgressByTargetUserId[targetUserId]
		if state == nil then
			state = ContainmentZoneEscapeState.NewState(ContainmentStructureConfig, at)
			escapeProgressByTargetUserId[targetUserId] = state
		end
		return state
	end

	local function resolveContainedRelease(targetUserId: number, at: number, endReason: string): any
		local captureApi = getCaptureServiceQueryApi()
		if captureApi == nil or type(captureApi.ResolveCustodyEnd) ~= "function" then
			return { accepted = false, reason = "capture_query_unavailable" }
		end
		local ok, result = pcall(captureApi.ResolveCustodyEnd, targetUserId, endReason, at, nil)
		if not ok then
			return { accepted = false, reason = "capture_custody_end_fault" }
		end
		clearEscapeProgressForTarget(targetUserId)
		return result
	end

	local service: any = {}

	function service.requestContainedEscape(targetUserId: number, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		local target = getPlayerByUserId(targetUserId)
		if target == nil then
			return { accepted = false, reason = "target_not_found" }
		end
		if target:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
			return { accepted = false, reason = "actor_not_tinyfolk" }
		end
		if not isPlayerAlive(target) then
			return { accepted = false, reason = "actor_not_alive" }
		end

		local record = getTargetCaptureRecord(targetUserId, resolvedNow)
		if record == nil then
			clearEscapeProgressForTarget(targetUserId)
			return { accepted = false, reason = "capture_missing" }
		end
		if record.containmentPhase ~= CaptivityDurationState.Phases.contained then
			return { accepted = false, reason = "not_contained" }
		end

		local structureApi = getContainmentStructureQueryApi()
		if structureApi == nil or type(structureApi.HasEscapeInteractionForTarget) ~= "function" then
			return { accepted = false, reason = "containment_structure_query_unavailable" }
		end
		if structureApi.HasEscapeInteractionForTarget(targetUserId) ~= true then
			return { accepted = false, reason = "contained_escape_unavailable" }
		end

		local escapeAllowed, escapeReason =
			canPerformEscapeAction(CapturePersistenceRules.EscapeActions.contained_escape)
		if escapeAllowed ~= true then
			return { accepted = false, reason = escapeReason or "escape_action_blocked" }
		end

		local structureId = nil
		if type(structureApi.GetStructureIdForTargetUserId) == "function" then
			structureId = structureApi.GetStructureIdForTargetUserId(targetUserId)
		end

		local state = ensureEscapeProgressState(targetUserId, resolvedNow)
		local transition =
			ContainmentZoneEscapeState.ResolveEscapeAction(state, resolvedNow, ContainmentStructureConfig)
		escapeProgressByTargetUserId[targetUserId] = transition.state
		applyEscapeProgressAttributes(target, transition.snapshot, structureId)

		if transition.completed == true then
			local release =
				resolveContainedRelease(targetUserId, resolvedNow, CapturePersistenceRules.CustodyEndReasons.released)
			return {
				accepted = release ~= nil and release.accepted == true,
				reason = if transition.completed then "contained_escape_completed" else transition.reason,
				snapshot = transition.snapshot,
				release = release,
				structureId = structureId,
			}
		end

		return {
			accepted = transition.accepted,
			reason = transition.reason,
			snapshot = transition.snapshot,
			structureId = structureId,
		}
	end

	function service.requestStructureRescue(rescuerUserId: number, targetUserId: number, at: number?): any
		local resolvedNow = if type(at) == "number" then at else now()
		local rescuer = getPlayerByUserId(rescuerUserId)
		if rescuer == nil then
			return { accepted = false, reason = "rescuer_not_found" }
		end
		if rescuer:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
			return { accepted = false, reason = "rescuer_not_tinyfolk" }
		end
		if not isPlayerAlive(rescuer) then
			return { accepted = false, reason = "rescuer_not_alive" }
		end
		if rescuerUserId == targetUserId then
			return { accepted = false, reason = "self_rescue_not_allowed" }
		end

		local record = getTargetCaptureRecord(targetUserId, resolvedNow)
		if record == nil then
			return { accepted = false, reason = "capture_missing" }
		end
		if record.containmentPhase ~= CaptivityDurationState.Phases.contained then
			return { accepted = false, reason = "target_not_contained" }
		end

		local rescueAllowed, rescueReason =
			canPerformEscapeAction(CapturePersistenceRules.EscapeActions.structure_rescue)
		if rescueAllowed ~= true then
			return { accepted = false, reason = rescueReason or "escape_action_blocked" }
		end

		local lastRequest = lastRescueRequestAtByUserId[rescuerUserId]
		if
			type(lastRequest) == "number"
			and (resolvedNow - lastRequest) < ContainmentStructureConfig.ContainmentRescueCooldownSeconds
		then
			return { accepted = false, reason = "request_cooldown" }
		end

		local structureApi = getContainmentStructureQueryApi()
		if structureApi == nil or type(structureApi.CanRescueOccupant) ~= "function" then
			return { accepted = false, reason = "containment_structure_query_unavailable" }
		end

		local rescuerRoot = getHumanoidRootPart(rescuer)
		local rescuerPosition = if rescuerRoot ~= nil then rescuerRoot.Position else nil
		local rescueDecision = structureApi.CanRescueOccupant(rescuerUserId, targetUserId, rescuerPosition)
		if type(rescueDecision) ~= "table" or rescueDecision.accepted ~= true then
			return {
				accepted = false,
				reason = if type(rescueDecision) == "table" then rescueDecision.reason else "structure_rescue_rejected",
			}
		end

		lastRescueRequestAtByUserId[rescuerUserId] = resolvedNow
		local release =
			resolveContainedRelease(targetUserId, resolvedNow, CapturePersistenceRules.CustodyEndReasons.rescued)
		return {
			accepted = release ~= nil and release.accepted == true,
			reason = if release ~= nil and release.accepted == true
				then "structure_rescue_completed"
				else "structure_rescue_failed",
			structureId = rescueDecision.structureId,
			release = release,
		}
	end

	function service.tryDeliverGrabPlacement(input: any): any
		if type(input) ~= "table" then
			return { accepted = false, reason = "delivery_input_invalid" }
		end
		local giantUserId = input.giantUserId
		local targetUserId = input.targetUserId
		if type(giantUserId) ~= "number" or type(targetUserId) ~= "number" then
			return { accepted = false, reason = "delivery_user_id_invalid" }
		end
		local resolvedNow = if type(input.at) == "number" then input.at else now()

		local record = getTargetCaptureRecord(targetUserId, resolvedNow)
		if record == nil then
			return { accepted = false, reason = "capture_missing", skipped = true }
		end
		if record.containmentPhase == CaptivityDurationState.Phases.contained then
			return { accepted = false, reason = "already_contained", skipped = true }
		end
		if record.custodianUserId ~= giantUserId then
			return { accepted = false, reason = "custodian_mismatch", skipped = true }
		end

		local structureApi = getContainmentStructureQueryApi()
		if structureApi == nil then
			return { accepted = false, reason = "containment_structure_query_unavailable" }
		end

		if type(structureApi.EvaluateCaptureDeliveryEligibility) == "function" then
			local eligibility = structureApi.EvaluateCaptureDeliveryEligibility({
				targetUserId = targetUserId,
				custodianUserId = giantUserId,
				custodianPosition = input.giantPosition,
				targetPosition = input.targetPosition,
			})
			if type(eligibility) ~= "table" or eligibility.eligible ~= true then
				return {
					accepted = false,
					reason = if type(eligibility) == "table"
						then eligibility.reason
						else "containment_structure_not_in_range",
					skipped = type(eligibility) == "table" and eligibility.skipped == true,
				}
			end
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

		local captivityEscapeApi = getCaptivityEscapeServiceQueryApi()
		if captivityEscapeApi ~= nil and type(captivityEscapeApi.TryApplyContainmentSuppression) == "function" then
			pcall(captivityEscapeApi.TryApplyContainmentSuppression, targetUserId, resolvedNow)
		end

		return {
			accepted = true,
			reason = "grab_place_containment_delivered",
			structureId = promoteResult.structureId,
			record = promoteResult.record,
		}
	end

	function service.ResetForTests()
		escapeProgressByTargetUserId = {}
		lastEscapeRequestAtByUserId = {}
		lastRescueRequestAtByUserId = {}
	end

	local function ensureRemotesFolder(): any
		if ReplicatedStorage == nil or type(ReplicatedStorage.FindFirstChild) ~= "function" then
			return nil
		end
		local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
		if existing ~= nil then
			return existing
		end
		if type(Instance) ~= "table" or type(Instance.new) ~= "function" then
			return nil
		end
		local folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end

	local function ensureRemoteEvent(parentFolder: any, remoteName: string): any?
		if parentFolder == nil or type(parentFolder.FindFirstChild) ~= "function" then
			return nil
		end
		local existing = parentFolder:FindFirstChild(remoteName)
		if existing ~= nil then
			return existing
		end
		if type(Instance) ~= "table" or type(Instance.new) ~= "function" then
			return nil
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = parentFolder
		return remote
	end

	if options == nil or options.disableRemotes ~= true then
		local remotesFolder = ensureRemotesFolder()
		local escapeRemote = ensureRemoteEvent(remotesFolder, ESCAPE_REMOTE_NAME)
		local rescueRemote = ensureRemoteEvent(remotesFolder, RESCUE_REMOTE_NAME)

		if escapeRemote ~= nil and type(escapeRemote.OnServerEvent) == "table" then
			escapeRemote.OnServerEvent:Connect(function(player: any, _payload: unknown)
				service.requestContainedEscape(player.UserId, nil)
			end)
		end

		if rescueRemote ~= nil and type(rescueRemote.OnServerEvent) == "table" then
			rescueRemote.OnServerEvent:Connect(function(player: any, payload: unknown)
				local targetUserId = nil
				if type(payload) == "number" then
					targetUserId = payload
				elseif type(payload) == "table" then
					targetUserId = (payload :: any).targetUserId
				end
				if type(targetUserId) == "number" then
					service.requestStructureRescue(player.UserId, targetUserId, nil)
				end
			end)
		end

		if
			Players ~= nil
			and type(Players.PlayerRemoving) == "table"
			and type(Players.PlayerRemoving.Connect) == "function"
		then
			Players.PlayerRemoving:Connect(function(player: any)
				clearEscapeProgressForTarget(player.UserId)
				lastRescueRequestAtByUserId[player.UserId] = nil
			end)
		end
	end

	globalEnv._ContainmentZoneInteractionService_QueryAPI = {
		RequestContainedEscape = function(targetUserId: number, at: number?): any
			return service.requestContainedEscape(targetUserId, at)
		end,
		RequestStructureRescue = function(rescuerUserId: number, targetUserId: number, at: number?): any
			return service.requestStructureRescue(rescuerUserId, targetUserId, at)
		end,
		TryDeliverGrabPlacement = function(input: any): any
			return service.tryDeliverGrabPlacement(input)
		end,
		ResetForTests = function()
			service.ResetForTests()
		end,
	}

	if type(_G) == "table" then
		rawset(_G, "_ContainmentZoneInteractionService_QueryAPI", globalEnv._ContainmentZoneInteractionService_QueryAPI)
	end

	return service
end

return createContainmentZoneInteractionService
