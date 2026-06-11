--!strict

local InventoryCraftProfileState = require("../src/ReplicatedStorage/Shared/InventoryCraft/InventoryCraftProfileState")

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
	assertFalse(InventoryCraftProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(InventoryCraftProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		InventoryCraftProfileState.HasPersistedState({ inventoryCraftState = { itemCounts = { iron_filings = 2 } } }),
		"missing schema version not persisted"
	)
end

do
	local profileData = {
		inventoryCraftState = {
			schemaVersion = 1,
			itemCounts = {
				iron_filings = 5,
				stone_shard = 2,
				unknown_item = 9,
				raw_fiber = 0,
				wood_scrap = -1,
			},
		},
	}
	assertTrue(InventoryCraftProfileState.HasPersistedState(profileData), "schema version marks persisted")
	local itemCounts = InventoryCraftProfileState.GetItemCounts(profileData, nil)
	assertEqual(itemCounts.iron_filings, 5, "canonical item count preserved")
	assertEqual(itemCounts.stone_shard, 2, "canonical item count preserved second")
	assertEqual(itemCounts.unknown_item, nil, "unknown item filtered")
	assertEqual(itemCounts.raw_fiber, nil, "non-positive count filtered")
	assertEqual(itemCounts.wood_scrap, nil, "negative count filtered")
end

do
	local copied = InventoryCraftProfileState.CopyProfileField({
		inventoryCraftState = {
			schemaVersion = 1,
			itemCounts = {
				iron_filings = 3,
				unknown_item = 9,
				raw_fiber = 0,
			},
			invalidField = "ignored",
		},
	})
	assertTrue(type(copied) == "table", "copy returns persisted state")
	assertEqual(copied.schemaVersion, 1, "copy keeps schema version")
	assertEqual(copied.itemCounts.iron_filings, 3, "copy keeps valid item count")
	assertEqual(copied.itemCounts.unknown_item, nil, "copy drops unknown item")
	assertEqual(copied.itemCounts.raw_fiber, nil, "copy drops non-positive count")
	assertTrue(copied.invalidField == nil, "copy drops invalid fields")

	local missingSchemaCopied = InventoryCraftProfileState.CopyProfileField({
		inventoryCraftState = {
			itemCounts = {
				iron_filings = 3,
			},
		},
	})
	assertTrue(missingSchemaCopied == nil, "copy omits state without schema version")

	local nilCopied = InventoryCraftProfileState.CopyProfileField(nil)
	assertTrue(nilCopied == nil, "nil profile copy returns nil")
end

do
	local applyResult = InventoryCraftProfileState.ApplyItemCounts({}, {
		iron_filings = 3,
		twine_satchel = 1,
	}, nil)
	assertTrue(applyResult.accepted, "apply accepted")
	assertEqual(applyResult.profileData.inventoryCraftState.schemaVersion, 1, "apply writes schema version")
	assertEqual(applyResult.profileData.inventoryCraftState.itemCounts.iron_filings, 3, "apply writes material count")
	assertEqual(applyResult.profileData.inventoryCraftState.itemCounts.twine_satchel, 1, "apply writes crafted count")

	local rejected = InventoryCraftProfileState.ApplyItemCounts({}, "not-a-table", nil)
	assertFalse(rejected.accepted, "invalid item counts rejected")
	assertEqual(rejected.reason, "item_counts_invalid", "invalid item counts reason")
end

print("inventory_craft_profile_state: all checks passed")
