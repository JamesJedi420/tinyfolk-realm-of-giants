--!strict

local RealmPermissionConfig = (require :: any)("../Config/RealmPermissionConfig")

local RealmPermissionState: any = {}

export type FriendsChecker = (ownerUserId: number, requesterUserId: number) -> boolean

export type EvaluateContext = {
	accessMode: string?,
	entryType: string?,
	requesterUserIds: { number }?,
	realmOwnerUserId: number?,
	inviteAllowlistUserIds: { number }?,
	isFriendsWithOwner: FriendsChecker?,
	resolverProbe: boolean?,
}

export type EvaluateResult = {
	accepted: boolean,
	reason: string,
}

local VALID_PERMISSION_MODES: { [string]: boolean } = {
	[RealmPermissionConfig.Modes.Public] = true,
	[RealmPermissionConfig.Modes.RaidEnabled] = true,
	[RealmPermissionConfig.Modes.Locked] = true,
	[RealmPermissionConfig.Modes.InviteOnly] = true,
	[RealmPermissionConfig.Modes.FriendsOnly] = true,
}

local INVITE_ENTRY_TYPES: { [string]: boolean } = {
	[RealmPermissionConfig.EntryTypes.DirectInvite] = true,
	[RealmPermissionConfig.EntryTypes.RescueContract] = true,
}

local function normalizeAccessMode(accessMode: any): string?
	if type(accessMode) ~= "string" or accessMode == "" then
		return nil
	end
	return accessMode
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
end

local function collectRequesterUserIds(requesterUserIds: any): { number }
	if type(requesterUserIds) ~= "table" then
		return {}
	end

	local resolved: { number } = {}
	for _, userId in ipairs(requesterUserIds) do
		if isPositiveInteger(userId) then
			table.insert(resolved, math.floor(userId))
		end
	end
	return resolved
end

local function buildAllowlistLookup(allowlistUserIds: any): { [number]: boolean }
	local lookup: { [number]: boolean } = {}
	if type(allowlistUserIds) ~= "table" then
		return lookup
	end

	for _, userId in ipairs(allowlistUserIds) do
		if isPositiveInteger(userId) then
			lookup[math.floor(userId)] = true
		end
	end
	return lookup
end

function RealmPermissionState.IsValidPermissionMode(accessMode: any): boolean
	local normalized = normalizeAccessMode(accessMode)
	if normalized == nil then
		return false
	end
	return VALID_PERMISSION_MODES[normalized] == true
end

function RealmPermissionState.NormalizeRegistryAccessMode(registryAccessMode: any): string
	if registryAccessMode == "private" then
		return RealmPermissionConfig.Modes.Locked
	end
	if registryAccessMode == RealmPermissionConfig.Modes.InviteOnly then
		return RealmPermissionConfig.Modes.InviteOnly
	end
	if registryAccessMode == RealmPermissionConfig.Modes.Public then
		return RealmPermissionConfig.Modes.Public
	end
	if registryAccessMode == RealmPermissionConfig.Modes.RaidEnabled then
		return RealmPermissionConfig.Modes.RaidEnabled
	end
	if registryAccessMode == RealmPermissionConfig.Modes.Locked then
		return RealmPermissionConfig.Modes.Locked
	end
	if registryAccessMode == RealmPermissionConfig.Modes.FriendsOnly then
		return RealmPermissionConfig.Modes.FriendsOnly
	end

	local normalized = normalizeAccessMode(registryAccessMode)
	if normalized ~= nil then
		return normalized
	end
	return RealmPermissionConfig.DefaultMode
end

function RealmPermissionState.ToRegistryAccessMode(permissionMode: any): string?
	local normalized = normalizeAccessMode(permissionMode)
	if normalized == nil or VALID_PERMISSION_MODES[normalized] ~= true then
		return nil
	end

	if normalized == RealmPermissionConfig.Modes.Locked then
		return "private"
	end
	return normalized
end

function RealmPermissionState.IsDiscoverableRegistryAccessMode(accessMode: any): boolean
	local normalized = normalizeAccessMode(accessMode)
	return normalized == RealmPermissionConfig.Modes.Public or normalized == RealmPermissionConfig.Modes.RaidEnabled
end

function RealmPermissionState.ParseRealmOwnerUserId(realmId: any): number?
	if type(realmId) ~= "string" then
		return nil
	end
	local ownerUserId = tonumber(string.match(realmId, "^giant_realm_(%d+)$"))
	if not isPositiveInteger(ownerUserId) then
		return nil
	end
	return math.floor(ownerUserId :: number)
end

function RealmPermissionState.AreAllRequestersAllowlisted(
	requesterUserIds: { number },
	allowlistUserIds: { number }?
): boolean
	local requesters = collectRequesterUserIds(requesterUserIds)
	if #requesters == 0 then
		return false
	end

	local allowlist = buildAllowlistLookup(allowlistUserIds)
	for _, userId in ipairs(requesters) do
		if allowlist[userId] ~= true then
			return false
		end
	end
	return true
end

function RealmPermissionState.AreAllRequestersFriends(
	requesterUserIds: { number },
	realmOwnerUserId: number,
	friendsChecker: FriendsChecker?
): boolean
	if not isPositiveInteger(realmOwnerUserId) then
		return false
	end
	if type(friendsChecker) ~= "function" then
		return false
	end

	local requesters = collectRequesterUserIds(requesterUserIds)
	if #requesters == 0 then
		return false
	end

	local ownerUserId = math.floor(realmOwnerUserId)
	for _, userId in ipairs(requesters) do
		local ok, isFriend = pcall(friendsChecker, ownerUserId, userId)
		if not ok or isFriend ~= true then
			return false
		end
	end
	return true
end

function RealmPermissionState.EvaluateAdmission(context: EvaluateContext): EvaluateResult
	local mode = normalizeAccessMode(context.accessMode) or RealmPermissionConfig.DefaultMode
	local entryType = if type(context.entryType) == "string" then context.entryType else nil
	local resolverProbe = context.resolverProbe == true

	if mode == RealmPermissionConfig.Modes.Public or mode == RealmPermissionConfig.Modes.RaidEnabled then
		return {
			accepted = true,
			reason = RealmPermissionConfig.Reasons.Accepted,
		}
	end

	if mode == RealmPermissionConfig.Modes.Locked then
		return {
			accepted = false,
			reason = RealmPermissionConfig.Reasons.Locked,
		}
	end

	if resolverProbe then
		return {
			accepted = true,
			reason = RealmPermissionConfig.Reasons.Accepted,
		}
	end

	if mode == RealmPermissionConfig.Modes.InviteOnly then
		if INVITE_ENTRY_TYPES[entryType or ""] ~= true then
			return {
				accepted = false,
				reason = RealmPermissionConfig.Reasons.InviteOnly,
			}
		end
		if
			not RealmPermissionState.AreAllRequestersAllowlisted(
				collectRequesterUserIds(context.requesterUserIds),
				context.inviteAllowlistUserIds
			)
		then
			return {
				accepted = false,
				reason = RealmPermissionConfig.Reasons.NotInvited,
			}
		end
		return {
			accepted = true,
			reason = RealmPermissionConfig.Reasons.Accepted,
		}
	end

	if mode == RealmPermissionConfig.Modes.FriendsOnly then
		local ownerUserId = context.realmOwnerUserId
		if not isPositiveInteger(ownerUserId) then
			return {
				accepted = false,
				reason = RealmPermissionConfig.Reasons.FriendsOnly,
			}
		end
		if
			not RealmPermissionState.AreAllRequestersFriends(
				collectRequesterUserIds(context.requesterUserIds),
				ownerUserId :: number,
				context.isFriendsWithOwner
			)
		then
			return {
				accepted = false,
				reason = RealmPermissionConfig.Reasons.NotFriend,
			}
		end
		return {
			accepted = true,
			reason = RealmPermissionConfig.Reasons.Accepted,
		}
	end

	return {
		accepted = false,
		reason = RealmPermissionConfig.Reasons.ModeInvalid,
	}
end

return RealmPermissionState
