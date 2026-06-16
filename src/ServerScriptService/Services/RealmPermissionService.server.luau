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
	local liveRegistryHubApiOverride: any = if type(options) == "table" then options.liveRegistryHubApi else nil
	local listLiveRealmAvailabilityOverride: ((number?, number?) -> { any })? = if type(options) == "table"
			and type(options.listLiveRealmAvailability) == "function"
		then options.listLiveRealmAvailability
		else nil

	local function isNonEmptyString(value: any): boolean
		return type(value) == "string" and value ~= ""
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

	local service: any = {}

	function service.setSessionRealmAccessMode(realmId: string, accessMode: string): any
		if not isNonEmptyString(realmId) or not isNonEmptyString(accessMode) then
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

	function service.evaluateAdmissionForRealm(realmId: string, context: any): any
		local entryType = if type(context) == "table" then context.entryType else nil
		local accessMode = service.getRealmAccessMode(realmId)
		return RealmPermissionState.EvaluateAdmission({
			accessMode = accessMode,
			entryType = entryType,
		})
	end

	function service.ConfigureForTests(config: any?)
		local configAny: any = config
		liveRegistryHubApiOverride = if type(configAny) == "table" then configAny.liveRegistryHubApi else nil
		listLiveRealmAvailabilityOverride = if type(configAny) == "table"
				and type(configAny.listLiveRealmAvailability) == "function"
			then configAny.listLiveRealmAvailability
			else nil
	end

	function service.ResetForTests()
		sessionModeByRealmId = {}
		liveRegistryHubApiOverride = nil
		listLiveRealmAvailabilityOverride = nil
	end

	globalEnv._RealmPermissionService_QueryAPI = {
		GetRealmAccessMode = function(realmId: string): string
			return service.getRealmAccessMode(realmId)
		end,
		EvaluateAdmissionForRealm = function(realmId: string, context: any): any
			return service.evaluateAdmissionForRealm(realmId, context)
		end,
		SetSessionRealmAccessMode = function(realmId: string, accessMode: string): any
			return service.setSessionRealmAccessMode(realmId, accessMode)
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
