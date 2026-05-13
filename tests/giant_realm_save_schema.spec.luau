--!strict

local GiantRealmSaveSchema = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value, label)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertValid(label: string, valid: boolean, reason: string?)
	if not valid then
		error(string.format("expected valid [%s] but got reason=%s", label, tostring(reason)))
	end
end

local function assertInvalid(expectedReason: string, label: string, valid: boolean, reason: string?)
	if valid then
		error(string.format("expected invalid [%s] but got valid", label))
	end
	assertEqual(reason, expectedReason, label .. " reason")
end

local function makeOccupiedBox(tag: string?)
	local box: any = {
		worldCenter = { x = 12, y = 3, z = -5 },
		halfExtents = { x = 4, y = 2, z = 6 },
	}
	if tag ~= nil then
		box.tag = tag
	end
	return box
end

local function makePlacedStructureRecord(structureId: string)
	return {
		structureId = structureId,
		placedByUserId = 9402,
		placedAt = 101.5,
		proposedOccupiedSpace = {
			makeOccupiedBox("body"),
		},
	}
end

local function makeSaveRoot()
	return {
		schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
		ownerUserId = 9402,
		placedStructures = {
			makePlacedStructureRecord("GiantStructure_Runtime_A"),
		},
	}
end

local function assertVector3Equal(actual, expected, label)
	assertEqual(actual.x, expected.x, label .. " x")
	assertEqual(actual.y, expected.y, label .. " y")
	assertEqual(actual.z, expected.z, label .. " z")
end

local function assertRecordMatchesState(record, state, label)
	assertEqual(record.structureId, state.structureId, label .. " structureId")
	assertEqual(record.placedByUserId, state.placedByUserId, label .. " placedByUserId")
	assertEqual(record.placedAt, state.placedAt, label .. " placedAt")
	assertEqual(#record.proposedOccupiedSpace, #state.proposedOccupiedSpace, label .. " occupied count")
	assertEqual(record.proposedOccupiedSpace[1].tag, state.proposedOccupiedSpace[1].tag, label .. " tag")
	assertVector3Equal(record.proposedOccupiedSpace[1].worldCenter, state.proposedOccupiedSpace[1].worldCenter, label .. " worldCenter")
	assertVector3Equal(record.proposedOccupiedSpace[1].halfExtents, state.proposedOccupiedSpace[1].halfExtents, label .. " halfExtents")
end

local function run()
	assertEqual(GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION, 1, "initial schema version is fixed")
	assertTrue(GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION > 0, "initial schema version is positive")

	do
		local valid, reason = GiantRealmSaveSchema.ValidateSaveRoot(makeSaveRoot())
		assertValid("valid save root", valid, reason)
	end

	do
		local valid, reason = GiantRealmSaveSchema.ValidatePlacedStructureRecord(makePlacedStructureRecord("A"))
		assertValid("valid placed structure record", valid, reason)
	end

	do
		local state = makePlacedStructureRecord("GiantStructure_Runtime_A")
		local record = GiantRealmSaveSchema.SerializePlacedStructureRecord(state)
		assertRecordMatchesState(record, state, "serialized record")
		assertTrue(record ~= state, "serialized record is a copy")
		assertTrue(record.proposedOccupiedSpace ~= state.proposedOccupiedSpace, "serialized occupied space is a copy")
		assertTrue(
			record.proposedOccupiedSpace[1].worldCenter ~= state.proposedOccupiedSpace[1].worldCenter,
			"serialized world center is a copy"
		)
	end

	do
		local statesById = {
			GiantStructure_Runtime_C = makePlacedStructureRecord("GiantStructure_Runtime_C"),
			GiantStructure_Runtime_A = makePlacedStructureRecord("GiantStructure_Runtime_A"),
			GiantStructure_Runtime_B = makePlacedStructureRecord("GiantStructure_Runtime_B"),
		}

		local records = GiantRealmSaveSchema.SerializePlacedStructuresById(statesById)
		assertEqual(#records, 3, "serialized record count")
		assertEqual(records[1].structureId, "GiantStructure_Runtime_A", "serialized order A")
		assertEqual(records[2].structureId, "GiantStructure_Runtime_B", "serialized order B")
		assertEqual(records[3].structureId, "GiantStructure_Runtime_C", "serialized order C")

		local repeatedRecords = GiantRealmSaveSchema.SerializePlacedStructuresById(statesById)
		assertEqual(repeatedRecords[1].structureId, records[1].structureId, "repeated order A stable")
		assertEqual(repeatedRecords[2].structureId, records[2].structureId, "repeated order B stable")
		assertEqual(repeatedRecords[3].structureId, records[3].structureId, "repeated order C stable")
	end

	do
		local statesById = {
			GiantStructure_Runtime_B = makePlacedStructureRecord("GiantStructure_Runtime_B"),
			GiantStructure_Runtime_A = makePlacedStructureRecord("GiantStructure_Runtime_A"),
		}

		local root = GiantRealmSaveSchema.BuildSaveRoot(9402, statesById)
		assertEqual(root.schemaVersion, GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION, "built root schema version")
		assertEqual(root.ownerUserId, 9402, "built root owner")
		assertEqual(root.placedStructures[1].structureId, "GiantStructure_Runtime_A", "built root deterministic first")
		assertEqual(root.placedStructures[2].structureId, "GiantStructure_Runtime_B", "built root deterministic second")
		assertValid("built root validates", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local root = makeSaveRoot()
		root.schemaVersion = 2
		assertInvalid(
			"save_root_schema_version_invalid",
			"invalid schema version",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local root = makeSaveRoot()
		root.ownerUserId = nil
		assertInvalid(
			"save_root_owner_user_id_invalid",
			"missing owner",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local root = makeSaveRoot()
		root.placedStructures = nil
		assertInvalid(
			"save_root_placed_structures_invalid",
			"missing placed structures",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local record = makePlacedStructureRecord("")
		assertInvalid(
			"placed_structure_structure_id_invalid",
			"invalid structure id",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end

	do
		local record = makePlacedStructureRecord("A")
		record.placedByUserId = 0
		assertInvalid(
			"placed_structure_placed_by_user_id_invalid",
			"invalid placedByUserId",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end

	do
		local record = makePlacedStructureRecord("A")
		record.placedAt = -1
		assertInvalid(
			"placed_structure_placed_at_invalid",
			"invalid placedAt",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end

	do
		local record = makePlacedStructureRecord("A")
		record.proposedOccupiedSpace = {}
		assertInvalid(
			"placed_structure_occupied_space_empty",
			"empty occupied space",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end

	do
		local record = makePlacedStructureRecord("A")
		record.proposedOccupiedSpace[1].tag = 42
		assertInvalid(
			"occupied_space_box_tag_invalid index=1",
			"invalid occupied tag",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end

	do
		local record = makePlacedStructureRecord("A")
		record.proposedOccupiedSpace[1].worldCenter = { x = 1, y = "bad", z = 3 }
		assertInvalid(
			"occupied_space_box_world_center_invalid index=1",
			"invalid occupied worldCenter",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end

	do
		local record = makePlacedStructureRecord("A")
		record.proposedOccupiedSpace[1].halfExtents = { x = 1, y = 0, z = 3 }
		assertInvalid(
			"occupied_space_box_half_extents_invalid index=1",
			"invalid occupied halfExtents",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end
end

run()

print("giant_realm_save_schema: all checks passed")
