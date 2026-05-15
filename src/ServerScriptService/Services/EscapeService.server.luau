--!strict

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
	local RoleConfig = resolveDependency(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	local ThroughGapValidation = resolveDependency(
		GiantRealm,
		"ThroughGapValidation",
		"../../ReplicatedStorage/Shared/GiantRealm/ThroughGapValidation"
	)
	local SafeZonePolicy = resolveDependency(
		GiantRealm,
		"SafeZonePolicy",
		"../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy"
	)
	local TraversalGapBlockState = resolveDependency(
		GiantRealm,
		"TraversalGapBlockState",
		"../../ReplicatedStorage/Shared/GiantRealm/TraversalGapBlockState"
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
	local lastBlockRequestAtByUserId: { [number]: number? } = {}
	local safeZoneAbuseStateByUserId: { [number]: any? } = {}

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

	local function isBlockRequestCoolingDown(userId: number): boolean
		local last = lastBlockRequestAtByUserId[userId]
		if last == nil then
			return false
		end

		return (now() - last) < EscapeConfig.TraversalGapBlockRequestCooldownSeconds
	end

	local function markBlockRequest(userId: number)
		lastBlockRequestAtByUserId[userId] = now()
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

		if
			type(windowSeconds) ~= "number"
			or type(threshold) ~= "number"
			or type(lockoutSeconds) ~= "number"
		then
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

	local function registerEscapeRoutePart(part: BasePart)
		local routeId = part.Name
		if escapeRouteById[routeId] then
			debugWarn(string.format("Duplicate escape route id ignored: %s", routeId))
			return
		end

		escapeRouteById[routeId] = part

		if part:GetAttribute(EscapeConfig.ThroughGapReachAllowedAttribute) == nil then
			part:SetAttribute(EscapeConfig.ThroughGapReachAllowedAttribute, false)
		end

		part:SetAttribute(ROUTE_ENABLED_ATTRIBUTE, true)
		part:SetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE, 0)
		part:SetAttribute(EscapeConfig.TraversalGapBlockStateAttribute, TraversalGapBlockState.States.Idle)
		part:SetAttribute(EscapeConfig.TraversalGapBlockStartupEndsAtAttribute, nil)
		part:SetAttribute(EscapeConfig.TraversalGapBlockActiveEndsAtAttribute, nil)
		part:SetAttribute(EscapeConfig.TraversalGapBlockExpiresAtAttribute, nil)
		part:SetAttribute(EscapeConfig.TraversalGapBlockedByUserIdAttribute, nil)
		if part:GetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute) == nil then
			part:SetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute, false)
		end
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
		TinyfolkMovementTraitService.OnValidRouteCrossing(player, routeId)
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
		if routePart ~= nil then
			return routePart
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

	local function routeRejectsTraversal(routeId: string, routePart: BasePart): boolean
		local currentTime = now()
		local snapshot = cleanupExpiredBlock(routeId, routePart, currentTime)
		return TraversalGapBlockState.ShouldRejectTraversal(
			traversalGapBlockByRouteId[routeId],
			currentTime,
			routeHasBlockExemption(routePart)
		)
	end

	local function buildRouteDebugPayload(routeId: string, routePart: BasePart, userId: number?): any
		local snapshot = getBlockSnapshot(routeId, routePart)
		local payload: any = {
			routeId = routeId,
			isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE),
			successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE),
			blockState = snapshot.state,
			blockStartupEndsAt = snapshot.startupEndsAt,
			blockActiveEndsAt = snapshot.activeEndsAt,
			blockExpiresAt = snapshot.expiresAt,
			blockedByUserId = snapshot.blockedByUserId,
			blockExempt = routeHasBlockExemption(routePart),
		}

		if userId ~= nil then
			payload.escaped = escapedTinyfolkByUserId[userId] == true
		end

		return payload
	end

	local service: any = {}

	function service.requestTraversalGapBlock(player: any, routeId: any): any
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
		if distance > EscapeConfig.TriggerRadiusStuds then
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

		if routeRejectsTraversal(routeId, routePart) then
			return { accepted = false, reason = "traversal_gap_block_active" }
		end

		escapedTinyfolkByUserId[player.UserId] = true
		player:SetAttribute(ESCAPED_ATTRIBUTE, true)

		local successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE)
		if type(successfulEscapes) ~= "number" then
			successfulEscapes = 0
		end
		routePart:SetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE, successfulEscapes + 1)
		trySendToTinyfolkMovementTraitService(player, routeId)

		return { accepted = true, reason = "accepted" }
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
		for registeredRouteId, routePart in escapeRouteById do
			table.insert(snapshot, buildRouteDebugPayload(registeredRouteId, routePart, nil))
		end

		return {
			routes = snapshot,
			escaped = if userId ~= nil then escapedTinyfolkByUserId[userId] == true else false,
		}
	end

	function service.ResetTraversalGapBlocksForTests()
		traversalGapBlockByRouteId = {}
		lastBlockRequestAtByUserId = {}
		safeZoneAbuseStateByUserId = {}
		for routeId, routePart in escapeRouteById do
			applyBlockAttributes(routePart, TraversalGapBlockState.Snapshot(nil, now()))
		end
	end

	function service.validateThroughGapReach(player: any, target: any, request: any?): boolean
		if player == nil or target == nil then
			return false
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
		local targetSafeZoneDecision = evaluateSafeZoneProtection(
			targetSafeZoneState,
			targetSafeZoneType,
			targetSafeZoneProtectionEndsAt
		)
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
			if isBlockRequestCoolingDown(player.UserId) then
				return
			end
			markBlockRequest(player.UserId)

			if type(payload) ~= "string" then
				return
			end

			service.requestTraversalGapBlock(player, payload)
		end)

		escapeDebugRequestRemoteEvent.OnServerEvent:Connect(function(player: Player, payload: unknown)
			if payload ~= nil and type(payload) ~= "string" then
				return
			end

			local requestedRouteId = payload :: string?
			if requestedRouteId ~= nil then
				local routePart = escapeRouteById[requestedRouteId]
				if routePart == nil then
					return
				end

				escapeDebugResponseRemoteEvent:FireClient(player, service.getDebugState(player, requestedRouteId))
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
				lastBlockRequestAtByUserId[player.UserId] = nil
				safeZoneAbuseStateByUserId[player.UserId] = nil
				escapedTinyfolkByUserId[player.UserId] = nil
			end)
		end

		debugLog("EscapeService initialized")
	end

	service.initialize = initialize

	if options == nil or options.autoInitialize ~= false then
		local ok, errorOrNil = pcall(initialize)
		if not ok then
			debugWarn(string.format("Initialization skipped due to runtime mismatch: %s", tostring(errorOrNil)))
		end
	end

	return service
end

return createEscapeService
