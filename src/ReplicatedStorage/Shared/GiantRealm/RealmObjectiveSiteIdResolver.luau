--!strict

local RealmObjectiveSiteIdResolver = {}

local CONSTRUCTION_SITE_PREFIX = "ConstructionSite_"
local WORKSTATION_PREFIX = "WorkStation_"
local MINING_STATION_PREFIX = "MiningStation_"
local SHRINE_PREFIX = "Shrine_"

local OBJECTIVE_SITE_WORKYARD = "ObjectiveSite_Workyard"
local OBJECTIVE_SITE_QUARRY = "ObjectiveSite_Quarry"
local OBJECTIVE_SITE_SHRINE = "ObjectiveSite_Shrine"

function RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId(contextualTaskSiteId: string): string?
	if type(contextualTaskSiteId) ~= "string" or string.len(contextualTaskSiteId) == 0 then
		return nil
	end

	if string.sub(contextualTaskSiteId, 1, string.len(CONSTRUCTION_SITE_PREFIX)) == CONSTRUCTION_SITE_PREFIX then
		return contextualTaskSiteId
	end

	if string.sub(contextualTaskSiteId, 1, string.len(WORKSTATION_PREFIX)) == WORKSTATION_PREFIX then
		return OBJECTIVE_SITE_WORKYARD
	end

	if string.sub(contextualTaskSiteId, 1, string.len(MINING_STATION_PREFIX)) == MINING_STATION_PREFIX then
		return OBJECTIVE_SITE_QUARRY
	end

	if string.sub(contextualTaskSiteId, 1, string.len(SHRINE_PREFIX)) == SHRINE_PREFIX then
		return OBJECTIVE_SITE_SHRINE
	end

	return nil
end

return RealmObjectiveSiteIdResolver
