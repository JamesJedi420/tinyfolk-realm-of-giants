--!strict

local RealmTeleportDispatcher: any = {}
local globalEnv: any = getfenv()

local LiveRealmHubRouting = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("LiveRealmHubRouting")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")

local RealmReservedServerAllocationState = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmReservedServerAllocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmReservedServerAllocationState")

local PublishedClientTeleportEvidenceCaller = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PublishedClientTeleportEvidenceCaller"))
	else (require :: any)("./PublishedClientTeleportEvidenceCaller")

local TeleportEvidencePhases = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("PublishedClientTeleportEvidence")
	).Phases
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/PublishedClientTeleportEvidence").Phases

local RealmTransferState = if game ~= nil and type(game.GetService) == "function"
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTransferState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local DEFAULT_AVAILABILITY_LIMIT = 25

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

local function resolveLiveRegistryHubApi(config: any?): any?
	local configAny: any = config
	if type(configAny) == "table" and (configAny :: any).liveRegistryHubApi ~= nil then
		return (configAny :: any).liveRegistryHubApi
	end

	return getGlobalTable("_LiveRealmRegistryHubSurface_QueryAPI")
end

local function readLiveRealmAvailability(config: any?, limit: number?, at: number?): { any }?
	local configAny: any = config
	local listOverride = if type(configAny) == "table" then configAny.listLiveRealmAvailability else nil
	if type(listOverride) == "function" then
		local ok, availability = pcall(listOverride, limit, at)
		if ok and type(availability) == "table" then
			return availability
		end
		return nil
	end

	local hubApi = resolveLiveRegistryHubApi(config)
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

local function resolveAllocationApi(config: any?): any?
	local configAny: any = config
	if type(configAny) == "table" and (configAny :: any).allocationApi ~= nil then
		return (configAny :: any).allocationApi
	end

	return getGlobalTable("_RealmReservedServerAllocationService_QueryAPI")
end

local function resolveReservedAccessCode(config: any?, targetRealmId: string): (string?, string?)
	local configAny: any = config
	local resolveOverride = if type(configAny) == "table" then configAny.resolveReservedAccessCode else nil
	if type(resolveOverride) == "function" then
		local ok, result = pcall(resolveOverride, targetRealmId)
		if ok and type(result) == "table" and result.accepted == true and isNonEmptyString(result.accessCode) then
			return result.accessCode, nil
		end
		if ok and type(result) == "table" and type(result.reason) == "string" then
			return nil, result.reason
		end
		return nil, "reserved_server_unallocated"
	end

	local allocationApi = resolveAllocationApi(config)
	if type(allocationApi) ~= "table" or type((allocationApi :: any).ResolveAccessCodeForRealm) ~= "function" then
		return nil, "allocation_api_unavailable"
	end

	local ok, result = pcall(function()
		return (allocationApi :: any).ResolveAccessCodeForRealm(targetRealmId)
	end)
	if not ok or type(result) ~= "table" then
		return nil, "allocation_resolve_failed"
	end
	if result.accepted ~= true or not isNonEmptyString(result.accessCode) then
		return nil, if type(result.reason) == "string" then result.reason else "reserved_server_unallocated"
	end

	return result.accessCode, nil
end

local function resolveRegistryTeleportAccessCode(config: any?, entry: any): (string?, string?, string?)
	local targetRealmId = if type(entry) == "table" then entry.targetRealmId else nil
	if not isNonEmptyString(targetRealmId) then
		return nil, "target_realm_id_invalid", "unresolved"
	end

	local availability = readLiveRealmAvailability(config, DEFAULT_AVAILABILITY_LIMIT, nil)
	local snapshot = if availability ~= nil
		then LiveRealmHubRouting.FindAvailabilityByRealmId(availability, targetRealmId)
		else nil

	if availability ~= nil then
		local hubResult = LiveRealmHubRouting.ResolveAdmissionTarget({
			targetRealmId = targetRealmId,
		}, availability)
		if hubResult.accepted ~= true then
			return nil, hubResult.reason, "unresolved"
		end

		local admissionOk, admissionReason =
			RealmReservedServerAllocationState.ValidateDispatchAdmission(entry.entryType, snapshot)
		if not admissionOk then
			return nil, admissionReason, "unresolved"
		end
	end

	local reservedAccessCode, allocationReason = resolveReservedAccessCode(config, targetRealmId)
	local ownerUserId = RealmTransferState.ParseRealmOwnerUserId(targetRealmId)
	local resolved = LiveRealmHubRouting.ResolveTeleportAccessCodeDetailed(snapshot, reservedAccessCode, ownerUserId)
	if isNonEmptyString(resolved.accessCode) then
		return resolved.accessCode, nil, resolved.resolverPath
	end

	if allocationReason == "reserved_server_unallocated" then
		return nil, "reserved_server_unallocated", "unresolved"
	end

	return nil, allocationReason or "target_private_server_unresolved", "unresolved"
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

local function appendPayloadFailure(failures: { any }, maxEntries: number, userId: number, reason: string)
	if #failures >= maxEntries then
		return
	end
	table.insert(failures, {
		userId = userId,
		reason = reason,
	})
end

local function mapPayloadFailureReasonToPublic(reason: string): string
	if reason == "player_profile_not_loaded" then
		return "profile_unavailable"
	end
	if reason == "tool_missing" or reason == "tool_locked_or_unavailable" then
		return "loadout_unavailable"
	end
	if reason == "tool_cooldown_metadata_missing" then
		return "payload_invalid"
	end
	if reason == "tinyfolk_role_required" then
		return "role_not_eligible"
	end
	if reason == "tinyfolk_tool_payload_build_failed" then
		return "payload_build_failed"
	end
	return "payload_rejected"
end

local function buildDispatchEvidenceInput(entry: any, userId: number, phase: string, resultReason: string): any
	local memberUserIds = if type(entry) == "table" and type(entry.partyMemberUserIds) == "table"
		then entry.partyMemberUserIds
		else nil
	return {
		userId = userId,
		realmId = if type(entry) == "table" then entry.targetRealmId else nil,
		partyId = if type(entry) == "table" then entry.partyId else nil,
		operationId = if type(entry) == "table" then entry.operationId else nil,
		partyMemberCount = if memberUserIds ~= nil then #memberUserIds else nil,
		targetPlaceId = if type(entry) == "table" then entry.targetPlaceId else nil,
		phase = phase,
		resultReason = resultReason,
	}
end

local function recordDispatchEvidence(entry: any, userId: number, phase: string, resultReason: string)
	pcall(PublishedClientTeleportEvidenceCaller.Record, buildDispatchEvidenceInput(entry, userId, phase, resultReason))
end

local function recordDispatchFailureForMembers(entry: any, memberUserIds: { number }?, resultReason: string)
	if type(memberUserIds) ~= "table" then
		return
	end
	for _, userId in ipairs(memberUserIds) do
		recordDispatchEvidence(entry, userId, TeleportEvidencePhases.Failed, resultReason)
	end
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
			recordDispatchFailureForMembers(entry, memberUserIds, "players_service_unavailable")
			return makeFailure("players_service_unavailable", true)
		end

		local players: { any } = {}
		for _, userId in ipairs(memberUserIds) do
			local player = playersService:GetPlayerByUserId(userId)
			if player == nil then
				recordDispatchFailureForMembers(entry, memberUserIds, "party_player_missing")
				return makeFailure("party_player_missing", true)
			end
			table.insert(players, player)
		end

		if type(handoffApi) ~= "table" or type(handoffApi.BeginCrossServerHandoff) ~= "function" then
			recordDispatchFailureForMembers(entry, memberUserIds, "handoff_api_unavailable")
			return makeFailure("handoff_api_unavailable", true)
		end

		local handoffTokensByUserId: { [number]: string } = {}
		local payloadFailureUserIds: { [number]: boolean } = {}
		local tinyfolkToolLoadoutByUserId: { [number]: any } = {}
		local tinyfolkToolPayloadFailures: { any } = {}
		local maxPayloadFailureDiagnostics = 5

		if type(tinyfolkToolLoadoutApi) == "table" and type(tinyfolkToolLoadoutApi.BuildEntryPayload) == "function" then
			local tinyfolkToolApiAny: any = tinyfolkToolLoadoutApi
			for _, player in ipairs(players) do
				if isPositiveInteger(player.UserId) and type(player.GetAttribute) == "function" then
					local role = player:GetAttribute("Role")
					if role == "Tinyfolk" then
						local payloadOk, payloadResult = pcall(function()
							return tinyfolkToolApiAny.BuildEntryPayload(player, entry.operationId)
						end)
						if payloadOk and type(payloadResult) == "table" and (payloadResult :: any).accepted == true then
							tinyfolkToolLoadoutByUserId[player.UserId] = (payloadResult :: any).payload
						else
							local resultReason = if payloadOk and type(payloadResult) == "table"
								then (payloadResult :: any).reason
								else "tinyfolk_tool_payload_build_failed"
							local publicReason = mapPayloadFailureReasonToPublic(
								if type(resultReason) == "string" and resultReason ~= ""
									then resultReason
									else "tinyfolk_tool_payload_rejected"
							)
							payloadFailureUserIds[player.UserId] = true
							appendPayloadFailure(
								tinyfolkToolPayloadFailures,
								maxPayloadFailureDiagnostics,
								player.UserId,
								publicReason
							)
						end
					end
				end
			end
		end

		local playersToTeleport: { any } = {}
		local transferredUserIds: { number } = {}
		for _, player in ipairs(players) do
			if isPositiveInteger(player.UserId) and payloadFailureUserIds[player.UserId] == true then
				continue
			end
			table.insert(playersToTeleport, player)
			if isPositiveInteger(player.UserId) then
				table.insert(transferredUserIds, player.UserId)
			end
		end

		if #playersToTeleport <= 0 then
			recordDispatchFailureForMembers(entry, memberUserIds, "party_payload_rejected")
			return makeFailure("party_payload_rejected", false)
		end

		for _, player in ipairs(playersToTeleport) do
			local handoffOk, handoffResult = pcall(function()
				return handoffApi.BeginCrossServerHandoff(player, {
					operationId = entry.operationId,
					partyId = entry.partyId,
					targetRealmId = entry.targetRealmId,
					targetPlaceId = entry.targetPlaceId,
				})
			end)
			if not handoffOk or type(handoffResult) ~= "table" or handoffResult.ok ~= true then
				recordDispatchFailureForMembers(entry, memberUserIds, "handoff_begin_failed")
				return makeFailure("handoff_begin_failed", true)
			end
			if isPositiveInteger(player.UserId) and isNonEmptyString(handoffResult.handoffToken) then
				handoffTokensByUserId[player.UserId] = handoffResult.handoffToken
			end
		end

		if type(teleportService) ~= "table" then
			recordDispatchFailureForMembers(entry, memberUserIds, "teleport_service_unavailable")
			return makeFailure("teleport_service_unavailable", true)
		end
		if type(teleportService.TeleportToPrivateServer) ~= "function" then
			recordDispatchFailureForMembers(entry, memberUserIds, "teleport_private_server_unavailable")
			return makeFailure("teleport_private_server_unavailable", true)
		end

		local placeId = resolveDestinationPlaceId(config, entry)
		if placeId == nil then
			recordDispatchFailureForMembers(entry, memberUserIds, "destination_place_unresolved")
			return makeFailure("destination_place_unresolved", true)
		end

		local registryAccessCode, registryReason, resolverPath = resolveRegistryTeleportAccessCode(config, entry)
		local serverCodeOrError: string? = nil
		if registryAccessCode ~= nil then
			serverCodeOrError = registryAccessCode
		else
			if registryReason == "target_realm_unavailable" or registryReason == "entry_access_mode_rejected" then
				recordDispatchFailureForMembers(entry, memberUserIds, registryReason)
				return makeFailure(registryReason, false)
			end
			recordDispatchFailureForMembers(entry, memberUserIds, registryReason or "target_private_server_unresolved")
			return makeFailure(registryReason or "target_private_server_unresolved", true)
		end

		if not isNonEmptyString(serverCodeOrError) then
			recordDispatchFailureForMembers(entry, memberUserIds, "target_private_server_unresolved")
			return makeFailure("target_private_server_unresolved", true)
		end

		local teleportData = {
			operationId = entry.operationId,
			partyId = entry.partyId,
			targetRealmId = entry.targetRealmId,
			handoffTokensByUserId = handoffTokensByUserId,
		}

		if next(tinyfolkToolLoadoutByUserId) ~= nil then
			(teleportData :: any).tinyfolkToolLoadoutByUserId = tinyfolkToolLoadoutByUserId
		end
		if #tinyfolkToolPayloadFailures > 0 then
			(teleportData :: any).tinyfolkToolPayloadFailures = tinyfolkToolPayloadFailures
		end

		for _, player in ipairs(playersToTeleport) do
			if isPositiveInteger(player.UserId) then
				recordDispatchEvidence(entry, player.UserId, TeleportEvidencePhases.Teleporting, "accepted")
			end
		end

		local teleportOk = pcall(function()
			teleportService:TeleportToPrivateServer(
				placeId,
				serverCodeOrError :: string,
				playersToTeleport,
				nil,
				teleportData
			)
		end)
		if not teleportOk then
			recordDispatchFailureForMembers(entry, memberUserIds, "teleport_dispatch_failed")
			return makeFailure("teleport_dispatch_failed", true)
		end

		local extraResult: any = {
			accessCode = serverCodeOrError,
			destinationPlaceId = placeId,
			registryAccessCodeResolved = registryAccessCode ~= nil,
			accessCodeResolverPath = resolverPath,
			transferredUserIds = transferredUserIds,
		}
		if #tinyfolkToolPayloadFailures > 0 then
			extraResult.tinyfolkToolPayloadFailures = tinyfolkToolPayloadFailures
		end
		return makeSuccess(extraResult)
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
