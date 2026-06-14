--!nocheck
-- DefensivePropService: bounded Tinyfolk defensive prop obstacles for TIN-161.

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "DefensivePropRequest"

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

local function createDefensivePropService(runtimeGame: any?, options: any?)
	local globalEnv: any = getfenv()
	local gameRef = runtimeGame or game
	local _Players = getService(gameRef, "Players")
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

	local DefensivePropConfig =
		resolveDependency(Config, "DefensivePropConfig", "../../ReplicatedStorage/Shared/Config/DefensivePropConfig")
	local RoleConfig = resolveDependency(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	local EscapeConfig = resolveDependency(Config, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
	local DefensivePropState = resolveDependency(
		GiantRealm,
		"DefensivePropState",
		"../../ReplicatedStorage/Shared/GiantRealm/DefensivePropState"
	)

	local function now(): number
		if options ~= nil and type(options.now) == "function" then
			return options.now()
		end
		return os.clock()
	end

	local function debugWarn(message: string)
		warn(string.format("[DefensivePropService] %s", message))
	end

	local propPartById: { [string]: any } = {}
	local zonePartById: { [string]: any } = {}
	local giantRoutePartById: { [string]: any } = {}
	local propRecordById: { [string]: any? } = {}
	local lastDropRequestAtByUserId: { [number]: number? } = {}
	local lastBreakRequestAtByUserId: { [number]: number? } = {}
	local lastBarrierContactAtByUserIdByPropId: { [string]: { [number]: number? } } = {}
	local scheduledTasks: { thread? } = {}
	local lastGiantBarrierContactScanAt = 0

	local function getNestedRoot(folderPath: { string }): any
		if Workspace == nil or type(Workspace.FindFirstChild) ~= "function" then
			return nil
		end
		local current: any = Workspace
		for _, childName in folderPath do
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
		return player.Character:FindFirstChild("HumanoidRootPart")
	end

	local function getRole(player: any): string?
		if player == nil or type(player.GetAttribute) ~= "function" then
			return nil
		end
		local role = player:GetAttribute("Role")
		return if type(role) == "string" then role else nil
	end

	local function isPlayerAlive(player: any): boolean
		if player == nil or player.Character == nil then
			return false
		end
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then
			return false
		end
		return humanoid.Health > 0
	end

	local function resolvePropType(propPart: any): string
		if type(propPart.GetAttribute) == "function" then
			local attr = propPart:GetAttribute(DefensivePropConfig.PropTypeAttribute)
			if type(attr) == "string" and DefensivePropState.ValidatePropType(DefensivePropConfig, attr) then
				return attr
			end
		end
		return "crate"
	end

	local function resolveZoneId(propPart: any): string
		if type(propPart.GetAttribute) == "function" then
			local attr = propPart:GetAttribute(DefensivePropConfig.ZoneIdAttribute)
			if type(attr) == "string" and attr ~= "" then
				return attr
			end
		end
		local suffix = string.gsub(propPart.Name, "^" .. DefensivePropConfig.PropNamePrefix, "")
		return DefensivePropConfig.ZoneNamePrefix .. suffix
	end

	local function resolveEnabled(propPart: any): boolean
		if type(propPart.GetAttribute) == "function" then
			local attr = propPart:GetAttribute(DefensivePropConfig.EnabledAttribute)
			if attr == false then
				return false
			end
		end
		return true
	end

	local function applyPropAttributes(propId: string)
		local propPart = propPartById[propId]
		local record = propRecordById[propId]
		if propPart == nil or type(propPart.SetAttribute) ~= "function" then
			return
		end
		local snapshot = DefensivePropState.Snapshot(DefensivePropConfig, record, now())
		local attrs = DefensivePropConfig.Attributes
		propPart:SetAttribute(attrs.State, snapshot.state)
		propPart:SetAttribute(attrs.PropType, snapshot.propType)
		propPart:SetAttribute(attrs.ZoneId, snapshot.zoneId)
		propPart:SetAttribute(attrs.DroppedByUserId, snapshot.droppedByUserId)
		propPart:SetAttribute(attrs.DroppedAt, snapshot.droppedAt)
		propPart:SetAttribute(attrs.BarrierStartupEndsAt, snapshot.barrierStartupEndsAt)
		propPart:SetAttribute(attrs.BarrierActiveEndsAt, snapshot.barrierActiveEndsAt)
		propPart:SetAttribute(attrs.ObstacleExpiresAt, snapshot.obstacleExpiresAt)
		propPart:SetAttribute(attrs.BreakStartedAt, snapshot.breakStartedAt)
		propPart:SetAttribute(attrs.BreakEndsAt, snapshot.breakEndsAt)
		propPart:SetAttribute(attrs.BrokenByUserId, snapshot.brokenByUserId)
		propPart:SetAttribute(attrs.BrokenAt, snapshot.brokenAt)
		propPart:SetAttribute(attrs.ResetEndsAt, snapshot.resetEndsAt)
	end

	local function refreshPropRecord(propId: string): any
		local record = propRecordById[propId]
		if record == nil then
			return nil
		end
		local nextRecord, changed = DefensivePropState.ResolveLifecycle(DefensivePropConfig, record, now())
		if changed and nextRecord ~= nil then
			propRecordById[propId] = nextRecord
			applyPropAttributes(propId)
		end
		return propRecordById[propId]
	end

	local function scheduleAt(delaySeconds: number, callback: () -> ())
		if options ~= nil and options.disableScheduling == true then
			return
		end
		if type(task) == "table" and type(task.delay) == "function" then
			local thread = task.delay(delaySeconds, callback)
			table.insert(scheduledTasks, thread)
			return
		end
		callback()
	end

	local function schedulePropRefresh(propId: string, record: any)
		if record == nil then
			return
		end
		local currentTime = now()
		local timestamps = {
			record.barrierStartupEndsAt,
			record.barrierActiveEndsAt,
			record.obstacleExpiresAt,
			record.breakEndsAt,
			record.resetEndsAt,
		}
		for _, timestamp in ipairs(timestamps) do
			if type(timestamp) == "number" and timestamp > currentTime then
				scheduleAt(math.max(timestamp - currentTime, 0), function()
					refreshPropRecord(propId)
				end)
			end
		end
	end

	local function registerProps()
		local root = getNestedRoot(DefensivePropConfig.PropsFolderPath)
		for _, descendant in ipairs(getDescendants(root)) do
			if isBasePart(descendant) and startsWithPrefix(descendant.Name, DefensivePropConfig.PropNamePrefix) then
				propPartById[descendant.Name] = descendant
				if propRecordById[descendant.Name] == nil then
					propRecordById[descendant.Name] = DefensivePropState.NewRecord(
						descendant.Name,
						resolvePropType(descendant),
						resolveZoneId(descendant),
						resolveEnabled(descendant)
					)
				end
				applyPropAttributes(descendant.Name)
			end
		end
	end

	local function registerZones()
		local root = getNestedRoot(DefensivePropConfig.ZonesFolderPath)
		for _, descendant in ipairs(getDescendants(root)) do
			if isBasePart(descendant) and startsWithPrefix(descendant.Name, DefensivePropConfig.ZoneNamePrefix) then
				zonePartById[descendant.Name] = descendant
			end
		end
	end

	local function shouldTrackGiantRoutePart(part: any): boolean
		if type(part.Name) ~= "string" then
			return false
		end
		if part:GetAttribute(EscapeConfig.GiantOnlyRouteAttribute) == true then
			return true
		end
		local prefix = EscapeConfig.GiantMacroRouteNamePrefix
		if type(prefix) == "string" and prefix ~= "" then
			return string.match(part.Name, "^" .. prefix) ~= nil
		end
		return false
	end

	local function registerGiantRoutes()
		local root = getNestedRoot(DefensivePropConfig.GiantRoutesFolderPath)
		for _, descendant in ipairs(getDescendants(root)) do
			if isBasePart(descendant) and shouldTrackGiantRoutePart(descendant) then
				giantRoutePartById[descendant.Name] = descendant
			end
		end
	end

	local function refreshRegistries()
		propPartById = {}
		zonePartById = {}
		giantRoutePartById = {}
		registerZones()
		registerGiantRoutes()
		registerProps()
		for propId in pairs(propRecordById) do
			if propPartById[propId] == nil then
				propRecordById[propId] = nil
			else
				refreshPropRecord(propId)
			end
		end
	end

	local function getEventLogQueryApi(): any?
		if type(globalEnv._EventLogService_QueryAPI) == "table" then
			return globalEnv._EventLogService_QueryAPI
		end
		if type(_G) == "table" and type((_G :: any)._EventLogService_QueryAPI) == "table" then
			return (_G :: any)._EventLogService_QueryAPI
		end
		return nil
	end

	local function getRescueContractQueryApi(): any?
		if type(globalEnv._RescueContractService_QueryAPI) == "table" then
			return globalEnv._RescueContractService_QueryAPI
		end
		if type(_G) == "table" and type((_G :: any)._RescueContractService_QueryAPI) == "table" then
			return (_G :: any)._RescueContractService_QueryAPI
		end
		return nil
	end

	local function getRoleServiceQueryApi(): any?
		if type(globalEnv._RoleService_QueryAPI) == "table" then
			return globalEnv._RoleService_QueryAPI
		end
		if type(_G) == "table" and type((_G :: any)._RoleService_QueryAPI) == "table" then
			return (_G :: any)._RoleService_QueryAPI
		end
		return nil
	end

	local function buildRescueDropContext(player: any, zoneId: string, currentTime: number): any
		local hasActiveRescueContract = false
		local rescueApi = getRescueContractQueryApi()
		if rescueApi ~= nil and type(rescueApi.GetRescuerContract) == "function" then
			local contract = rescueApi.GetRescuerContract(player.UserId, currentTime)
			hasActiveRescueContract = contract ~= nil
		end

		local downedAllyInZone = false
		local zonePart = zonePartById[zoneId]
		local roleApi = getRoleServiceQueryApi()
		if zonePart ~= nil and roleApi ~= nil and _Players ~= nil and type(_Players.GetPlayers) == "function" then
			for _, otherPlayer in ipairs(_Players:GetPlayers()) do
				if
					otherPlayer ~= nil
					and type(otherPlayer.UserId) == "number"
					and otherPlayer.UserId ~= player.UserId
					and getRole(otherPlayer) == RoleConfig.Roles.Tinyfolk
					and isPlayerAlive(otherPlayer)
					and type(roleApi.IsPlayerDowned) == "function"
					and roleApi.IsPlayerDowned(otherPlayer.UserId) == true
				then
					local root = getHumanoidRootPart(otherPlayer)
					if root ~= nil and partInsideZone(root, zonePart) then
						downedAllyInZone = true
						break
					end
				end
			end
		end

		return {
			hasActiveRescueContract = hasActiveRescueContract,
			downedAllyInZone = downedAllyInZone,
		}
	end

	local function tryGrantRescueDropEffect(player: any, zoneId: string, currentTime: number): any
		local context = buildRescueDropContext(player, zoneId, currentTime)
		local effect = DefensivePropState.EvaluateRescueDropEffect(DefensivePropConfig, context)
		if effect.granted ~= true then
			return effect
		end

		local rescueApi = getRescueContractQueryApi()
		if rescueApi ~= nil and type(rescueApi.GrantRescueAcceleration) == "function" then
			pcall(rescueApi.GrantRescueAcceleration, player.UserId, currentTime)
		end
		return effect
	end

	local function recordEvent(message: string, metadata: any)
		local eventLog = getEventLogQueryApi()
		if eventLog == nil or type(eventLog.RecordEvent) ~= "function" then
			return
		end
		pcall(eventLog.RecordEvent, "defensive_prop", message, "info", now(), metadata)
	end

	local function validatePropPlayer(player: any, propId: any, expectedRole: string, rangeStuds: number): any
		if type(propId) ~= "string" or propId == "" then
			return { accepted = false, reason = "prop_id_invalid" }
		end
		refreshRegistries()
		local propPart = propPartById[propId]
		if propPart == nil then
			return { accepted = false, reason = "prop_not_found" }
		end
		if player == nil or type(player.UserId) ~= "number" then
			return { accepted = false, reason = "user_id_invalid" }
		end
		if getRole(player) ~= expectedRole then
			return {
				accepted = false,
				reason = if expectedRole == RoleConfig.Roles.Tinyfolk
					then "requester_not_tinyfolk"
					else "requester_not_giant",
			}
		end
		if not isPlayerAlive(player) then
			return { accepted = false, reason = "player_not_alive" }
		end
		local root = getHumanoidRootPart(player)
		if root == nil then
			return { accepted = false, reason = "humanoid_root_missing" }
		end
		local distance = distanceBetween(getPosition(propPart), getPosition(root))
		if distance == nil then
			return { accepted = false, reason = "distance_unavailable" }
		end
		if distance > rangeStuds then
			return { accepted = false, reason = "prop_out_of_range" }
		end
		return { accepted = true, reason = "accepted", propPart = propPart, record = refreshPropRecord(propId) }
	end

	local function getBarrierContactCooldown(propId: string, userId: number): number?
		local byUserId = lastBarrierContactAtByUserIdByPropId[propId]
		if type(byUserId) ~= "table" then
			return nil
		end
		return byUserId[userId]
	end

	local function markBarrierContact(propId: string, userId: number, at: number)
		local byUserId = lastBarrierContactAtByUserIdByPropId[propId]
		if type(byUserId) ~= "table" then
			byUserId = {}
			lastBarrierContactAtByUserIdByPropId[propId] = byUserId
		end
		byUserId[userId] = at
	end

	local function applyGiantBarrierStaggerAttributes(
		player: any,
		propId: string,
		staggerUntil: number,
		currentTime: number
	)
		if player == nil or type(player.SetAttribute) ~= "function" then
			return
		end
		local attrs = DefensivePropConfig.Attributes
		player:SetAttribute(attrs.GiantBarrierStaggerActive, staggerUntil > currentTime)
		player:SetAttribute(attrs.GiantBarrierStaggerUntil, staggerUntil)
		player:SetAttribute(attrs.GiantBarrierStaggerPropId, propId)
	end

	local function resolveGiantBarrierContact(userId: number, position: any, currentTime: number): any
		if type(userId) ~= "number" or type(position) ~= "table" then
			return { accepted = false, reason = "barrier_contact_invalid", propId = nil }
		end

		refreshRegistries()
		local contactRadius = DefensivePropConfig.BarrierContactRadiusStuds
		if type(contactRadius) ~= "number" or contactRadius <= 0 then
			return { accepted = false, reason = "barrier_contact_disabled", propId = nil }
		end

		for propId, record in pairs(propRecordById) do
			if record ~= nil then
				local resolved = refreshPropRecord(propId)
				if resolved ~= nil then
					local propPart = propPartById[propId]
					if propPart ~= nil then
						local distance = distanceBetween(getPosition(propPart), position)
						if distance ~= nil and distance <= contactRadius then
							local lastContactAt = getBarrierContactCooldown(propId, userId)
							local result = DefensivePropState.ApplyBarrierContact(
								DefensivePropConfig,
								resolved,
								currentTime,
								lastContactAt
							)
							if result.accepted == true and result.record ~= nil then
								propRecordById[propId] = result.record
								applyPropAttributes(propId)
								markBarrierContact(propId, userId, currentTime)
								recordEvent("defensive prop barrier contact", {
									propId = propId,
									userId = userId,
									breakInterrupted = result.breakInterrupted,
									staggerSeconds = result.staggerSeconds,
								})
								return {
									accepted = true,
									reason = result.reason,
									propId = propId,
									snapshot = result.snapshot,
									breakInterrupted = result.breakInterrupted,
									staggerSeconds = result.staggerSeconds,
									staggerUntil = result.staggerUntil,
								}
							end
							if result.reason == "barrier_contact_cooldown" then
								return {
									accepted = false,
									reason = result.reason,
									propId = propId,
									snapshot = result.snapshot,
								}
							end
						end
					end
				end
			end
		end

		return { accepted = false, reason = "barrier_contact_not_in_range", propId = nil }
	end

	local function tickGiantBarrierContacts(currentTime: number)
		if _Players == nil or type(_Players.GetPlayers) ~= "function" then
			return
		end
		local scanInterval = DefensivePropConfig.GiantBarrierContactScanIntervalSeconds
		if type(scanInterval) == "number" and scanInterval > 0 then
			if (currentTime - lastGiantBarrierContactScanAt) < scanInterval then
				return
			end
		end
		lastGiantBarrierContactScanAt = currentTime

		for _, player in ipairs(_Players:GetPlayers()) do
			if getRole(player) == RoleConfig.Roles.Giant and isPlayerAlive(player) then
				local root = getHumanoidRootPart(player)
				if root ~= nil then
					local contactResult = resolveGiantBarrierContact(player.UserId, getPosition(root), currentTime)
					if contactResult.accepted == true and type(contactResult.staggerUntil) == "number" then
						applyGiantBarrierStaggerAttributes(
							player,
							contactResult.propId,
							contactResult.staggerUntil,
							currentTime
						)
					elseif type(player.GetAttribute) == "function" and type(player.SetAttribute) == "function" then
						local attrs = DefensivePropConfig.Attributes
						local staggerUntil = player:GetAttribute(attrs.GiantBarrierStaggerUntil)
						if type(staggerUntil) == "number" and staggerUntil <= currentTime then
							player:SetAttribute(attrs.GiantBarrierStaggerActive, false)
						end
					end
				end
			end
		end
	end

	local function isGiantMacroRouteBlocked(routeId: string): boolean
		refreshRegistries()
		local routePart = giantRoutePartById[routeId]
		if routePart == nil then
			return false
		end
		for propId, record in pairs(propRecordById) do
			if record ~= nil then
				local resolved = refreshPropRecord(propId)
				if
					resolved ~= nil
					and DefensivePropState.BlocksGiantMacroRoutes(DefensivePropConfig, resolved, now())
				then
					local zonePart = zonePartById[resolved.zoneId]
					if zonePart ~= nil and partInsideZone(routePart, zonePart) then
						return true
					end
				end
			end
		end
		return false
	end

	local service: any = {}

	function service.requestDrop(player: any, propId: any): any
		local validation =
			validatePropPlayer(player, propId, RoleConfig.Roles.Tinyfolk, DefensivePropConfig.DropInteractionRangeStuds)
		if validation.accepted ~= true then
			return validation
		end

		local currentTime = now()
		local lastRequest = lastDropRequestAtByUserId[player.UserId]
		if
			type(lastRequest) == "number"
			and (currentTime - lastRequest) < DefensivePropConfig.DropRequestCooldownSeconds
		then
			return { accepted = false, reason = "request_rate_limited" }
		end

		local record = validation.record
		local activeCount =
			DefensivePropState.CountActiveForUser(DefensivePropConfig, propRecordById, player.UserId, currentTime)
		local canDrop = DefensivePropState.CanDrop(DefensivePropConfig, record, player.UserId, currentTime, activeCount)
		if canDrop.accepted ~= true then
			return {
				accepted = false,
				reason = canDrop.reason,
				snapshot = canDrop.snapshot,
			}
		end

		local result = DefensivePropState.CreateDrop(DefensivePropConfig, record, player.UserId, currentTime)
		local rescueDropEffect = nil
		if result.accepted == true and result.record ~= nil then
			propRecordById[propId] = result.record
			applyPropAttributes(propId)
			schedulePropRefresh(propId, result.record)
			lastDropRequestAtByUserId[player.UserId] = currentTime
			rescueDropEffect = tryGrantRescueDropEffect(player, result.record.zoneId, currentTime)
			recordEvent("defensive prop dropped", {
				propId = propId,
				userId = player.UserId,
				propType = result.record.propType,
				zoneId = result.record.zoneId,
				rescueDropEffect = rescueDropEffect,
			})
		end

		return {
			accepted = result.accepted,
			reason = result.reason,
			snapshot = result.snapshot,
			rescueDropEffect = rescueDropEffect,
		}
	end

	function service.requestStartBreak(player: any, propId: any): any
		local validation =
			validatePropPlayer(player, propId, RoleConfig.Roles.Giant, DefensivePropConfig.BreakInteractionRangeStuds)
		if validation.accepted ~= true then
			return validation
		end

		local currentTime = now()
		local lastRequest = lastBreakRequestAtByUserId[player.UserId]
		if
			type(lastRequest) == "number"
			and (currentTime - lastRequest) < DefensivePropConfig.BreakRequestCooldownSeconds
		then
			return { accepted = false, reason = "request_rate_limited" }
		end

		local result = DefensivePropState.StartBreak(DefensivePropConfig, validation.record, player.UserId, currentTime)
		if result.accepted == true and result.record ~= nil then
			propRecordById[propId] = result.record
			applyPropAttributes(propId)
			schedulePropRefresh(propId, result.record)
			lastBreakRequestAtByUserId[player.UserId] = currentTime
			recordEvent("defensive prop break started", {
				propId = propId,
				userId = player.UserId,
			})
		end

		return {
			accepted = result.accepted,
			reason = result.reason,
			snapshot = result.snapshot,
		}
	end

	function service.requestCompleteBreak(player: any, propId: any): any
		local validation =
			validatePropPlayer(player, propId, RoleConfig.Roles.Giant, DefensivePropConfig.BreakInteractionRangeStuds)
		if validation.accepted ~= true then
			return validation
		end

		local result = DefensivePropState.CompleteBreak(DefensivePropConfig, validation.record, player.UserId, now())
		if result.accepted == true and result.record ~= nil then
			propRecordById[propId] = result.record
			applyPropAttributes(propId)
			schedulePropRefresh(propId, result.record)
			recordEvent("defensive prop broken", {
				propId = propId,
				userId = player.UserId,
			})
		end

		return {
			accepted = result.accepted,
			reason = result.reason,
			snapshot = result.snapshot,
		}
	end

	function service.getPropSnapshot(propId: string): any
		refreshRegistries()
		return DefensivePropState.Snapshot(DefensivePropConfig, refreshPropRecord(propId), now())
	end

	function service.resolveGiantBarrierContact(userId: number, position: any): any
		return resolveGiantBarrierContact(userId, position, now())
	end

	function service.isGiantMacroRouteBlocked(routeId: string): boolean
		return isGiantMacroRouteBlocked(routeId)
	end

	function service.getGiantMacroRouteBlockReason(routeId: string): string?
		if isGiantMacroRouteBlocked(routeId) then
			return "defensive_prop_blocked"
		end
		return nil
	end

	function service.ResetForTests()
		for _, thread in ipairs(scheduledTasks) do
			if thread ~= nil and type(task) == "table" and type(task.cancel) == "function" then
				pcall(task.cancel, thread)
			end
		end
		scheduledTasks = {}
		propRecordById = {}
		lastDropRequestAtByUserId = {}
		lastBreakRequestAtByUserId = {}
		lastBarrierContactAtByUserIdByPropId = {}
		lastGiantBarrierContactScanAt = 0
		refreshRegistries()
	end

	local function ensureRemotesFolder(): any?
		if ReplicatedStorage == nil or type(ReplicatedStorage.FindFirstChild) ~= "function" then
			return nil
		end
		local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
		if remotes ~= nil then
			return remotes
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

	local function bindRemote()
		if options ~= nil and options.disableRemotes == true then
			return
		end
		local remotes = ensureRemotesFolder()
		local remote = ensureRemoteEvent(remotes, REQUEST_REMOTE_NAME)
		if remote == nil or type(remote.OnServerEvent) ~= "table" or type(remote.OnServerEvent.Connect) ~= "function" then
			return
		end
		remote.OnServerEvent:Connect(function(player: any, payload: any)
			if type(payload) ~= "table" then
				return
			end
			local mode = payload.mode
			local propId = payload.propId
			if mode == "drop" then
				service.requestDrop(player, propId)
			elseif mode == "start_break" then
				service.requestStartBreak(player, propId)
			elseif mode == "complete_break" then
				service.requestCompleteBreak(player, propId)
			end
		end)
	end

	local function bindHeartbeat()
		if options ~= nil and options.disableScheduling == true then
			return
		end
		local RunService = getService(gameRef, "RunService")
		if
			RunService == nil
			or type(RunService.Heartbeat) ~= "table"
			or type(RunService.Heartbeat.Connect) ~= "function"
		then
			return
		end
		RunService.Heartbeat:Connect(function()
			tickGiantBarrierContacts(now())
		end)
	end

	local function initialize()
		refreshRegistries()
		bindRemote()
		bindHeartbeat()
	end

	globalEnv._DefensivePropService_QueryAPI = {
		RequestDrop = function(player: any, propId: string): any
			return service.requestDrop(player, propId)
		end,
		RequestStartBreak = function(player: any, propId: string): any
			return service.requestStartBreak(player, propId)
		end,
		RequestCompleteBreak = function(player: any, propId: string): any
			return service.requestCompleteBreak(player, propId)
		end,
		GetPropSnapshot = function(propId: string): any
			return service.getPropSnapshot(propId)
		end,
		IsGiantMacroRouteBlocked = function(routeId: string): boolean
			return service.isGiantMacroRouteBlocked(routeId)
		end,
		GetGiantMacroRouteBlockReason = function(routeId: string): string?
			return service.getGiantMacroRouteBlockReason(routeId)
		end,
		ResolveGiantBarrierContact = function(userId: number, position: any, at: number?): any
			local currentTime = if type(at) == "number" then at else now()
			return resolveGiantBarrierContact(userId, position, currentTime)
		end,
		ResetForTests = function()
			service.ResetForTests()
		end,
	}

	if type(_G) == "table" then
		rawset(_G, "_DefensivePropService_QueryAPI", globalEnv._DefensivePropService_QueryAPI)
	end

	if options == nil or options.autoInitialize ~= false then
		local ok, errorOrNil = pcall(initialize)
		if not ok then
			debugWarn(string.format("Initialization skipped due to runtime mismatch: %s", tostring(errorOrNil)))
		end
	end

	return service
end

return createDefensivePropService
