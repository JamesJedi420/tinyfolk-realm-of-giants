--!strict

local RealmEntryPortalHubState = require("./RealmEntryPortalHubState")

local RealmEntryPortalHubPresentation: any = {}

function RealmEntryPortalHubPresentation.BuildPanelModel(response: any): any
	if type(response) ~= "table" or response.accepted ~= true then
		local reason = if type(response) == "table" and type(response.reason) == "string"
			then response.reason
			else "list_unavailable"
		return {
			visible = true,
			title = "Realm Portal",
			subtitle = "Unable to load realm entries",
			bodyText = reason,
			tone = "warning",
			listings = {},
		}
	end

	local lines: { string } = {}
	local listings = if type(response.listings) == "table" then response.listings else {}
	if #listings == 0 then
		table.insert(lines, "No eligible realms are available for portal entry right now.")
	else
		for _, row in ipairs(listings) do
			table.insert(lines, RealmEntryPortalHubState.FormatListingRowLine(row))
		end
	end

	local entryMethodLabel = if type(response.entryMethod) == "string" then response.entryMethod else "portal"

	return {
		visible = true,
		title = "Realm Portal",
		subtitle = string.format("%d eligible realm(s) via %s", #listings, entryMethodLabel),
		bodyText = table.concat(lines, "\n"),
		tone = "neutral",
		listings = listings,
	}
end

function RealmEntryPortalHubPresentation.BuildEnterStatusMessage(response: any): string
	if type(response) ~= "table" then
		return "Entry response unavailable"
	end
	if response.accepted == true then
		local targetRealmId = if type(response.targetRealmId) == "string" then response.targetRealmId else "realm"
		local entryRoleLabel = if type(response.entryRoleLabel) == "string" then response.entryRoleLabel else "guest"
		return string.format("Entering %s as %s", targetRealmId, entryRoleLabel)
	end
	local reason = if type(response.reason) == "string" then response.reason else "entry_failed"
	return string.format("Entry failed: %s", reason)
end

return RealmEntryPortalHubPresentation
