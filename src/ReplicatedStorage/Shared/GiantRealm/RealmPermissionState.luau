--!strict

local RealmPermissionConfig = (require :: any)("../Config/RealmPermissionConfig")

local RealmPermissionState: any = {}

export type EvaluateContext = {
	accessMode: string?,
	entryType: string?,
}

export type EvaluateResult = {
	accepted: boolean,
	reason: string,
}

local function normalizeAccessMode(accessMode: any): string?
	if type(accessMode) ~= "string" or accessMode == "" then
		return nil
	end
	return accessMode
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

function RealmPermissionState.EvaluateAdmission(context: EvaluateContext): EvaluateResult
	local mode = normalizeAccessMode(context.accessMode) or RealmPermissionConfig.DefaultMode

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

	if mode == RealmPermissionConfig.Modes.InviteOnly then
		return {
			accepted = false,
			reason = RealmPermissionConfig.Reasons.InviteOnly,
		}
	end

	if mode == RealmPermissionConfig.Modes.FriendsOnly then
		return {
			accepted = false,
			reason = RealmPermissionConfig.Reasons.FriendsOnly,
		}
	end

	return {
		accepted = false,
		reason = RealmPermissionConfig.Reasons.ModeInvalid,
	}
end

return RealmPermissionState
