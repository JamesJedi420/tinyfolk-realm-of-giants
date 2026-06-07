--!strict

local RealmTeleportDispatcher: any = {}
local globalEnv: any = getfenv()

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveInteger(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	if value <= 0 then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end

	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end

	return nil
end

local function makeFailure(reason: string, retryable: boolean): any
	return {
		ok = false,
		retryable = retryable,
		reason = reason,
	}
end

local function makeSuccess(extra: any?): any
	local result = {
		ok = true,
		retryable = false,
		reason = "accepted",
	}
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			(result :: any)[key] = value
		end
	end
	return result
end

local function resolveTeleportService(config: any?): any?
	local configAny: any = config
	if type(configAny) == "table" and (configAny :: any).teleportService ~= nil then
		return (configAny :: any).teleportService
	end

	if game ~= nil and type(game.GetService) == "function" then
		local ok, service = pcall(function()
			return game:GetService("TeleportService")
		end)
		if ok and service ~= nil then
			return service
		end
	end

	return nil
end

local function resolvePlayersService(config: any?): any?
	local configAny: any = config
	if type(configAny) == "table" and (configAny :: any).playersService ~= nil then
		return (configAny :: any).playersService
	end

	if game ~= nil and type(game.GetService) == "function" then
		local ok, service = pcall(function()
			return game:GetService("Players")
		end)
		if ok and service ~= nil then
			return service
		end
	end

	return nil
end

local function resolveHandoffApi(config: any?): any?
	local configAny: any = config
	if type(configAny) == "table" and (configAny :: any).handoffApi ~= nil then
		return (configAny :: any).handoffApi
	end

	return getGlobalTable("_ProfileTeleportHandoffService_QueryAPI")
end

local function resolveTinyfolkToolLoadoutApi(config: any?): any?
	local configAny: any = config
	if type(configAny) == "table" and (configAny :: any).tinyfolkToolLoadoutApi ~= nil then
		return (configAny :: any).tinyfolkToolLoadoutApi
	end

	return getGlobalTable("_TinyfolkToolLoadoutService_QueryAPI")
end

local function resolvePartyMembers(config: any?, entry: any): { number }?
	local configAny: any = config
	local partyResolver = if type(configAny) == "table" then configAny.partyResolver else nil

	if partyResolver == nil then
		local resolverApi = getGlobalTable("_RealmAdmissionPartyResolver_QueryAPI")
		if type(resolverApi) == "table" and type((resolverApi :: any).ResolvePartyMemberUserIds) == "function" then
			partyResolver = function(partyId: string, resolverEntry: any)
				return (resolverApi :: any).ResolvePartyMemberUserIds(partyId, resolverEntry)
			end
		end
	end

	if type(partyResolver) ~= "function" then
		return nil
	end

	local ok, members = pcall(partyResolver, entry.partyId, entry)
	if not ok or type(members) ~= "table" then
		return nil
	end

	local membersTable: any = members
	local rawMembers = membersTable
	if membersTable.accepted ~= nil then
		if membersTable.accepted ~= true then
			return nil
		end
		rawMembers = membersTable.memberUserIds
	end
	if type(rawMembers) ~= "table" then
		return nil
	end

	local resolvedMembers: { number } = {}
	for _, userId in ipairs(rawMembers) do
		if isPositiveInteger(userId) then
			table.insert(resolvedMembers, userId)
		end
	end

	if #resolvedMembers <= 0 then
		return nil
	end

	return resolvedMembers
end

local function resolveDestinationPlaceId(config: any?, entry: any): number?
	local configAny: any = config
	local destinationResolver = if type(configAny) == "table" then configAny.destinationResolver else nil
	if type(destinationResolver) == "function" then
		local ok, destination = pcall(destinationResolver, entry)
		if ok and type(destination) == "table" and isPositiveInteger((destination :: any).placeId) then
			return (destination :: any).placeId
		end
	end

	if isPositiveInteger(entry.targetPlaceId) then
		return entry.targetPlaceId
	end

	if game ~= nil and isPositiveInteger(game.PlaceId) then
		return game.PlaceId
	end

	return nil
end

function RealmTeleportDispatcher.Create(config: any?): any
	local teleportService = resolveTeleportService(config)
	local playersService = resolvePlayersService(config)
	local handoffApi = resolveHandoffApi(config)
	local tinyfolkToolLoadoutApi = resolveTinyfolkToolLoadoutApi(config)

	local dispatcher: any = {}

	function dispatcher.Dispatch(entry: any): any
		if type(entry) ~= "table" then
			return makeFailure("entry_invalid", false)
		end
		if not isNonEmptyString(entry.operationId) then
			return makeFailure("operation_id_invalid", false)
		end
		if not isNonEmptyString(entry.partyId) then
			return makeFailure("party_id_invalid", false)
		end
		if not isNonEmptyString(entry.targetRealmId) then
			return makeFailure("target_realm_id_invalid", false)
		end

		local memberUserIds = resolvePartyMembers(config, entry)
		if memberUserIds == nil then
			return makeFailure("party_members_unavailable", true)
		end

		if type(playersService) ~= "table" or type(playersService.GetPlayerByUserId) ~= "function" then
			return makeFailure("players_service_unavailable", true)
		end

		local players: { any } = {}
		for _, userId in ipairs(memberUserIds) do
			local player = playersService:GetPlayerByUserId(userId)
			if player == nil then
				return makeFailure("party_player_missing", true)
			end
			table.insert(players, player)
		end

		if type(handoffApi) ~= "table" or type(handoffApi.BeginCrossServerHandoff) ~= "function" then
			return makeFailure("handoff_api_unavailable", true)
		end

		local handoffTokensByUserId: { [number]: string } = {}
		for _, player in ipairs(players) do
			local handoffOk, handoffResult = pcall(function()
				return handoffApi.BeginCrossServerHandoff(player, {
					operationId = entry.operationId,
					partyId = entry.partyId,
					targetRealmId = entry.targetRealmId,
					targetPlaceId = entry.targetPlaceId,
				})
			end)
			if not handoffOk or type(handoffResult) ~= "table" or handoffResult.ok ~= true then
				return makeFailure("handoff_begin_failed", true)
			end
			if isPositiveInteger(player.UserId) and isNonEmptyString(handoffResult.handoffToken) then
				handoffTokensByUserId[player.UserId] = handoffResult.handoffToken
			end
		end

		if type(teleportService) ~= "table" then
			return makeFailure("teleport_service_unavailable", true)
		end
		if type(teleportService.ReserveServer) ~= "function" then
			return makeFailure("reserve_server_unavailable", true)
		end
		if type(teleportService.TeleportToPrivateServer) ~= "function" then
			return makeFailure("teleport_private_server_unavailable", true)
		end

		local placeId = resolveDestinationPlaceId(config, entry)
		if placeId == nil then
			return makeFailure("destination_place_unresolved", true)
		end

		local reserveOk, serverCodeOrError = pcall(function()
			return teleportService:ReserveServer(placeId)
		end)
		if not reserveOk or not isNonEmptyString(serverCodeOrError) then
			return makeFailure("reserve_server_failed", true)
		end

		local teleportData = {
			operationId = entry.operationId,
			partyId = entry.partyId,
			targetRealmId = entry.targetRealmId,
			handoffTokensByUserId = handoffTokensByUserId,
		}

		if type(tinyfolkToolLoadoutApi) == "table" and type(tinyfolkToolLoadoutApi.BuildEntryPayload) == "function" then
			local tinyfolkToolApiAny: any = tinyfolkToolLoadoutApi
			local tinyfolkToolLoadoutByUserId: { [number]: any } = {}
			for _, player in ipairs(players) do
				if isPositiveInteger(player.UserId) and type(player.GetAttribute) == "function" then
					local role = player:GetAttribute("Role")
					if role == "Tinyfolk" then
						local payloadOk, payloadResult = pcall(function()
							return tinyfolkToolApiAny.BuildEntryPayload(player, entry.operationId)
						end)
						if payloadOk and type(payloadResult) == "table" and (payloadResult :: any).accepted == true then
							tinyfolkToolLoadoutByUserId[player.UserId] = (payloadResult :: any).payload
						end
					end
				end
			end

			if next(tinyfolkToolLoadoutByUserId) ~= nil then
				(teleportData :: any).tinyfolkToolLoadoutByUserId = tinyfolkToolLoadoutByUserId
			end
		end

		local teleportOk = pcall(function()
			teleportService:TeleportToPrivateServer(placeId, serverCodeOrError, players, nil, teleportData)
		end)
		if not teleportOk then
			return makeFailure("teleport_dispatch_failed", true)
		end

		return makeSuccess({
			accessCode = serverCodeOrError,
			destinationPlaceId = placeId,
		})
	end

	return dispatcher
end

function RealmTeleportDispatcher.CreateDefault(): any
	return RealmTeleportDispatcher.Create(nil)
end

local defaultDispatcher = RealmTeleportDispatcher.CreateDefault()

globalEnv._RealmTeleportDispatcher_QueryAPI = defaultDispatcher

if type(_G) == "table" then
	rawset(_G, "_RealmTeleportDispatcher_QueryAPI", defaultDispatcher)
end

return RealmTeleportDispatcher
