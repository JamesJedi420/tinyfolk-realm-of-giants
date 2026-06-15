--!strict

local LiveRealmRegistryState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("LiveRealmRegistryState"))
	else (require :: any)("./LiveRealmRegistryState")

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

function LiveRealmHubRouting.SelectRaidBoardTarget(availability: { any }): any?
	if type(availability) ~= "table" then
		return nil
	end

	for _, snapshot in ipairs(availability) do
		if type(snapshot) == "table" and snapshot.isAvailable == true and isNonEmptyString(snapshot.realmId) then
			return snapshot
		end
	end

	return nil
end

function LiveRealmHubRouting.ResolveTeleportAccessCode(snapshot: any?): string?
	if type(snapshot) ~= "table" or snapshot.isAvailable ~= true then
		return nil
	end
	if snapshot.accessMode ~= LiveRealmRegistryState.AccessMode.Private then
		return nil
	end
	if not isNonEmptyString(snapshot.privateServerId) then
		return nil
	end
	if LiveRealmHubRouting.IsStablePrivateServerFallback(snapshot.privateServerId, snapshot.ownerUserId) then
		return nil
	end
	return snapshot.privateServerId
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
