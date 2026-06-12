--!nocheck
local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected %q got %q", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local RealmObjectiveSiteIdResolver = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmObjectiveSiteIdResolver")

assertEqual(
	RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId("ConstructionSite_A"),
	"ConstructionSite_A",
	"construction site maps to same registered id"
)
assertEqual(
	RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId("WorkStation_A"),
	"ObjectiveSite_Workyard",
	"work station maps to workyard objective site"
)
assertEqual(
	RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId("MiningStation_A"),
	"ObjectiveSite_Quarry",
	"mining station maps to quarry objective site"
)
assertEqual(
	RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId("Shrine_A"),
	"ObjectiveSite_Shrine",
	"shrine maps to shrine objective site"
)
assertEqual(RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId(""), nil, "empty site id rejected")
assertEqual(RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId("UnknownSite_A"), nil, "unknown prefix rejected")

print("realm_objective_site_id_resolver: all checks passed")
