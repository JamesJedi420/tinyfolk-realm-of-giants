--!nocheck

local TinyfolkToolCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/TinyfolkToolCatalogSchema")

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

local validCatalog, validReason =
	TinyfolkToolCatalogSchema.ValidateToolCatalog(TinyfolkToolCatalogSchema.DEFAULT_TOOL_CATALOG)
assertTrue(validCatalog, "default catalog valid: " .. tostring(validReason))
assertEqual(TinyfolkToolCatalogSchema.GetMaxSelectableSlots(), 2, "max selectable slots is two")

do
	local grappling, reason = TinyfolkToolCatalogSchema.GetToolRecord("grappling_hook")
	assertEqual(reason, nil, "lookup grappling reason")
	assertTrue(grappling ~= nil, "lookup grappling exists")
	assertEqual(grappling.cooldown.seconds, 30, "lookup grappling cooldown seconds")
end

do
	local missing, reason = TinyfolkToolCatalogSchema.GetToolRecord("missing_tool")
	assertEqual(missing, nil, "missing tool returns nil")
	assertEqual(reason, "tool_missing", "missing tool reason")
end

do
	local invalidCategory = TinyfolkToolCatalogSchema.GetAllToolRecords()
	invalidCategory[1].categories = { "escape", "invalid" }
	local valid, reason = TinyfolkToolCatalogSchema.ValidateToolCatalog(invalidCategory)
	assertFalse(valid, "invalid category rejected")
	assertEqual(reason, "tool_category_invalid index=1", "invalid category reason")
end

do
	local missingCooldown = TinyfolkToolCatalogSchema.GetAllToolRecords()
	missingCooldown[2].cooldown = nil
	local valid, reason = TinyfolkToolCatalogSchema.ValidateToolCatalog(missingCooldown)
	assertFalse(valid, "missing cooldown rejected")
	assertEqual(reason, "tool_cooldown_missing index=2", "missing cooldown reason")
end

print("tinyfolk_tool_catalog_schema: all checks passed")
