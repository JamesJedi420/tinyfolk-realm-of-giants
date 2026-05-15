--!strict

local SafeZonePolicy = {}

export type SafeZoneDecision = {
	protected: boolean,
	reason: string?,
}

function SafeZonePolicy.EvaluateProtection(
	config: any,
	params: {
		safeZoneState: boolean,
		safeZoneType: any,
		safeZoneProtectionEndsAt: any,
		now: number,
	}
): SafeZoneDecision
	if params.safeZoneState ~= true then
		return { protected = false, reason = nil }
	end

	if type(params.safeZoneType) ~= "string" then
		return { protected = true, reason = "safe_zone_type_missing" }
	end

	local safeZoneType = params.safeZoneType
	local knownTypes = config.SafeZoneTypes
	if safeZoneType == knownTypes.SharedHub then
		return { protected = true, reason = "shared_hub_no_capture" }
	end
	if safeZoneType == knownTypes.RealmExit then
		return { protected = true, reason = "realm_exit_protected" }
	end
	if safeZoneType == knownTypes.RealmEntry then
		if type(params.safeZoneProtectionEndsAt) ~= "number" then
			return { protected = true, reason = "realm_entry_protection_missing_expiry" }
		end
		if params.now <= params.safeZoneProtectionEndsAt then
			return { protected = true, reason = "realm_entry_protected" }
		end
		return { protected = false, reason = nil }
	end

	return { protected = true, reason = "safe_zone_type_unknown" }
end

return SafeZonePolicy
