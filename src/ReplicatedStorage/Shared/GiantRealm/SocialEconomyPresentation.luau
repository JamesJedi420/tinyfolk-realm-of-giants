--!strict

local SocialEconomyConfig = require("../Config/SocialEconomyConfig")

local SocialEconomyPresentation: any = {}

export type SocialEconomyHudModel = {
	visible: boolean,
	title: string,
	summary: string,
	tone: string,
}

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function readNumber(snapshot: any, fieldName: string, defaultValue: number): number
	if type(snapshot) ~= "table" then
		return defaultValue
	end
	local value = finiteNumber(snapshot[fieldName])
	if value == nil then
		return defaultValue
	end
	return value
end

local function readString(snapshot: any, fieldName: string, defaultValue: string): string
	if type(snapshot) ~= "table" then
		return defaultValue
	end
	local value = snapshot[fieldName]
	if type(value) ~= "string" then
		return defaultValue
	end
	return value
end

function SocialEconomyPresentation.BuildHudModel(snapshot: any): SocialEconomyHudModel
	local favor = readNumber(snapshot, "favor", SocialEconomyConfig.DefaultFavor)
	local control = readNumber(snapshot, "control", SocialEconomyConfig.DefaultControl)
	local dominantAxis = readString(snapshot, "dominantAxis", SocialEconomyConfig.DominantAxes.Balanced)

	local title = "Realm Social Economy"
	local summary =
		string.format("Favor %d | Control %d | Dominant %s", math.floor(favor), math.floor(control), dominantAxis)
	local tone = "neutral"
	if dominantAxis == SocialEconomyConfig.DominantAxes.Favor then
		tone = "warm"
	elseif dominantAxis == SocialEconomyConfig.DominantAxes.Control then
		tone = "cold"
	end

	return {
		visible = true,
		title = title,
		summary = summary,
		tone = tone,
	}
end

return SocialEconomyPresentation
