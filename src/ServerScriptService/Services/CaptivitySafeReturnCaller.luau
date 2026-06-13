--!strict

local CaptivitySafeReturnCaller = {}

local function getEscapeServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._EscapeService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

function CaptivitySafeReturnCaller.Apply(targetUserId: number, at: number?, returnReason: string?): any?
	local queryApi = getEscapeServiceQueryApi()
	if queryApi == nil or type(queryApi.ApplyCaptivitySafeReturn) ~= "function" then
		return nil
	end

	return queryApi.ApplyCaptivitySafeReturn(targetUserId, at, returnReason)
end

return CaptivitySafeReturnCaller
