--!strict

local RescueContractHubState = require("./RescueContractHubState")

local RescueContractHubPresentation: any = {}

function RescueContractHubPresentation.BuildPanelModel(response: any): any
	if type(response) ~= "table" or response.accepted ~= true then
		local reason = if type(response) == "table" and type(response.reason) == "string"
			then response.reason
			else "list_unavailable"
		return {
			visible = true,
			title = "Rescue Contracts",
			subtitle = "Unable to load rescue opportunities",
			bodyText = reason,
			tone = "warning",
			contracts = {},
		}
	end

	local lines: { string } = {}
	local contracts = if type(response.contracts) == "table" then response.contracts else {}
	if #contracts == 0 then
		table.insert(lines, "No rescue contracts are available right now.")
	else
		for _, row in ipairs(contracts) do
			table.insert(lines, RescueContractHubState.FormatContractRowLine(row))
		end
	end

	return {
		visible = true,
		title = "Rescue Contracts",
		subtitle = string.format("%d eligible rescue contract(s)", #contracts),
		bodyText = table.concat(lines, "\n"),
		tone = "neutral",
		contracts = contracts,
	}
end

function RescueContractHubPresentation.BuildAcceptStatusMessage(response: any): string
	if type(response) ~= "table" then
		return "Accept response unavailable"
	end
	if response.accepted == true then
		local queueEntryId = if type(response.queueEntryId) == "string" then response.queueEntryId else "contract"
		if response.duplicate == true then
			return string.format("Rescue contract %s already accepted", queueEntryId)
		end
		return string.format("Accepted rescue contract %s", queueEntryId)
	end
	local reason = if type(response.reason) == "string" then response.reason else "accept_failed"
	return string.format("Accept failed: %s", reason)
end

return RescueContractHubPresentation
