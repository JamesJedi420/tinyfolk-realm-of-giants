--!strict

local SpecialistConfig = require("../Config/SpecialistConfig")
local TinyfolkHaulLogisticsConfig = require("../Config/TinyfolkHaulLogisticsConfig")
local TinyfolkInspectConfig = require("../Config/TinyfolkInspectConfig")
local TinyfolkJobSchedulingConfig = require("../Config/TinyfolkJobSchedulingConfig")
local TinyfolkLaborJobHudConfig = require("../Config/TinyfolkLaborJobHudConfig")
local TinyfolkMovementTraitConfig = require("../Config/TinyfolkMovementTraitConfig")

local TinyfolkInspectState = {}

export type Snapshot = {
	displayName: string,
	roleLine: string,
	custodyLine: string,
	traitsLine: string,
	moraleLine: string,
	fatigueLine: string,
	loyaltyLine: string,
	assignmentLine: string,
	valueLine: string,
	tone: string,
}

local function readString(value: any): string?
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function readBoolean(value: any): boolean
	return value == true
end

local function readNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function resolveDisplayName(targetId: string?): string
	if type(targetId) ~= "string" or targetId == "" then
		return "target"
	end
	local configured = TinyfolkLaborJobHudConfig.DisplayNameByTargetId[targetId]
	if type(configured) == "string" and configured ~= "" then
		return configured
	end
	return targetId
end

local function titleCase(value: string): string
	local normalized = string.gsub(string.lower(value), "[_%-]+", " ")
	local words: { string } = {}
	for word in string.gmatch(normalized, "%S+") do
		local head = string.upper(string.sub(word, 1, 1))
		local tail = string.sub(word, 2)
		table.insert(words, head .. tail)
	end
	return table.concat(words, " ")
end

function TinyfolkInspectState.ResolveRoleLine(input: any): string
	local role = readString(input.role) or "Unknown"
	if role ~= "Tinyfolk" then
		return role
	end

	local specialistRole = readString(input.specialistRole)
	if specialistRole == nil or specialistRole == SpecialistConfig.SpecialistRoles.None then
		return "Tinyfolk"
	end
	return string.format("Tinyfolk · %s", specialistRole)
end

function TinyfolkInspectState.ResolveCustodyLine(input: any): string
	if input.carriedState == "Carried" or input.carriedState == "Counterplay" then
		return "Custody: Carried"
	end
	if readBoolean(input.captureActive) then
		local phase = readString(input.captureContainmentPhase)
		if phase ~= nil then
			return string.format("Custody: Captured (%s)", titleCase(phase))
		end
		return "Custody: Captured"
	end
	if readBoolean(input.downedIsDowned) then
		return "Custody: Downed"
	end
	return "Custody: Free"
end

function TinyfolkInspectState.ResolveTraitsLine(input: any): string
	local traits: { string } = {}

	local specialistRole = readString(input.specialistRole)
	if specialistRole ~= nil and specialistRole ~= SpecialistConfig.SpecialistRoles.None then
		table.insert(traits, specialistRole)
	end

	if readBoolean(input.movementTraitEnabled) then
		local traitName = TinyfolkMovementTraitConfig.TraitAttributeName
		local suffix = string.match(traitName, "TinyfolkTrait_(.+)$")
		if suffix ~= nil then
			table.insert(traits, suffix)
		else
			table.insert(traits, traitName)
		end
	end

	if #traits == 0 then
		return TinyfolkInspectConfig.NoneLabel
	end
	return table.concat(traits, ", ")
end

function TinyfolkInspectState.ResolveMoraleLine(input: any): string
	if readBoolean(input.captiveStarving) then
		return "Morale: Captive stress (starving)"
	end

	local shortfallStreak = readNumber(input.captiveShortfallStreak)
	if shortfallStreak ~= nil and shortfallStreak > 0 then
		return string.format("Morale: Captive stress (streak %d)", math.floor(shortfallStreak))
	end

	if readBoolean(input.captureActive) then
		return "Morale: Captive (held)"
	end

	local threatStage = readString(input.raidHudThreatStage)
	if threatStage ~= nil and threatStage ~= "calm" then
		return string.format("Morale: Raid pressure (%s)", titleCase(threatStage))
	end

	local fearRatio = readNumber(input.fearExposureRatio)
	if fearRatio ~= nil and fearRatio > 0 then
		local percent = math.clamp(math.floor(fearRatio * 100 + 0.5), 0, 100)
		return string.format("Morale: Raid pressure (%d%%)", percent)
	end

	return "Morale: Stable"
end

function TinyfolkInspectState.ResolveFatigueLine(input: any): string
	if readBoolean(input.sprintExhausted) then
		return "Fatigue: Exhausted"
	end

	local staminaRatio = readNumber(input.sprintStaminaRatio)
	if staminaRatio ~= nil then
		local percent = math.clamp(math.floor(staminaRatio * 100 + 0.5), 0, 100)
		return string.format("Fatigue: %d%%", percent)
	end

	return string.format("Fatigue: %s", TinyfolkInspectConfig.MissingLabel)
end

function TinyfolkInspectState.ResolveLoyaltyLine(): string
	return string.format("Loyalty: %s", TinyfolkInspectConfig.UnavailableLabel)
end

function TinyfolkInspectState.ResolveAssignmentLine(input: any): string
	local scheduledKind = readString(input.scheduledJobKind)
	if scheduledKind == nil or scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.None then
		return string.format("Assignment: %s", TinyfolkInspectConfig.UnassignedLabel)
	end

	if scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction then
		local stationId = readString(input.scheduledJobStationId) or "station"
		local specialistRole = readString(input.specialistRole) or SpecialistConfig.SpecialistRoles.None
		return string.format("Assignment: Work at %s (%s)", resolveDisplayName(stationId), specialistRole)
	end

	if scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
		local material = readString(input.scheduledJobMaterial) or readString(input.haulMaterial) or "material"
		local haulPhase = readString(input.haulPhase)
		if haulPhase == TinyfolkHaulLogisticsConfig.Phases.Deliver then
			local deliveryId = readString(input.haulRouteDeliveryId) or readString(input.scheduledJobStationId)
			return string.format("Assignment: Deliver %s to %s", material, resolveDisplayName(deliveryId))
		end
		local sourceId = readString(input.haulRouteSourceId) or readString(input.scheduledJobStationId)
		return string.format("Assignment: Pick up %s at %s", material, resolveDisplayName(sourceId))
	end

	return string.format("Assignment: %s", titleCase(scheduledKind))
end

function TinyfolkInspectState.ResolveValueLine(input: any): string
	local scoreTotal = readNumber(input.scoreTotal)
	local laborTokens = readNumber(input.laborTokens)
	local scoreDisplay = if scoreTotal ~= nil then math.floor(scoreTotal) else 0
	local tokenDisplay = if laborTokens ~= nil then math.floor(laborTokens) else 0
	return string.format("Value: Score %d · Tokens %d", scoreDisplay, tokenDisplay)
end

function TinyfolkInspectState.ResolveTone(input: any): string
	if readBoolean(input.captiveStarving) then
		return TinyfolkInspectConfig.Tones.Critical
	end

	local shortfallStreak = readNumber(input.captiveShortfallStreak)
	if shortfallStreak ~= nil and shortfallStreak >= 3 then
		return TinyfolkInspectConfig.Tones.Critical
	end

	if input.carriedState == "Carried" or input.carriedState == "Counterplay" then
		return TinyfolkInspectConfig.Tones.Warning
	end
	if readBoolean(input.captureActive) then
		return TinyfolkInspectConfig.Tones.Warning
	end
	if readBoolean(input.downedIsDowned) then
		return TinyfolkInspectConfig.Tones.Warning
	end

	return TinyfolkInspectConfig.Tones.Neutral
end

function TinyfolkInspectState.BuildSnapshot(input: any): Snapshot
	local displayName = readString(input.displayName) or "Tinyfolk"

	return {
		displayName = displayName,
		roleLine = TinyfolkInspectState.ResolveRoleLine(input),
		custodyLine = TinyfolkInspectState.ResolveCustodyLine(input),
		traitsLine = string.format("Traits: %s", TinyfolkInspectState.ResolveTraitsLine(input)),
		moraleLine = TinyfolkInspectState.ResolveMoraleLine(input),
		fatigueLine = TinyfolkInspectState.ResolveFatigueLine(input),
		loyaltyLine = TinyfolkInspectState.ResolveLoyaltyLine(),
		assignmentLine = TinyfolkInspectState.ResolveAssignmentLine(input),
		valueLine = TinyfolkInspectState.ResolveValueLine(input),
		tone = TinyfolkInspectState.ResolveTone(input),
	}
end

function TinyfolkInspectState.CollectAttributeInput(displayName: string, attributes: { [string]: any }): any
	local attrs = TinyfolkInspectConfig.Attributes
	return {
		displayName = displayName,
		role = attributes[attrs.Role],
		specialistRole = attributes[attrs.SpecialistRole],
		carriedState = attributes[attrs.CarriedState],
		captureActive = attributes[attrs.CaptureActive],
		captureContainmentPhase = attributes[attrs.CaptureContainmentPhase],
		downedIsDowned = attributes[attrs.DownedIsDowned],
		captiveStarving = attributes[attrs.CaptiveStarving],
		captiveShortfallStreak = attributes[attrs.CaptiveShortfallStreak],
		fearExposureRatio = attributes[attrs.FearExposureRatio],
		raidHudThreatStage = attributes[attrs.RaidHudThreatStage],
		movementTraitEnabled = attributes[attrs.MovementTraitEnabled],
		sprintStaminaRatio = attributes[attrs.SprintStaminaRatio],
		sprintExhausted = attributes[attrs.SprintExhausted],
		scheduledJobKind = attributes[attrs.ScheduledJobKind],
		scheduledJobStationId = attributes[attrs.ScheduledJobStationId],
		scheduledJobMaterial = attributes[attrs.ScheduledJobMaterial],
		haulPhase = attributes[attrs.HaulPhase],
		haulRouteSourceId = attributes[attrs.HaulRouteSourceId],
		haulRouteDeliveryId = attributes[attrs.HaulRouteDeliveryId],
		haulMaterial = attributes[attrs.HaulMaterial],
		scoreTotal = attributes[attrs.ScoreTotal],
		laborTokens = attributes[attrs.LaborTokens],
	}
end

return TinyfolkInspectState
