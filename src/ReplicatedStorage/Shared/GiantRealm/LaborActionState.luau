--!strict

local LaborActionConfig = require("../Config/LaborActionConfig")

local LaborActionState = {}

export type WorkActionValidation = {
	accepted: boolean,
	reason: string?,
	laborAction: string?,
}

function LaborActionState.ResolveActionForSpecialistRole(specialistRole: string?): string?
	if type(specialistRole) ~= "string" or specialistRole == "" then
		return nil
	end

	local action = LaborActionConfig.ActionBySpecialistRole[specialistRole]
	if type(action) == "string" and action ~= "" then
		return action
	end

	return nil
end

function LaborActionState.ResolveRequiredSpecialistRoleForAction(laborAction: string?): string?
	if type(laborAction) ~= "string" or laborAction == "" then
		return nil
	end

	local specialistRole = LaborActionConfig.SpecialistRoleByAction[laborAction]
	if type(specialistRole) == "string" and specialistRole ~= "" then
		return specialistRole
	end

	return nil
end

function LaborActionState.ValidateWorkAction(
	specialistRole: string?,
	requiredSpecialistRole: string?
): WorkActionValidation
	local laborAction = LaborActionState.ResolveActionForSpecialistRole(specialistRole)
	if laborAction == nil then
		return {
			accepted = false,
			reason = "labor_action_unmapped",
			laborAction = nil,
		}
	end

	if type(requiredSpecialistRole) == "string" and requiredSpecialistRole ~= "" then
		if specialistRole ~= requiredSpecialistRole then
			return {
				accepted = false,
				reason = string.format(
					"labor_action_role_mismatch action=%s required=%s actual=%s",
					laborAction,
					requiredSpecialistRole,
					tostring(specialistRole)
				),
				laborAction = laborAction,
			}
		end
	end

	return {
		accepted = true,
		reason = nil,
		laborAction = laborAction,
	}
end

return LaborActionState
