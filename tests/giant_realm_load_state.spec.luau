--!strict

local GiantRealmLoadState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmLoadState")
local GiantRealmSaveSchema = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")

local LoadOutcome = GiantRealmLoadState.LoadOutcome

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local validRoot = GiantRealmLoadState.BuildDefaultStarterSaveRoot(9402)
	local resolved = GiantRealmLoadState.ResolveSaveRootForSession(validRoot, 9402)
	assertTrue(resolved.accepted == true, "valid root accepted")
	assertEqual(resolved.loadOutcome, LoadOutcome.LoadedExisting, "valid root loaded existing")
	assertTrue(resolved.recovered == false, "valid root not recovered")
end

do
	local templateRoot = {
		schemaVersion = 1,
		ownerUserId = 0,
		placedStructures = {},
	}
	local resolved = GiantRealmLoadState.ResolveSaveRootForSession(templateRoot, 9402)
	assertTrue(resolved.accepted == true, "template root accepted")
	assertEqual(resolved.loadOutcome, LoadOutcome.CreatedDefault, "template created default")
	assertTrue(resolved.recovered == true, "template recovered")
	assertEqual(resolved.saveRoot.ownerUserId, 9402, "template owner normalized")
	local valid, _ = GiantRealmSaveSchema.ValidateSaveRoot(resolved.saveRoot)
	assertTrue(valid == true, "template normalized root validates")
end

do
	local corruptRoot = {
		schemaVersion = "bad",
		ownerUserId = 9402,
		placedStructures = {},
	}
	local resolved = GiantRealmLoadState.ResolveSaveRootForSession(corruptRoot, 9402)
	assertTrue(resolved.accepted == true, "corrupt root accepted via recovery")
	assertEqual(resolved.loadOutcome, LoadOutcome.RecoveredCorrupt, "corrupt recovery outcome")
	assertTrue(resolved.recovered == true, "corrupt recovered flag")
	local valid, _ = GiantRealmSaveSchema.ValidateSaveRoot(resolved.saveRoot)
	assertTrue(valid == true, "corrupt recovery root validates")
end

print("giant_realm_load_state: all checks passed")
