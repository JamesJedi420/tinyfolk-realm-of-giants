--!nocheck

local LiveRealmHubRouting = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("LiveRealmHubRouting")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")

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
	return nil
end

local function createRealmPermissionService(runtimeGame: any?, options: any?)
	local globalEnv: any = getfenv()
	local gameRef = runtimeGame or game
	local ReplicatedStorage = getService(gameRef, "ReplicatedStorage")
	local Shared = if ReplicatedStorage ~= nil and type(ReplicatedStorage.WaitForChild) == "function"
		then ReplicatedStorage:WaitForChild("Shared")
		else nil
	local GiantRealm = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("GiantRealm")
		else nil

	local RealmPermissionConfig = resolveDependency(
		if Shared ~= nil then Shared:FindFirstChild("Config") else nil,
		"RealmPermissionConfig",
		"../../ReplicatedStorage/Shared/Config/RealmPermissionConfig"
	)
	local RealmPermissionState = resolveDependency(
		GiantRealm,
		"RealmPermissionState",
		"../../ReplicatedStorage/Shared/GiantRealm/RealmPermissionState"
	)

	local DEFAULT_AVAILABILITY_LIMIT = 25
	local sessionModeByRealmId: { [string]: string } = {}
	local inviteAllowlistByRealmId: { [string]: { [number]: boolean } } = {}
	local liveRegistryHubApiOverride: any = if type(options) == "table" then options.liveRegistryHubApi else nil
	local liveRegistryApiOverride: any = if type(options) == "table" then options.liveRegistryApi else nil
	local listLiveRealmAvailabilityOverride: ((number?, number?) -> { any })? = if type(options) == "table"
			and type(options.listLiveRealmAvailability) == "function"
		then options.listLiveRealmAvailability
		else nil
	local friendsCheckerOverride: ((number, number) -> boolean)? = if type(options) == "table"
			and type(options.isFriendsWithOwner) == "function"
		then options.isFriendsWithOwner
		else nil

	local function isNonEmptyString(value: any): boolean
		return type(value) == "string" and value ~= ""
	end

	local function isPositiveInteger(value: any): boolean
		return type(value) == "number" and value == math.floor(value) and value > 0
	end

	local function getLiveRegistryHubApi(): any?
		if liveRegistryHubApiOverride ~= nil then
			return liveRegistryHubApiOverride
		end

		local queryApi = globalEnv._LiveRealmRegistryHubSurface_QueryAPI
		if type(queryApi) == "table" then
			return queryApi
		end
		if type(_G) == "table" and type((_G :: any)._LiveRealmRegistryHubSurface_QueryAPI) == "table" then
			return (_G :: any)._LiveRealmRegistryHubSurface_QueryAPI
		end
		return nil
	end

	local function getLiveRegistryApi(): any?
		if liveRegistryApiOverride ~= nil then
			return liveRegistryApiOverride
		end

		local queryApi = globalEnv._LiveRealmRegistry_QueryAPI
		if type(queryApi) == "table" then
			return queryApi
		end
		if type(_G) == "table" and type((_G :: any)._LiveRealmRegistry_QueryAPI) == "table" then
			return (_G :: any)._LiveRealmRegistry_QueryAPI
		end
		return nil
	end

	local function readLiveRealmAvailability(limit: number?, at: number?): { any }?
		if type(listLiveRealmAvailabilityOverride) == "function" then
			local ok, availability = pcall(listLiveRealmAvailabilityOverride, limit, at)
			if ok and type(availability) == "table" then
				return availability
			end
			return nil
		end

		local hubApi = getLiveRegistryHubApi()
		if type(hubApi) ~= "table" or type((hubApi :: any).ListLiveRealmAvailability) ~= "function" then
			return nil
		end

		local resolvedLimit = if type(limit) == "number" and limit > 0 then limit else DEFAULT_AVAILABILITY_LIMIT
		local ok, availability = pcall(function()
			return (hubApi :: any).ListLiveRealmAvailability(resolvedLimit, at)
		end)
		if not ok or type(availability) ~= "table" then
			return nil
		end

		return availability
	end

	local function collectInviteAllowlistUserIds(realmId: string): { number }
		local allowlist = inviteAllowlistByRealmId[realmId]
		if type(allowlist) ~= "table" then
			return {}
		end

		local userIds: { number } = {}
		for userId in pairs(allowlist) do
			if isPositiveInteger(userId) then
				table.insert(userIds, math.floor(userId))
			end
		end
		table.sort(userIds)
		return userIds
	end

	local function resolveFriendsChecker(): ((number, number) -> boolean)?
		if type(friendsCheckerOverride) == "function" then
			return friendsCheckerOverride
		end

		local Players = getService(gameRef, "Players")
		if Players == nil or type(Players.GetPlayerByUserId) ~= "function" then
			return nil
		end

		return function(ownerUserId: number, requesterUserId: number): boolean
			if ownerUserId == requesterUserId then
				return true
			end

			local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
			if ownerPlayer ~= nil and type(ownerPlayer.IsFriendsWith) == "function" then
				local ok, isFriend = pcall(function()
					return ownerPlayer:IsFriendsWith(requesterUserId)
				end)
				if ok and isFriend == true then
					return true
				end
			end

			local requesterPlayer = Players:GetPlayerByUserId(requesterUserId)
			if requesterPlayer ~= nil and type(requesterPlayer.IsFriendsWith) == "function" then
				local ok, isFriend = pcall(function()
					return requesterPlayer:IsFriendsWith(ownerUserId)
				end)
				if ok and isFriend == true then
					return true
				end
			end

			return false
		end
	end

	local function publishRegistryAccessMode(ownerUserId: number, permissionMode: string): (boolean, string?)
		local registryAccessMode = RealmPermissionState.ToRegistryAccessMode(permissionMode)
		if registryAccessMode == nil then
			return false, RealmPermissionConfig.Reasons.ModeInvalid
		end

		local registryApi = getLiveRegistryApi()
		if type(registryApi) ~= "table" or type(registryApi.RefreshActiveRealm) ~= "function" then
			return true, nil
		end

		local ok, result = pcall(function()
			return registryApi.RefreshActiveRealm({
				ownerUserId = ownerUserId,
				accessMode = registryAccessMode,
			})
		end)
		if not ok or type(result) ~= "table" or result.accepted ~= true then
			local reason = if type(result) == "table" and type(result.reason) == "string"
				then result.reason
				else "registry_refresh_failed"
			return false, reason
		end

		return true, nil
	end

	local service: any = {}

	function service.setSessionRealmAccessMode(realmId: string, accessMode: string): any
		if not isNonEmptyString(realmId) or not isNonEmptyString(accessMode) then
			return { accepted = false, reason = RealmPermissionConfig.Reasons.ModeInvalid }
		end
		if not RealmPermissionState.IsValidPermissionMode(accessMode) then
			return { accepted = false, reason = RealmPermissionConfig.Reasons.ModeInvalid }
		end
		sessionModeByRealmId[realmId] = accessMode
		return { accepted = true, reason = RealmPermissionConfig.Reasons.Accepted }
	end

	function service.getRealmAccessMode(realmId: string): string
		if not isNonEmptyString(realmId) then
			return RealmPermissionConfig.DefaultMode
		end

		local sessionMode = sessionModeByRealmId[realmId]
		if isNonEmptyString(sessionMode) then
			return RealmPermissionState.NormalizeRegistryAccessMode(sessionMode)
		end

		local availability = readLiveRealmAvailability(DEFAULT_AVAILABILITY_LIMIT, nil)
		if type(availability) == "table" then
			local snapshot = LiveRealmHubRouting.FindAvailabilityByRealmId(availability, realmId)
			if type(snapshot) == "table" and isNonEmptyString(snapshot.accessMode) then
				return RealmPermissionState.NormalizeRegistryAccessMode(snapshot.accessMode)
			end
		end

		return RealmPermissionConfig.DefaultMode
	end

	function service.getRegistryAccessMode(realmId: string): string
		local permissionMode = service.getRealmAccessMode(realmId)
		local registryMode = RealmPermissionState.ToRegistryAccessMode(permissionMode)
		if registryMode ~= nil then
			return registryMode
		end
		return "public"
	end

	function service.addInviteAllowlistUser(realmId: string, userId: number): any
		if not isNonEmptyString(realmId) or not isPositiveInteger(userId) then
			return { accepted = false, reason = RealmPermissionConfig.Reasons.ModeInvalid }
		end

		local allowlist = inviteAllowlistByRealmId[realmId]
		if type(allowlist) ~= "table" then
			allowlist = {}
			inviteAllowlistByRealmId[realmId] = allowlist
		end
		allowlist[math.floor(userId)] = true
		return { accepted = true, reason = RealmPermissionConfig.Reasons.Accepted }
	end

	function service.removeInviteAllowlistUser(realmId: string, userId: number): any
		if not isNonEmptyString(realmId) or not isPositiveInteger(userId) then
			return { accepted = false, reason = RealmPermissionConfig.Reasons.ModeInvalid }
		end

		local allowlist = inviteAllowlistByRealmId[realmId]
		if type(allowlist) == "table" then
			allowlist[math.floor(userId)] = nil
		end
		return { accepted = true, reason = RealmPermissionConfig.Reasons.Accepted }
	end

	function service.setOwnerRealmAccessMode(ownerUserId: number, accessMode: string): any
		if not isPositiveInteger(ownerUserId) or not isNonEmptyString(accessMode) then
			return { accepted = false, reason = RealmPermissionConfig.Reasons.ModeInvalid }
		end
		if not RealmPermissionState.IsValidPermissionMode(accessMode) then
			return { accepted = false, reason = RealmPermissionConfig.Reasons.ModeInvalid }
		end

		local realmId = string.format("giant_realm_%d", math.floor(ownerUserId))
		local sessionResult = service.setSessionRealmAccessMode(realmId, accessMode)
		if sessionResult.accepted ~= true then
			return sessionResult
		end

		local published, publishReason = publishRegistryAccessMode(math.floor(ownerUserId), accessMode)
		if not published then
			return {
				accepted = false,
				reason = publishReason or "registry_refresh_failed",
			}
		end

		return {
			accepted = true,
			reason = RealmPermissionConfig.Reasons.Accepted,
			realmId = realmId,
			accessMode = accessMode,
		}
	end

	function service.evaluateAdmissionForRealm(realmId: string, context: any): any
		local entryType = if type(context) == "table" then context.entryType else nil
		local requesterUserIds = if type(context) == "table" then context.requesterUserIds else nil
		local resolverProbe = if type(context) == "table" then context.resolverProbe == true else false
		local accessMode = service.getRealmAccessMode(realmId)
		return RealmPermissionState.EvaluateAdmission({
			accessMode = accessMode,
			entryType = entryType,
			requesterUserIds = requesterUserIds,
			realmOwnerUserId = RealmPermissionState.ParseRealmOwnerUserId(realmId),
			inviteAllowlistUserIds = collectInviteAllowlistUserIds(realmId),
			isFriendsWithOwner = resolveFriendsChecker(),
			resolverProbe = resolverProbe,
		})
	end

	function service.ConfigureForTests(config: any?)
		local configAny: any = config
		liveRegistryHubApiOverride = if type(configAny) == "table" then configAny.liveRegistryHubApi else nil
		liveRegistryApiOverride = if type(configAny) == "table" then configAny.liveRegistryApi else nil
		listLiveRealmAvailabilityOverride = if type(configAny) == "table"
				and type(configAny.listLiveRealmAvailability) == "function"
			then configAny.listLiveRealmAvailability
			else nil
		friendsCheckerOverride = if type(configAny) == "table"
				and type(configAny.isFriendsWithOwner) == "function"
			then configAny.isFriendsWithOwner
			else nil
	end

	function service.ResetForTests()
		sessionModeByRealmId = {}
		inviteAllowlistByRealmId = {}
		liveRegistryHubApiOverride = nil
		liveRegistryApiOverride = nil
		listLiveRealmAvailabilityOverride = nil
		friendsCheckerOverride = nil
	end

	globalEnv._RealmPermissionService_QueryAPI = {
		GetRealmAccessMode = function(realmId: string): string
			return service.getRealmAccessMode(realmId)
		end,
		GetRegistryAccessMode = function(realmId: string): string
			return service.getRegistryAccessMode(realmId)
		end,
		EvaluateAdmissionForRealm = function(realmId: string, context: any): any
			return service.evaluateAdmissionForRealm(realmId, context)
		end,
		SetSessionRealmAccessMode = function(realmId: string, accessMode: string): any
			return service.setSessionRealmAccessMode(realmId, accessMode)
		end,
		SetOwnerRealmAccessMode = function(ownerUserId: number, accessMode: string): any
			return service.setOwnerRealmAccessMode(ownerUserId, accessMode)
		end,
		AddInviteAllowlistUser = function(realmId: string, userId: number): any
			return service.addInviteAllowlistUser(realmId, userId)
		end,
		RemoveInviteAllowlistUser = function(realmId: string, userId: number): any
			return service.removeInviteAllowlistUser(realmId, userId)
		end,
		ConfigureForTests = function(config: any?)
			service.ConfigureForTests(config)
		end,
		ResetForTests = function()
			service.ResetForTests()
		end,
	}
	if type(_G) == "table" then
		rawset(_G, "_RealmPermissionService_QueryAPI", globalEnv._RealmPermissionService_QueryAPI)
	end

	return service
end

return createRealmPermissionService
