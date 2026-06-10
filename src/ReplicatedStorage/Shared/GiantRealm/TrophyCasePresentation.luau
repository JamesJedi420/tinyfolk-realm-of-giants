--!strict

local TrophyConfig = require("../Config/TrophyConfig")

local TrophyCasePresentation: any = {}

export type ReputationSnapshot = {
	score: number,
	rank: number,
	rankTitle: string,
	scoreToNextRank: number,
}

export type CaseModel = {
	visible: boolean,
	title: string,
	header: string,
	body: string,
	count: number,
}

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function readReputationSnapshot(reputationSnapshot: any): ReputationSnapshot
	local score = finiteNumber(reputationSnapshot and reputationSnapshot.score) or 0
	local rank = finiteNumber(reputationSnapshot and reputationSnapshot.rank) or 1
	local rankTitle = if type(reputationSnapshot) == "table"
			and type(reputationSnapshot.rankTitle) == "string"
			and reputationSnapshot.rankTitle ~= ""
		then reputationSnapshot.rankTitle
		else "Unknown Giant"
	local scoreToNextRank = finiteNumber(reputationSnapshot and reputationSnapshot.scoreToNextRank) or 0
	return {
		score = math.max(0, math.floor(score)),
		rank = math.max(1, math.floor(rank)),
		rankTitle = rankTitle,
		scoreToNextRank = math.max(0, math.floor(scoreToNextRank)),
	}
end

function TrophyCasePresentation.BuildHeader(reputationSnapshot: any): string
	local reputation = readReputationSnapshot(reputationSnapshot)
	if reputation.scoreToNextRank > 0 then
		return string.format(
			"%s (Rank %d) · %d rep · %d to next",
			reputation.rankTitle,
			reputation.rank,
			reputation.score,
			reputation.scoreToNextRank
		)
	end
	return string.format("%s (Rank %d) · %d rep", reputation.rankTitle, reputation.rank, reputation.score)
end

function TrophyCasePresentation.BuildBody(trophies: any, maxEntries: number?): string
	local limit = if type(maxEntries) == "number" and maxEntries > 0 then math.floor(maxEntries) else 5
	if type(trophies) ~= "table" or #trophies == 0 then
		return "No trophies recorded yet."
	end

	local lines: { string } = {}
	local startIndex = math.max(1, #trophies - limit + 1)
	for index = #trophies, startIndex, -1 do
		local record = trophies[index]
		if type(record) == "table" then
			local summary = if type(record.summary) == "string" and record.summary ~= ""
				then record.summary
				else TrophyConfig.DisplayTitlesByKind[record.trophyKind] or "Realm Event"
			table.insert(lines, string.format("• %s", summary))
		end
	end

	return table.concat(lines, "\n")
end

function TrophyCasePresentation.BuildCaseModel(trophies: any, reputationSnapshot: any, maxEntries: number?): CaseModel
	local count = if type(trophies) == "table" then #trophies else 0
	local header = TrophyCasePresentation.BuildHeader(reputationSnapshot)
	local body = TrophyCasePresentation.BuildBody(trophies, maxEntries)

	return {
		visible = true,
		title = "Giant Trophy Case",
		header = header,
		body = body,
		count = count,
	}
end

return TrophyCasePresentation
