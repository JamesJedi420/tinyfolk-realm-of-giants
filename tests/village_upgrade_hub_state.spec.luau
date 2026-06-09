--!strict

local VillageUpgradeHubState = require("../src/ReplicatedStorage/Shared/GiantRealm/VillageUpgradeHubState")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

do
	local snapshot = VillageUpgradeHubState.BuildHubSnapshot({
		boardId = "GiantUpgradeBoard_A",
		selectedByUpgradeId = { PowerCore = true },
		progression = {
			completedSteps = 1,
			totalSteps = 2,
			status = "InProgress",
			nextUpgradeId = "IronStride",
		},
		resolvedEffects = {
			maxHealthBonus = 50,
			powerBudgetBonus = 25,
			walkSpeedBonus = 0,
			movementControlBonus = 0,
		},
		levelByWorksiteId = {
			Farm_A = 2,
			GiantDwelling_A = 1,
		},
	})

	assertEqual(snapshot.accepted, true, "hub snapshot accepted")
	assertEqual(snapshot.boardTrack.progression.nextUpgradeId, "IronStride", "next board upgrade")
	assertEqual(snapshot.boardTrack.entries[1].status, "purchased", "power core purchased")
	assertEqual(snapshot.boardTrack.entries[2].status, "available", "iron stride available")
	assertEqual(snapshot.boardTrack.entries[1].migrationTarget, "shrine_levels", "power core migration target")
	assertEqual(snapshot.boardTrack.entries[2].migrationTarget, "giant_dwelling_levels", "iron stride migration target")

	local farmEntry = nil
	for _, entry in snapshot.worksiteSummaries do
		if entry.worksiteId == "Farm_A" then
			farmEntry = entry
			break
		end
	end
	assertTrue(farmEntry ~= nil, "farm entry present")
	assertEqual(farmEntry.level, 2, "farm level")
	assertEqual(farmEntry.status, "upgradeable", "farm upgradeable")
end

do
	local line = VillageUpgradeHubState.FormatBoardEntryLine({
		label = "Power Core",
		status = "purchased",
		migrationTarget = "shrine_levels",
		effectSummary = "+50 health, +25 power budget",
	})
	assertTrue(string.find(line, "legacy active", 1, true) ~= nil, "legacy active copy")
	assertTrue(string.find(line, "shrine_levels", 1, true) ~= nil, "migration hint in line")
end

print("village_upgrade_hub_state.spec.luau: all checks passed")
