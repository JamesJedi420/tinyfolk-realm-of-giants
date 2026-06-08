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
		essenceStored = 0,
	})
	assertEqual(model.visible, true, "treasury model visible")
	assertEqual(model.ledgerEssence, 12, "ledger essence")
	assertEqual(model.sessionWood, 120, "session wood")
	assertTrue(string.find(model.summary, "Ledger E12", 1, true) ~= nil, "summary includes ledger")
end

print("giant_realm_treasury_presentation.spec.luau: all checks passed")
