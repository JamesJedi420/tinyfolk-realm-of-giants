--!strict

local SpecialistConfig = require("../Config/SpecialistConfig")
local StationConfig = require("../Config/StationConfig")
local TinyfolkHaulLogisticsConfig = require("../Config/TinyfolkHaulLogisticsConfig")
local TinyfolkJobSchedulingConfig = require("../Config/TinyfolkJobSchedulingConfig")
local TinyfolkLaborJobHudConfig = require("../Config/TinyfolkLaborJobHudConfig")

local TinyfolkLaborJobHudPresentation = {}

export type ProximityContext = {
	targetId: string?,
	inRange: boolean?,
	targetFound: boolean?,
}

export type LaborJobHudModel = {
	visible: boolean,
	title: string,
	instruction: string,
	tone: string,
	billboardTargetId: string?,
	billboardLabel: string?,
	showBillboard: boolean,
}

local function readString(snapshot: any, fieldName: string): string?
	if type(snapshot) ~= "table" then
		return nil
	end
	local value = snapshot[fieldName]
	if type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function readBoolean(snapshot: any, fieldName: string): boolean
	if type(snapshot) ~= "table" then
		return false
	end
	return snapshot[fieldName] == true
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

function TinyfolkLaborJobHudPresentation.ResolveBillboardTarget(snapshot: any): string?
	local scheduledKind = readString(snapshot, "scheduledJobKind")
	if scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
		local haulPhase = readString(snapshot, "haulPhase")
		if haulPhase == TinyfolkHaulLogisticsConfig.Phases.Deliver then
			return readString(snapshot, "haulRouteDeliveryId") or readString(snapshot, "scheduledSourceStationId")
		end
		return readString(snapshot, "haulRouteSourceId") or readString(snapshot, "scheduledSourceStationId")
	end

	if scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction then
		return readString(snapshot, "scheduledSourceStationId")
	end

	return nil
end

function TinyfolkLaborJobHudPresentation.BuildHudModel(snapshot: any, proximity: ProximityContext?): LaborJobHudModel
	local role = readString(snapshot, "role")
	local scheduledKind = readString(snapshot, "scheduledJobKind")
	local completionFlashActive = readBoolean(snapshot, "completionFlashActive")

	if completionFlashActive then
		return {
			visible = true,
			title = "Labor Job",
			instruction = "Job complete",
			tone = TinyfolkLaborJobHudConfig.Tones.Complete,
			billboardTargetId = nil,
			billboardLabel = nil,
			showBillboard = false,
		}
	end

	if role ~= "Tinyfolk" then
		return {
			visible = false,
			title = "Labor Job",
			instruction = "",
			tone = TinyfolkLaborJobHudConfig.Tones.None,
			billboardTargetId = nil,
			billboardLabel = nil,
			showBillboard = false,
		}
	end

	if scheduledKind == nil or scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.None then
		return {
			visible = false,
			title = "Labor Job",
			instruction = "",
			tone = TinyfolkLaborJobHudConfig.Tones.None,
			billboardTargetId = nil,
			billboardLabel = nil,
			showBillboard = false,
		}
	end

	local manualHaulActive = readBoolean(snapshot, "haulInteractionActive")
	local billboardTargetId = TinyfolkLaborJobHudPresentation.ResolveBillboardTarget(snapshot)
	local targetDisplayName = resolveDisplayName(billboardTargetId)
	local inRange = if type(proximity) == "table" then proximity.inRange == true else false
	local targetFound = if type(proximity) == "table" then proximity.targetFound ~= false else true
	local rangeSuffix = if inRange then " — in range" else ""

	if scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.SpecialistProduction then
		local specialistRole = readString(snapshot, "specialistRole") or SpecialistConfig.SpecialistRoles.None
		local stationId = readString(snapshot, "scheduledSourceStationId") or billboardTargetId or "station"
		local stationDisplay = resolveDisplayName(stationId)
		local instruction = string.format("Work at %s (%s)", stationDisplay, specialistRole)
		if manualHaulActive then
			instruction = "Manual haul active — scheduler paused"
		end
		instruction ..= rangeSuffix

		return {
			visible = true,
			title = "Specialist Job",
			instruction = instruction,
			tone = if inRange then TinyfolkLaborJobHudConfig.Tones.Active else TinyfolkLaborJobHudConfig.Tones.Neutral,
			billboardTargetId = billboardTargetId,
			billboardLabel = stationDisplay,
			showBillboard = billboardTargetId ~= nil and targetFound,
		}
	end

	if scheduledKind == TinyfolkJobSchedulingConfig.JobKinds.GeneralHaul then
		local material = readString(snapshot, "scheduledMaterial") or readString(snapshot, "haulMaterial") or "material"
		local haulPhase = readString(snapshot, "haulPhase")

		local instruction: string
		if manualHaulActive then
			instruction = "Manual haul active — scheduler paused"
		elseif haulPhase == TinyfolkHaulLogisticsConfig.Phases.Deliver then
			instruction = string.format("Deliver %s to %s", material, targetDisplayName)
		else
			instruction = string.format("Pick up %s at %s", material, targetDisplayName)
		end

		if not targetFound and billboardTargetId ~= nil then
			instruction = string.format("%s — target not found", instruction)
		end
		instruction ..= rangeSuffix

		return {
			visible = true,
			title = "Haul Job",
			instruction = instruction,
			tone = if manualHaulActive
				then TinyfolkLaborJobHudConfig.Tones.Warning
				elseif inRange then TinyfolkLaborJobHudConfig.Tones.Active
				else TinyfolkLaborJobHudConfig.Tones.Neutral,
			billboardTargetId = billboardTargetId,
			billboardLabel = if haulPhase == TinyfolkHaulLogisticsConfig.Phases.Deliver
				then string.format("Deliver %s", material)
				else string.format("Pickup %s", material),
			showBillboard = billboardTargetId ~= nil and targetFound and not manualHaulActive,
		}
	end

	return {
		visible = false,
		title = "Labor Job",
		instruction = "",
		tone = TinyfolkLaborJobHudConfig.Tones.None,
		billboardTargetId = nil,
		billboardLabel = nil,
		showBillboard = false,
	}
end

function TinyfolkLaborJobHudPresentation.GetActivationRangeStuds(): number
	return StationConfig.ActivationRangeStuds
end

return TinyfolkLaborJobHudPresentation
