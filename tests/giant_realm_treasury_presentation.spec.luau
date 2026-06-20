--!strict

local GiantRealmTreasuryPresentation =
	require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmTreasuryPresentation")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local model = GiantRealmTreasuryPresentation.BuildHudModel({
		essence = 12,
		wood = 8,
		stone = 4,
	}, {
		woodStored = 120,
		stoneStored = 90,
		metalStored = 15,
		essenceStored = 0,
	})
	assertEqual(model.visible, true, "treasury model visible")
	assertEqual(model.ledgerEssence, 12, "ledger essence")
	assertEqual(model.sessionWood, 120, "session wood")
	assertEqual(model.sessionMetal, 15, "session metal")
	assertTrue(string.find(model.summary, "Ledger E12", 1, true) ~= nil, "summary includes ledger")
	assertTrue(string.find(model.summary, "M15", 1, true) ~= nil, "summary includes session metal")
end

print("giant_realm_treasury_presentation.spec.luau: all checks passed")
