--!nocheck

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

local function createGiantFollowerProxyService(runtimeGame: any?, options: any?)
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

	local RoleConfig = resolveDependency(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	local GiantFollowerProxyConfig = resolveDependency(
		Config,
		"GiantFollowerProxyConfig",
		"../../ReplicatedStorage/Shared/Config/GiantFollowerProxyConfig"
	)
	local GiantFollowerProxyState = resolveDependency(
		GiantRealm,
		"GiantFollowerProxyState",
		"../../ReplicatedStorage/Shared/GiantRealm/GiantFollowerProxyState"
	)

	local proxyStateByUserId: { [number]: any } = {}

	local function now(): number
		if options ~= nil and type(options.clock) == "function" then
			return options.clock()
		end
		return os.clock()
	end

	local function getRemoteControlQueryApi(): any?
		local queryApi = globalEnv._RemoteControlStationService_QueryAPI
		if type(queryApi) == "table" then
			return queryApi
		end
		if type(_G) == "table" and type((_G :: any)._RemoteControlStationService_QueryAPI) == "table" then
			return (_G :: any)._RemoteControlStationService_QueryAPI
		end
		return nil
	end

	local function getStatusQueryApi(): any?
		local queryApi = globalEnv._TinyfolkStatusService_QueryAPI
		if type(queryApi) == "table" then
			return queryApi
		end
		if type(_G) == "table" and type((_G :: any)._TinyfolkStatusService_QueryAPI) == "table" then
			return (_G :: any)._TinyfolkStatusService_QueryAPI
		end
		return nil
	end

	local function getOrCreateState(userId: number): any
		local state = proxyStateByUserId[userId]
		if state == nil then
			state = GiantFollowerProxyState.NewState(now())
			proxyStateByUserId[userId] = state
		end
		return state
	end

	local service: any = {}

	function service.requestControlMode(player: any, mode: string): any
		if player == nil or type(player.UserId) ~= "number" then
			return { accepted = false, reason = "user_id_invalid" }
		end
		if type(player.GetAttribute) ~= "function" or player:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
			return { accepted = false, reason = "requester_not_giant" }
		end

		if mode == "proxy" then
			local remoteApi = getRemoteControlQueryApi()
			if type(remoteApi) == "table" and type(remoteApi.IsGiantOperatingStation) == "function" then
				local ok, operating = pcall(remoteApi.IsGiantOperatingStation, player.UserId)
				if ok and operating == true then
					return { accepted = false, reason = "remote_control_active" }
				end
			end
		end

		local state = getOrCreateState(player.UserId)
		local result = GiantFollowerProxyState.RequestMode(state, GiantFollowerProxyConfig, mode, now())
		return {
			accepted = result.accepted,
			reason = result.reason,
			snapshot = service.getSnapshot(player.UserId),
		}
	end

	function service.getSnapshot(giantUserId: number): any
		if type(giantUserId) ~= "number" then
			return nil
		end
		local state = getOrCreateState(giantUserId)
		local trailSnapshots = {}
		local statusApi = getStatusQueryApi()
		if type(statusApi) == "table" and type(statusApi.GetAllTrailSnapshots) == "function" then
			local ok, result = pcall(statusApi.GetAllTrailSnapshots, now())
			if ok and type(result) == "table" then
				trailSnapshots = result
			end
		end
		local pressure =
			GiantFollowerProxyState.BuildPressureSnapshot(state, GiantFollowerProxyConfig, now(), trailSnapshots)
		return {
			giantUserId = giantUserId,
			controlMode = state.controlMode,
			proxyEnabled = state.enabled == true,
			pressureBand = pressure.pressureBand,
			pressureDirection = pressure.direction,
			trackedCount = pressure.trackedCount,
			updatedAt = pressure.updatedAt,
		}
	end

	function service.isProxyControlActive(giantUserId: number): boolean
		local state = proxyStateByUserId[giantUserId]
		return state ~= nil and state.enabled == true
	end

	function service.ResetForTests()
		proxyStateByUserId = {}
	end

	if
		type(Players) == "table"
		and type(Players.PlayerRemoving) == "table"
		and type(Players.PlayerRemoving.Connect) == "function"
	then
		Players.PlayerRemoving:Connect(function(player: any)
			if type(player) == "table" and type(player.UserId) == "number" then
				proxyStateByUserId[player.UserId] = nil
			end
		end)
	end

	globalEnv._GiantFollowerProxyService_QueryAPI = {
		RequestControlMode = function(player: any, mode: string): any
			return service.requestControlMode(player, mode)
		end,
		GetSnapshot = function(giantUserId: number): any
			return service.getSnapshot(giantUserId)
		end,
		IsProxyControlActive = function(giantUserId: number): boolean
			return service.isProxyControlActive(giantUserId)
		end,
	}
	if type(_G) == "table" then
		rawset(_G, "_GiantFollowerProxyService_QueryAPI", globalEnv._GiantFollowerProxyService_QueryAPI)
	end

	return service
end

return createGiantFollowerProxyService
