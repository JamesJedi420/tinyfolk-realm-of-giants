--!strict

local GiantRealmSaveSchema = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")

type Vector3Data = {
	x: number,
	y: number,
	z: number,
}

type OccupiedSpaceBoxRecord = {
	tag: string?,
	worldCenter: Vector3Data,
	halfExtents: Vector3Data,
}

type PlacedStructureSaveRecord = {
	structureId: string,
	placedByUserId: number,
	placedAt: number,
	proposedOccupiedSpace: { OccupiedSpaceBoxRecord },
}

type EmergencyReinforcementSaveRecord = {
	used: boolean,
	callStartedAt: number?,
	cooldownEndsAt: number?,
	triggeredByUserId: number?,
	spawnedUserId: number?,
	lastReason: string?,
	lastObjectiveId: string?,
}

type ShrineSaveRecord = {
	shrineId: string,
	isActive: boolean,
	essenceTotal: number,
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
}

type ShrinePersistenceSaveRecord = {
	shrines: { ShrineSaveRecord },
}

type RescueContractSaveRecord = {
	rescuerUserId: number,
	targetUserId: number,
	targetRealmOwnerUserId: number,
	entryRouteId: string,
	entryRouteKind: string,
	startedAt: number,
	expiresAt: number,
	isAccelerated: boolean,
}

type RescueQueueEntrySaveRecord = {
	queueEntryId: string,
	capturedUserId: number,
	realmId: string,
	sessionId: string,
	rewardHint: string,
	dangerRating: number,
	expiration: number,
	rescuerUserId: number,
	targetRealmOwnerUserId: number,
	entryRouteId: string,
	entryRouteKind: string,
	createdAt: number,
	status: string,
	acceptedAt: number?,
	acceptedByUserId: number?,
	resolvedAt: number?,
	resolvedReason: string?,
}

type RescuePersistenceSaveRecord = {
	contracts: { RescueContractSaveRecord },
	queueEntries: { RescueQueueEntrySaveRecord },
}

type DefenseHistorySaveRecord = {
	escapeOutcomes: { any },
}

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
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

local function makeOccupiedBox(tag: string?): OccupiedSpaceBoxRecord
	local box: OccupiedSpaceBoxRecord = {
		tag = nil,
		worldCenter = { x = 12, y = 3, z = -5 },
		halfExtents = { x = 4, y = 2, z = 6 },
	}
	if tag ~= nil then
		box.tag = tag
	end
	return box
end

local function makePlacedStructureRecord(structureId: string): PlacedStructureSaveRecord
	return {
		structureId = structureId,
		placedByUserId = 9402,
		placedAt = 101.5,
		proposedOccupiedSpace = {
			makeOccupiedBox("body"),
		},
	}
end

local function makeSaveRoot(): any
	return {
		schemaVersion = GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION,
		ownerUserId = 9402,
		placedStructures = {
			makePlacedStructureRecord("GiantStructure_Runtime_A"),
		},
	}
end

local function makeEmergencyReinforcementRecord(): EmergencyReinforcementSaveRecord
	return {
		used = true,
		callStartedAt = 55,
		cooldownEndsAt = 100,
		triggeredByUserId = 1101,
		spawnedUserId = 1103,
		lastReason = "accepted",
		lastObjectiveId = "CallCenter_A",
	}
end

local function makeShrinePersistenceRecord(): ShrinePersistenceSaveRecord
	return {
		shrines = {
			{
				shrineId = "Shrine_B",
				isActive = false,
				essenceTotal = 12,
				tickCount = 4,
				lastTickAt = 90,
				activatedByUserId = nil,
			},
			{
				shrineId = "Shrine_A",
				isActive = true,
				essenceTotal = 33,
				tickCount = 11,
				lastTickAt = 120,
				activatedByUserId = 7201,
			},
		},
	}
end

local function makeRescuePersistenceRecord(): RescuePersistenceSaveRecord
	return {
		contracts = {
			{
				rescuerUserId = 9404,
				targetUserId = 9409,
				targetRealmOwnerUserId = 9402,
				entryRouteId = "RescueRoute_B",
				entryRouteKind = "RealmEntry",
				startedAt = 90,
				expiresAt = 125,
				isAccelerated = false,
			},
			{
				rescuerUserId = 9401,
				targetUserId = 9408,
				targetRealmOwnerUserId = 9402,
				entryRouteId = "RescueRoute_A",
				entryRouteKind = "RealmEntry",
				startedAt = 80,
				expiresAt = 130,
				isAccelerated = true,
			},
		},
		queueEntries = {
			{
				queueEntryId = "RQ_02",
				capturedUserId = 7402,
				realmId = "Realm_A",
				sessionId = "Session_A",
				rewardHint = "high",
				dangerRating = 0.8,
				expiration = 220,
				rescuerUserId = 9404,
				targetRealmOwnerUserId = 9402,
				entryRouteId = "RescueRoute_B",
				entryRouteKind = "RealmEntry",
				createdAt = 110,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
			{
				queueEntryId = "RQ_01",
				capturedUserId = 7401,
				realmId = "Realm_A",
				sessionId = "Session_A",
				rewardHint = "medium",
				dangerRating = 0.4,
				expiration = 210,
				rescuerUserId = 9401,
				targetRealmOwnerUserId = 9402,
				entryRouteId = "RescueRoute_A",
				entryRouteKind = "RealmEntry",
				createdAt = 100,
				status = "accepted",
				acceptedAt = 105,
				acceptedByUserId = 9401,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	}
end

local function makeDefenseHistoryRecord(): DefenseHistorySaveRecord
	return {
		escapeOutcomes = {
			{
				operationId = "escape:101:EscapeRoute_A:10",
				escapedUserId = 101,
				escapedAt = 10,
				sourceKind = "final_exit",
				sourceId = "EscapeRoute_A",
				routeId = "EscapeRoute_A",
				difficulty = 2,
				lootValue = 3,
				rewardPoints = 155,
			},
			{
				operationId = "escape_transport:Transport_A:102:20",
				escapedUserId = 102,
				escapedAt = 20,
				sourceKind = "transport",
				sourceId = "Transport_A",
				routeId = nil,
				difficulty = 1,
				lootValue = 0,
				rewardPoints = 100,
			},
		},
	}
end

local function assertVector3Equal(actual: Vector3Data, expected: Vector3Data, label: string)
	assertEqual(actual.x, expected.x, label .. " x")
	assertEqual(actual.y, expected.y, label .. " y")
	assertEqual(actual.z, expected.z, label .. " z")
end

local function assertRecordMatchesState(
	record: PlacedStructureSaveRecord,
	state: PlacedStructureSaveRecord,
	label: string
)
	assertEqual(record.structureId, state.structureId, label .. " structureId")
	assertEqual(record.placedByUserId, state.placedByUserId, label .. " placedByUserId")
	assertEqual(record.placedAt, state.placedAt, label .. " placedAt")
	assertEqual(#record.proposedOccupiedSpace, #state.proposedOccupiedSpace, label .. " occupied count")
	assertEqual(record.proposedOccupiedSpace[1].tag, state.proposedOccupiedSpace[1].tag, label .. " tag")
	assertVector3Equal(
		record.proposedOccupiedSpace[1].worldCenter,
		state.proposedOccupiedSpace[1].worldCenter,
		label .. " worldCenter"
	)
	assertVector3Equal(
		record.proposedOccupiedSpace[1].halfExtents,
		state.proposedOccupiedSpace[1].halfExtents,
		label .. " halfExtents"
	)
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
		root.emergencyReinforcement = makeEmergencyReinforcementRecord()
		assertValid("valid save root with emergency reinforcement", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local root = makeSaveRoot()
		root.shrinePersistence = makeShrinePersistenceRecord()
		assertValid("valid save root with shrine persistence", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local root = makeSaveRoot()
		root.rescuePersistence = makeRescuePersistenceRecord()
		assertValid("valid save root with rescue persistence", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local root = makeSaveRoot()
		root.defenseHistory = makeDefenseHistoryRecord()
		assertValid("valid save root with defense history", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local serialized =
			GiantRealmSaveSchema.SerializeEmergencyReinforcementRecord(makeEmergencyReinforcementRecord())
		assertEqual(serialized.used, true, "serialized reinforcement used")
		assertEqual(serialized.triggeredByUserId, 1101, "serialized reinforcement triggeredByUserId")
		assertEqual(serialized.lastObjectiveId, "CallCenter_A", "serialized reinforcement lastObjectiveId")
	end

	do
		local statesById = {
			GiantStructure_Runtime_B = makePlacedStructureRecord("GiantStructure_Runtime_B"),
			GiantStructure_Runtime_A = makePlacedStructureRecord("GiantStructure_Runtime_A"),
		}

		local root = GiantRealmSaveSchema.BuildSaveRoot(9402, statesById, makeEmergencyReinforcementRecord())
		assertTrue(type(root.emergencyReinforcement) == "table", "built root includes reinforcement record")
		assertEqual(root.emergencyReinforcement.used, true, "built root reinforcement used")
		assertEqual(root.emergencyReinforcement.spawnedUserId, 1103, "built root reinforcement spawned user")
		assertValid("built root with reinforcement validates", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local serialized = GiantRealmSaveSchema.SerializeShrinePersistenceRecord(makeShrinePersistenceRecord())
		assertEqual(#serialized.shrines, 2, "serialized shrine persistence count")
		assertEqual(serialized.shrines[1].shrineId, "Shrine_A", "serialized shrine order first")
		assertEqual(serialized.shrines[2].shrineId, "Shrine_B", "serialized shrine order second")
		assertEqual(serialized.shrines[1].activatedByUserId, 7201, "serialized shrine activatedByUserId")
	end

	do
		local statesById = {
			GiantStructure_Runtime_B = makePlacedStructureRecord("GiantStructure_Runtime_B"),
			GiantStructure_Runtime_A = makePlacedStructureRecord("GiantStructure_Runtime_A"),
		}

		local root = GiantRealmSaveSchema.BuildSaveRoot(9402, statesById, nil, makeShrinePersistenceRecord())
		assertTrue(type(root.shrinePersistence) == "table", "built root includes shrine persistence")
		assertEqual(root.shrinePersistence.shrines[1].shrineId, "Shrine_A", "built root shrine order first")
		assertEqual(root.shrinePersistence.shrines[2].shrineId, "Shrine_B", "built root shrine order second")
		assertValid("built root with shrine persistence validates", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local serialized = GiantRealmSaveSchema.SerializeRescuePersistenceRecord(makeRescuePersistenceRecord())
		assertEqual(#serialized.contracts, 2, "serialized rescue contract count")
		assertEqual(serialized.contracts[1].rescuerUserId, 9401, "serialized rescue contract order first")
		assertEqual(serialized.contracts[2].rescuerUserId, 9404, "serialized rescue contract order second")
		assertEqual(#serialized.queueEntries, 2, "serialized rescue queue count")
		assertEqual(serialized.queueEntries[1].queueEntryId, "RQ_01", "serialized rescue queue order first")
		assertEqual(serialized.queueEntries[2].queueEntryId, "RQ_02", "serialized rescue queue order second")
	end

	do
		local serialized = GiantRealmSaveSchema.SerializeDefenseHistoryRecord(makeDefenseHistoryRecord())
		assertEqual(#serialized.escapeOutcomes, 2, "serialized defense history count")
		assertEqual(serialized.escapeOutcomes[1].operationId, "escape:101:EscapeRoute_A:10", "defense order first")
		assertEqual(
			serialized.escapeOutcomes[2].operationId,
			"escape_transport:Transport_A:102:20",
			"defense order second"
		)
	end

	do
		local statesById = {
			GiantStructure_Runtime_B = makePlacedStructureRecord("GiantStructure_Runtime_B"),
			GiantStructure_Runtime_A = makePlacedStructureRecord("GiantStructure_Runtime_A"),
		}

		local root = GiantRealmSaveSchema.BuildSaveRoot(9402, statesById, nil, nil, makeRescuePersistenceRecord())
		assertTrue(type(root.rescuePersistence) == "table", "built root includes rescue persistence")
		assertEqual(root.rescuePersistence.contracts[1].rescuerUserId, 9401, "built root rescue contract first")
		assertEqual(root.rescuePersistence.queueEntries[1].queueEntryId, "RQ_01", "built root rescue queue first")
		assertValid("built root with rescue persistence validates", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local root = GiantRealmSaveSchema.BuildSaveRoot(9402, {}, nil, nil, nil, makeDefenseHistoryRecord())
		assertTrue(type(root.defenseHistory) == "table", "built root includes defense history")
		assertEqual(root.defenseHistory.escapeOutcomes[1].escapedUserId, 101, "built defense first user")
		assertValid("built root with defense history validates", GiantRealmSaveSchema.ValidateSaveRoot(root))
	end

	do
		local root = makeSaveRoot()
		root.emergencyReinforcement = {
			used = "yes",
		}
		assertInvalid(
			"emergency_reinforcement_used_invalid",
			"invalid reinforcement used",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local root = makeSaveRoot()
		root.shrinePersistence = {
			shrines = {
				{
					shrineId = "Shrine_A",
					isActive = true,
					essenceTotal = 10,
					tickCount = 2,
					lastTickAt = 20,
					activatedByUserId = nil,
				},
			},
		}
		assertInvalid(
			"shrine_activated_by_user_id_missing index=1",
			"invalid shrine activatedByUserId missing",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local root = makeSaveRoot()
		root.shrinePersistence = makeShrinePersistenceRecord()
		root.shrinePersistence.shrines[2].shrineId = "Shrine_B"
		assertInvalid(
			"shrine_id_duplicate index=2",
			"invalid shrine duplicate id",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local root = makeSaveRoot()
		root.rescuePersistence = makeRescuePersistenceRecord()
		root.rescuePersistence.queueEntries[2].queueEntryId = "RQ_02"
		assertInvalid(
			"rescue_queue_entry_id_duplicate index=2",
			"invalid rescue queue duplicate id",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local root = makeSaveRoot()
		root.defenseHistory = makeDefenseHistoryRecord()
		root.defenseHistory.escapeOutcomes[2].operationId = root.defenseHistory.escapeOutcomes[1].operationId
		assertInvalid(
			"defense_escape_operation_id_duplicate index=2",
			"invalid defense duplicate operation id",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
	end

	do
		local root = makeSaveRoot()
		root.emergencyReinforcement = makeEmergencyReinforcementRecord()
		root.emergencyReinforcement.triggeredByUserId = 0
		assertInvalid(
			"emergency_reinforcement_triggered_by_user_id_invalid",
			"invalid reinforcement triggeredByUserId",
			GiantRealmSaveSchema.ValidateSaveRoot(root)
		)
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
		assertInvalid("save_root_owner_user_id_invalid", "missing owner", GiantRealmSaveSchema.ValidateSaveRoot(root))
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
		local invalidBox: any = record.proposedOccupiedSpace[1]
		invalidBox.tag = 42
		assertInvalid(
			"occupied_space_box_tag_invalid index=1",
			"invalid occupied tag",
			GiantRealmSaveSchema.ValidatePlacedStructureRecord(record)
		)
	end

	do
		local record = makePlacedStructureRecord("A")
		local invalidBox: any = record.proposedOccupiedSpace[1]
		invalidBox.worldCenter = { x = 1, y = "bad", z = 3 }
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
