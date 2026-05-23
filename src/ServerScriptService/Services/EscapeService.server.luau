--!nocheck
-- EscapeService: Orchestrates escape, block, and through-gap validation for TIN-76
-- Enforces all safe zone and no-capture rules (routes with InSafeZone=true are rejected for escape/block)
-- All logic is attribute-driven and server-authoritative; integrates with EscapeConfig and validator modules

local REMOTES_FOLDER_NAME = "Remotes"
local ESCAPE_ATTEMPT_REMOTE_NAME = "EscapeAttemptRequest"
local ESCAPE_DEBUG_REQUEST_REMOTE_NAME = "EscapeDebugStateRequest"
local ESCAPE_DEBUG_RESPONSE_REMOTE_NAME = "EscapeDebugStateResponse"
local TRAVERSAL_GAP_BLOCK_REQUEST_REMOTE_NAME = "TraversalGapBlockRequest"

local ESCAPE_ROUTES_FOLDER_PATH = { "Map", "EscapeRoutes" }

local ESCAPED_ATTRIBUTE = "Escaped"
local ROUTE_ENABLED_ATTRIBUTE = "RouteEnabled"
local ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE = "SuccessfulEscapes"

local function debugLog(message: string)
	print(string.format("[EscapeService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[EscapeService] %s", message))
end

local function resolveDependency(parent: any, childName: string, fallbackRequirePath: string): any
	if parent ~= nil and type(parent.WaitForChild) == "function" then
		local child = parent:WaitForChild(childName)
		if child ~= nil then
			local childAny = child :: any
			if type(childAny) == "table" then
				if
					rawget(childAny, "ValidateReachAttempt") ~= nil
					or rawget(childAny, "CreateBlock") ~= nil
					or rawget(childAny, "Roles") ~= nil
					or rawget(childAny, "RequestCooldownSeconds") ~= nil
				then
					return childAny
				end
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

local function createEscapeService(runtimeGame: any?, options: any?)
	local globalEnv: any = getfenv()
	local gameRef = runtimeGame or game
	local Players = getService(gameRef, "Players")
	local ReplicatedStorage = getService(gameRef, "ReplicatedStorage")
	local Workspace = getService(gameRef, "Workspace")

	local Shared = if ReplicatedStorage ~= nil and type(ReplicatedStorage.WaitForChild) == "function"
		then ReplicatedStorage:WaitForChild("Shared")
		else nil
	local Config = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("Config")
		else nil
	local GiantRealm = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("GiantRealm")
		else nil

	local EscapeConfig = resolveDependency(Config, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
	local RescueContractConfig =
		resolveDependency(Config, "RescueContractConfig", "../../ReplicatedStorage/Shared/Config/RescueContractConfig")
	local RoleConfig = resolveDependency(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	local ThroughGapValidation = resolveDependency(
		GiantRealm,
		"ThroughGapValidation",
		"../../ReplicatedStorage/Shared/GiantRealm/ThroughGapValidation"
	)
	local SafeZonePolicy =
		resolveDependency(GiantRealm, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
	local TraversalGapBlockState = resolveDependency(
		GiantRealm,
		"TraversalGapBlockState",
		"../../ReplicatedStorage/Shared/GiantRealm/TraversalGapBlockState"
	)
	local FinalExitState =
		resolveDependency(GiantRealm, "FinalExitState", "../../ReplicatedStorage/Shared/GiantRealm/FinalExitState")
	local FallbackEscapeState = resolveDependency(
		GiantRealm,
		"FallbackEscapeState",
		"../../ReplicatedStorage/Shared/GiantRealm/FallbackEscapeState"
	)

	local TinyfolkMovementTraitService: any = nil
	if options ~= nil and type(options.tinyfolkMovementTraitService) == "table" then
		TinyfolkMovementTraitService = options.tinyfolkMovementTraitService
	end
	if runtimeGame == nil then
		local optionalTinyfolkServiceLoaded, optionalTinyfolkService = pcall(function()
			if script ~= nil and script.Parent ~= nil then
				return require(script.Parent:WaitForChild("TinyfolkMovementTraitService"))
			end
			return require("./TinyfolkMovementTraitService")
		end)
		if optionalTinyfolkServiceLoaded then
			TinyfolkMovementTraitService = optionalTinyfolkService
		end
	end

	local escapeRouteById: { [string]: BasePart } = {}
	local escapedTinyfolkByUserId: { [number]: boolean? } = {}
	local lastRequestAtByUserId: { [number]: number? } = {}
	local traversalGapBlockByRouteId: { [string]: any? } = {}
	local finalExitStateByRouteId: { [string]: any? } = {}
	local fallbackEscapeStateByRouteId: { [string]: any? } = {}
	local lastDashRequestAtByUserId: { [number]: number? } = {}
	local safeZoneAbuseStateByUserId: { [number]: any? } = {}

	local function getScoreServiceQueryApi(): any?
		local globalValue: any = globalEnv
		if type(globalValue) ~= "table" then
			return nil
		end

		local queryApi = globalValue._ScoreService_QueryAPI
		if type(queryApi) ~= "table" then
			return nil
		end

		return queryApi
	end

	local function ensureRemotesFolder(): Folder?
		if ReplicatedStorage == nil or type(ReplicatedStorage.FindFirstChild) ~= "function" then
			return nil
		end

		local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
		if existing and existing:IsA("Folder") then
			return existing
		end

		if type(Instance) ~= "table" or type(Instance.new) ~= "function" then
			return nil
		end

		local folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER_NAME
		folder.Parent = ReplicatedStorage
		debugLog("Created ReplicatedStorage.Remotes folder")
		return folder
	end

	local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent?
		local existing = parentFolder:FindFirstChild(remoteName)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end

		if type(Instance) ~= "table" or type(Instance.new) ~= "function" then
			return nil
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = parentFolder
		debugLog(string.format("Created ReplicatedStorage.Remotes.%s", remoteName))
		return remote
	end

	local function isCoolingDown(userId: number): boolean
		local last = lastRequestAtByUserId[userId]
		if last == nil then
			return false
		end

		return (os.clock() - last) < EscapeConfig.RequestCooldownSeconds
	end

	local function markRequest(userId: number)
		lastRequestAtByUserId[userId] = os.clock()
	end

	local function now(): number
		if options ~= nil and type(options.clock) == "function" then
			local value = options.clock()
			if type(value) == "number" then
				return value
			end
		end
		return os.clock()
	end

	local function isDashCoolingDown(userId: number): boolean
		local last = lastDashRequestAtByUserId[userId]
		if last == nil then
			return false
		end

		return (now() - last) < EscapeConfig.DashCooldownSeconds
	end

	local function markDashRequest(userId: number)
		lastDashRequestAtByUserId[userId] = now()
	end

	local function isSafeZoneAbuseLocked(userId: number, currentTime: number): boolean
		local state = safeZoneAbuseStateByUserId[userId]
		if state == nil then
			return false
		end
		if type(state.lockoutEndsAt) ~= "number" then
			return false
		end
		return currentTime <= state.lockoutEndsAt
	end

	local function noteSafeZoneAbuse(userId: number, currentTime: number)
		local windowSeconds = EscapeConfig.SafeZoneAbuseWindowSeconds
		local threshold = EscapeConfig.SafeZoneAbuseThreshold
		local lockoutSeconds = EscapeConfig.SafeZoneAbuseLockoutSeconds

		if type(windowSeconds) ~= "number" or type(threshold) ~= "number" or type(lockoutSeconds) ~= "number" then
			return
		end

		local state = safeZoneAbuseStateByUserId[userId]
		if state == nil or type(state.windowStartedAt) ~= "number" then
			safeZoneAbuseStateByUserId[userId] = {
				count = 1,
				windowStartedAt = currentTime,
				lockoutEndsAt = nil,
			}
			return
		end

		if currentTime - state.windowStartedAt > windowSeconds then
			state.count = 1
			state.windowStartedAt = currentTime
			state.lockoutEndsAt = nil
		else
			state.count += 1
		end

		if state.count >= threshold then
			state.lockoutEndsAt = currentTime + lockoutSeconds
			state.count = 0
			state.windowStartedAt = currentTime
		end
	end

	local function evaluateSafeZoneProtection(safeZoneState: boolean, safeZoneType: any, protectionEndsAt: any): any
		return SafeZonePolicy.EvaluateProtection(EscapeConfig, {
			safeZoneState = safeZoneState,
			safeZoneType = safeZoneType,
			safeZoneProtectionEndsAt = protectionEndsAt,
			now = now(),
		})
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
			local aVector = a :: any
			local bVector = b :: any
			local dx = aVector.x - bVector.x
			local dy = aVector.y - bVector.y
			local dz = aVector.z - bVector.z
			return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
		end

		local ok, delta = pcall(function()
			return a - b
		end)
		if not ok then
			return nil
		end
		if type(delta) == "table" and type((delta :: any).Magnitude) == "function" then
			return (delta :: any):Magnitude()
		end
		if type(delta) == "table" and type((delta :: any).Magnitude) == "number" then
			return (delta :: any).Magnitude
		end
		if type(delta) == "number" then
			return math.abs(delta)
		end

		return nil
	end

	local function getHumanoidRootPart(player: any): BasePart?
		if player == nil then
			return nil
		end

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

	local function isPlayerAlive(player: any): boolean
		if player == nil or player.Character == nil then
			return false
		end

		if type(player.Character.FindFirstChildOfClass) ~= "function" then
			return true
		end

		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then
			return false
		end

		return (humanoid :: Humanoid).Health > 0
	end

	local function isTinyfolk(player: any): boolean
		if player == nil or type(player.GetAttribute) ~= "function" then
			return false
		end
		return player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
	end

	local function findEscapeRoutesRoot(): Instance?
		if Workspace == nil then
			return nil
		end

		local current: any = Workspace
		for _, childName in ESCAPE_ROUTES_FOLDER_PATH do
			if type(current.FindFirstChild) ~= "function" then
				return nil
			end
			local nextNode = current:FindFirstChild(childName)
			if not nextNode then
				return nil
			end
			current = nextNode
		end

		return current
	end

	local function shouldTrackEscapeRoutePart(part: BasePart): boolean
		return string.match(part.Name, "^" .. EscapeConfig.EscapeRouteNamePrefix) ~= nil
	end

	local function buildFinalExitConfig(routeId: string): any
		return {
			RouteId = routeId,
			PoweredDurationSeconds = EscapeConfig.FinalExitPoweredDurationSeconds,
			OpeningDurationSeconds = EscapeConfig.FinalExitOpeningDurationSeconds,
			BlockedDurationSeconds = EscapeConfig.FinalExitBlockedDurationSeconds,
			ReopenDurationSeconds = EscapeConfig.FinalExitReopenDurationSeconds,
		}
	end

	local function buildFallbackEscapeConfig(routeId: string): any
		return {
			RouteId = routeId,
			OpenDelaySeconds = EscapeConfig.FallbackEscapeOpenDelaySeconds,
			CloseDurationSeconds = EscapeConfig.FallbackEscapeCloseDurationSeconds,
		}
	end

	local function isFallbackEscapeCandidate(routePart: BasePart): boolean
		return routePart:GetAttribute(EscapeConfig.FallbackEscapeCandidateAttribute) == true
	end

	local function isFinalExitManaged(routePart: BasePart): boolean
		if isFallbackEscapeCandidate(routePart) then
			return false
		end
		return routePart:GetAttribute(EscapeConfig.FinalExitManagedAttribute) ~= false
	end

	local function finalExitRejectReason(phase: string?): string
		if phase == FinalExitState.Phases.Powered then
			return "final_exit_powered"
		end
		if phase == FinalExitState.Phases.Opening then
			return "final_exit_opening"
		end
		if phase == FinalExitState.Phases.Blocked then
			return "final_exit_blocked"
		end
		if phase == FinalExitState.Phases.Resolved then
			return "final_exit_resolved"
		end
		return "final_exit_dormant"
	end

	local function applyFinalExitAttributes(routePart: BasePart, snapshot: any?)
		if snapshot == nil then
			routePart:SetAttribute(EscapeConfig.FinalExitPhaseAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FinalExitPoweredEndsAtAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FinalExitOpeningEndsAtAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FinalExitBlockedEndsAtAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FinalExitResolvedAtAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FinalExitBlockedByUserIdAttribute, nil)
			if routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) == nil then
				routePart:SetAttribute(ROUTE_ENABLED_ATTRIBUTE, true)
			end
			return
		end

		routePart:SetAttribute(EscapeConfig.FinalExitPhaseAttribute, snapshot.phase)
		routePart:SetAttribute(EscapeConfig.FinalExitPoweredEndsAtAttribute, snapshot.poweredEndsAt)
		routePart:SetAttribute(EscapeConfig.FinalExitOpeningEndsAtAttribute, snapshot.openingEndsAt)
		routePart:SetAttribute(EscapeConfig.FinalExitBlockedEndsAtAttribute, snapshot.blockedEndsAt)
		routePart:SetAttribute(EscapeConfig.FinalExitResolvedAtAttribute, snapshot.resolvedAt)
		routePart:SetAttribute(EscapeConfig.FinalExitBlockedByUserIdAttribute, snapshot.blockedByUserId)
		routePart:SetAttribute(ROUTE_ENABLED_ATTRIBUTE, snapshot.isEscapeOpen == true)
	end

	local function fallbackEscapeRejectReason(phase: string?): string
		if phase == FallbackEscapeState.Phases.Searching then
			return "fallback_escape_searching"
		end
		if phase == FallbackEscapeState.Phases.Closed then
			return "fallback_escape_closed"
		end
		if phase == FallbackEscapeState.Phases.Resolved then
			return "fallback_escape_resolved"
		end
		return "fallback_escape_inactive"
	end

	local function applyFallbackEscapeAttributes(routePart: BasePart, snapshot: any?)
		if snapshot == nil then
			routePart:SetAttribute(EscapeConfig.FallbackEscapePhaseAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FallbackEscapeCueBandAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FallbackEscapeClosedEndsAtAttribute, nil)
			routePart:SetAttribute(EscapeConfig.FallbackEscapeClosedByUserIdAttribute, nil)
			return
		end

		routePart:SetAttribute(EscapeConfig.FallbackEscapePhaseAttribute, snapshot.phase)
		routePart:SetAttribute(
			EscapeConfig.FallbackEscapeCueBandAttribute,
			if snapshot.phase == FallbackEscapeState.Phases.Inactive then nil else "local_search"
		)
		routePart:SetAttribute(EscapeConfig.FallbackEscapeClosedEndsAtAttribute, snapshot.closedEndsAt)
		routePart:SetAttribute(EscapeConfig.FallbackEscapeClosedByUserIdAttribute, snapshot.closedByUserId)
		routePart:SetAttribute(ROUTE_ENABLED_ATTRIBUTE, snapshot.isEscapeOpen == true)
	end

	local function ensureFinalExitState(routeId: string, routePart: BasePart): any?
		if not isFinalExitManaged(routePart) then
			finalExitStateByRouteId[routeId] = nil
			applyFinalExitAttributes(routePart, nil)
			return nil
		end

		local state = finalExitStateByRouteId[routeId]
		if state == nil then
			state = FinalExitState.NewState(buildFinalExitConfig(routeId))
			finalExitStateByRouteId[routeId] = state
		end
		return state
	end

	local function registerEscapeRoutePart(part: BasePart)
		local routeId = part.Name
		if escapeRouteById[routeId] == part then
			return
		end
		if escapeRouteById[routeId] then
			debugWarn(string.format("Duplicate escape route id ignored: %s", routeId))
			return
		end

		escapeRouteById[routeId] = part

		if isFallbackEscapeCandidate(part) then
			if part:GetAttribute(EscapeConfig.FinalExitManagedAttribute) == nil then
				part:SetAttribute(EscapeConfig.FinalExitManagedAttribute, false)
			end
			if part:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) == nil then
				part:SetAttribute(ROUTE_ENABLED_ATTRIBUTE, false)
			end
		end

		if part:GetAttribute(EscapeConfig.FinalExitManagedAttribute) == nil then
			part:SetAttribute(EscapeConfig.FinalExitManagedAttribute, true)
		end

		if part:GetAttribute(EscapeConfig.ThroughGapReachAllowedAttribute) == nil then
			part:SetAttribute(EscapeConfig.ThroughGapReachAllowedAttribute, false)
		end
		if part:GetAttribute(EscapeConfig.TinyfolkOnlyRouteAttribute) == nil then
			part:SetAttribute(EscapeConfig.TinyfolkOnlyRouteAttribute, true)
		end

		if part:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) == nil then
			part:SetAttribute(ROUTE_ENABLED_ATTRIBUTE, true)
		end
		part:SetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE, 0)
		part:SetAttribute(EscapeConfig.TraversalGapBlockStateAttribute, TraversalGapBlockState.States.Idle)
		part:SetAttribute(EscapeConfig.TraversalGapBlockStartupEndsAtAttribute, nil)
		part:SetAttribute(EscapeConfig.TraversalGapBlockActiveEndsAtAttribute, nil)
		part:SetAttribute(EscapeConfig.TraversalGapBlockExpiresAtAttribute, nil)
		part:SetAttribute(EscapeConfig.TraversalGapBlockedByUserIdAttribute, nil)
		if part:GetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute) == nil then
			part:SetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute, false)
		end
		if isFallbackEscapeCandidate(part) then
			applyFallbackEscapeAttributes(part, FallbackEscapeState.GetSnapshot(FallbackEscapeState.NewState(buildFallbackEscapeConfig(routeId))))
		end

		local finalExitState = ensureFinalExitState(routeId, part)
		if finalExitState ~= nil then
			applyFinalExitAttributes(part, FinalExitState.GetSnapshot(finalExitState))
		else
			applyFinalExitAttributes(part, nil)
		end
	end

	local function isRoutePartStillRegistered(routePart: BasePart): boolean
		if routePart == nil then
			return false
		end

		local current: any = routePart
		while current ~= nil do
			if current == Workspace then
				return true
			end
			current = current.Parent
		end

		return false
	end

	local function registerEscapeRoutesFromWorkspace()
		local routesRoot = findEscapeRoutesRoot()
		if not routesRoot then
			return
		end

		for _, descendant in routesRoot:GetDescendants() do
			if descendant:IsA("BasePart") and shouldTrackEscapeRoutePart(descendant) then
				registerEscapeRoutePart(descendant)
			end
		end
	end

	local function trySendToTinyfolkMovementTraitService(player: any, routeId: string)
		if TinyfolkMovementTraitService == nil then
			return
		end
		if type(TinyfolkMovementTraitService.OnValidRouteCrossing) ~= "function" then
			return
		end
		pcall(function()
			TinyfolkMovementTraitService.OnValidRouteCrossing(player, routeId)
		end)
	end

	local function getRoleServiceQueryApi(): any?
		local globalValue: any = globalEnv
		if type(globalValue) ~= "table" then
			return nil
		end
		local queryApi = globalValue._RoleService_QueryAPI
		if type(queryApi) ~= "table" then
			return nil
		end
		return queryApi
	end

	local function getGrabServiceQueryApi(): any?
		local globalValue: any = globalEnv
		if type(globalValue) ~= "table" then
			return nil
		end
		local queryApi = globalValue._GrabService_QueryAPI
		if type(queryApi) ~= "table" then
			return nil
		end
		return queryApi
	end

	local function getTransportServiceQueryApi(): any?
		local globalValue: any = globalEnv
		if type(globalValue) ~= "table" then
			return nil
		end
		local queryApi = globalValue._TransportEscapeService_QueryAPI
		if type(queryApi) ~= "table" then
			return nil
		end
		return queryApi
	end

	local function getObjectiveServiceQueryApi(): any?
		local globalValue: any = globalEnv
		if type(globalValue) ~= "table" then
			return nil
		end
		local queryApi = globalValue._RealmObjectiveService_QueryAPI
		if type(queryApi) ~= "table" then
			return nil
		end
		return queryApi
	end

	local function getPlayerByUserId(userId: number): any?
		if Players == nil or type(Players.GetPlayerByUserId) ~= "function" then
			return nil
		end

		if runtimeGame ~= nil then
			local ok, result = pcall(function()
				return Players.GetPlayerByUserId(userId)
			end)
			if ok then
				return result
			end
			return nil
		end

		local ok, result = pcall(function()
			return Players:GetPlayerByUserId(userId)
		end)
		if ok then
			return result
		end

		return nil
	end

	local function findTinyfolkReturnPoint(): any?
		if Workspace == nil then
			return nil
		end

		local current: any = Workspace
		for _, childName in EscapeConfig.TinyfolkWorldFolderPath do
			if type(current.FindFirstChild) ~= "function" then
				return nil
			end
			local nextNode = current:FindFirstChild(childName)
			if nextNode == nil then
				return nil
			end
			current = nextNode
		end

		if type(current.FindFirstChild) ~= "function" then
			return nil
		end

		return current:FindFirstChild(EscapeConfig.TinyfolkReturnPointName)
	end

	local function resolveReturnPointPivot(returnPoint: any): any?
		if returnPoint == nil then
			return nil
		end
		if (returnPoint :: any).CFrame ~= nil then
			return (returnPoint :: any).CFrame
		end
		if (returnPoint :: any).Position ~= nil then
			if type(CFrame) == "table" and type((CFrame :: any).new) == "function" then
				local ok, created = pcall(function()
					return (CFrame :: any).new((returnPoint :: any).Position)
				end)
				if ok then
					return created
				end
			end
			return { Position = (returnPoint :: any).Position }
		end
		return nil
	end

	local function relocatePlayerToTinyfolkReturn(player: any): boolean
		if player == nil or player.Character == nil then
			return false
		end
		if type((player.Character :: any).PivotTo) ~= "function" then
			return false
		end

		local returnPoint = findTinyfolkReturnPoint()
		local targetPivot = resolveReturnPointPivot(returnPoint)
		if targetPivot == nil then
			return false
		end

		local ok = pcall(function()
			(player.Character :: any):PivotTo(targetPivot)
		end)
		return ok
	end

	local function markPlayerEscaped(player: any, sourceId: string?): boolean
		if player == nil or type(player.UserId) ~= "number" then
			return false
		end

		if escapedTinyfolkByUserId[player.UserId] == true then
			if type(player.SetAttribute) == "function" then
				player:SetAttribute(ESCAPED_ATTRIBUTE, true)
			end
			return false
		end

		escapedTinyfolkByUserId[player.UserId] = true
		if type(player.SetAttribute) == "function" then
			player:SetAttribute(ESCAPED_ATTRIBUTE, true)
		end

		local scoreApi = getScoreServiceQueryApi()
		if scoreApi ~= nil and type(scoreApi.RequestScoreEvent) == "function" then
			pcall(function()
				scoreApi.RequestScoreEvent(player.UserId, "escape_success", now(), {
					routeId = if type(sourceId) == "string" then sourceId else "transport_endpoint",
				})
			end)
		end

		return true
	end

	local function resolveLineOfSightCheck(request: any): ((Vector3, Vector3) -> boolean)?
		if request ~= nil and type(request.lineOfSightCheck) == "function" then
			return request.lineOfSightCheck
		end

		if options ~= nil and type(options.lineOfSightCheck) == "function" then
			return options.lineOfSightCheck
		end

		if Workspace ~= nil and type((Workspace :: any).Raycast) == "function" then
			return function(callerPosition: Vector3, targetPosition: Vector3): boolean
				local direction = targetPosition - callerPosition
				local ok, raycastResult = pcall(function()
					return (Workspace :: any):Raycast(callerPosition, direction)
				end)
				if not ok then
					return false
				end
				return raycastResult == nil
			end
		end

		return nil
	end

	local function resolveRoutePart(routeId: string): BasePart?
		local routePart = escapeRouteById[routeId]
		if routePart ~= nil and isRoutePartStillRegistered(routePart) then
			return routePart
		end

		if routePart ~= nil then
			escapeRouteById[routeId] = nil
			traversalGapBlockByRouteId[routeId] = nil
			finalExitStateByRouteId[routeId] = nil
			fallbackEscapeStateByRouteId[routeId] = nil
		end

		registerEscapeRoutesFromWorkspace()
		return escapeRouteById[routeId]
	end

	local function routeHasBlockExemption(routePart: BasePart): boolean
		return routePart:GetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute) == true
	end

	local function applyBlockAttributes(routePart: BasePart, snapshot: any)
		routePart:SetAttribute(EscapeConfig.TraversalGapBlockStateAttribute, snapshot.state)
		routePart:SetAttribute(EscapeConfig.TraversalGapBlockStartupEndsAtAttribute, snapshot.startupEndsAt)
		routePart:SetAttribute(EscapeConfig.TraversalGapBlockActiveEndsAtAttribute, snapshot.activeEndsAt)
		routePart:SetAttribute(EscapeConfig.TraversalGapBlockExpiresAtAttribute, snapshot.expiresAt)
		routePart:SetAttribute(EscapeConfig.TraversalGapBlockedByUserIdAttribute, snapshot.blockedByUserId)
		routePart:SetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute, routeHasBlockExemption(routePart))
	end

	local function cleanupExpiredBlock(routeId: string, routePart: BasePart, currentTime: number): any
		local record = traversalGapBlockByRouteId[routeId]
		local snapshot = TraversalGapBlockState.Snapshot(record, currentTime)
		if snapshot.state == TraversalGapBlockState.States.Expired then
			traversalGapBlockByRouteId[routeId] = nil
			snapshot = TraversalGapBlockState.Snapshot(nil, currentTime)
		end
		applyBlockAttributes(routePart, snapshot)
		return snapshot
	end

	local function getBlockSnapshot(routeId: string, routePart: BasePart): any
		return cleanupExpiredBlock(routeId, routePart, now())
	end

	local function getSortedFallbackCandidateRouteIds(): { string }
		registerEscapeRoutesFromWorkspace()
		local routeIds: { string } = {}
		for routeId in escapeRouteById do
			local routePart = resolveRoutePart(routeId)
			if routePart ~= nil and isFallbackEscapeCandidate(routePart) then
				table.insert(routeIds, routeId)
			end
		end
		table.sort(routeIds)
		return routeIds
	end

	local function getSelectedFallbackRouteId(): string?
		local routeIds = getSortedFallbackCandidateRouteIds()
		return routeIds[1]
	end

	local function getPlayersList(): { any }
		if Players == nil or type(Players.GetPlayers) ~= "function" then
			return {}
		end
		if runtimeGame ~= nil then
			local ok, result = pcall(function()
				return Players.GetPlayers()
			end)
			return if ok and type(result) == "table" then result else {}
		end

		local ok, result = pcall(function()
			return Players:GetPlayers()
		end)
		return if ok and type(result) == "table" then result else {}
	end

	local function getActiveTinyfolkUserIds(): { number }
		local activeUserIds: { number } = {}
		local roleServiceQueryApi = getRoleServiceQueryApi()
		for _, candidate in ipairs(getPlayersList()) do
			if
				candidate ~= nil
				and type(candidate.UserId) == "number"
				and isTinyfolk(candidate)
				and isPlayerAlive(candidate)
				and escapedTinyfolkByUserId[candidate.UserId] ~= true
			then
				local downed = false
				if roleServiceQueryApi ~= nil and type(roleServiceQueryApi.IsPlayerDowned) == "function" then
					local downedOk, downedResult = pcall(function()
						return roleServiceQueryApi.IsPlayerDowned(candidate.UserId)
					end)
					downed = downedOk and downedResult == true
				end
				if downed ~= true then
					table.insert(activeUserIds, candidate.UserId)
				end
			end
		end
		table.sort(activeUserIds)
		return activeUserIds
	end

	local function ensureFallbackEscapeState(routeId: string, routePart: BasePart): any?
		if not isFallbackEscapeCandidate(routePart) then
			fallbackEscapeStateByRouteId[routeId] = nil
			applyFallbackEscapeAttributes(routePart, nil)
			return nil
		end
		if getSelectedFallbackRouteId() ~= routeId then
			fallbackEscapeStateByRouteId[routeId] = nil
			applyFallbackEscapeAttributes(routePart, FallbackEscapeState.GetSnapshot(FallbackEscapeState.NewState(buildFallbackEscapeConfig(routeId))))
			return nil
		end

		local state = fallbackEscapeStateByRouteId[routeId]
		if state == nil then
			state = FallbackEscapeState.NewState(buildFallbackEscapeConfig(routeId))
			fallbackEscapeStateByRouteId[routeId] = state
		end
		return state
	end

	local function refreshFallbackEscapeState(routeId: string, routePart: BasePart): any?
		local state = ensureFallbackEscapeState(routeId, routePart)
		if state == nil then
			return nil
		end

		while true do
			local transition = FallbackEscapeState.Refresh(state, buildFallbackEscapeConfig(routeId), getActiveTinyfolkUserIds(), now())
			state = transition.state
			fallbackEscapeStateByRouteId[routeId] = state
			if transition.accepted ~= true then
				break
			end
		end

		local snapshot = FallbackEscapeState.GetSnapshot(state)
		applyFallbackEscapeAttributes(routePart, snapshot)
		return snapshot
	end

	local function refreshFinalExitState(routeId: string, routePart: BasePart): any?
		local finalExitState = ensureFinalExitState(routeId, routePart)
		if finalExitState == nil then
			return nil
		end

		local config = buildFinalExitConfig(routeId)
		local objectiveQueryApi = getObjectiveServiceQueryApi()
		local thresholdMet = false
		if objectiveQueryApi ~= nil and type(objectiveQueryApi.IsEscapeObjectiveThresholdMet) == "function" then
			local thresholdOk, thresholdResult = pcall(function()
				return objectiveQueryApi.IsEscapeObjectiveThresholdMet()
			end)
			if thresholdOk and thresholdResult == true then
				thresholdMet = true
			end
		end
		if finalExitState.phase == FinalExitState.Phases.Dormant and thresholdMet == true then
			local activation = FinalExitState.MarkObjectiveThresholdMet(finalExitState, config, now())
			if activation.accepted == true then
				finalExitState = activation.state
				finalExitStateByRouteId[routeId] = finalExitState
			end
		end

		while true do
			local resolved = FinalExitState.ResolveTime(finalExitState, config, now())
			if resolved.accepted ~= true then
				break
			end
			finalExitState = resolved.state
			finalExitStateByRouteId[routeId] = finalExitState
		end

		local blockSnapshot = getBlockSnapshot(routeId, routePart)
		if
			blockSnapshot.state == TraversalGapBlockState.States.Active
			and (
				finalExitState.phase == FinalExitState.Phases.Open
				or finalExitState.phase == FinalExitState.Phases.Opening
			)
		then
			local blocked =
				FinalExitState.ApplyBlockInterruption(finalExitState, config, blockSnapshot.blockedByUserId, now())
			if blocked.accepted == true then
				finalExitState = blocked.state
				finalExitStateByRouteId[routeId] = finalExitState
			end
		end

		local snapshot = FinalExitState.GetSnapshot(finalExitState)
		applyFinalExitAttributes(routePart, snapshot)
		return snapshot
	end

	local function routeRejectsTraversal(routeId: string, routePart: BasePart): boolean
		local currentTime = now()
		cleanupExpiredBlock(routeId, routePart, currentTime)
		return TraversalGapBlockState.ShouldRejectTraversal(
			traversalGapBlockByRouteId[routeId],
			currentTime,
			routeHasBlockExemption(routePart)
		)
	end

	local function getPlayerRole(player: any): string?
		if player == nil or type(player.GetAttribute) ~= "function" then
			return nil
		end
		local role = player:GetAttribute("Role")
		return if type(role) == "string" then role else nil
	end

	local function buildRouteAccessPayload(routeId: string, routePart: BasePart, player: any?): any
		local role = getPlayerRole(player)
		local tinyfolkOnly = routePart:GetAttribute(EscapeConfig.TinyfolkOnlyRouteAttribute) == true
		if role ~= RoleConfig.Roles.Tinyfolk then
			return {
				accepted = false,
				reason = "requester_not_tinyfolk",
				routeId = routeId,
				role = role,
				tinyfolkOnly = tinyfolkOnly,
				isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) ~= false,
				blockState = routePart:GetAttribute(EscapeConfig.TraversalGapBlockStateAttribute),
				blockExempt = routeHasBlockExemption(routePart),
				finalExitPhase = routePart:GetAttribute(EscapeConfig.FinalExitPhaseAttribute),
			}
		end

		local finalExitSnapshot = nil
		local fallbackEscapeSnapshot = nil
		if isFallbackEscapeCandidate(routePart) then
			fallbackEscapeSnapshot = refreshFallbackEscapeState(routeId, routePart)
		end
		if isFinalExitManaged(routePart) then
			finalExitSnapshot = refreshFinalExitState(routeId, routePart)
		end
		local isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) ~= false
		local snapshot = getBlockSnapshot(routeId, routePart)
		local isBlocked = snapshot.state == TraversalGapBlockState.States.Active
			and not routeHasBlockExemption(routePart)

		local accepted = true
		local reason = "accepted"
		if fallbackEscapeSnapshot ~= nil and fallbackEscapeSnapshot.isEscapeOpen ~= true then
			accepted = false
			reason = fallbackEscapeRejectReason(fallbackEscapeSnapshot.phase)
		elseif finalExitSnapshot ~= nil and finalExitSnapshot.isEscapeOpen ~= true then
			accepted = false
			reason = finalExitRejectReason(finalExitSnapshot.phase)
		elseif not isEnabled then
			accepted = false
			reason = "route_disabled"
		elseif isBlocked then
			accepted = false
			reason = "traversal_gap_block_active"
		end

		return {
			accepted = accepted,
			reason = reason,
			routeId = routeId,
			role = role,
			tinyfolkOnly = tinyfolkOnly,
			isEnabled = isEnabled,
			blockState = snapshot.state,
			blockExempt = routeHasBlockExemption(routePart),
			finalExitPhase = if finalExitSnapshot ~= nil then finalExitSnapshot.phase else nil,
			fallbackEscapePhase = if fallbackEscapeSnapshot ~= nil then fallbackEscapeSnapshot.phase else nil,
			fallbackEscapeCueBand = routePart:GetAttribute(EscapeConfig.FallbackEscapeCueBandAttribute),
		}
	end

	local function buildObjectiveSafeRouteMetadata(routeId: string, routePart: BasePart): any
		local snapshot = getBlockSnapshot(routeId, routePart)
		local finalExitSnapshot = refreshFinalExitState(routeId, routePart)
		local fallbackEscapeSnapshot = refreshFallbackEscapeState(routeId, routePart)
		return {
			routeId = routeId,
			tinyfolkOnly = routePart:GetAttribute(EscapeConfig.TinyfolkOnlyRouteAttribute) == true,
			isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) ~= false,
			routeType = routePart:GetAttribute(EscapeConfig.RouteTypeAttribute),
			blockState = snapshot.state,
			blockExempt = routeHasBlockExemption(routePart),
			finalExitPhase = if finalExitSnapshot ~= nil then finalExitSnapshot.phase else nil,
			fallbackEscapeCandidate = isFallbackEscapeCandidate(routePart),
			fallbackEscapePhase = if fallbackEscapeSnapshot ~= nil then fallbackEscapeSnapshot.phase else nil,
			fallbackEscapeCueBand = routePart:GetAttribute(EscapeConfig.FallbackEscapeCueBandAttribute),
		}
	end

	local function buildRouteDebugPayload(routeId: string, routePart: BasePart, userId: number?): any
		local snapshot = getBlockSnapshot(routeId, routePart)
		local finalExitSnapshot = refreshFinalExitState(routeId, routePart)
		local fallbackEscapeSnapshot = refreshFallbackEscapeState(routeId, routePart)
		local payload: any = {
			routeId = routeId,
			isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE),
			tinyfolkOnly = routePart:GetAttribute(EscapeConfig.TinyfolkOnlyRouteAttribute) == true,
			successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE),
			blockState = snapshot.state,
			blockStartupEndsAt = snapshot.startupEndsAt,
			blockActiveEndsAt = snapshot.activeEndsAt,
			blockExpiresAt = snapshot.expiresAt,
			blockedByUserId = snapshot.blockedByUserId,
			blockExempt = routeHasBlockExemption(routePart),
			finalExitPhase = if finalExitSnapshot ~= nil then finalExitSnapshot.phase else nil,
			finalExitPoweredEndsAt = if finalExitSnapshot ~= nil then finalExitSnapshot.poweredEndsAt else nil,
			finalExitOpeningEndsAt = if finalExitSnapshot ~= nil then finalExitSnapshot.openingEndsAt else nil,
			finalExitBlockedEndsAt = if finalExitSnapshot ~= nil then finalExitSnapshot.blockedEndsAt else nil,
			finalExitResolvedAt = if finalExitSnapshot ~= nil then finalExitSnapshot.resolvedAt else nil,
			fallbackEscapeCandidate = isFallbackEscapeCandidate(routePart),
			fallbackEscapePhase = if fallbackEscapeSnapshot ~= nil then fallbackEscapeSnapshot.phase else nil,
			fallbackEscapeCueBand = routePart:GetAttribute(EscapeConfig.FallbackEscapeCueBandAttribute),
			fallbackEscapeClosedEndsAt = if fallbackEscapeSnapshot ~= nil then fallbackEscapeSnapshot.closedEndsAt else nil,
			fallbackEscapeClosedByUserId = if fallbackEscapeSnapshot ~= nil then fallbackEscapeSnapshot.closedByUserId else nil,
		}

		if userId ~= nil then
			payload.escaped = escapedTinyfolkByUserId[userId] == true
		end

		return payload
	end

	local service: any = {}

	local function requestBlockWithSettings(player: any, routeId: any, triggerRadius: number): any
		if type(routeId) ~= "string" then
			return { accepted = false, reason = "route_id_invalid" }
		end

		local callerUserId = if player ~= nil and type(player.UserId) == "number" then player.UserId else nil
		if callerUserId ~= nil and isSafeZoneAbuseLocked(callerUserId, now()) then
			return { accepted = false, reason = "safe_zone_abuse_rate_limited" }
		end

		local routePart = resolveRoutePart(routeId)
		if routePart == nil then
			return { accepted = false, reason = "route_not_found" }
		end

		local callerRole = nil
		if player ~= nil and type(player.GetAttribute) == "function" then
			callerRole = player:GetAttribute("Role")
		end
		if callerRole ~= RoleConfig.Roles.Giant then
			return { accepted = false, reason = "caller_not_giant" }
		end

		local grabServiceQueryApi = getGrabServiceQueryApi()
		if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.IsPlayerCarried) == "function" then
			local isCarriedOk, isCarried = pcall(function()
				return grabServiceQueryApi.IsPlayerCarried(player.UserId)
			end)
			if not isCarriedOk then
				return { accepted = false, reason = "grab_query_fault" }
			end
			if isCarried == true then
				return { accepted = false, reason = "actor_carried" }
			end
		end
		if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.CanGiantPerformCarryInteraction) == "function" then
			local carryInteractionOk, carryInteraction = pcall(function()
				return grabServiceQueryApi.CanGiantPerformCarryInteraction(player.UserId, "traversalGapBlock")
			end)
			if not carryInteractionOk then
				return { accepted = false, reason = "grab_query_fault" }
			end
			if type(carryInteraction) == "table" and carryInteraction.accepted ~= true then
				local carryInteractionAny = carryInteraction :: any
				return {
					accepted = false,
					reason = tostring(carryInteractionAny.reason or "carrier_encumbered"),
				}
			end
		end

		local callerRoot = getHumanoidRootPart(player)
		if callerRoot == nil then
			return { accepted = false, reason = "missing_character_root" }
		end

		if routePart:GetAttribute(EscapeConfig.ThroughGapReachAllowedAttribute) ~= true then
			return { accepted = false, reason = "route_disallows_through_gap_reach" }
		end

		local routeType = routePart:GetAttribute(EscapeConfig.RouteTypeAttribute)
		if type(routeType) ~= "string" then
			return { accepted = false, reason = "route_type_missing" }
		end
		if EscapeConfig.SupportedThroughGapRouteTypes[routeType] ~= true then
			return { accepted = false, reason = "route_type_unsupported" }
		end

		local routeSafeZoneDecision = evaluateSafeZoneProtection(
			routePart:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
			routePart:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
			routePart:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
		)
		if routeSafeZoneDecision.protected == true then
			if callerUserId ~= nil then
				noteSafeZoneAbuse(callerUserId, now())
			end
			return { accepted = false, reason = tostring(routeSafeZoneDecision.reason or "route_in_safe_zone") }
		end

		local distance = resolveDistance((routePart :: any).Position, (callerRoot :: any).Position)
		if distance == nil then
			return { accepted = false, reason = "distance_unavailable" }
		end
		if distance > triggerRadius then
			return { accepted = false, reason = "caller_out_of_range" }
		end

		local currentTime = now()
		cleanupExpiredBlock(routeId, routePart, currentTime)
		local result = TraversalGapBlockState.CreateBlock(EscapeConfig, {
			routeId = routeId,
			blockedByUserId = player.UserId,
			now = currentTime,
			existingRecord = traversalGapBlockByRouteId[routeId],
		})

		if result.accepted and result.record ~= nil then
			traversalGapBlockByRouteId[routeId] = result.record
			applyBlockAttributes(routePart, result.snapshot)

			if options == nil or options.disableBlockExpirationSchedule ~= true then
				local record = result.record
				local delaySeconds = math.max(record.expiresAt - now(), 0)
				if task ~= nil and type(task.delay) == "function" then
					task.delay(delaySeconds, function()
						if traversalGapBlockByRouteId[routeId] ~= record then
							return
						end
						local latestRoutePart = resolveRoutePart(routeId)
						if latestRoutePart == nil then
							traversalGapBlockByRouteId[routeId] = nil
							return
						end
						cleanupExpiredBlock(routeId, latestRoutePart, now())
					end)
				end
			end
		else
			applyBlockAttributes(routePart, result.snapshot)
		end

		return result
	end

	function service.requestDash(player: any, routeId: any): any
		if type(routeId) ~= "string" then
			return { accepted = false, reason = "route_id_invalid" }
		end

		if player == nil or type(player.UserId) ~= "number" then
			return { accepted = false, reason = "caller_user_id_invalid" }
		end
		if isDashCoolingDown(player.UserId) then
			return { accepted = false, reason = "dash_cooldown" }
		end

		local result = requestBlockWithSettings(player, routeId, EscapeConfig.DashTriggerRadiusStuds)
		if result.accepted == true then
			markDashRequest(player.UserId)
		end

		return result
	end

	function service.requestTraversalGapBlock(player: any, routeId: any): any
		return requestBlockWithSettings(player, routeId, EscapeConfig.TriggerRadiusStuds)
	end

	function service.requestFallbackEscapeClose(player: any, routeId: any): any
		if type(routeId) ~= "string" then
			return { accepted = false, reason = "route_id_invalid" }
		end
		if player == nil or type(player.UserId) ~= "number" then
			return { accepted = false, reason = "caller_user_id_invalid" }
		end

		local routePart = resolveRoutePart(routeId)
		if routePart == nil then
			return { accepted = false, reason = "route_not_found" }
		end
		if not isFallbackEscapeCandidate(routePart) then
			return { accepted = false, reason = "fallback_escape_not_candidate" }
		end

		local callerRole = getPlayerRole(player)
		if callerRole ~= RoleConfig.Roles.Giant then
			return { accepted = false, reason = "caller_not_giant" }
		end
		if not isPlayerAlive(player) then
			return { accepted = false, reason = "player_not_alive" }
		end

		local callerRoot = getHumanoidRootPart(player)
		if callerRoot == nil then
			return { accepted = false, reason = "missing_character_root" }
		end
		local distance = resolveDistance((routePart :: any).Position, (callerRoot :: any).Position)
		if distance == nil then
			return { accepted = false, reason = "distance_unavailable" }
		end
		if distance > EscapeConfig.TriggerRadiusStuds then
			return { accepted = false, reason = "caller_out_of_range" }
		end

		local routeSafeZoneDecision = evaluateSafeZoneProtection(
			routePart:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
			routePart:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
			routePart:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
		)
		if routeSafeZoneDecision.protected == true then
			return { accepted = false, reason = tostring(routeSafeZoneDecision.reason or "route_in_safe_zone") }
		end

		local state = ensureFallbackEscapeState(routeId, routePart)
		if state == nil then
			return { accepted = false, reason = "fallback_escape_inactive" }
		end
		local snapshot = refreshFallbackEscapeState(routeId, routePart)
		if snapshot == nil then
			return { accepted = false, reason = "fallback_escape_inactive" }
		end

		local closed = FallbackEscapeState.ApplyClose(
			fallbackEscapeStateByRouteId[routeId],
			buildFallbackEscapeConfig(routeId),
			player.UserId,
			now()
		)
		fallbackEscapeStateByRouteId[routeId] = closed.state
		applyFallbackEscapeAttributes(routePart, FallbackEscapeState.GetSnapshot(closed.state))
		return {
			accepted = closed.accepted == true,
			reason = if closed.accepted == true then "closed" else fallbackEscapeRejectReason(closed.state.phase),
			snapshot = FallbackEscapeState.GetSnapshot(closed.state),
		}
	end

	function service.requestEscapeAttempt(player: any, routeId: any): any
		if type(routeId) ~= "string" then
			return { accepted = false, reason = "route_id_invalid" }
		end

		local routePart = resolveRoutePart(routeId)
		if routePart == nil then
			return { accepted = false, reason = "route_not_found" }
		end
		if not isTinyfolk(player) then
			return { accepted = false, reason = "requester_not_tinyfolk" }
		end

		local roleServiceQueryApi = getRoleServiceQueryApi()
		if roleServiceQueryApi ~= nil and type(roleServiceQueryApi.IsPlayerDowned) == "function" then
			local downedOk, downed = pcall(function()
				return roleServiceQueryApi.IsPlayerDowned(player.UserId)
			end)
			if not downedOk then
				return { accepted = false, reason = "role_query_fault" }
			end
			if downed == true then
				return { accepted = false, reason = "actor_downed" }
			end
		end

		local grabServiceQueryApi = getGrabServiceQueryApi()
		if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.IsPlayerCarried) == "function" then
			local carriedOk, isCarried = pcall(function()
				return grabServiceQueryApi.IsPlayerCarried(player.UserId)
			end)
			if not carriedOk then
				return { accepted = false, reason = "grab_query_fault" }
			end
			if isCarried == true then
				return { accepted = false, reason = "actor_carried" }
			end
		end

		if roleServiceQueryApi ~= nil and type(roleServiceQueryApi.CanPlayerPerformInteraction) == "function" then
			local interactionOk, interactionAllowed = pcall(function()
				return roleServiceQueryApi.CanPlayerPerformInteraction(player.UserId, "escapeAttempt")
			end)
			if not interactionOk then
				return { accepted = false, reason = "role_query_fault" }
			end
			if interactionAllowed ~= true then
				return { accepted = false, reason = "actor_interaction_restricted" }
			end
		end

		if escapedTinyfolkByUserId[player.UserId] then
			return { accepted = false, reason = "already_escaped" }
		end
		if not isPlayerAlive(player) then
			return { accepted = false, reason = "player_not_alive" }
		end

		local root = getHumanoidRootPart(player)
		if root == nil then
			return { accepted = false, reason = "humanoid_root_missing" }
		end

		local distance = resolveDistance((routePart :: any).Position, (root :: any).Position)
		if distance == nil then
			return { accepted = false, reason = "distance_unavailable" }
		end
		if distance > EscapeConfig.TriggerRadiusStuds then
			return { accepted = false, reason = "route_out_of_range" }
		end

		local routeSafeZoneDecision = evaluateSafeZoneProtection(
			routePart:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
			routePart:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
			routePart:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
		)
		if routeSafeZoneDecision.protected == true then
			return { accepted = false, reason = tostring(routeSafeZoneDecision.reason or "route_in_safe_zone") }
		end

		local fallbackEscapeSnapshot = nil
		if isFallbackEscapeCandidate(routePart) then
			fallbackEscapeSnapshot = refreshFallbackEscapeState(routeId, routePart)
			if fallbackEscapeSnapshot == nil or fallbackEscapeSnapshot.isEscapeOpen ~= true then
				return {
					accepted = false,
					reason = fallbackEscapeRejectReason(if fallbackEscapeSnapshot ~= nil then fallbackEscapeSnapshot.phase else nil),
				}
			end
		end

		if not isFinalExitManaged(routePart) and not isFallbackEscapeCandidate(routePart) and routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) == false then
			return { accepted = false, reason = "route_disabled" }
		end

		local finalExitSnapshot = refreshFinalExitState(routeId, routePart)
		if finalExitSnapshot ~= nil and finalExitSnapshot.isEscapeOpen ~= true then
			return {
				accepted = false,
				reason = finalExitRejectReason(finalExitSnapshot.phase),
			}
		end

		if routeRejectsTraversal(routeId, routePart) then
			return { accepted = false, reason = "traversal_gap_block_active" }
		end

		if finalExitStateByRouteId[routeId] ~= nil then
			local resolvedTransition =
				FinalExitState.ResolveEscape(finalExitStateByRouteId[routeId], player.UserId, now())
			if resolvedTransition.accepted ~= true then
				return { accepted = false, reason = "final_exit_resolution_failed" }
			end
			finalExitStateByRouteId[routeId] = resolvedTransition.state
			applyFinalExitAttributes(routePart, FinalExitState.GetSnapshot(resolvedTransition.state))
		end
		if fallbackEscapeStateByRouteId[routeId] ~= nil then
			local resolvedFallback =
				FallbackEscapeState.ResolveEscape(fallbackEscapeStateByRouteId[routeId], player.UserId, now())
			if resolvedFallback.accepted ~= true then
				return { accepted = false, reason = "fallback_escape_resolution_failed" }
			end
			fallbackEscapeStateByRouteId[routeId] = resolvedFallback.state
			applyFallbackEscapeAttributes(routePart, FallbackEscapeState.GetSnapshot(resolvedFallback.state))
		end

		markPlayerEscaped(player, routeId)

		local successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE)
		if type(successfulEscapes) ~= "number" then
			successfulEscapes = 0
		end
		routePart:SetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE, successfulEscapes + 1)
		trySendToTinyfolkMovementTraitService(player, routeId)

		return { accepted = true, reason = "accepted" }
	end

	function service.resolveTransportDeparture(endpointId: string, candidateTinyfolkUserIds: { number }): any
		if type(endpointId) ~= "string" or string.len(endpointId) <= 0 then
			return { accepted = false, reason = "endpoint_id_invalid" }
		end
		if type(candidateTinyfolkUserIds) ~= "table" then
			return { accepted = false, reason = "candidate_user_ids_invalid" }
		end

		local candidateByUserId: { [number]: boolean } = {}
		for _, userId in ipairs(candidateTinyfolkUserIds) do
			if type(userId) == "number" and userId > 0 and userId % 1 == 0 then
				candidateByUserId[userId] = true
			end
		end

		local transportQueryApi = getTransportServiceQueryApi()
		if transportQueryApi == nil or type(transportQueryApi.ResolveTransportDepartureOutcome) ~= "function" then
			return { accepted = false, reason = "transport_query_unavailable" }
		end

		local transportResultOk, transportResult = pcall(function()
			return transportQueryApi.ResolveTransportDepartureOutcome(endpointId, candidateTinyfolkUserIds)
		end)
		if not transportResultOk then
			return { accepted = false, reason = "transport_query_fault" }
		end
		if type(transportResult) ~= "table" then
			return { accepted = false, reason = "transport_outcome_invalid" }
		end
		if transportResult.accepted ~= true or type(transportResult.outcome) ~= "table" then
			return {
				accepted = false,
				reason = tostring(transportResult.reason or "transport_not_departed"),
				outcome = transportResult.outcome,
			}
		end

		local boardedEscapedUserIds = transportResult.outcome.boardedEscapedUserIds
		local unboardedRemainingUserIds = transportResult.outcome.unboardedRemainingUserIds
		local escapedUserIds: { number } = {}
		local safeReturnedUserIds: { number } = {}
		local unresolvedUserIds: { number } = {}
		local boardedByUserId: { [number]: boolean } = {}
		local unboardedProcessedByUserId: { [number]: boolean } = {}

		if type(boardedEscapedUserIds) == "table" then
			for _, userId in ipairs(boardedEscapedUserIds) do
				if
					type(userId) == "number"
					and candidateByUserId[userId] == true
					and boardedByUserId[userId] ~= true
				then
					boardedByUserId[userId] = true
					local player = getPlayerByUserId(userId)
					if player ~= nil and isTinyfolk(player) then
						if markPlayerEscaped(player, endpointId) then
							table.insert(escapedUserIds, userId)
						end
					end
				end
			end
		end

		if type(unboardedRemainingUserIds) == "table" then
			for _, userId in ipairs(unboardedRemainingUserIds) do
				if
					type(userId) == "number"
					and candidateByUserId[userId] == true
					and boardedByUserId[userId] ~= true
					and unboardedProcessedByUserId[userId] ~= true
				then
					unboardedProcessedByUserId[userId] = true
					local player = getPlayerByUserId(userId)
					if player ~= nil and isTinyfolk(player) then
						escapedTinyfolkByUserId[userId] = false
						if type(player.SetAttribute) == "function" then
							player:SetAttribute(ESCAPED_ATTRIBUTE, false)
						end

						if relocatePlayerToTinyfolkReturn(player) then
							table.insert(safeReturnedUserIds, userId)
						else
							table.insert(unresolvedUserIds, userId)
						end
					end
				end
			end
		end

		local transportRouteId = transportResult.outcome.routeId
		local resolvedTransportFinalExit = false
		if type(transportRouteId) == "string" and string.len(transportRouteId) > 0 and #escapedUserIds > 0 then
			local routePart = resolveRoutePart(transportRouteId)
			if routePart ~= nil then
				local finalExitSnapshot = refreshFinalExitState(transportRouteId, routePart)
				if finalExitSnapshot ~= nil and finalExitSnapshot.phase == FinalExitState.Phases.Open then
					local resolvedTransition = FinalExitState.ResolveEscape(
						finalExitStateByRouteId[transportRouteId],
						escapedUserIds[1],
						now()
					)
					if resolvedTransition.accepted == true then
						finalExitStateByRouteId[transportRouteId] = resolvedTransition.state
						applyFinalExitAttributes(routePart, FinalExitState.GetSnapshot(resolvedTransition.state))
						resolvedTransportFinalExit = true
					end
				end
			end
		end

		return {
			accepted = true,
			reason = "accepted",
			escapedUserIds = escapedUserIds,
			safeReturnedUserIds = safeReturnedUserIds,
			unresolvedUserIds = unresolvedUserIds,
			resolvedTransportFinalExit = resolvedTransportFinalExit,
			outcome = transportResult.outcome,
		}
	end

	function service.getDebugState(player: any, routeId: any?): any
		local userId = if player ~= nil and type(player.UserId) == "number" then player.UserId else nil
		if routeId ~= nil then
			if type(routeId) ~= "string" then
				return nil
			end
			local routePart = resolveRoutePart(routeId)
			if routePart == nil then
				return nil
			end
			return buildRouteDebugPayload(routeId, routePart, userId)
		end

		local snapshot = {}
		for registeredRouteId in escapeRouteById do
			local routePart = resolveRoutePart(registeredRouteId)
			if routePart ~= nil then
				table.insert(snapshot, buildRouteDebugPayload(registeredRouteId, routePart, nil))
			end
		end

		return {
			routes = snapshot,
			escaped = if userId ~= nil then escapedTinyfolkByUserId[userId] == true else false,
		}
	end

	function service.ResetTraversalGapBlocksForTests()
		traversalGapBlockByRouteId = {}
		lastDashRequestAtByUserId = {}
		safeZoneAbuseStateByUserId = {}
		for _, routePart in escapeRouteById do
			applyBlockAttributes(routePart, TraversalGapBlockState.Snapshot(nil, now()))
		end
	end

	function service.ResetEscapeAttemptStateForTests()
		escapedTinyfolkByUserId = {}
	end

	function service.getFinalExitSnapshot(routeId: any): any
		if type(routeId) ~= "string" then
			return nil
		end
		local routePart = resolveRoutePart(routeId)
		if routePart == nil then
			return nil
		end
		return refreshFinalExitState(routeId, routePart)
	end

	function service.getFallbackEscapeSnapshot(routeId: any?): any
		registerEscapeRoutesFromWorkspace()
		if routeId ~= nil then
			if type(routeId) ~= "string" then
				return nil
			end
			local routePart = resolveRoutePart(routeId)
			if routePart == nil then
				return nil
			end
			return refreshFallbackEscapeState(routeId, routePart)
		end

		local selectedRouteId = getSelectedFallbackRouteId()
		if selectedRouteId == nil then
			return nil
		end
		local selectedRoutePart = resolveRoutePart(selectedRouteId)
		if selectedRoutePart == nil then
			return nil
		end
		return refreshFallbackEscapeState(selectedRouteId, selectedRoutePart)
	end

	function service.getRouteAccess(player: any, routeId: any): any
		if type(routeId) ~= "string" then
			return { accepted = false, reason = "route_id_invalid" }
		end
		local routePart = resolveRoutePart(routeId)
		if routePart == nil then
			return { accepted = false, reason = "route_not_found" }
		end
		return buildRouteAccessPayload(routeId, routePart, player)
	end

	function service.getObjectiveSafeRouteMetadata(routeId: any?): any
		registerEscapeRoutesFromWorkspace()
		if routeId ~= nil then
			if type(routeId) ~= "string" then
				return nil
			end
			local routePart = resolveRoutePart(routeId)
			if routePart == nil then
				return nil
			end
			return buildObjectiveSafeRouteMetadata(routeId, routePart)
		end

		local routes = {}
		for registeredRouteId in escapeRouteById do
			local routePart = resolveRoutePart(registeredRouteId)
			if routePart ~= nil then
				table.insert(routes, buildObjectiveSafeRouteMetadata(registeredRouteId, routePart))
			end
		end
		table.sort(routes, function(a: any, b: any)
			return tostring(a.routeId) < tostring(b.routeId)
		end)
		return routes
	end

	function service.resolveRescueEntryRoute(_targetUserId: any, targetRealmOwnerUserId: any): any
		if
			type(targetRealmOwnerUserId) ~= "number"
			or targetRealmOwnerUserId <= 0
			or targetRealmOwnerUserId % 1 ~= 0
		then
			return { accepted = false, reason = "target_realm_owner_user_id_invalid" }
		end

		registerEscapeRoutesFromWorkspace()

		local rescueRouteIds: { string } = {}
		local rescueEntryAttribute = RescueContractConfig.RescueEntryRouteAttribute
		local rescueEntryRouteKind = RescueContractConfig.RescueEntryRouteKind
		for routeId in escapeRouteById do
			local routePart = resolveRoutePart(routeId)
			if routePart == nil then
				continue
			end
			local isRescueRoute = false
			if type(rescueEntryAttribute) == "string" and rescueEntryAttribute ~= "" then
				isRescueRoute = routePart:GetAttribute(rescueEntryAttribute) == true
			end
			if not isRescueRoute then
				isRescueRoute = routePart:GetAttribute(EscapeConfig.RouteTypeAttribute) == rescueEntryRouteKind
			end

			if isRescueRoute then
				table.insert(rescueRouteIds, routeId)
			end
		end

		table.sort(rescueRouteIds)

		for _, routeId in ipairs(rescueRouteIds) do
			local routePart = resolveRoutePart(routeId)
			if routePart ~= nil then
				local routeOwnerUserId = routePart:GetAttribute(RescueContractConfig.TargetRealmOwnerUserIdAttribute)
				local ownerMatches = routeOwnerUserId == nil or routeOwnerUserId == targetRealmOwnerUserId
				local safeZoneDecision = evaluateSafeZoneProtection(
					routePart:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
					routePart:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
					routePart:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
				)

				if ownerMatches and safeZoneDecision.protected ~= true then
					return {
						accepted = true,
						reason = "accepted",
						routeId = routeId,
						routeKind = RescueContractConfig.RescueEntryRouteKind,
					}
				end
			end
		end

		return { accepted = false, reason = "rescue_entry_route_missing" }
	end

	function service.RefreshFinalExitStateForTests(routeId: any): any
		return service.getFinalExitSnapshot(routeId)
	end

	function service.ResetFinalExitForTests()
		finalExitStateByRouteId = {}
		for routeId, routePart in escapeRouteById do
			local finalExitState = ensureFinalExitState(routeId, routePart)
			if finalExitState ~= nil then
				applyFinalExitAttributes(routePart, FinalExitState.GetSnapshot(finalExitState))
			else
				applyFinalExitAttributes(routePart, nil)
			end
		end
	end

	function service.ResetFallbackEscapeForTests()
		fallbackEscapeStateByRouteId = {}
		for routeId, routePart in escapeRouteById do
			if isFallbackEscapeCandidate(routePart) then
				applyFallbackEscapeAttributes(routePart, FallbackEscapeState.GetSnapshot(FallbackEscapeState.NewState(buildFallbackEscapeConfig(routeId))))
			end
		end
	end

	function service.validateThroughGapReach(player: any, target: any, request: any?): boolean
		if player == nil or target == nil then
			return false
		end

		local grabServiceQueryApi = getGrabServiceQueryApi()
		if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.IsPlayerCarried) == "function" then
			if type(player.UserId) == "number" then
				local callerCarriedOk, callerCarried = pcall(function()
					return grabServiceQueryApi.IsPlayerCarried(player.UserId)
				end)
				if not callerCarriedOk then
					return false
				end
				if callerCarried == true then
					return false
				end
			end
			if type(target.UserId) == "number" then
				local targetCarriedOk, targetCarried = pcall(function()
					return grabServiceQueryApi.IsPlayerCarried(target.UserId)
				end)
				if not targetCarriedOk then
					return false
				end
				if targetCarried == true then
					return false
				end
			end
		end
		if
			grabServiceQueryApi ~= nil
			and type(grabServiceQueryApi.CanGiantPerformCarryInteraction) == "function"
			and type(player.UserId) == "number"
		then
			local carryInteractionOk, carryInteraction = pcall(function()
				return grabServiceQueryApi.CanGiantPerformCarryInteraction(player.UserId, "throughGapReach")
			end)
			if not carryInteractionOk then
				return false
			end
			if type(carryInteraction) == "table" and carryInteraction.accepted ~= true then
				return false
			end
		end

		if type(player.UserId) == "number" and isSafeZoneAbuseLocked(player.UserId, now()) then
			return false
		end

		if type(request) ~= "table" then
			return false
		end

		local requestTable = request :: any
		if type(requestTable.routeId) ~= "string" then
			return false
		end

		local routeId = requestTable.routeId :: string
		local routePart = resolveRoutePart(routeId)
		if routePart == nil then
			return false
		end
		if routeRejectsTraversal(routeId, routePart) then
			return false
		end

		local callerRoot = getHumanoidRootPart(player)
		local targetRoot = getHumanoidRootPart(target)
		if callerRoot == nil or targetRoot == nil then
			return false
		end

		if type(target.UserId) ~= "number" then
			return false
		end

		local targetByUserId = getPlayerByUserId(target.UserId)
		if targetByUserId == nil then
			return false
		end

		local routeAllowsThroughGapReach = routePart:GetAttribute(EscapeConfig.ThroughGapReachAllowedAttribute) == true

		local routeTypeValue = routePart:GetAttribute(EscapeConfig.RouteTypeAttribute)
		local routeType = if type(routeTypeValue) == "string" then routeTypeValue else nil

		local routeSafeZoneDecision = evaluateSafeZoneProtection(
			routePart:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
			routePart:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
			routePart:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
		)
		if routeSafeZoneDecision.protected == true then
			noteSafeZoneAbuse(player.UserId, now())
			return false
		end

		local crossingPhaseValid = false
		if type(target.GetAttribute) == "function" then
			crossingPhaseValid = target:GetAttribute(EscapeConfig.CrossingPhaseAttribute)
				== EscapeConfig.RequiredCrossingPhase
		end

		local targetSafeZoneState = false
		local targetSafeZoneType = nil
		local targetSafeZoneProtectionEndsAt = nil
		if type(target.GetAttribute) == "function" then
			targetSafeZoneState = target:GetAttribute(EscapeConfig.SafeZoneAttribute) == true
			targetSafeZoneType = target:GetAttribute(EscapeConfig.SafeZoneTypeAttribute)
			targetSafeZoneProtectionEndsAt = target:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
		end
		local targetSafeZoneDecision =
			evaluateSafeZoneProtection(targetSafeZoneState, targetSafeZoneType, targetSafeZoneProtectionEndsAt)
		if targetSafeZoneDecision.protected == true then
			noteSafeZoneAbuse(player.UserId, now())
			return false
		end

		local lineOfSightCheck = resolveLineOfSightCheck(requestTable)

		local callerRole = RoleConfig.Roles.Giant
		if type(player.GetAttribute) == "function" then
			local role = player:GetAttribute("Role")
			if type(role) == "string" then
				callerRole = role
			end
		end

		local targetRole = RoleConfig.Roles.Tinyfolk
		if type(target.GetAttribute) == "function" then
			local role = target:GetAttribute("Role")
			if type(role) == "string" then
				targetRole = role
			end
		end

		local result = ThroughGapValidation.ValidateReachAttempt({
			EscapeConfig = EscapeConfig,
			RoleConfig = RoleConfig,
		}, {
			callerRole = callerRole,
			targetRole = targetRole,
			routeType = routeType,
			routeAllowsThroughGapReach = routeAllowsThroughGapReach,
			callerPosition = (callerRoot :: any).Position,
			targetPosition = (targetRoot :: any).Position,
			distanceThreshold = EscapeConfig.TriggerRadiusStuds,
			angleThreshold = nil,
			lineOfSightCheck = lineOfSightCheck,
			safeZoneState = targetSafeZoneDecision.protected,
			crossingPhaseValid = crossingPhaseValid,
		})

		return result.valid == true
	end

	local function initialize()
		local remotesFolder = ensureRemotesFolder()
		if remotesFolder == nil then
			return
		end

		local escapeAttemptRemote = ensureRemoteEvent(remotesFolder, ESCAPE_ATTEMPT_REMOTE_NAME)
		local escapeDebugRequestRemote = ensureRemoteEvent(remotesFolder, ESCAPE_DEBUG_REQUEST_REMOTE_NAME)
		local escapeDebugResponseRemote = ensureRemoteEvent(remotesFolder, ESCAPE_DEBUG_RESPONSE_REMOTE_NAME)
		local traversalGapBlockRequestRemote = ensureRemoteEvent(remotesFolder, TRAVERSAL_GAP_BLOCK_REQUEST_REMOTE_NAME)
		if
			escapeAttemptRemote == nil
			or escapeDebugRequestRemote == nil
			or escapeDebugResponseRemote == nil
			or traversalGapBlockRequestRemote == nil
		then
			return
		end

		local escapeAttemptRemoteEvent = escapeAttemptRemote :: RemoteEvent
		local escapeDebugRequestRemoteEvent = escapeDebugRequestRemote :: RemoteEvent
		local escapeDebugResponseRemoteEvent = escapeDebugResponseRemote :: RemoteEvent
		local traversalGapBlockRequestRemoteEvent = traversalGapBlockRequestRemote :: RemoteEvent

		registerEscapeRoutesFromWorkspace()

		escapeAttemptRemoteEvent.OnServerEvent:Connect(function(player: Player, payload: unknown)
			if isCoolingDown(player.UserId) then
				return
			end
			markRequest(player.UserId)

			if type(payload) ~= "string" then
				return
			end

			service.requestEscapeAttempt(player, payload)
		end)

		traversalGapBlockRequestRemoteEvent.OnServerEvent:Connect(function(player: Player, payload: unknown)
			if type(payload) ~= "string" then
				return
			end

			service.requestDash(player, payload)
		end)

		escapeDebugRequestRemoteEvent.OnServerEvent:Connect(function(player: Player, payload: unknown)
			if payload ~= nil and type(payload) ~= "string" then
				return
			end

			local requestedRouteId = payload :: string?
			if requestedRouteId ~= nil then
				local debugState = service.getDebugState(player, requestedRouteId)
				if debugState == nil then
					return
				end

				escapeDebugResponseRemoteEvent:FireClient(player, debugState)
				return
			end

			escapeDebugResponseRemoteEvent:FireClient(player, service.getDebugState(player, nil))
		end)

		if
			Players ~= nil
			and type(Players.PlayerAdded) == "table"
			and type(Players.PlayerAdded.Connect) == "function"
		then
			Players.PlayerAdded:Connect(function(player: Player)
				escapedTinyfolkByUserId[player.UserId] = false
				player:SetAttribute(ESCAPED_ATTRIBUTE, false)
			end)
		end

		if
			Players ~= nil
			and type(Players.PlayerRemoving) == "table"
			and type(Players.PlayerRemoving.Connect) == "function"
		then
			Players.PlayerRemoving:Connect(function(player: Player)
				lastRequestAtByUserId[player.UserId] = nil
				lastDashRequestAtByUserId[player.UserId] = nil
				safeZoneAbuseStateByUserId[player.UserId] = nil
				escapedTinyfolkByUserId[player.UserId] = nil
			end)
		end

		debugLog("EscapeService initialized")
	end

	service.initialize = initialize

	globalEnv._EscapeService_QueryAPI = {
		RequestDash = function(player: any, routeId: string): any
			return service.requestDash(player, routeId)
		end,
		ResolveTransportDeparture = function(endpointId: string, candidateTinyfolkUserIds: { number }): any
			return service.resolveTransportDeparture(endpointId, candidateTinyfolkUserIds)
		end,
		GetFinalExitSnapshot = function(routeId: string): any
			return service.getFinalExitSnapshot(routeId)
		end,
		GetFallbackEscapeSnapshot = function(routeId: string?): any
			return service.getFallbackEscapeSnapshot(routeId)
		end,
		RefreshFallbackEscapeState = function(routeId: string?): any
			return service.getFallbackEscapeSnapshot(routeId)
		end,
		RequestFallbackEscapeClose = function(player: any, routeId: string): any
			return service.requestFallbackEscapeClose(player, routeId)
		end,
		GetRouteAccess = function(player: any, routeId: string): any
			return service.getRouteAccess(player, routeId)
		end,
		GetObjectiveSafeRouteMetadata = function(routeId: string?): any
			return service.getObjectiveSafeRouteMetadata(routeId)
		end,
		ResolveRescueEntryRoute = function(targetUserId: number, targetRealmOwnerUserId: number): any
			return service.resolveRescueEntryRoute(targetUserId, targetRealmOwnerUserId)
		end,
	}

	if options == nil or options.autoInitialize ~= false then
		local ok, errorOrNil = pcall(initialize)
		if not ok then
			debugWarn(string.format("Initialization skipped due to runtime mismatch: %s", tostring(errorOrNil)))
		end
	end

	return service
end

return createEscapeService
