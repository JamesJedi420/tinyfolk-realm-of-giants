--!strict

local RealmReservedServerAllocationService: any = {}
local globalEnv: any = getfenv()

local RealmReservedServerAllocationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmReservedServerAllocationState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmReservedServerAllocationState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTransferState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local RealmReservedServerAllocationStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmReservedServerAllocationStore"))
	else (require :: any)("./RealmReservedServerAllocationStore")

local allocationByOwnerUserId: { [number]: any } = {}
local allocationStore: any = nil
local runtimeConfig: any = nil

local diagnostics = {
	ensureAttempts = 0,
	ensureSucceeded = 0,
	ensureCreated = 0,
	resolveAttempts = 0,
	resolveSucceeded = 0,
	lastReason = "not_started",
	lastRealmId = nil :: string?,
}

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function resolveNow(): number
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and type(configAny.now) == "function" then
		local at = configAny.now()
		if type(at) == "number" and at == at then
			return at
		end
	end
	return os.clock()
end

local function resolveTeleportService(): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and configAny.teleportService ~= nil then
		return configAny.teleportService
	end
	if game ~= nil and type(game.GetService) == "function" then
		local ok, service = pcall(function()
			return game:GetService("TeleportService")
		end)
		if ok then
			return service
		end
	end
	return nil
end

local function resolveDestinationPlaceId(input: any): number?
	if type(input) == "table" and isPositiveInteger(input.destinationPlaceId) then
		return math.floor(input.destinationPlaceId)
	end
	if game ~= nil and isPositiveInteger(game.PlaceId) then
		return game.PlaceId
	end
	return nil
end

local function getAllocationStore(): any
	if allocationStore ~= nil then
		return allocationStore
	end
	local configAny: any = runtimeConfig
	allocationStore = RealmReservedServerAllocationStore.Create({
		adapter = if type(configAny) == "table" then configAny.memoryStoreAdapter else nil,
		allocationState = RealmReservedServerAllocationState,
		structurePolicy = if type(configAny) == "table" and configAny.structurePolicy ~= nil
			then configAny.structurePolicy
			else MemoryStoreStructurePolicy,
	})
	return allocationStore
end

local function getProfilePersistenceGateway(): any?
	local configAny: any = runtimeConfig
	if type(configAny) == "table" and configAny.profilePersistenceGateway ~= nil then
		return configAny.profilePersistenceGateway
	end
	local gateway = globalEnv.ProfilePersistenceGateway
	if type(gateway) == "table" then
		return gateway
	end
	if type(_G) == "table" and type((_G :: any).ProfilePersistenceGateway) == "table" then
		return (_G :: any).ProfilePersistenceGateway
	end
	return nil
end

local function publishMirror(record: any, at: number): (boolean, string)
	local mirror = RealmReservedServerAllocationState.ToMirrorRecord(record, at)
	if mirror == nil then
		return false, "mirror_record_invalid"
	end
	local store = getAllocationStore()
	local result = store.PublishAllocationRecord(mirror)
	if type(result) ~= "table" or result.accepted ~= true then
		return false,
			if type(result) == "table" and type(result.reason) == "string"
				then result.reason
				else "mirror_publish_failed"
	end
	return true, "accepted"
end

function RealmReservedServerAllocationService.GetDiagnostics(): any
	return {
		ensureAttempts = diagnostics.ensureAttempts,
		ensureSucceeded = diagnostics.ensureSucceeded,
		ensureCreated = diagnostics.ensureCreated,
		resolveAttempts = diagnostics.resolveAttempts,
		resolveSucceeded = diagnostics.resolveSucceeded,
		lastReason = diagnostics.lastReason,
		lastRealmId = diagnostics.lastRealmId,
	}
end

function RealmReservedServerAllocationService.BuildPersistenceState(ownerUserId: any): any?
	if not isPositiveInteger(ownerUserId) then
		return nil
	end
	return allocationByOwnerUserId[math.floor(ownerUserId)]
end

function RealmReservedServerAllocationService.ApplyPersistenceState(
	saveRecord: any,
	ownerUserId: any
): (boolean, string?)
	if not isPositiveInteger(ownerUserId) then
		return false, "owner_user_id_invalid"
	end
	local resolvedOwnerUserId = math.floor(ownerUserId)
	if saveRecord == nil then
		allocationByOwnerUserId[resolvedOwnerUserId] = nil
		return true, nil
	end
	local record = RealmReservedServerAllocationState.FromSaveRecord(resolvedOwnerUserId, saveRecord)
	if record == nil then
		return false, "realm_server_allocation_invalid"
	end
	allocationByOwnerUserId[resolvedOwnerUserId] = record
	local published, publishReason = publishMirror(record, resolveNow())
	if not published then
		return false, publishReason
	end
	return true, nil
end

function RealmReservedServerAllocationService.EnsureAllocation(input: any): any
	diagnostics.ensureAttempts += 1
	if type(input) ~= "table" or not isPositiveInteger(input.ownerUserId) then
		diagnostics.lastReason = "owner_user_id_invalid"
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
			record = nil,
			created = false,
		}
	end

	local ownerUserId = math.floor(input.ownerUserId)
	local destinationPlaceId = resolveDestinationPlaceId(input)
	if destinationPlaceId == nil then
		diagnostics.lastReason = "destination_place_unresolved"
		return {
			accepted = false,
			reason = "destination_place_unresolved",
			record = nil,
			created = false,
		}
	end

	local existing = allocationByOwnerUserId[ownerUserId]
	if existing ~= nil then
		local valid, _ = RealmReservedServerAllocationState.ValidateAllocationRecord(existing)
		if valid then
			diagnostics.ensureSucceeded += 1
			diagnostics.lastReason = "accepted"
			diagnostics.lastRealmId = existing.realmId
			local published, publishReason = publishMirror(existing, resolveNow())
			if not published then
				diagnostics.lastReason = publishReason
				return {
					accepted = false,
					reason = publishReason,
					record = existing,
					created = false,
				}
			end
			return {
				accepted = true,
				reason = "accepted",
				record = existing,
				created = false,
			}
		end
	end

	local teleportService = resolveTeleportService()
	if type(teleportService) ~= "table" or type(teleportService.ReserveServer) ~= "function" then
		diagnostics.lastReason = "reserve_server_unavailable"
		return {
			accepted = false,
			reason = "reserve_server_unavailable",
			record = nil,
			created = false,
		}
	end

	local reserveOk, reservedAccessCode = pcall(function()
		return teleportService:ReserveServer(destinationPlaceId)
	end)
	if not reserveOk or type(reservedAccessCode) ~= "string" or reservedAccessCode == "" then
		diagnostics.lastReason = "reserve_server_failed"
		return {
			accepted = false,
			reason = "reserve_server_failed",
			record = nil,
			created = false,
		}
	end

	local created = RealmReservedServerAllocationState.BuildAllocationRecord({
		ownerUserId = ownerUserId,
		reservedAccessCode = reservedAccessCode,
		destinationPlaceId = destinationPlaceId,
		allocatedAt = resolveNow(),
		created = true,
	})
	if created.accepted ~= true or created.record == nil then
		diagnostics.lastReason = created.reason
		return created
	end

	allocationByOwnerUserId[ownerUserId] = created.record
	diagnostics.ensureSucceeded += 1
	diagnostics.ensureCreated += 1
	diagnostics.lastReason = "accepted"
	diagnostics.lastRealmId = created.record.realmId

	local published, publishReason = publishMirror(created.record, resolveNow())
	if not published then
		diagnostics.lastReason = publishReason
		return {
			accepted = false,
			reason = publishReason,
			record = created.record,
			created = true,
		}
	end

	local gateway = getProfilePersistenceGateway()
	if type(gateway) == "table" and type(gateway.SaveGiantRealmProfile) == "function" then
		local saveResult = gateway.SaveGiantRealmProfile(ownerUserId)
		if type(saveResult) ~= "table" or saveResult.ok ~= true then
			diagnostics.lastReason = "allocation_save_failed"
			return {
				accepted = false,
				reason = "allocation_save_failed",
				record = created.record,
				created = true,
			}
		end
	end

	return created
end

function RealmReservedServerAllocationService.ResolveAccessCodeForRealm(realmId: any): any
	diagnostics.resolveAttempts += 1
	diagnostics.lastRealmId = if type(realmId) == "string" then realmId else nil

	if type(realmId) ~= "string" or realmId == "" then
		diagnostics.lastReason = "realm_id_invalid"
		return {
			accepted = false,
			reason = "realm_id_invalid",
			accessCode = nil,
			destinationPlaceId = nil,
		}
	end

	local ownerUserId = RealmTransferState.ParseRealmOwnerUserId(realmId)
	if ownerUserId ~= nil then
		local inMemory = allocationByOwnerUserId[ownerUserId]
		if
			inMemory ~= nil
			and RealmReservedServerAllocationState.IsUsableReservedAccessCode(inMemory.reservedAccessCode, ownerUserId)
		then
			diagnostics.resolveSucceeded += 1
			diagnostics.lastReason = "accepted"
			return {
				accepted = true,
				reason = "accepted",
				accessCode = inMemory.reservedAccessCode,
				destinationPlaceId = inMemory.destinationPlaceId,
			}
		end
	end

	local store = getAllocationStore()
	local readResult = store.GetAllocationRecord(realmId)
	if type(readResult) ~= "table" or readResult.accepted ~= true then
		diagnostics.lastReason = if type(readResult) == "table" and type(readResult.reason) == "string"
			then readResult.reason
			else "allocation_mirror_unavailable"
		return {
			accepted = false,
			reason = diagnostics.lastReason,
			accessCode = nil,
			destinationPlaceId = nil,
		}
	end

	local mirrorRecord = readResult.record
	if mirrorRecord == nil then
		diagnostics.lastReason = "reserved_server_unallocated"
		return {
			accepted = false,
			reason = "reserved_server_unallocated",
			accessCode = nil,
			destinationPlaceId = nil,
		}
	end

	local valid, reason = RealmReservedServerAllocationState.ValidateAllocationRecord(mirrorRecord)
	if not valid then
		diagnostics.lastReason = reason or "allocation_mirror_invalid"
		return {
			accepted = false,
			reason = diagnostics.lastReason,
			accessCode = nil,
			destinationPlaceId = nil,
		}
	end

	diagnostics.resolveSucceeded += 1
	diagnostics.lastReason = "accepted"
	return {
		accepted = true,
		reason = "accepted",
		accessCode = mirrorRecord.reservedAccessCode,
		destinationPlaceId = mirrorRecord.destinationPlaceId,
	}
end

function RealmReservedServerAllocationService.ConfigureForTests(config: any?)
	runtimeConfig = if type(config) == "table" then config else {}
	allocationStore = nil
	if type(config) == "table" and type(config.allocationStore) == "table" then
		allocationStore = config.allocationStore
	end
end

function RealmReservedServerAllocationService.ResetForTests()
	allocationByOwnerUserId = {}
	allocationStore = nil
	runtimeConfig = nil
	diagnostics = {
		ensureAttempts = 0,
		ensureSucceeded = 0,
		ensureCreated = 0,
		resolveAttempts = 0,
		resolveSucceeded = 0,
		lastReason = "not_started",
		lastRealmId = nil,
	}
end

return RealmReservedServerAllocationService
