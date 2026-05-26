--!strict

local MemoryStoreStructurePolicy: any = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local RealmAdmissionPartyResolverService: any = {}
local globalEnv: any = getfenv()

local DEFAULT_TTL_SECONDS = 600
local PRIMARY_PARTY_ATTRIBUTE = "RealmAdmissionPartyId"
local LEGACY_PARTY_ATTRIBUTE = "PartyId"

type PartyRecord = {
	memberUserIds: { number },
	expiresAt: number,
}

local partyMembersByPartyId: { [string]: PartyRecord? } = {}
local nowFn: (() -> number)? = nil
local playersServiceOverride: any = nil

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
	if value <= 0 or value % 1 ~= 0 then
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

local function resolveNow(at: any?): number
	if isFiniteNumber(at) then
		return at :: number
	end
	if type(nowFn) == "function" then
		local resolved = nowFn()
		if isFiniteNumber(resolved) then
			return resolved
		end
	end
	return os.clock()
end

local function resolveTtlSeconds(ttlSeconds: any?): number
	if isFiniteNumber(ttlSeconds) and ttlSeconds > 0 then
		return ttlSeconds :: number
	end

	local structurePolicyAny: any = MemoryStoreStructurePolicy
	if type(structurePolicyAny) == "table" and type((structurePolicyAny :: any).ResolveExpiration) == "function" then
		local ttlResultAny: any = (structurePolicyAny :: any).ResolveExpiration("realmAdmissionQueue")
		if type(ttlResultAny) == "table" and ttlResultAny.ok == true then
			local ttlTable: any = ttlResultAny
			local resolvedTtlSeconds: any = ttlTable.ttlSeconds
			if isFiniteNumber(resolvedTtlSeconds) and resolvedTtlSeconds > 0 then
				return resolvedTtlSeconds :: number
			end
		end
	end

	return DEFAULT_TTL_SECONDS
end

local function cloneUserIds(userIds: { number }): { number }
	local cloned: { number } = {}
	for _, userId in ipairs(userIds) do
		table.insert(cloned, userId)
	end
	table.sort(cloned)
	return cloned
end

local function normalizeUserIds(values: any): { number }?
	if type(values) ~= "table" then
		return nil
	end

	local seen: { [number]: boolean } = {}
	local normalized: { number } = {}
	for _, value in ipairs(values) do
		if isPositiveInteger(value) then
			local userId = value :: number
			if seen[userId] ~= true then
				seen[userId] = true
				table.insert(normalized, userId)
			end
		end
	end

	if #normalized <= 0 then
		return nil
	end

	table.sort(normalized)
	return normalized
end

local function pruneExpired(at: number)
	for partyId, record in pairs(partyMembersByPartyId) do
		if record ~= nil and (record :: PartyRecord).expiresAt <= at then
			partyMembersByPartyId[partyId] = nil
		end
	end
end

local function resolvePlayersService(): any?
	if playersServiceOverride ~= nil then
		return playersServiceOverride
	end

	if game ~= nil and type(game.GetService) == "function" then
		local ok, players = pcall(function()
			return game:GetService("Players")
		end)
		if ok and players ~= nil then
			return players
		end
	end

	return nil
end

local function resolveFromPlayerAttributes(partyId: string): { number }?
	local playersService = resolvePlayersService()
	if type(playersService) ~= "table" or type(playersService.GetPlayers) ~= "function" then
		return nil
	end

	local ok, players = pcall(function()
		return playersService:GetPlayers()
	end)
	if not ok or type(players) ~= "table" then
		return nil
	end

	local members: { number } = {}
	local seen: { [number]: boolean } = {}

	for _, player in ipairs(players) do
		if type(player) == "table" or typeof(player) == "Instance" then
			local attributeValue = nil
			if type((player :: any).GetAttribute) == "function" then
				attributeValue = (player :: any):GetAttribute(PRIMARY_PARTY_ATTRIBUTE)
				if not isNonEmptyString(attributeValue) then
					attributeValue = (player :: any):GetAttribute(LEGACY_PARTY_ATTRIBUTE)
				end
			end

			if attributeValue == partyId and isPositiveInteger((player :: any).UserId) then
				local userId = (player :: any).UserId
				if seen[userId] ~= true then
					seen[userId] = true
					table.insert(members, userId)
				end
			end
		end
	end

	if #members <= 0 then
		return nil
	end

	table.sort(members)
	return members
end

function RealmAdmissionPartyResolverService.ConfigureForTests(config: any?)
	local configAny: any = config
	nowFn = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else nil
	playersServiceOverride = if type(configAny) == "table" then configAny.playersService else nil
end

function RealmAdmissionPartyResolverService.ResetForTests()
	partyMembersByPartyId = {}
	nowFn = nil
	playersServiceOverride = nil
end

function RealmAdmissionPartyResolverService.RegisterPartyMembers(input: any): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "input_invalid",
		}
	end

	local partyId = input.partyId
	if not isNonEmptyString(partyId) then
		return {
			accepted = false,
			reason = "party_id_invalid",
		}
	end

	local normalizedUserIds = normalizeUserIds(input.memberUserIds)
	if normalizedUserIds == nil then
		return {
			accepted = false,
			reason = "member_user_ids_invalid",
		}
	end

	local nowAt = resolveNow(input.at)
	pruneExpired(nowAt)

	partyMembersByPartyId[partyId] = {
		memberUserIds = normalizedUserIds,
		expiresAt = nowAt + resolveTtlSeconds(input.ttlSeconds),
	}

	return {
		accepted = true,
		reason = "accepted",
		memberUserIds = cloneUserIds(normalizedUserIds),
	}
end

function RealmAdmissionPartyResolverService.UnregisterParty(partyId: any): any
	if not isNonEmptyString(partyId) then
		return {
			accepted = false,
			reason = "party_id_invalid",
		}
	end

	partyMembersByPartyId[partyId] = nil
	return {
		accepted = true,
		reason = "accepted",
	}
end

function RealmAdmissionPartyResolverService.ResolvePartyMemberUserIds(partyId: any, at: any?): { number }
	if not isNonEmptyString(partyId) then
		return {}
	end

	local nowAt = resolveNow(at)
	pruneExpired(nowAt)

	local record = partyMembersByPartyId[partyId]
	if record ~= nil then
		return cloneUserIds(record.memberUserIds)
	end

	local attributeMembers = resolveFromPlayerAttributes(partyId)
	if attributeMembers ~= nil then
		return attributeMembers
	end

	return {}
end

globalEnv._RealmAdmissionPartyResolver_QueryAPI = {
	ResolvePartyMemberUserIds = function(partyId: any, at: any?): { number }
		return RealmAdmissionPartyResolverService.ResolvePartyMemberUserIds(partyId, at)
	end,
	RegisterPartyMembers = function(input: any): any
		return RealmAdmissionPartyResolverService.RegisterPartyMembers(input)
	end,
	UnregisterParty = function(partyId: any): any
		return RealmAdmissionPartyResolverService.UnregisterParty(partyId)
	end,
	ConfigureForTests = function(config: any?)
		RealmAdmissionPartyResolverService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		RealmAdmissionPartyResolverService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RealmAdmissionPartyResolver_QueryAPI", globalEnv._RealmAdmissionPartyResolver_QueryAPI)
end

return RealmAdmissionPartyResolverService
