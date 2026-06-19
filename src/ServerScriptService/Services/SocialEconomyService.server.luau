--!nocheck
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local SocialEconomyConfig = require(Config:WaitForChild("SocialEconomyConfig"))
local SocialEconomyState = require(GiantRealm:WaitForChild("SocialEconomyState"))

local globalEnv: any = getfenv()

local socialState = SocialEconomyState.CreateEmptyState()

local function debugLog(message: string)
	print(string.format("[SocialEconomyService] %s", message))
end

local function getGiantBuildModeQueryApi(): any?
	local queryApi = globalEnv._GiantBuildModeService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._GiantBuildModeService_QueryAPI) == "table" then
		return (_G :: any)._GiantBuildModeService_QueryAPI
	end
	return nil
end

local function getRealmOwnerUserId(): number?
	local buildModeApi = getGiantBuildModeQueryApi()
	if type(buildModeApi) == "table" and type(buildModeApi.GetActiveGiantRealmOwnerUserId) == "function" then
		local ownerUserId = buildModeApi.GetActiveGiantRealmOwnerUserId()
		if type(ownerUserId) == "number" and ownerUserId > 0 then
			return math.floor(ownerUserId)
		end
	end
	return nil
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function buildSnapshot(lastEventKind: string?): any
	local effectSnapshot = SocialEconomyState.ResolveEffectSnapshot(socialState)
	return {
		favor = socialState.favor,
		control = socialState.control,
		recentEvents = socialState.recentEvents,
		effectSnapshot = effectSnapshot,
		dominantAxis = effectSnapshot.dominantAxis,
		lastEventKind = lastEventKind,
	}
end

local function projectRealmOwnerAttributes(lastEventKind: string?)
	local ownerUserId = getRealmOwnerUserId()
	if ownerUserId == nil then
		return
	end

	local owner = getPlayerByUserId(ownerUserId)
	if owner == nil then
		return
	end

	local effectSnapshot = SocialEconomyState.ResolveEffectSnapshot(socialState)
	local attrs = SocialEconomyConfig.StateAttributes
	owner:SetAttribute(attrs.Favor, socialState.favor)
	owner:SetAttribute(attrs.Control, socialState.control)
	owner:SetAttribute(attrs.DominantAxis, effectSnapshot.dominantAxis)
	owner:SetAttribute(attrs.FavorComplianceBonus, effectSnapshot.favorComplianceBonus)
	owner:SetAttribute(attrs.ControlIntimidationBonus, effectSnapshot.controlIntimidationBonus)
	if type(lastEventKind) == "string" then
		owner:SetAttribute(attrs.LastEventKind, lastEventKind)
	end
end

local function recordSocialEvent(input: any): any
	local result = SocialEconomyState.ApplySocialEvent(socialState, input)
	if type(result) ~= "table" then
		return { accepted = false, reason = "apply_social_event_invalid" }
	end
	if result.accepted == true and type(result.state) == "table" then
		socialState = result.state
		local eventKind = if type(input.eventKind) == "string" then input.eventKind else nil
		projectRealmOwnerAttributes(eventKind)
		debugLog(
			string.format(
				"Recorded social event kind=%s operationId=%s favor=%d control=%d",
				tostring(input.eventKind),
				tostring(input.operationId),
				socialState.favor,
				socialState.control
			)
		)
	end
	return result
end

local function recordSocialEventByKind(eventKind: string, operationId: string, awardedAt: number): any
	return recordSocialEvent({
		operationId = operationId,
		eventKind = eventKind,
		awardedAt = awardedAt,
	})
end

local function recordTrophySocialEvent(trophyKind: string, operationId: string, awardedAt: number): any
	local resolvedKind = SocialEconomyState.ResolveTrophyEventKind(trophyKind)
	if resolvedKind == nil then
		return { accepted = false, reason = "trophy_kind_not_mapped" }
	end
	return recordSocialEvent({
		operationId = operationId,
		eventKind = resolvedKind,
		awardedAt = awardedAt,
	})
end

_G._SocialEconomyService_QueryAPI = {
	RecordSocialEvent = recordSocialEventByKind,
	RecordTrophySocialEvent = recordTrophySocialEvent,
	GetSnapshot = function(): any
		return buildSnapshot(nil)
	end,
	GetEffectSnapshot = function(): any
		return SocialEconomyState.ResolveEffectSnapshot(socialState)
	end,
	GetFavor = function(): number
		return socialState.favor
	end,
	GetControl = function(): number
		return socialState.control
	end,
	ResetForTests = function()
		socialState = SocialEconomyState.CreateEmptyState()
		projectRealmOwnerAttributes(nil)
	end,
}

debugLog("SocialEconomyService initialized")
