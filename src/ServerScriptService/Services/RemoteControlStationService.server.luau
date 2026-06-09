--!nocheck
-- RemoteControlStationService: bounded Giant station-zone route pressure for TIN-217.

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "RemoteControlStationRequest"
local DEBUG_REQUEST_REMOTE_NAME = "RemoteControlStationDebugRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "RemoteControlStationDebugResponse"

local CONTROL_ZONES_FOLDER_PATH = { "Map", "ControlZones" }
local STATIONS_FOLDER_PATH = { "Map", "Stations" }
local ESCAPE_ROUTES_FOLDER_PATH = { "Map", "EscapeRoutes" }

local ROUTE_ENABLED_ATTRIBUTE = "RouteEnabled"

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

local function createRemoteControlStationService(runtimeGame: any?, options: any?)
	local globalEnv: any = getfenv()
	local gameRef = runtimeGame or game
	local Players = getService(gameRef, "Players")
	local ReplicatedStorage = getService(gameRef, "ReplicatedStorage")
	local Workspace = getService(gameRef, "Workspace")
	local RunService = getService(gameRef, "RunService")

	local Shared = if ReplicatedStorage ~= nil and type(ReplicatedStorage.WaitForChild) == "function"
		then ReplicatedStorage:WaitForChild("Shared")
		else nil
	local Config = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("Config")
		else nil
	local GiantRealm = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("GiantRealm")
		else nil

	local RemoteControlStationConfig = resolveDependency(
		Config,
		"RemoteControlStationConfig",
		"../../ReplicatedStorage/Shared/Config/RemoteControlStationConfig"
	)
	local EscapeConfig = resolveDependency(Config, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
	local RoleConfig = resolveDependency(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	local SafeZonePolicy =
		resolveDependency(GiantRealm, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
	local RemoteControlStationState = resolveDependency(
		GiantRealm,
		"RemoteControlStationState",
		"../../ReplicatedStorage/Shared/GiantRealm/RemoteControlStationState"
	)
	local GiantRealmResourceState = resolveDependency(
		GiantRealm,
		"GiantRealmResourceState",
		"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState"
	)
	local StationConfig =
		resolveDependency(Config, "StationConfig", "../../ReplicatedStorage/Shared/Config/StationConfig")

	local function getVillageWorksiteUpgradeQueryApi(): any?
		if type(globalEnv._VillageWorksiteUpgradeService_QueryAPI) == "table" then
			return globalEnv._VillageWorksiteUpgradeService_QueryAPI
		end
		if type(_G) == "table" and type((_G :: any)._VillageWorksiteUpgradeService_QueryAPI) == "table" then
			return (_G :: any)._VillageWorksiteUpgradeService_QueryAPI
		end
		return nil
	end

	local function resolveDefenseMultiplier(): number
		local upgradeApi = getVillageWorksiteUpgradeQueryApi()
		if type(upgradeApi) == "table" and type(upgradeApi.GetDefenseMultiplier) == "function" then
			local resolvedMultiplier = upgradeApi.GetDefenseMultiplier(StationConfig.DefaultGuardTowerId)
			if type(resolvedMultiplier) == "number" and resolvedMultiplier > 0 then
				return resolvedMultiplier
			end
		end
		return 1
	end

	local function resolveRemoteControlConfig(): any
		local defenseMultiplier = resolveDefenseMultiplier()
		if defenseMultiplier == 1 then
			return RemoteControlStationConfig
		end
		return {
			StationNamePrefix = RemoteControlStationConfig.StationNamePrefix,
			ZoneNamePrefix = RemoteControlStationConfig.ZoneNamePrefix,
			DefaultStationId = RemoteControlStationConfig.DefaultStationId,
			DefaultZoneId = RemoteControlStationConfig.DefaultZoneId,
			InteractionRangeStuds = RemoteControlStationConfig.InteractionRangeStuds,
			SabotageRangeStuds = RemoteControlStationConfig.SabotageRangeStuds,
			RequestCooldownSeconds = RemoteControlStationConfig.RequestCooldownSeconds,
			SabotageTaskDurationSeconds = RemoteControlStationConfig.SabotageTaskDurationSeconds,
			MaxEnergy = RemoteControlStationConfig.MaxEnergy,
			InitialEnergy = RemoteControlStationConfig.InitialEnergy,
			PressureEnergyCost = RemoteControlStationConfig.PressureEnergyCost,
			EnergyRecoverySeconds = RemoteControlStationConfig.EnergyRecoverySeconds,
			EnergyRecoveryAmount = RemoteControlStationConfig.EnergyRecoveryAmount,
			SabotageEnergyDrain = RemoteControlStationConfig.SabotageEnergyDrain,
			SabotageLockoutSeconds = RemoteControlStationConfig.SabotageLockoutSeconds,
			BarrierWarningSeconds = RemoteControlStationConfig.BarrierWarningSeconds * defenseMultiplier,
			BarrierActiveSeconds = RemoteControlStationConfig.BarrierActiveSeconds * defenseMultiplier,
			Mode = RemoteControlStationConfig.Mode,
			BarrierState = RemoteControlStationConfig.BarrierState,
			StationActiveOperatorUserIdAttribute = RemoteControlStationConfig.StationActiveOperatorUserIdAttribute,
			StationEnergyAttribute = RemoteControlStationConfig.StationEnergyAttribute,
			StationLockoutEndsAtAttribute = RemoteControlStationConfig.StationLockoutEndsAtAttribute,
			StationZoneIdAttribute = RemoteControlStationConfig.StationZoneIdAttribute,
			RouteBarrierStateAttribute = RemoteControlStationConfig.RouteBarrierStateAttribute,
			RouteBarrierWarningEndsAtAttribute = RemoteControlStationConfig.RouteBarrierWarningEndsAtAttribute,
			RouteBarrierActiveEndsAtAttribute = RemoteControlStationConfig.RouteBarrierActiveEndsAtAttribute,
			RouteBarrierExpiresAtAttribute = RemoteControlStationConfig.RouteBarrierExpiresAtAttribute,
			RouteBarrierByUserIdAttribute = RemoteControlStationConfig.RouteBarrierByUserIdAttribute,
			RouteBarrierStationIdAttribute = RemoteControlStationConfig.RouteBarrierStationIdAttribute,
		}
	end

	local function getGiantRealmResourceResolver(): any?
		if
			type(globalEnv._GiantRealmResourceResolver) == "table"
			and type(globalEnv._GiantRealmResourceResolver.Create) == "function"
		then
			return globalEnv._GiantRealmResourceResolver.Create()
		end

		local ok, moduleValue = pcall(function()
			return require("../../ServerScriptService/Services/GiantRealmResourceResolver")
		end)
		if not ok or type(moduleValue) ~= "table" or type(moduleValue.Create) ~= "function" then
			return nil
		end
		return moduleValue.Create()
	end

	local function getBuildModeQueryApi(): any?
		if type(globalEnv._GiantBuildModeService_QueryAPI) == "table" then
			return globalEnv._GiantBuildModeService_QueryAPI
		end
		if type(_G) == "table" and type((_G :: any)._GiantBuildModeService_QueryAPI) == "table" then
			return (_G :: any)._GiantBuildModeService_QueryAPI
		end
		return nil
	end

	local function awardDefendedRaidRoutePressure(
		stationId: string,
		routeId: string,
		warningStartedAt: number,
		at: number
	)
		local buildApi = getBuildModeQueryApi()
		local ownerUserId = if type(buildApi) == "table" and type(buildApi.GetRealmOwnerUserId) == "function"
			then buildApi.GetRealmOwnerUserId()
			else nil
		if type(ownerUserId) ~= "number" or ownerUserId <= 0 then
			return
		end

		local resolver = getGiantRealmResourceResolver()
		if resolver == nil or type(resolver.Resolve) ~= "function" then
			return
		end

		pcall(resolver.Resolve, {
			sourceKind = GiantRealmResourceState.SourceKinds.DefendedRaidRoutePressure,
			operationId = string.format(
				"realm-resource:defended-raid:%s:%s:%.6f",
				stationId,
				routeId,
				warningStartedAt
			),
			ownerUserId = ownerUserId,
			at = at,
			metadata = {
				stationId = stationId,
				routeId = routeId,
				warningStartedAt = warningStartedAt,
				defenseMultiplier = resolveDefenseMultiplier(),
			},
		})
	end

	local stationStateById: { [string]: any } = {}
	local stationPartById: { [string]: any } = {}
	local zonePartById: { [string]: any } = {}
	local routePartById: { [string]: any } = {}
	local barrierByRouteId: { [string]: any } = {}
	local lastRequestAtByUserId: { [number]: number? } = {}

	local function debugWarn(message: string)
		warn(string.format("[RemoteControlStationService] %s", message))
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

	local function getNestedRoot(pathParts: { string }): any
		if Workspace == nil then
			return nil
		end
		local current: any = Workspace
		for _, childName in ipairs(pathParts) do
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

	local function startsWithPrefix(name: string, prefix: string): boolean
		return string.match(name, "^" .. prefix) ~= nil
	end

	local function isBasePart(node: any): boolean
		return node ~= nil and type(node.IsA) == "function" and node:IsA("BasePart")
	end

	local function getDescendants(root: any): { any }
		if root == nil or type(root.GetDescendants) ~= "function" then
			return {}
		end
		local ok, result = pcall(function()
			return root:GetDescendants()
		end)
		return if ok and type(result) == "table" then result else {}
	end

	local function getCoordinate(position: any, keyUpper: string, keyLower: string): number?
		if type(position) ~= "table" then
			return nil
		end
		if type(position[keyUpper]) == "number" then
			return position[keyUpper]
		end
		if type(position[keyLower]) == "number" then
			return position[keyLower]
		end
		return nil
	end

	local function getPosition(part: any): any
		return if part ~= nil then part.Position else nil
	end

	local function horizontalDistance(a: any, b: any): number?
		local ax = getCoordinate(a, "X", "x")
		local az = getCoordinate(a, "Z", "z")
		local bx = getCoordinate(b, "X", "x")
		local bz = getCoordinate(b, "Z", "z")
		if ax == nil or az == nil or bx == nil or bz == nil then
			return nil
		end
		local dx = ax - bx
		local dz = az - bz
		return math.sqrt((dx * dx) + (dz * dz))
	end

	local function distanceBetween(a: any, b: any): number?
		local ax = getCoordinate(a, "X", "x")
		local ay = getCoordinate(a, "Y", "y")
		local az = getCoordinate(a, "Z", "z")
		local bx = getCoordinate(b, "X", "x")
		local by = getCoordinate(b, "Y", "y")
		local bz = getCoordinate(b, "Z", "z")
		if ax == nil or ay == nil or az == nil or bx == nil or by == nil or bz == nil then
			return nil
		end
		local dx = ax - bx
		local dy = ay - by
		local dz = az - bz
		return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
	end

	local function readNumberValueChild(part: any, childName: string): number?
		if part == nil or type(part.FindFirstChild) ~= "function" then
			return nil
		end
		local child = part:FindFirstChild(childName)
		if child ~= nil and type(child.Value) == "number" then
			return child.Value
		end
		return nil
	end

	local function partInsideZone(part: any, zonePart: any): boolean
		local radius = readNumberValueChild(zonePart, "Radius")
		if type(radius) == "number" then
			local dist = horizontalDistance(getPosition(part), getPosition(zonePart))
			return dist ~= nil and dist <= radius
		end

		local px = getCoordinate(getPosition(part), "X", "x")
		local pz = getCoordinate(getPosition(part), "Z", "z")
		local zx = getCoordinate(getPosition(zonePart), "X", "x")
		local zz = getCoordinate(getPosition(zonePart), "Z", "z")
		local sx = getCoordinate(zonePart.Size, "X", "x")
		local sz = getCoordinate(zonePart.Size, "Z", "z")
		if px == nil or pz == nil or zx == nil or zz == nil or sx == nil or sz == nil then
			return false
		end
		return math.abs(px - zx) <= (sx / 2) and math.abs(pz - zz) <= (sz / 2)
	end

	local function getHumanoidRootPart(player: any): any
		if player == nil or player.Character == nil or type(player.Character.FindFirstChild) ~= "function" then
			return nil
		end
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if isBasePart(root) then
			return root
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
		return humanoid ~= nil and humanoid.Health > 0
	end

	local function getRole(player: any): string?
		if player == nil or type(player.GetAttribute) ~= "function" then
			return nil
		end
		local role = player:GetAttribute("Role")
		return if type(role) == "string" then role else nil
	end

	local function isCoolingDown(userId: number): boolean
		local last = lastRequestAtByUserId[userId]
		return type(last) == "number" and (now() - last) < RemoteControlStationConfig.RequestCooldownSeconds
	end

	local function markRequest(userId: number)
		lastRequestAtByUserId[userId] = now()
	end

	local function getEventLogQueryApi(): any?
		local globalValue: any = globalEnv
		if type(globalValue) == "table" and type(globalValue._EventLogService_QueryAPI) == "table" then
			return globalValue._EventLogService_QueryAPI
		end
		if type(_G) == "table" and type((_G :: any)._EventLogService_QueryAPI) == "table" then
			return (_G :: any)._EventLogService_QueryAPI
		end
		return nil
	end

	local function recordEvent(message: string, metadata: any?)
		local eventLog = getEventLogQueryApi()
		if eventLog ~= nil and type(eventLog.RecordEvent) == "function" then
			pcall(function()
				eventLog.RecordEvent("remote_control_station", message, "info", now(), metadata)
			end)
		end
	end

	local function applyStationAttributes(stationId: string)
		local stationPart = stationPartById[stationId]
		local state = stationStateById[stationId]
		if stationPart == nil or state == nil or type(stationPart.SetAttribute) ~= "function" then
			return
		end
		stationPart:SetAttribute(
			RemoteControlStationConfig.StationActiveOperatorUserIdAttribute,
			state.activeOperatorUserId
		)
		stationPart:SetAttribute(RemoteControlStationConfig.StationEnergyAttribute, state.energy)
		stationPart:SetAttribute(RemoteControlStationConfig.StationLockoutEndsAtAttribute, state.lockoutEndsAt)
		stationPart:SetAttribute(RemoteControlStationConfig.StationZoneIdAttribute, state.zoneId)
	end

	local function applyBarrierAttributes(routePart: any, snapshot: any)
		if routePart == nil or type(routePart.SetAttribute) ~= "function" then
			return
		end
		routePart:SetAttribute(RemoteControlStationConfig.RouteBarrierStateAttribute, snapshot.state)
		routePart:SetAttribute(RemoteControlStationConfig.RouteBarrierWarningEndsAtAttribute, snapshot.warningEndsAt)
		routePart:SetAttribute(RemoteControlStationConfig.RouteBarrierActiveEndsAtAttribute, snapshot.activeEndsAt)
		routePart:SetAttribute(RemoteControlStationConfig.RouteBarrierExpiresAtAttribute, snapshot.expiresAt)
		routePart:SetAttribute(RemoteControlStationConfig.RouteBarrierByUserIdAttribute, snapshot.createdByUserId)
		routePart:SetAttribute(RemoteControlStationConfig.RouteBarrierStationIdAttribute, snapshot.stationId)
	end

	local function cleanupBarrier(routeId: string): any
		local routePart = routePartById[routeId]
		local record = barrierByRouteId[routeId]
		local snapshot = RemoteControlStationState.GetBarrierSnapshot(RemoteControlStationConfig, record, now())
		if snapshot.state == RemoteControlStationConfig.BarrierState.Expired then
			barrierByRouteId[routeId] = nil
			snapshot = RemoteControlStationState.GetBarrierSnapshot(RemoteControlStationConfig, nil, now())
		end
		applyBarrierAttributes(routePart, snapshot)
		return snapshot
	end

	local function registerControlZones()
		local root = getNestedRoot(CONTROL_ZONES_FOLDER_PATH)
		for _, descendant in ipairs(getDescendants(root)) do
			if
				isBasePart(descendant) and startsWithPrefix(descendant.Name, RemoteControlStationConfig.ZoneNamePrefix)
			then
				zonePartById[descendant.Name] = descendant
			end
		end
	end

	local function registerRoutes()
		local root = getNestedRoot(ESCAPE_ROUTES_FOLDER_PATH)
		for _, descendant in ipairs(getDescendants(root)) do
			if isBasePart(descendant) and startsWithPrefix(descendant.Name, EscapeConfig.EscapeRouteNamePrefix) then
				routePartById[descendant.Name] = descendant
				applyBarrierAttributes(
					descendant,
					RemoteControlStationState.GetBarrierSnapshot(
						RemoteControlStationConfig,
						barrierByRouteId[descendant.Name],
						now()
					)
				)
			end
		end
	end

	local function resolveZoneIdForStation(stationPart: any): string
		if type(stationPart.GetAttribute) == "function" then
			local attr = stationPart:GetAttribute(RemoteControlStationConfig.StationZoneIdAttribute)
			if type(attr) == "string" and attr ~= "" then
				return attr
			end
		end
		local suffix = string.gsub(stationPart.Name, "^" .. RemoteControlStationConfig.StationNamePrefix, "")
		return RemoteControlStationConfig.ZoneNamePrefix .. suffix
	end

	local function registerStations()
		local root = getNestedRoot(STATIONS_FOLDER_PATH)
		for _, descendant in ipairs(getDescendants(root)) do
			if
				isBasePart(descendant)
				and startsWithPrefix(descendant.Name, RemoteControlStationConfig.StationNamePrefix)
			then
				stationPartById[descendant.Name] = descendant
				if stationStateById[descendant.Name] == nil then
					stationStateById[descendant.Name] = RemoteControlStationState.NewStation(
						RemoteControlStationConfig,
						descendant.Name,
						resolveZoneIdForStation(descendant),
						now()
					)
				end
				applyStationAttributes(descendant.Name)
			end
		end
	end

	local function refreshRegistries()
		stationPartById = {}
		zonePartById = {}
		routePartById = {}
		registerControlZones()
		registerRoutes()
		registerStations()
		for stationId in pairs(stationStateById) do
			if stationPartById[stationId] == nil then
				stationStateById[stationId] = nil
			end
		end
		for routeId in pairs(barrierByRouteId) do
			if routePartById[routeId] == nil then
				barrierByRouteId[routeId] = nil
			end
		end
	end

	local function recoverStationEnergy(stationId: string)
		local state = stationStateById[stationId]
		if state ~= nil then
			RemoteControlStationState.RecoverEnergy(RemoteControlStationConfig, state, now())
			applyStationAttributes(stationId)
		end
	end

	local function validateStationPlayer(player: any, stationId: any, expectedRole: string, rangeStuds: number): any
		if type(stationId) ~= "string" or stationId == "" then
			return { accepted = false, reason = "station_id_invalid" }
		end
		refreshRegistries()
		local stationPart = stationPartById[stationId]
		if stationPart == nil then
			return { accepted = false, reason = "station_not_found" }
		end
		if player == nil or type(player.UserId) ~= "number" then
			return { accepted = false, reason = "user_id_invalid" }
		end
		if getRole(player) ~= expectedRole then
			return {
				accepted = false,
				reason = if expectedRole == RoleConfig.Roles.Giant
					then "requester_not_giant"
					else "requester_not_tinyfolk",
			}
		end
		if not isPlayerAlive(player) then
			return { accepted = false, reason = "player_not_alive" }
		end
		local root = getHumanoidRootPart(player)
		if root == nil then
			return { accepted = false, reason = "humanoid_root_missing" }
		end
		local distance = distanceBetween(getPosition(stationPart), getPosition(root))
		if distance == nil then
			return { accepted = false, reason = "distance_unavailable" }
		end
		if distance > rangeStuds then
			return { accepted = false, reason = "station_out_of_range" }
		end
		return {
			accepted = true,
			reason = "accepted",
			stationPart = stationPart,
			stationState = stationStateById[stationId],
		}
	end

	local function getRouteProtectionDecision(routePart: any): any
		if routePart == nil or type(routePart.GetAttribute) ~= "function" then
			return { protected = true, reason = "route_metadata_unavailable" }
		end
		return SafeZonePolicy.EvaluateProtection(EscapeConfig, {
			safeZoneState = routePart:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
			safeZoneType = routePart:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
			safeZoneProtectionEndsAt = routePart:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute),
			now = now(),
		})
	end

	local function isRouteEligibleAsUnpressuredEscape(routeId: string, routePart: any): boolean
		if routePart == nil or type(routePart.GetAttribute) ~= "function" then
			return false
		end
		if routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) == false then
			return false
		end
		if routePart:GetAttribute(EscapeConfig.TinyfolkOnlyRouteAttribute) ~= true then
			return false
		end
		if routePart:GetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute) == true then
			return false
		end
		if getRouteProtectionDecision(routePart).protected == true then
			return false
		end
		local localBlockState = routePart:GetAttribute(EscapeConfig.TraversalGapBlockStateAttribute)
		if localBlockState ~= nil and localBlockState ~= "Idle" and localBlockState ~= "Expired" then
			return false
		end
		local snapshot = cleanupBarrier(routeId)
		return snapshot.state ~= RemoteControlStationConfig.BarrierState.Warning
			and snapshot.state ~= RemoteControlStationConfig.BarrierState.Active
	end

	local function wouldLeaveUnpressuredEscapeRoute(targetRouteId: string): boolean
		for routeId, routePart in pairs(routePartById) do
			if routeId ~= targetRouteId and isRouteEligibleAsUnpressuredEscape(routeId, routePart) then
				return true
			end
		end
		return false
	end

	local function validateRoutePressure(stationState: any, routeId: any): any
		if type(routeId) ~= "string" or routeId == "" then
			return { accepted = false, reason = "route_id_invalid" }
		end
		refreshRegistries()
		local routePart = routePartById[routeId]
		if routePart == nil then
			return { accepted = false, reason = "route_not_found" }
		end
		local zonePart = zonePartById[stationState.zoneId]
		if zonePart == nil then
			return { accepted = false, reason = "control_zone_not_found" }
		end
		if not partInsideZone(routePart, zonePart) then
			return { accepted = false, reason = "route_outside_control_zone" }
		end
		if type(routePart.GetAttribute) == "function" then
			if routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE) == false then
				return { accepted = false, reason = "route_disabled" }
			end
			if routePart:GetAttribute(EscapeConfig.TinyfolkOnlyRouteAttribute) ~= true then
				return { accepted = false, reason = "route_not_tinyfolk_only" }
			end
			if routePart:GetAttribute(EscapeConfig.TraversalGapBlockExemptAttribute) == true then
				return { accepted = false, reason = "route_block_exempt" }
			end
			local localBlockState = routePart:GetAttribute(EscapeConfig.TraversalGapBlockStateAttribute)
			if localBlockState ~= nil and localBlockState ~= "Idle" and localBlockState ~= "Expired" then
				return { accepted = false, reason = "traversal_gap_block_active" }
			end
			local routeProtectionDecision = getRouteProtectionDecision(routePart)
			if routeProtectionDecision.protected == true then
				return { accepted = false, reason = tostring(routeProtectionDecision.reason or "route_in_safe_zone") }
			end
		end
		local snapshot = cleanupBarrier(routeId)
		if snapshot.state == RemoteControlStationConfig.BarrierState.Warning then
			return { accepted = false, reason = "remote_barrier_warning" }
		end
		if snapshot.state == RemoteControlStationConfig.BarrierState.Active then
			return { accepted = false, reason = "remote_barrier_active" }
		end
		if not wouldLeaveUnpressuredEscapeRoute(routeId) then
			return { accepted = false, reason = "would_seal_all_routes" }
		end
		return { accepted = true, reason = "accepted", routePart = routePart }
	end

	local service: any = {}

	function service.requestEnter(player: any, stationId: any): any
		local validation = validateStationPlayer(
			player,
			stationId,
			RoleConfig.Roles.Giant,
			RemoteControlStationConfig.InteractionRangeStuds
		)
		if validation.accepted ~= true then
			return validation
		end
		recoverStationEnergy(stationId)
		local result = RemoteControlStationState.Enter(validation.stationState, player.UserId, now())
		applyStationAttributes(stationId)
		if result.accepted == true then
			recordEvent("control station entered", { stationId = stationId, userId = player.UserId })
		end
		return {
			accepted = result.accepted,
			reason = result.reason,
			snapshot = RemoteControlStationState.GetStationSnapshot(validation.stationState),
		}
	end

	function service.requestExit(player: any, stationId: any): any
		local validation = validateStationPlayer(
			player,
			stationId,
			RoleConfig.Roles.Giant,
			RemoteControlStationConfig.InteractionRangeStuds
		)
		if validation.accepted ~= true then
			return validation
		end
		local result = RemoteControlStationState.Exit(validation.stationState, player.UserId)
		applyStationAttributes(stationId)
		return {
			accepted = result.accepted,
			reason = result.reason,
			snapshot = RemoteControlStationState.GetStationSnapshot(validation.stationState),
		}
	end

	function service.requestRoutePressure(player: any, stationId: any, routeId: any): any
		local validation = validateStationPlayer(
			player,
			stationId,
			RoleConfig.Roles.Giant,
			RemoteControlStationConfig.InteractionRangeStuds
		)
		if validation.accepted ~= true then
			return validation
		end
		recoverStationEnergy(stationId)
		local routeValidation = validateRoutePressure(validation.stationState, routeId)
		if routeValidation.accepted ~= true then
			return routeValidation
		end
		local result = RemoteControlStationState.CreateBarrier(resolveRemoteControlConfig(), validation.stationState, {
			routeId = routeId,
			createdByUserId = player.UserId,
			now = now(),
			existingRecord = barrierByRouteId[routeId],
		})
		if result.accepted == true and result.record ~= nil then
			barrierByRouteId[routeId] = result.record
		end
		local barrierSnapshot = cleanupBarrier(routeId)
		applyStationAttributes(stationId)
		if result.accepted == true then
			recordEvent(
				"remote route pressure accepted",
				{ stationId = stationId, routeId = routeId, userId = player.UserId }
			)
			if type(result.record) == "table" and type(result.record.warningStartedAt) == "number" then
				awardDefendedRaidRoutePressure(stationId, routeId, result.record.warningStartedAt, now())
			end
		end
		return {
			accepted = result.accepted,
			reason = result.reason,
			stationSnapshot = RemoteControlStationState.GetStationSnapshot(validation.stationState),
			barrierSnapshot = barrierSnapshot,
		}
	end

	function service.requestSabotage(player: any, stationId: any): any
		local validation = validateStationPlayer(
			player,
			stationId,
			RoleConfig.Roles.Tinyfolk,
			RemoteControlStationConfig.SabotageRangeStuds
		)
		if validation.accepted ~= true then
			return validation
		end
		local result = RemoteControlStationState.ApplySabotage(
			RemoteControlStationConfig,
			validation.stationState,
			player.UserId,
			now()
		)
		applyStationAttributes(stationId)
		if result.accepted == true then
			recordEvent("control station sabotaged", { stationId = stationId, userId = player.UserId })
		end
		return {
			accepted = result.accepted,
			reason = result.reason,
			snapshot = RemoteControlStationState.GetStationSnapshot(validation.stationState),
		}
	end

	function service.handleRequest(player: any, payload: any): any
		if type(payload) ~= "table" then
			return { accepted = false, reason = "payload_invalid" }
		end
		if player ~= nil and type(player.UserId) == "number" then
			if isCoolingDown(player.UserId) then
				return { accepted = false, reason = "request_cooldown" }
			end
			markRequest(player.UserId)
		end
		local stationId = payload.stationId
		local mode = payload.mode
		if mode == RemoteControlStationConfig.Mode.Enter then
			return service.requestEnter(player, stationId)
		end
		if mode == RemoteControlStationConfig.Mode.Exit then
			return service.requestExit(player, stationId)
		end
		if mode == RemoteControlStationConfig.Mode.Pressure then
			return service.requestRoutePressure(player, stationId, payload.routeId)
		end
		if mode == RemoteControlStationConfig.Mode.Sabotage then
			return service.requestSabotage(player, stationId)
		end
		return { accepted = false, reason = "mode_invalid" }
	end

	function service.getStationSnapshot(stationId: any): any
		refreshRegistries()
		if type(stationId) ~= "string" then
			return nil
		end
		local state = stationStateById[stationId]
		if state == nil then
			return nil
		end
		recoverStationEnergy(stationId)
		return RemoteControlStationState.GetStationSnapshot(state)
	end

	function service.getAllStationSnapshots(): any
		refreshRegistries()
		local snapshots = {}
		for stationId in pairs(stationStateById) do
			table.insert(snapshots, service.getStationSnapshot(stationId))
		end
		table.sort(snapshots, function(a: any, b: any)
			return tostring(a.stationId) < tostring(b.stationId)
		end)
		return snapshots
	end

	function service.getBarrierSnapshot(routeId: any): any
		if type(routeId) ~= "string" then
			return nil
		end
		refreshRegistries()
		return cleanupBarrier(routeId)
	end

	function service.isRouteRemoteBarrierActive(routeId: any): boolean
		local snapshot = service.getBarrierSnapshot(routeId)
		return type(snapshot) == "table" and snapshot.state == RemoteControlStationConfig.BarrierState.Active
	end

	function service.ResetForTests()
		stationStateById = {}
		stationPartById = {}
		zonePartById = {}
		routePartById = {}
		barrierByRouteId = {}
		lastRequestAtByUserId = {}
		refreshRegistries()
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

	local function ensureRemoteEvent(parentFolder: any, remoteName: string): any
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

	local function initialize()
		refreshRegistries()
		local remotesFolder = ensureRemotesFolder()
		local requestRemote = ensureRemoteEvent(remotesFolder, REQUEST_REMOTE_NAME)
		local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
		local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)
		if
			requestRemote ~= nil
			and type(requestRemote.OnServerEvent) == "table"
			and type(requestRemote.OnServerEvent.Connect) == "function"
		then
			requestRemote.OnServerEvent:Connect(function(player: any, payload: any)
				service.handleRequest(player, payload)
			end)
		end
		if
			debugRequestRemote ~= nil
			and debugResponseRemote ~= nil
			and type(debugRequestRemote.OnServerEvent) == "table"
			and type(debugRequestRemote.OnServerEvent.Connect) == "function"
			and type(debugResponseRemote.FireClient) == "function"
		then
			debugRequestRemote.OnServerEvent:Connect(function(player: any, payload: any)
				if type(payload) == "string" then
					debugResponseRemote:FireClient(player, service.getStationSnapshot(payload))
				else
					debugResponseRemote:FireClient(player, service.getAllStationSnapshots())
				end
			end)
		end
		if
			RunService ~= nil
			and type(RunService.Heartbeat) == "table"
			and type(RunService.Heartbeat.Connect) == "function"
		then
			RunService.Heartbeat:Connect(function()
				for stationId in pairs(stationStateById) do
					recoverStationEnergy(stationId)
				end
				for routeId in pairs(barrierByRouteId) do
					cleanupBarrier(routeId)
				end
			end)
		end
		if
			Players ~= nil
			and type(Players.PlayerRemoving) == "table"
			and type(Players.PlayerRemoving.Connect) == "function"
		then
			Players.PlayerRemoving:Connect(function(player: any)
				lastRequestAtByUserId[player.UserId] = nil
				for stationId, state in pairs(stationStateById) do
					if state.activeOperatorUserId == player.UserId then
						state.activeOperatorUserId = nil
						applyStationAttributes(stationId)
					end
				end
			end)
		end
	end

	service.initialize = initialize

	globalEnv._RemoteControlStationService_QueryAPI = {
		GetStationSnapshot = function(stationId: string): any
			return service.getStationSnapshot(stationId)
		end,
		GetAllStationSnapshots = function(): any
			return service.getAllStationSnapshots()
		end,
		RequestRoutePressure = function(player: any, stationId: string, routeId: string): any
			return service.requestRoutePressure(player, stationId, routeId)
		end,
		RequestSabotage = function(player: any, stationId: string): any
			return service.requestSabotage(player, stationId)
		end,
		IsRouteRemoteBarrierActive = function(routeId: string): boolean
			return service.isRouteRemoteBarrierActive(routeId)
		end,
		GetRouteBarrierSnapshot = function(routeId: string): any
			return service.getBarrierSnapshot(routeId)
		end,
	}

	if type(_G) == "table" then
		rawset(_G, "_RemoteControlStationService_QueryAPI", globalEnv._RemoteControlStationService_QueryAPI)
	end

	if options == nil or options.autoInitialize ~= false then
		local ok, errorOrNil = pcall(initialize)
		if not ok then
			debugWarn(string.format("Initialization skipped due to runtime mismatch: %s", tostring(errorOrNil)))
		end
	end

	return service
end

return createRemoteControlStationService
