--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local PostRescueProtectionState = require(GiantRealm:WaitForChild("PostRescueProtectionState"))

local PostRescueProtectionCancellationCaller = {}

local function getRescueContractQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RescueContractService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

function PostRescueProtectionCancellationCaller.RecordObjectiveTaskCompletion(
	completedByUserId: number,
	at: number?
): any?
	local queryApi = getRescueContractQueryApi()
	if queryApi == nil or type(queryApi.CancelPostRescueProtection) ~= "function" then
		return nil
	end

	return queryApi.CancelPostRescueProtection(
		completedByUserId,
		PostRescueProtectionState.BreakingActions.objective_task_complete,
		at
	)
end

return PostRescueProtectionCancellationCaller
