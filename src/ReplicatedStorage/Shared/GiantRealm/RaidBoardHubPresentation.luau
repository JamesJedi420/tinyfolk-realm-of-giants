--!strict

local RaidBoardHubState = require("./RaidBoardHubState")

local RaidBoardHubPresentation: any = {}

function RaidBoardHubPresentation.BuildPanelModel(response: any): any
	if type(response) ~= "table" or response.accepted ~= true then
		local reason = if type(response) == "table" and type(response.reason) == "string"
			then response.reason
			else "list_unavailable"
		return {
			visible = true,
			title = "Raid Board",
			subtitle = "Unable to load realm listings",
			bodyText = reason,
			tone = "warning",
			listings = {},
		}
	end

	local lines: { string } = {}
	local listings = if type(response.listings) == "table" then response.listings else {}
	if #listings == 0 then
		table.insert(lines, "No public realms are available right now.")
	else
		for _, row in ipairs(listings) do
			table.insert(lines, RaidBoardHubState.FormatListingRowLine(row))
		end
	end

	return {
		visible = true,
		title = "Raid Board",
		subtitle = string.format("%d eligible realm(s)", #listings),
		bodyText = table.concat(lines, "\n"),
		tone = "neutral",
		listings = listings,
	}
end

function RaidBoardHubPresentation.BuildQueueStatusMessage(response: any): string
	if type(response) ~= "table" then
		return "Queue response unavailable"
	end
	if response.accepted == true then
		local targetRealmId = if type(response.targetRealmId) == "string" then response.targetRealmId else "realm"
		return string.format("Queued for %s", targetRealmId)
	end
	local reason = if type(response.reason) == "string" then response.reason else "queue_failed"
	return string.format("Queue failed: %s", reason)
end

return RaidBoardHubPresentation
