--!strict

local VillageWorksiteUpgradePresentation: any = {}

local function nonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function VillageWorksiteUpgradePresentation.BuildFeedbackModel(payload: any): any
	if type(payload) ~= "table" then
		return {
			visible = false,
			title = "Worksite Upgrade",
			summary = "",
			tone = "neutral",
		}
	end

	local accepted = payload.accepted == true
	local reason = nonEmptyString(payload.reason) or "unknown"
	local worksiteId = nonEmptyString(payload.worksiteId) or "worksite"
	local level = if type(payload.level) == "number" then payload.level else nil
	local cost = if type(payload.cost) == "table" then payload.cost else nil

	if accepted and level ~= nil then
		local costText = ""
		if cost ~= nil then
			costText = string.format(" (W%d S%d E%d)", cost.wood or 0, cost.stone or 0, cost.essence or 0)
		end
		return {
			visible = true,
			title = "Worksite Upgraded",
			summary = string.format("%s → L%d%s", worksiteId, level, costText),
			tone = "positive",
		}
	end

	return {
		visible = true,
		title = "Worksite Upgrade Failed",
		summary = string.format("%s: %s", worksiteId, reason),
		tone = "warning",
	}
end

return VillageWorksiteUpgradePresentation
