--!strict

local SocialEconomyConfig = require("../src/ReplicatedStorage/Shared/Config/SocialEconomyConfig")
local SocialEconomyPresentation = require("../src/ReplicatedStorage/Shared/GiantRealm/SocialEconomyPresentation")

local function assertTrue(value: boolean, label: string)
	if value ~= true then
		error(string.format("FAIL [%s]", label))
	end
end

local model = SocialEconomyPresentation.BuildHudModel({
	favor = 70,
	control = 40,
	dominantAxis = SocialEconomyConfig.DominantAxes.Favor,
	favorComplianceBonus = 1.35,
	controlIntimidationBonus = 1.2,
})
assertTrue(model.visible, "model visible")
assertTrue(string.find(model.summary, "Compliance x1.35") ~= nil, "summary includes compliance bonus")
assertTrue(string.find(model.summary, "Intimidation x1.20") ~= nil, "summary includes intimidation bonus")
assertTrue(model.tone == "warm", "favor dominant warm tone")

print("social_economy_presentation.spec.luau: all checks passed")
