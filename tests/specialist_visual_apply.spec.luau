--!nocheck

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local SpecialistVisualConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistVisualConfig")
local SpecialistVisualApply = require("../src/ReplicatedStorage/Shared/SpecialistVisual/SpecialistVisualApply")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

do
	local plan = SpecialistVisualApply.Resolve({
		requesterRole = RoleConfig.Roles.Tinyfolk,
		specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
	}, SpecialistVisualConfig.ApplyReasons.Assigned)
	assertTrue(plan.shouldApply, "woodcutter should apply")
	assertFalse(plan.shouldClear, "woodcutter should not clear")
	assertEqual(plan.activeRole, SpecialistConfig.SpecialistRoles.Woodcutter, "woodcutter active role")
	assertEqual(plan.outfitId, "woodcutter_vest", "woodcutter outfit id")
	assertEqual(plan.toolId, "woodcutter_axe", "woodcutter tool id")
	assertEqual(plan.reason, SpecialistVisualConfig.ApplyReasons.Assigned, "woodcutter apply reason")
end

do
	local plan = SpecialistVisualApply.Resolve({
		requesterRole = RoleConfig.Roles.Tinyfolk,
		specialistRole = SpecialistConfig.SpecialistRoles.Miner,
	}, SpecialistVisualConfig.ApplyReasons.Assigned)
	assertEqual(plan.outfitId, "miner_tunic", "miner outfit id")
	assertEqual(plan.toolId, "miner_pick", "miner tool id")
end

do
	local plan = SpecialistVisualApply.Resolve({
		requesterRole = RoleConfig.Roles.Tinyfolk,
		specialistRole = SpecialistConfig.SpecialistRoles.Farmer,
	}, SpecialistVisualConfig.ApplyReasons.Assigned)
	assertEqual(plan.outfitId, "farmer_apron", "farmer outfit id")
	assertEqual(plan.toolId, "farmer_hoe", "farmer tool id")
end

do
	local plan = SpecialistVisualApply.Resolve({
		requesterRole = RoleConfig.Roles.Tinyfolk,
		specialistRole = SpecialistConfig.SpecialistRoles.Worshipper,
	}, SpecialistVisualConfig.ApplyReasons.Assigned)
	assertEqual(plan.outfitId, "worshipper_robe", "worshipper outfit id")
	assertEqual(plan.toolId, "worshipper_relic", "worshipper tool id")
end

do
	local plan = SpecialistVisualApply.Resolve({
		requesterRole = RoleConfig.Roles.Tinyfolk,
		specialistRole = SpecialistConfig.SpecialistRoles.None,
	}, SpecialistVisualConfig.ApplyReasons.Cleared)
	assertFalse(plan.shouldApply, "none should not apply")
	assertTrue(plan.shouldClear, "none should clear")
	assertEqual(plan.activeRole, SpecialistConfig.SpecialistRoles.None, "none active role")
	assertEqual(plan.reason, SpecialistVisualConfig.ApplyReasons.Cleared, "none clear reason")
end

do
	local plan = SpecialistVisualApply.Resolve({
		requesterRole = RoleConfig.Roles.Giant,
		specialistRole = SpecialistConfig.SpecialistRoles.Woodcutter,
	}, SpecialistVisualConfig.ApplyReasons.ClearedRoleChange)
	assertFalse(plan.shouldApply, "giant should not apply specialist visuals")
	assertTrue(plan.shouldClear, "giant should clear specialist visuals")
	assertEqual(plan.reason, SpecialistVisualConfig.ApplyReasons.ClearedRoleChange, "giant clear reason")
end

do
	local snapshot = SpecialistVisualApply.Snapshot({
		applied = true,
		activeRole = SpecialistConfig.SpecialistRoles.Miner,
		outfitId = "miner_tunic",
		toolId = "miner_pick",
		lastApplyReason = SpecialistVisualConfig.ApplyReasons.Assigned,
		lastAppliedAt = 42,
	})
	assertTrue(snapshot.applied, "snapshot applied")
	assertEqual(snapshot.activeRole, SpecialistConfig.SpecialistRoles.Miner, "snapshot active role")
	assertEqual(snapshot.outfitId, "miner_tunic", "snapshot outfit id")
	assertEqual(snapshot.toolId, "miner_pick", "snapshot tool id")
	assertEqual(snapshot.lastApplyReason, SpecialistVisualConfig.ApplyReasons.Assigned, "snapshot reason")
	assertEqual(snapshot.lastAppliedAt, 42, "snapshot applied at")
end

print("specialist_visual_apply: all checks passed")
