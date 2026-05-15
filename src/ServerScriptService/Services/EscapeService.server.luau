--!strict

local REMOTES_FOLDER_NAME = "Remotes"
local ESCAPE_ATTEMPT_REMOTE_NAME = "EscapeAttemptRequest"
local ESCAPE_DEBUG_REQUEST_REMOTE_NAME = "EscapeDebugStateRequest"
local ESCAPE_DEBUG_RESPONSE_REMOTE_NAME = "EscapeDebugStateResponse"

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

	local TinyfolkMovementTraitService: any = nil
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

	local service: any = {}

	function service.validateThroughGapReach(player: any, target: any, request: any?): boolean
		if player == nil or target == nil then
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

		local routeAllowsThroughGapReach =
			routePart:GetAttribute(EscapeConfig.ThroughGapReachAllowedAttribute) == true

		local routeTypeValue = routePart:GetAttribute(EscapeConfig.RouteTypeAttribute)
		local routeType = if type(routeTypeValue) == "string" then routeTypeValue else nil

		local crossingPhaseValid = false
		if type(target.GetAttribute) == "function" then
			crossingPhaseValid =
				target:GetAttribute(EscapeConfig.CrossingPhaseAttribute) == EscapeConfig.RequiredCrossingPhase
		end

		local safeZoneState = false
		if type(target.GetAttribute) == "function" then
			safeZoneState = target:GetAttribute(EscapeConfig.SafeZoneAttribute) == true
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
			safeZoneState = safeZoneState,
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
		if escapeAttemptRemote == nil or escapeDebugRequestRemote == nil or escapeDebugResponseRemote == nil then
			return
		end

		local escapeAttemptRemoteEvent = escapeAttemptRemote :: RemoteEvent
		local escapeDebugRequestRemoteEvent = escapeDebugRequestRemote :: RemoteEvent
		local escapeDebugResponseRemoteEvent = escapeDebugResponseRemote :: RemoteEvent

		registerEscapeRoutesFromWorkspace()

		escapeAttemptRemoteEvent.OnServerEvent:Connect(function(player: Player, payload: unknown)
			if isCoolingDown(player.UserId) then
				return
			end
			markRequest(player.UserId)

			if type(payload) ~= "string" then
				return
			end

			local routeId = payload
			local routePart = escapeRouteById[routeId]
			if routePart == nil then
				return
			end
			if not isTinyfolk(player) then
				return
			end
			if escapedTinyfolkByUserId[player.UserId] then
				return
			end
			if not isPlayerAlive(player) then
				return
			end

			local root = getHumanoidRootPart(player)
			if root == nil then
				return
			end

			local distance = (routePart.Position - root.Position).Magnitude
			if distance > EscapeConfig.TriggerRadiusStuds then
				return
			end

			escapedTinyfolkByUserId[player.UserId] = true
			player:SetAttribute(ESCAPED_ATTRIBUTE, true)

			local successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE)
			if type(successfulEscapes) ~= "number" then
				successfulEscapes = 0
			end
			routePart:SetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE, successfulEscapes + 1)
			trySendToTinyfolkMovementTraitService(player, routeId)
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

				escapeDebugResponseRemoteEvent:FireClient(player, {
					routeId = requestedRouteId,
					isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE),
					successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE),
					escaped = escapedTinyfolkByUserId[player.UserId] == true,
				})
				return
			end

			local snapshot = {}
			for routeId, routePart in escapeRouteById do
				table.insert(snapshot, {
					routeId = routeId,
					isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE),
					successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE),
				})
			end

			escapeDebugResponseRemoteEvent:FireClient(player, {
				routes = snapshot,
				escaped = escapedTinyfolkByUserId[player.UserId] == true,
			})
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
