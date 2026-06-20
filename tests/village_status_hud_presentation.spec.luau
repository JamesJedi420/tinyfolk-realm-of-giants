--!strict

local VillageStatusHudConfig = require("../src/ReplicatedStorage/Shared/Config/VillageStatusHudConfig")
local VillageStatusHudPresentation = require("../src/ReplicatedStorage/Shared/GiantRealm/VillageStatusHudPresentation")

local function assertTrue(value: boolean, label: string)
	if value ~= true then
		error(string.format("FAIL [%s]", label))
	end
end

local model = VillageStatusHudPresentation.BuildHudModel({
	activeRaiderCount = 3,
	workerCount = 5,
	activeCaptiveCount = 2,
	foodStored = 120,
	foodInTransit = 8,
	morale = 42,
	woodProduced = 12,
	stoneProduced = 4,
	activeJobCount = 2,
	lastFoodShortfall = false,
	consecutiveShortfallTicks = 0,
})
assertTrue(model.visible, "model visible")
assertTrue(model.title == "Village Status", "title")
assertTrue(string.find(model.summary, "Raiders 3 | Workers 5 | Captives 2", 1, true) ~= nil, "population line")
assertTrue(string.find(model.summary, "Food 120 stored (+8 transit)", 1, true) ~= nil, "food line")
assertTrue(string.find(model.summary, "Morale 42", 1, true) ~= nil, "morale line")
assertTrue(string.find(model.summary, "Production W+12 S+4 | Jobs 2 active", 1, true) ~= nil, "production line")
assertTrue(string.find(model.summary, "Escape pressure: Calm", 1, true) ~= nil, "escape calm")

local warningModel = VillageStatusHudPresentation.BuildHudModel({
	activeRaiderCount = 2,
	foodStored = 120,
	morale = 80,
})
assertTrue(warningModel.tone == VillageStatusHudConfig.Tones.Warning, "warning tone from raiders")

print("village_status_hud_presentation.spec.luau: all checks passed")
