--!strict

-- GiantMacroRouteAccess: role-gated access decisions for Giant-only macro navigation routes (TIN-91).

local GiantMacroRouteAccess = {}

export type AccessParams = {
	role: string?,
	giantOnly: boolean,
	tinyfolkOnly: boolean,
	isEnabled: boolean,
}

export type AccessResult = {
	accepted: boolean,
	reason: string,
}

function GiantMacroRouteAccess.EvaluateGiantMacroRouteAccess(params: AccessParams): AccessResult
	if params.giantOnly ~= true then
		return { accepted = false, reason = "route_not_giant_only" }
	end
	if params.tinyfolkOnly == true then
		return { accepted = false, reason = "route_role_metadata_conflict" }
	end
	if params.role ~= "Giant" then
		return { accepted = false, reason = "requester_not_giant" }
	end
	if params.isEnabled ~= true then
		return { accepted = false, reason = "route_disabled" }
	end
	return { accepted = true, reason = "accepted" }
end

function GiantMacroRouteAccess.EvaluateTinyfolkEscapeRouteAccess(params: AccessParams): AccessResult
	if params.giantOnly == true then
		return { accepted = false, reason = "requester_not_giant" }
	end
	if params.role ~= "Tinyfolk" then
		return { accepted = false, reason = "requester_not_tinyfolk" }
	end
	if params.isEnabled ~= true then
		return { accepted = false, reason = "route_disabled" }
	end
	return { accepted = true, reason = "accepted" }
end

return GiantMacroRouteAccess
