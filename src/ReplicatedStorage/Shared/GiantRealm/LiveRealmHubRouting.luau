--!strict

local LiveRealmRegistryState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("LiveRealmRegistryState"))
	else (require :: any)("./LiveRealmRegistryState")

local RealmReservedServerAllocationState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmReservedServerAllocationState"))
	else (require :: any)("./RealmReservedServerAllocationState")

local LiveRealmHubRouting: any = {}

export type ResolveAdmissionTargetInput = {
	targetRealmId: string?,
}

export type ResolveAdmissionTargetResult = {
	accepted: boolean,
	reason: string,
	targetRealmId: string?,
	privateServerId: string?,
	resolverPath: string,
}

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

function LiveRealmHubRouting.IsStablePrivateServerFallback(privateServerId: any, ownerUserId: any): boolean
	if not isNonEmptyString(privateServerId) or type(ownerUserId) ~= "number" then
		return false
	end
	return privateServerId == LiveRealmRegistryState.ResolveStablePrivateServerId(ownerUserId, nil)
end

function LiveRealmHubRouting.FindAvailabilityByRealmId(availability: { any }, realmId: any): any?
	if type(availability) ~= "table" or not isNonEmptyString(realmId) then
		return nil
	end

	for _, snapshot in ipairs(availability) do
		if type(snapshot) == "table" and snapshot.realmId == realmId then
			return snapshot
		end
	end

	return nil
end

local function isRaidBoardDiscoverableSnapshot(snapshot: any): boolean
	if type(snapshot) ~= "table" or snapshot.isAvailable ~= true or not isNonEmptyString(snapshot.realmId) then
		return false
	end
	return snapshot.accessMode == "public" or snapshot.accessMode == "raid_enabled"
end

function LiveRealmHubRouting.SelectRaidBoardTarget(availability: { any }): any?
	if type(availability) ~= "table" then
		return nil
	end

	local bestSnapshot: any = nil
	local bestDanger = -1
	for _, snapshot in ipairs(availability) do
		if isRaidBoardDiscoverableSnapshot(snapshot) then
			local dangerRating = if type(snapshot.dangerRating) == "number" then snapshot.dangerRating else 0
			if dangerRating > bestDanger then
				bestDanger = dangerRating
				bestSnapshot = snapshot
			elseif dangerRating == bestDanger and bestSnapshot ~= nil then
				local bestRealmId = if type(bestSnapshot.realmId) == "string" then bestSnapshot.realmId else ""
				local candidateRealmId = snapshot.realmId
				if candidateRealmId < bestRealmId then
					bestSnapshot = snapshot
				end
			elseif bestSnapshot == nil then
				bestSnapshot = snapshot
				bestDanger = dangerRating
			end
		end
	end

	return bestSnapshot
end

local function isDiscoverableSnapshot(snapshot: any): boolean
	if type(snapshot) ~= "table" or snapshot.isAvailable ~= true or not isNonEmptyString(snapshot.realmId) then
		return false
	end
	return snapshot.accessMode == "public" or snapshot.accessMode == "raid_enabled"
end

local function compareRealmTieBreak(candidate: any, incumbent: any): boolean
	local candidateRealmId = if type(candidate.realmId) == "string" then candidate.realmId else ""
	local incumbentRealmId = if type(incumbent.realmId) == "string" then incumbent.realmId else ""
	return candidateRealmId < incumbentRealmId
end

local function selectByDangerPreference(availability: { any }, preferHighest: boolean): any?
	if type(availability) ~= "table" then
		return nil
	end

	local bestSnapshot: any = nil
	local bestDanger: number? = nil
	for _, snapshot in ipairs(availability) do
		if isDiscoverableSnapshot(snapshot) then
			local dangerRating = if type(snapshot.dangerRating) == "number" then snapshot.dangerRating else 0
			if bestSnapshot == nil then
				bestSnapshot = snapshot
				bestDanger = dangerRating
				continue
			end

			local shouldReplace = if preferHighest
				then dangerRating > (bestDanger :: number)
				else dangerRating < (bestDanger :: number)
			if shouldReplace then
				bestSnapshot = snapshot
				bestDanger = dangerRating
			elseif dangerRating == bestDanger and compareRealmTieBreak(snapshot, bestSnapshot) then
				bestSnapshot = snapshot
			end
		end
	end

	return bestSnapshot
end

function LiveRealmHubRouting.SelectMatchmakingTarget(
	availability: { any },
	desiredActivity: any,
	_skillBand: any?,
	_toolTier: any?
): any?
	if type(availability) ~= "table" or type(desiredActivity) ~= "string" then
		return nil
	end

	if desiredActivity == "raid" then
		return LiveRealmHubRouting.SelectRaidBoardTarget(availability)
	end
	if desiredActivity == "rescue" then
		return selectByDangerPreference(availability, true)
	end
	if desiredActivity == "scouting" then
		return selectByDangerPreference(availability, false)
	end
	if desiredActivity == "work_contract" then
		local bestSnapshot: any = nil
		local bestDistance = math.huge
		for _, snapshot in ipairs(availability) do
			if isDiscoverableSnapshot(snapshot) then
				local dangerRating = if type(snapshot.dangerRating) == "number" then snapshot.dangerRating else 0
				local distance = math.abs(dangerRating - 0.5)
				if distance < bestDistance then
					bestDistance = distance
					bestSnapshot = snapshot
				elseif
					distance == bestDistance
					and bestSnapshot ~= nil
					and compareRealmTieBreak(snapshot, bestSnapshot)
				then
					bestSnapshot = snapshot
				elseif bestSnapshot == nil then
					bestSnapshot = snapshot
					bestDistance = distance
				end
			end
		end
		return bestSnapshot
	end

	return nil
end

export type ResolveTeleportAccessCodeResult = {
	accessCode: string?,
	resolverPath: string,
}

function LiveRealmHubRouting.ResolveTeleportAccessCode(snapshot: any?, reservedAccessCode: any?): string?
	local detailed = LiveRealmHubRouting.ResolveTeleportAccessCodeDetailed(snapshot, reservedAccessCode, nil)
	return detailed.accessCode
end

function LiveRealmHubRouting.ResolveTeleportAccessCodeDetailed(
	snapshot: any?,
	reservedAccessCode: any?,
	ownerUserId: any?
): ResolveTeleportAccessCodeResult
	local resolvedOwnerUserId = if type(snapshot) == "table" then snapshot.ownerUserId else ownerUserId

	if type(snapshot) ~= "table" or snapshot.isAvailable ~= true then
		if
			type(resolvedOwnerUserId) == "number"
			and RealmReservedServerAllocationState.IsUsableReservedAccessCode(reservedAccessCode, resolvedOwnerUserId)
		then
			return {
				accessCode = reservedAccessCode,
				resolverPath = "durable_allocation",
			}
		end
		return {
			accessCode = nil,
			resolverPath = "unresolved",
		}
	end

	if isNonEmptyString(snapshot.privateServerId) then
		if not LiveRealmHubRouting.IsStablePrivateServerFallback(snapshot.privateServerId, snapshot.ownerUserId) then
			return {
				accessCode = snapshot.privateServerId,
				resolverPath = "live_registry",
			}
		end
	end

	if
		type(snapshot.ownerUserId) == "number"
		and RealmReservedServerAllocationState.IsUsableReservedAccessCode(reservedAccessCode, snapshot.ownerUserId)
	then
		return {
			accessCode = reservedAccessCode,
			resolverPath = "durable_allocation",
		}
	end

	return {
		accessCode = nil,
		resolverPath = "unresolved",
	}
end

function LiveRealmHubRouting.ResolveAdmissionTarget(
	input: ResolveAdmissionTargetInput,
	availability: { any }
): ResolveAdmissionTargetResult
	if type(availability) ~= "table" then
		return {
			accepted = false,
			reason = "live_registry_unavailable",
			targetRealmId = nil,
			privateServerId = nil,
			resolverPath = "hub_unavailable",
		}
	end

	if isNonEmptyString(input.targetRealmId) then
		local snapshot = LiveRealmHubRouting.FindAvailabilityByRealmId(availability, input.targetRealmId)
		if snapshot == nil then
			return {
				accepted = false,
				reason = "target_realm_unavailable",
				targetRealmId = nil,
				privateServerId = nil,
				resolverPath = "hub_direct_missing",
			}
		end
		if snapshot.isAvailable ~= true then
			return {
				accepted = false,
				reason = "target_realm_unavailable",
				targetRealmId = input.targetRealmId,
				privateServerId = nil,
				resolverPath = "hub_direct_offline",
			}
		end

		return {
			accepted = true,
			reason = "accepted",
			targetRealmId = snapshot.realmId,
			privateServerId = snapshot.privateServerId,
			resolverPath = "hub_direct",
		}
	end

	local raidBoardTarget = LiveRealmHubRouting.SelectRaidBoardTarget(availability)
	if raidBoardTarget == nil then
		return {
			accepted = false,
			reason = "target_realm_unavailable",
			targetRealmId = nil,
			privateServerId = nil,
			resolverPath = "hub_raid_board_empty",
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		targetRealmId = raidBoardTarget.realmId,
		privateServerId = raidBoardTarget.privateServerId,
		resolverPath = "hub_raid_board",
	}
end

return LiveRealmHubRouting
