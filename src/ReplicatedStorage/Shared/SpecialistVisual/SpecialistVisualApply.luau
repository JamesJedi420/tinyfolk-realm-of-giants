--!strict

local RoleConfig = require("../Config/RoleConfig")
local SpecialistConfig = require("../Config/SpecialistConfig")
local SpecialistVisualConfig = require("../Config/SpecialistVisualConfig")

local SpecialistVisualApply = {}

export type ApplyInput = {
	requesterRole: string?,
	specialistRole: string?,
}

export type ApplyPlan = {
	shouldApply: boolean,
	shouldClear: boolean,
	activeRole: string,
	outfitId: string?,
	toolId: string?,
	reason: string,
}

export type AppliedState = {
	applied: boolean,
	activeRole: string,
	outfitId: string?,
	toolId: string?,
	lastApplyReason: string,
	lastAppliedAt: number?,
}

local function resolvePlaceholder(specialistRole: string): any?
	local placeholder = SpecialistVisualConfig.PlaceholderBySpecialistRole[specialistRole]
	if type(placeholder) ~= "table" then
		return nil
	end
	return placeholder
end

function SpecialistVisualApply.Resolve(input: ApplyInput, applyReason: string?): ApplyPlan
	local requesterRole = input.requesterRole
	local specialistRole = input.specialistRole
	local reason = if type(applyReason) == "string" and applyReason ~= ""
		then applyReason
		else SpecialistVisualConfig.ApplyReasons.Initial

	if requesterRole ~= RoleConfig.Roles.Tinyfolk then
		return {
			shouldApply = false,
			shouldClear = true,
			activeRole = SpecialistConfig.SpecialistRoles.None,
			outfitId = nil,
			toolId = nil,
			reason = SpecialistVisualConfig.ApplyReasons.ClearedRoleChange,
		}
	end

	if type(specialistRole) ~= "string" or specialistRole == SpecialistConfig.SpecialistRoles.None then
		return {
			shouldApply = false,
			shouldClear = true,
			activeRole = SpecialistConfig.SpecialistRoles.None,
			outfitId = nil,
			toolId = nil,
			reason = SpecialistVisualConfig.ApplyReasons.Cleared,
		}
	end

	local placeholder = resolvePlaceholder(specialistRole)
	if placeholder == nil then
		return {
			shouldApply = false,
			shouldClear = true,
			activeRole = SpecialistConfig.SpecialistRoles.None,
			outfitId = nil,
			toolId = nil,
			reason = SpecialistVisualConfig.ApplyReasons.Cleared,
		}
	end

	return {
		shouldApply = true,
		shouldClear = false,
		activeRole = specialistRole,
		outfitId = placeholder.outfitId,
		toolId = placeholder.toolId,
		reason = reason,
	}
end

function SpecialistVisualApply.Snapshot(state: AppliedState): AppliedState
	return {
		applied = state.applied == true,
		activeRole = state.activeRole,
		outfitId = state.outfitId,
		toolId = state.toolId,
		lastApplyReason = state.lastApplyReason,
		lastAppliedAt = state.lastAppliedAt,
	}
end

return SpecialistVisualApply
