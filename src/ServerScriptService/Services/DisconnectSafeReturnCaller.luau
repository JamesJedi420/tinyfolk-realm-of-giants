--!strict

local EscapeConfig = require("../../ReplicatedStorage/Shared/Config/EscapeConfig")
local SafeLocationProfileState = require("../../ReplicatedStorage/Shared/Escape/SafeLocationProfileState")

local DisconnectSafeReturnCaller = {}

local function getPlayersService(): any?
	if type(game) ~= "table" or type((game :: any).GetService) ~= "function" then
		return nil
	end

	local ok, players = pcall(function()
		return (game :: any):GetService("Players")
	end)
	if not ok then
		return nil
	end
	return players
end

local function getPlayerByUserId(userId: number): any?
	local players = getPlayersService()
	if players == nil or type(players.GetPlayers) ~= "function" then
		return nil
	end

	for _, player in players:GetPlayers() do
		if type(player) == "table" and player.UserId == userId then
			return player
		end
	end
	return nil
end

local function getProfileGateway(): any?
	local globalValue: any = _G
	if type(globalValue) == "table" and type(globalValue._ProfilePersistenceGateway_QueryAPI) == "table" then
		return globalValue._ProfilePersistenceGateway_QueryAPI
	end

	if script ~= nil and script.Parent ~= nil then
		local ok, gateway = pcall(function()
			return require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
		end)
		if ok and type(gateway) == "table" then
			return gateway
		end
	end

	return nil
end

local function getEscapeServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._EscapeService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

function DisconnectSafeReturnCaller.PersistDisconnectReturnPending(userId: number, at: number?, input: any?): any
	if type(userId) ~= "number" then
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	local player = getPlayerByUserId(userId)
	if player == nil then
		return { accepted = false, reason = "target_not_found" }
	end

	local gateway = getProfileGateway()
	if gateway == nil or type(gateway.UpdateLoadedPlayerProfileData) ~= "function" then
		return { accepted = false, reason = "profile_gateway_missing" }
	end

	local resolvedAt = if type(at) == "number" then at else os.clock()
	local payload = if type(input) == "table" then input else {}
	local safeLocationInput = {
		returnPointName = EscapeConfig.TinyfolkReturnPointName,
		returnedAt = resolvedAt,
		returnReason = "logout",
		realmId = payload.realmId,
		realmOwnerUserId = payload.realmOwnerUserId,
		sourceId = if type(payload.sourceId) == "string" then payload.sourceId else "disconnect_resolution",
	}

	local ok, result = pcall(gateway.UpdateLoadedPlayerProfileData, player, function(currentData: any): any
		if type(currentData) ~= "table" then
			return nil, "profile_data_invalid"
		end
		local safeLocationResult = SafeLocationProfileState.ApplySafeReturn(currentData, safeLocationInput)
		if safeLocationResult.accepted ~= true then
			return nil, safeLocationResult.reason
		end
		return safeLocationResult.profileData
	end)

	if not ok or type(result) ~= "table" or result.ok ~= true then
		return {
			accepted = false,
			reason = if type(result) == "table" and type(result.reason) == "string"
				then result.reason
				else "profile_update_failed",
		}
	end

	return {
		accepted = true,
		reason = "return_pending_persisted",
		returnReason = "logout",
		returnedAt = resolvedAt,
	}
end

function DisconnectSafeReturnCaller.ApplyOnlineSafeReturn(
	targetUserId: number,
	at: number?,
	returnReason: string?
): any?
	local queryApi = getEscapeServiceQueryApi()
	if queryApi == nil or type(queryApi.ApplyCaptivitySafeReturn) ~= "function" then
		return nil
	end

	local resolvedReason = if type(returnReason) == "string" then returnReason else "safe_return"
	return queryApi.ApplyCaptivitySafeReturn(targetUserId, at, resolvedReason)
end

return DisconnectSafeReturnCaller
