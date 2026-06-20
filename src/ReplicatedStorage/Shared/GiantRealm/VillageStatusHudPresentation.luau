--!strict

local VillageStatusHudConfig = require("../Config/VillageStatusHudConfig")
local VillageStatusState = require("./VillageStatusState")

local VillageStatusHudPresentation = {}

export type VillageStatusHudModel = {
	visible: boolean,
	title: string,
	summary: string,
	tone: string,
}

local function capitalizeEscapePressure(escapePressure: string): string
	if escapePressure == VillageStatusHudConfig.EscapePressure.Calm then
		return "Calm"
	end
	if escapePressure == VillageStatusHudConfig.EscapePressure.Elevated then
		return "Elevated"
	end
	if escapePressure == VillageStatusHudConfig.EscapePressure.Critical then
		return "Critical"
	end
	return escapePressure
end

function VillageStatusHudPresentation.BuildHudModel(snapshotInput: any): VillageStatusHudModel
	local snapshot = VillageStatusState.BuildSnapshot(snapshotInput)

	local transitSuffix = if snapshot.foodInTransit > 0
		then string.format("(+%d transit)", snapshot.foodInTransit)
		else ""

	local summary = string.format(
		"Raiders %d | Workers %d | Captives %d\nFood %d stored %s | Morale %d\nProduction W+%d S+%d | Jobs %d active\nEscape pressure: %s",
		snapshot.activeRaiderCount,
		snapshot.workerCount,
		snapshot.activeCaptiveCount,
		snapshot.foodStored,
		transitSuffix,
		snapshot.morale,
		snapshot.woodProduced,
		snapshot.stoneProduced,
		snapshot.activeJobCount,
		capitalizeEscapePressure(snapshot.escapePressure)
	)

	return {
		visible = true,
		title = "Village Status",
		summary = summary,
		tone = snapshot.tone,
	}
end

return VillageStatusHudPresentation
