--!strict

local StationConfig = require("./StationConfig")

local GiantDwellingConfig: any = {}

GiantDwellingConfig.DefaultDwellingId = StationConfig.DefaultGiantDwellingId
GiantDwellingConfig.BaseGiantHousingCapacity = 1
GiantDwellingConfig.EffectOwner = StationConfig.DefaultGiantDwellingId
GiantDwellingConfig.EffectKind = "GiantHousingCapacity"
GiantDwellingConfig.EffectScope = "GiantRealm"
GiantDwellingConfig.SourceType = "FixedMapAnchor"
GiantDwellingConfig.StationPath = "Stations/GiantDwelling/GiantDwelling_A"

return GiantDwellingConfig
