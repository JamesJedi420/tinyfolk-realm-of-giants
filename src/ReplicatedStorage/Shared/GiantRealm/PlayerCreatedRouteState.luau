--!strict

local PlayerCreatedRouteState = {}

export type RouteRecord = {
	routeId: string,
	createdByUserId: number,
	createdAt: number,
	enabled: boolean,
	expiresAt: number?,
}

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonNegativeFiniteNumber(value: any): boolean
	return finiteNumber(value) and value >= 0
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

return PlayerCreatedRouteState
