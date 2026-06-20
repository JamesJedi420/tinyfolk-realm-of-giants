--!nocheck
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
		dyadicByUserId = socialState.dyadicByUserId,
		recentEvents = socialState.recentEvents,
		effectSnapshot = effectSnapshot,
		dominantAxis = effectSnapshot.dominantAxis,
		lastEventKind = lastEventKind,
	}
end

local function clearDyadicAttributesForPlayer(player: Player)
	local attrs = SocialEconomyConfig.DyadicAttributes
	player:SetAttribute(attrs.Favor, nil)
	player:SetAttribute(attrs.Control, nil)
end

local function projectDyadicAttributesForUserId(userId: number)
	if type(userId) ~= "number" or userId <= 0 then
		return
	end

	local player = getPlayerByUserId(math.floor(userId))
	if player == nil then
		return
	end

	local userIdKey = tostring(math.floor(userId))
	local relation = if type(socialState.dyadicByUserId) == "table" then socialState.dyadicByUserId[userIdKey] else nil
	if type(relation) ~= "table" then
		clearDyadicAttributesForPlayer(player)
		return
	end

	local attrs = SocialEconomyConfig.DyadicAttributes
	player:SetAttribute(attrs.Favor, math.floor(relation.favor))
	player:SetAttribute(attrs.Control, math.floor(relation.control))
end

local function clearDyadicProjectionForTarget(targetUserId: number)
	if type(targetUserId) ~= "number" or targetUserId <= 0 then
		return
	end

	local player = getPlayerByUserId(math.floor(targetUserId))
	if player ~= nil then
		clearDyadicAttributesForPlayer(player)
	end
end

local function projectAllOnlineDyadicAttributes()
	if type(socialState.dyadicByUserId) ~= "table" then
		return
	end

	for userIdKey in pairs(socialState.dyadicByUserId) do
		local userId = tonumber(userIdKey)
		if type(userId) == "number" and userId > 0 then
			projectDyadicAttributesForUserId(userId)
		end
	end
end

local function clearAllOnlineDyadicAttributes()
	for _, player in Players:GetPlayers() do
		clearDyadicAttributesForPlayer(player :: any)
	end
end

local function applyDyadicProjectionForSocialEvent(input: any)
	if type(input) ~= "table" or type(input.targetUserId) ~= "number" or input.targetUserId <= 0 then
		return
	end

	local eventKind = if type(input.eventKind) == "string" then input.eventKind else nil
	local clearKinds = SocialEconomyConfig.DyadicProjectionClearEventKinds
	if type(eventKind) == "string" and type(clearKinds) == "table" and clearKinds[eventKind] == true then
		clearDyadicProjectionForTarget(input.targetUserId)
		return
	end

	projectDyadicAttributesForUserId(input.targetUserId)
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

local function applyAxisDecay(deltaSeconds: number)
	if not (type(deltaSeconds) == "number" and deltaSeconds > 0) then
		return
	end
	local nextState = SocialEconomyState.ApplyAxisDecay(socialState, deltaSeconds)
	if nextState.favor ~= socialState.favor or nextState.control ~= socialState.control then
		socialState = nextState
		projectRealmOwnerAttributes(nil)
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
		applyDyadicProjectionForSocialEvent(input)
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

local function recordTrophySocialEvent(
	trophyKind: string,
	operationId: string,
	awardedAt: number,
	targetUserId: number?
): any
	local resolvedKind = SocialEconomyState.ResolveTrophyEventKind(trophyKind)
	if resolvedKind == nil then
		return { accepted = false, reason = "trophy_kind_not_mapped" }
	end
	return recordSocialEvent({
		operationId = operationId,
		eventKind = resolvedKind,
		awardedAt = awardedAt,
		targetUserId = targetUserId,
	})
end

local function BuildPersistenceState(): any
	return SocialEconomyState.SerializePersistenceState(socialState)
end

local function ApplyPersistenceState(raw: any): (boolean, string?)
	local applied = SocialEconomyState.ApplyPersistenceState(raw)
	if applied.accepted ~= true then
		return false, applied.reason or "social_economy_apply_failed"
	end
	socialState = applied.state
	projectRealmOwnerAttributes(nil)
	projectAllOnlineDyadicAttributes()
	return true, nil
end

_G._SocialEconomyService_QueryAPI = {
	RecordSocialEvent = recordSocialEventByKind,
	RecordTrophySocialEvent = recordTrophySocialEvent,
	BuildPersistenceState = BuildPersistenceState,
	ApplyPersistenceState = ApplyPersistenceState,
	GetSnapshot = function(): any
		return buildSnapshot(nil)
	end,
	GetEffectSnapshot = function(targetUserId: number?): any
		return SocialEconomyState.ResolveEffectSnapshot(socialState, targetUserId)
	end,
	GetFavor = function(): number
		return socialState.favor
	end,
	GetControl = function(): number
		return socialState.control
	end,
	ResetForTests = function()
		socialState = SocialEconomyState.CreateEmptyState()
		clearAllOnlineDyadicAttributes()
		projectRealmOwnerAttributes(nil)
	end,
	AdvanceDecayForTests = function(deltaSeconds: number)
		applyAxisDecay(deltaSeconds)
	end,
	ClearDyadicProjectionForTarget = clearDyadicProjectionForTarget,
	ProjectDyadicAttributesForTarget = projectDyadicAttributesForUserId,
}

RunService.Heartbeat:Connect(function(deltaTime: number)
	applyAxisDecay(deltaTime)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	clearDyadicAttributesForPlayer(player)
end)

debugLog("SocialEconomyService initialized")
