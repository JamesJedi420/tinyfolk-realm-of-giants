--!strict

local GiantRealmLoadConfig: any = {}

GiantRealmLoadConfig.ProfileKeyPrefix = "GiantRealmProfile:"

function GiantRealmLoadConfig.FormatProfileKey(ownerUserId: number): string
	return string.format("%s%d", GiantRealmLoadConfig.ProfileKeyPrefix, ownerUserId)
end

return GiantRealmLoadConfig
