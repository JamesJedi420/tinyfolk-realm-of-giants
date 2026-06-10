--!strict

local GiantLevelPresentation: any = {}

function GiantLevelPresentation.BuildLevelUpFeedbackModel(input: any): any
	if type(input) ~= "table" then
		return {
			visible = false,
			title = "Giant Level Up",
			summary = "",
			tone = "neutral",
		}
	end

	local level = if type(input.level) == "number" then math.floor(input.level) else 0
	if level < 2 then
		return {
			visible = false,
			title = "Giant Level Up",
			summary = "",
			tone = "neutral",
		}
	end

	local unlockNames = {}
	if type(input.newlyResolved) == "table" then
		for _, entry in ipairs(input.newlyResolved) do
			if type(entry) == "table" then
				local displayName = if type(entry.displayName) == "string" and entry.displayName ~= ""
					then entry.displayName
					else entry.unlockId
				if type(displayName) == "string" and displayName ~= "" then
					table.insert(unlockNames, displayName)
				end
			end
		end
	end

	local summary = string.format("Reached Giant level %d.", level)
	if #unlockNames > 0 then
		summary = string.format("%s Unlocked: %s.", summary, table.concat(unlockNames, ", "))
	end

	return {
		visible = true,
		title = "Giant Level Up",
		summary = summary,
		tone = "positive",
	}
end

return GiantLevelPresentation
