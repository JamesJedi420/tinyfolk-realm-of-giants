--!strict

local VillageUpgradeHubConfig = require("../Config/VillageUpgradeHubConfig")
local VillageUpgradeHubState = require("./VillageUpgradeHubState")

local VillageUpgradeHubPresentation: any = {}

local function buildSectionLines(title: string, lines: { string }): any
	return {
		title = title,
		lines = lines,
	}
end

function VillageUpgradeHubPresentation.BuildPanelModel(snapshot: any): any
	if type(snapshot) ~= "table" or snapshot.accepted ~= true then
		local reason = if type(snapshot) == "table" and type(snapshot.reason) == "string"
			then snapshot.reason
			else "hub_unavailable"
		return {
			visible = true,
			title = "Village Upgrade Hub",
			subtitle = "Unable to load upgrade overview",
			bodyText = reason,
			tone = "warning",
		}
	end

	local boardTrack = snapshot.boardTrack
	local boardLines: { string } = {}
	if type(boardTrack) == "table" then
		local progression = if type(boardTrack.progression) == "table" then boardTrack.progression else {}
		table.insert(
			boardLines,
			string.format(
				"%s — Shrine L%d, Giant Dwelling L%d",
				boardTrack.trackSubtitle or VillageUpgradeHubConfig.BoardTrackSubtitle,
				progression.shrineLevel or 0,
				progression.dwellingLevel or 0
			)
		)
		if type(boardTrack.activeEffectSummary) == "string" and boardTrack.activeEffectSummary ~= "" then
			table.insert(boardLines, string.format("Active legacy effects: %s", boardTrack.activeEffectSummary))
		end
		if type(boardTrack.entries) == "table" then
			for _, entry in boardTrack.entries do
				table.insert(boardLines, VillageUpgradeHubState.FormatBoardEntryLine(entry))
			end
		end
	end

	local worksiteLines: { string } = {}
	if type(snapshot.worksiteSummaries) == "table" then
		for _, entry in snapshot.worksiteSummaries do
			table.insert(worksiteLines, VillageUpgradeHubState.FormatWorksiteEntryLine(entry))
		end
	end

	local sections = {
		buildSectionLines(boardTrack.trackTitle or VillageUpgradeHubConfig.BoardTrackTitle, boardLines),
		buildSectionLines(VillageUpgradeHubConfig.WorksiteSectionTitle, worksiteLines),
	}

	local bodyParts: { string } = {}
	for _, section in sections do
		table.insert(bodyParts, section.title)
		for _, line in section.lines do
			table.insert(bodyParts, line)
		end
		table.insert(bodyParts, "")
	end

	return {
		visible = true,
		title = "Village Upgrade Hub",
		subtitle = "Read-only reconciliation view",
		bodyText = table.concat(bodyParts, "\n"),
		sections = sections,
		tone = "neutral",
	}
end

return VillageUpgradeHubPresentation
