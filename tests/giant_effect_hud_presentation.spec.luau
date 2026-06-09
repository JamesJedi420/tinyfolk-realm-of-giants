--!nocheck

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local GiantEffectHudPresentation = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantEffectHudPresentation")

local model = GiantEffectHudPresentation.BuildHudModel({
	maxHealth = 117,
	walkSpeed = 18,
	powerBudget = 108,
	movementControl = 1.08,
	maxHealthBonus = 17,
	walkSpeedBonus = 2,
	powerBudgetBonus = 8,
	movementControlBonus = 0.08,
})

assertTrue(model.visible, "hud visible for giant effects")
assertEqual(model.title, "Giant Effects", "hud title")
assertTrue(string.find(model.summary, "HP 117") ~= nil, "summary includes max health")
assertTrue(string.find(model.summary, "Power 108") ~= nil, "summary includes power budget")

local emptyModel = GiantEffectHudPresentation.BuildHudModel(nil)
assertTrue(emptyModel.visible, "empty snapshot still visible with defaults")
assertTrue(string.find(emptyModel.summary, "HP 0") ~= nil, "empty snapshot uses zero defaults")

print("PASS giant_effect_hud_presentation.spec.luau")
