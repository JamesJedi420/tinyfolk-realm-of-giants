--!strict

local PlayerCreatedRouteState: any = {}

export type RouteRecord = {
	routeId: string,
	createdByUserId: number,
	createdAt: number,
	enabled: boolean,
	expiresAt: number?,
}

local function finiteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function nonNegativeFiniteNumber(value: any): boolean
	if not finiteNumber(value) then
		return false
	end
	return (value :: number) >= 0
end

function PlayerCreatedRouteState.ValidateRouteRecord(record: any): any
	if type(record) ~= "table" then
		return { valid = false, reason = "route_record_invalid" }
	end
	if type(record.routeId) ~= "string" or record.routeId == "" then
		return { valid = false, reason = "route_id_invalid" }
	end
	if type(record.createdByUserId) ~= "number" or record.createdByUserId <= 0 or record.createdByUserId % 1 ~= 0 then
		return { valid = false, reason = "created_by_user_id_invalid" }
	end
	if not nonNegativeFiniteNumber(record.createdAt) then
		return { valid = false, reason = "created_at_invalid" }
	end
	if type(record.enabled) ~= "boolean" then
		return { valid = false, reason = "enabled_invalid" }
	end
	if record.expiresAt ~= nil and not nonNegativeFiniteNumber(record.expiresAt) then
		return { valid = false, reason = "expires_at_invalid" }
	end
	if record.expiresAt ~= nil and record.expiresAt < record.createdAt then
		return { valid = false, reason = "expires_before_created" }
	end

	return { valid = true, reason = "accepted" }
end

function PlayerCreatedRouteState.QueryActivePlayerRoutes(routesById: any, now: number): { [string]: RouteRecord }
	if type(routesById) ~= "table" then
		return {}
	end

	local currentTime = if nonNegativeFiniteNumber(now) then now else 0
	local activeByRouteId: { [string]: RouteRecord } = {}
	for routeId, rawRecord in routesById do
		if type(routeId) ~= "string" then
			continue
		end

		local validation = PlayerCreatedRouteState.ValidateRouteRecord(rawRecord)
		if validation.valid ~= true then
			continue
		end

		local record = rawRecord :: RouteRecord
		if record.enabled ~= true then
			continue
		end
		if record.createdAt > currentTime then
			continue
		end
		if record.expiresAt ~= nil and currentTime >= record.expiresAt then
			continue
		end

		activeByRouteId[routeId] = {
			routeId = record.routeId,
			createdByUserId = record.createdByUserId,
			createdAt = record.createdAt,
			enabled = record.enabled,
			expiresAt = record.expiresAt,
		}
	end

	return activeByRouteId
end

function PlayerCreatedRouteState.UpsertRouteRecord(existingRecord: any, request: any): any
	if type(request) ~= "table" then
		return { accepted = false, reason = "route_id_invalid" }
	end
	if type(request.routeId) ~= "string" or request.routeId == "" then
		return { accepted = false, reason = "route_id_invalid" }
	end
	if
		type(request.requesterUserId) ~= "number"
		or request.requesterUserId <= 0
		or request.requesterUserId % 1 ~= 0
	then
		return { accepted = false, reason = "requester_user_id_invalid" }
	end
	if not nonNegativeFiniteNumber(request.createdAt) then
		return { accepted = false, reason = "created_at_invalid" }
	end
	if request.expiresAt ~= nil and not nonNegativeFiniteNumber(request.expiresAt) then
		return { accepted = false, reason = "expires_at_invalid" }
	end
	if request.expiresAt ~= nil and request.expiresAt < request.createdAt then
		return { accepted = false, reason = "expires_before_created" }
	end

	local existingRecordTyped = if existingRecord ~= nil then existingRecord :: RouteRecord else nil
	local existingOwnerUserId: number? = nil
	if existingRecordTyped ~= nil then
		existingOwnerUserId = (existingRecordTyped :: RouteRecord).createdByUserId
	end
	if existingOwnerUserId ~= nil and existingOwnerUserId ~= request.requesterUserId then
		return { accepted = false, reason = "player_route_owner_mismatch" }
	end

	local record: RouteRecord = {
		routeId = request.routeId,
		createdByUserId = if existingOwnerUserId ~= nil then existingOwnerUserId else request.requesterUserId,
		createdAt = request.createdAt,
		enabled = true,
		expiresAt = request.expiresAt,
	}
	local validation = PlayerCreatedRouteState.ValidateRouteRecord(record)
	if validation.valid ~= true then
		return { accepted = false, reason = validation.reason }
	end

	return {
		accepted = true,
		reason = "accepted",
		record = record,
	}
end

function PlayerCreatedRouteState.DisableRouteRecord(existingRecord: any, requesterUserId: any): any
	if type(requesterUserId) ~= "number" or requesterUserId <= 0 or requesterUserId % 1 ~= 0 then
		return { accepted = false, reason = "requester_user_id_invalid" }
	end
	if existingRecord == nil then
		return { accepted = false, reason = "player_route_owner_mismatch" }
	end

	local existingRecordTyped = existingRecord :: RouteRecord
	if existingRecordTyped.createdByUserId ~= requesterUserId then
		return { accepted = false, reason = "player_route_owner_mismatch" }
	end

	local disabledRecord: RouteRecord = {
		routeId = existingRecordTyped.routeId,
		createdByUserId = existingRecordTyped.createdByUserId,
		createdAt = existingRecordTyped.createdAt,
		enabled = false,
		expiresAt = existingRecordTyped.expiresAt,
	}

	return {
		accepted = true,
		reason = "accepted",
		record = disabledRecord,
	}
end

return PlayerCreatedRouteState
