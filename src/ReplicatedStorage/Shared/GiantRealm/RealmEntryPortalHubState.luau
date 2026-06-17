--!strict

local LiveRealmHubRouting = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("LiveRealmHubRouting"))
	else (require :: any)("./LiveRealmHubRouting")

local LiveRealmRegistryState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("LiveRealmRegistryState"))
	else (require :: any)("./LiveRealmRegistryState")

local PlayerLocationState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("PlayerLocationState"))
	else (require :: any)("./PlayerLocationState")

local RealmAssignmentProfileState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAssignmentProfileState"))
	else (require :: any)("./RealmAssignmentProfileState")

local RealmEntryPortalConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("RealmEntryPortalConfig"))
	else (require :: any)("../Config/RealmEntryPortalConfig")

local RealmPermissionConfig = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("RealmPermissionConfig"))
	else (require :: any)("../Config/RealmPermissionConfig")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTransferState"))
	else (require :: any)("./RealmTransferState")

local RealmEntryPortalHubState: any = {}

local EntryMethods = RealmEntryPortalConfig.EntryMethods
local EntryRoles = RealmEntryPortalConfig.EntryRoles
local LocationOps = PlayerLocationState.Operations
local TransitReason = PlayerLocationState.TransitReason
local AssignmentOps = RealmTransferState.Operations

local FORBIDDEN_CLIENT_FIELDS = {
	privateServerId = true,
	jobId = true,
}

local DEFAULT_ROLE_BY_METHOD: { [string]: string } = {
	[EntryMethods.Portal] = EntryRoles.Guest,
	[EntryMethods.Contract] = EntryRoles.Worker,
	[EntryMethods.Raid] = EntryRoles.Raider,
	[EntryMethods.Invitation] = EntryRoles.Guest,
}

local validEntryMethodSet: { [string]: boolean } = {}
for _, methodName in pairs(EntryMethods) do
	validEntryMethodSet[methodName] = true
end

local validEntryRoleSet: { [string]: boolean } = {}
for _, roleName in pairs(EntryRoles) do
	validEntryRoleSet[roleName] = true
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
end

function RealmEntryPortalHubState.ResolveEntryRole(entryMethod: any, requestedRole: any?): (string?, string?)
	if not isNonEmptyString(entryMethod) or validEntryMethodSet[entryMethod] ~= true then
		return nil, "entry_method_invalid"
	end

	if requestedRole == nil then
		local defaultRole = DEFAULT_ROLE_BY_METHOD[entryMethod :: string]
		if defaultRole == nil then
			return nil, "entry_role_default_missing"
		end
		return defaultRole, "accepted"
	end

	if not isNonEmptyString(requestedRole) or validEntryRoleSet[requestedRole] ~= true then
		return nil, "entry_role_invalid"
	end

	if entryMethod == EntryMethods.Raid and requestedRole ~= EntryRoles.Raider then
		return nil, "raid_entry_requires_raider_role"
	end
	if entryMethod == EntryMethods.Contract and requestedRole == EntryRoles.Raider then
		return nil, "contract_entry_role_invalid"
	end
	if entryMethod == EntryMethods.Invitation and requestedRole == EntryRoles.Raider then
		return nil, "invitation_entry_role_invalid"
	end

	return requestedRole :: string, "accepted"
end

function RealmEntryPortalHubState.ResolveAdmissionEntryType(entryMethod: string, entryRole: string): string
	if entryMethod == EntryMethods.Invitation then
		return RealmPermissionConfig.EntryTypes.DirectInvite
	end
	if entryRole == EntryRoles.PrisonerTransfer then
		return RealmPermissionConfig.EntryTypes.RescueContract
	end
	return RealmPermissionConfig.EntryTypes.Standard
end

function RealmEntryPortalHubState.ResolveAssignmentReason(_entryMethod: string, entryRole: string): string
	if entryRole == EntryRoles.PrisonerTransfer then
		return RealmAssignmentProfileState.AssignmentReason.Rescue
	end
	return RealmAssignmentProfileState.AssignmentReason.PartyAdmission
end

function RealmEntryPortalHubState.ResolveAssignmentBeginOperation(assignmentReason: string): string?
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.Rescue then
		return AssignmentOps.BeginRescue
	end
	if assignmentReason == RealmAssignmentProfileState.AssignmentReason.PartyAdmission then
		return AssignmentOps.BeginPartyAdmission
	end
	return nil
end

function RealmEntryPortalHubState.ResolveTransitReason(entryMethod: string, entryRole: string): string
	if entryRole == EntryRoles.PrisonerTransfer then
		return TransitReason.Capture
	end
	if entryMethod == EntryMethods.Raid or entryRole == EntryRoles.Raider then
		return TransitReason.Raid
	end
	return TransitReason.PartyAdmission
end

function RealmEntryPortalHubState.ResolveConfirmLocationOperation(entryRole: string): string
	if entryRole == EntryRoles.Raider then
		return LocationOps.ConfirmRealmInvader
	end
	if entryRole == EntryRoles.PrisonerTransfer then
		return LocationOps.ConfirmCaptured
	end
	return LocationOps.ConfirmRealmGuest
end

function RealmEntryPortalHubState.IsDiscoverableForMethod(snapshot: any, entryMethod: any): boolean
	if type(snapshot) ~= "table" or snapshot.isAvailable ~= true then
		return false
	end

	local accessMode = snapshot.accessMode
	if entryMethod == EntryMethods.Raid then
		return accessMode == LiveRealmRegistryState.AccessMode.Public
			or accessMode == LiveRealmRegistryState.AccessMode.RaidEnabled
	end
	if entryMethod == EntryMethods.Invitation then
		return accessMode == LiveRealmRegistryState.AccessMode.Public
			or accessMode == LiveRealmRegistryState.AccessMode.InviteOnly
	end
	return accessMode == LiveRealmRegistryState.AccessMode.Public
		or accessMode == LiveRealmRegistryState.AccessMode.RaidEnabled
end

function RealmEntryPortalHubState.BuildOwnerDisplayName(ownerUserId: any, resolvedDisplayName: any?): string
	if isNonEmptyString(resolvedDisplayName) then
		return resolvedDisplayName :: string
	end
	if isPositiveInteger(ownerUserId) then
		return string.format("Giant %d", ownerUserId)
	end
	return "Unknown Giant"
end

function RealmEntryPortalHubState.BuildRealmDisplayName(ownerDisplayName: string): string
	if ownerDisplayName == "" then
		return "Unknown Realm"
	end
	return string.format("%s's Realm", ownerDisplayName)
end

function RealmEntryPortalHubState.ResolveAccessModeLabel(accessMode: any): string
	if type(accessMode) ~= "string" then
		return "Unknown"
	end
	local label = RealmEntryPortalConfig.AccessModeLabels[accessMode]
	return if type(label) == "string" then label else "Unknown"
end

function RealmEntryPortalHubState.ResolveEntryRoleLabel(entryRole: any): string
	if type(entryRole) ~= "string" then
		return "Unknown"
	end
	local label = RealmEntryPortalConfig.EntryRoleLabels[entryRole]
	return if type(label) == "string" then label else "Unknown"
end

function RealmEntryPortalHubState.BuildListingRow(
	snapshot: any,
	availability: { any },
	entryMethod: string,
	ownerDisplayName: string?
): any?
	if not RealmEntryPortalHubState.IsDiscoverableForMethod(snapshot, entryMethod) then
		return nil
	end
	if not isNonEmptyString(snapshot.realmId) or not isPositiveInteger(snapshot.ownerUserId) then
		return nil
	end

	local ownerLabel = RealmEntryPortalHubState.BuildOwnerDisplayName(snapshot.ownerUserId, ownerDisplayName)
	local resolvedRole = select(1, RealmEntryPortalHubState.ResolveEntryRole(entryMethod, nil))
	if resolvedRole == nil then
		return nil
	end

	local admissionTarget = LiveRealmHubRouting.ResolveAdmissionTarget({
		targetRealmId = snapshot.realmId,
	}, availability)

	return {
		realmId = snapshot.realmId,
		ownerUserId = snapshot.ownerUserId,
		ownerDisplayName = ownerLabel,
		realmDisplayName = RealmEntryPortalHubState.BuildRealmDisplayName(ownerLabel),
		entryMethod = entryMethod,
		entryMethodLabel = RealmEntryPortalConfig.EntryMethodLabels[entryMethod] or "Portal",
		entryRole = resolvedRole,
		entryRoleLabel = RealmEntryPortalHubState.ResolveEntryRoleLabel(resolvedRole),
		accessMode = snapshot.accessMode,
		accessModeLabel = RealmEntryPortalHubState.ResolveAccessModeLabel(snapshot.accessMode),
		playerCount = if type(snapshot.playerCount) == "number"
			then math.max(0, math.floor(snapshot.playerCount))
			else 0,
		capacity = if type(snapshot.capacity) == "number"
			then math.max(1, math.floor(snapshot.capacity))
			else LiveRealmRegistryState.DEFAULT_CAPACITY,
		isEnterable = admissionTarget.accepted == true,
		updatedAt = if type(snapshot.updatedAt) == "number" then snapshot.updatedAt else 0,
	}
end

function RealmEntryPortalHubState.SortListingRows(rows: { any }): { any }
	local sorted = table.clone(rows)
	table.sort(sorted, function(left: any, right: any): boolean
		local leftRealmId = if type(left) == "table" then left.realmId else ""
		local rightRealmId = if type(right) == "table" then right.realmId else ""
		return leftRealmId < rightRealmId
	end)
	return sorted
end

function RealmEntryPortalHubState.ProjectListings(input: any): any
	if type(input) ~= "table" or type(input.availability) ~= "table" then
		return {
			accepted = false,
			reason = "availability_invalid",
			listings = {},
		}
	end

	local entryMethod = if isNonEmptyString(input.entryMethod) then input.entryMethod else EntryMethods.Portal
	if validEntryMethodSet[entryMethod] ~= true then
		return {
			accepted = false,
			reason = "entry_method_invalid",
			listings = {},
		}
	end

	local limit = input.limit
	if limit == nil then
		limit = RealmEntryPortalConfig.DefaultListLimit
	end
	if not isPositiveInteger(limit) then
		return {
			accepted = false,
			reason = "list_limit_invalid",
			listings = {},
		}
	end
	if limit > RealmEntryPortalConfig.MaxListLimit then
		limit = RealmEntryPortalConfig.MaxListLimit
	end

	local ownerDisplayNames = if type(input.ownerDisplayNames) == "table" then input.ownerDisplayNames else {}
	local rows = {}
	for _, snapshot in ipairs(input.availability) do
		local ownerDisplayName = if type(snapshot) == "table" and type(snapshot.ownerUserId) == "number"
			then ownerDisplayNames[snapshot.ownerUserId]
			else nil
		local row =
			RealmEntryPortalHubState.BuildListingRow(snapshot, input.availability, entryMethod, ownerDisplayName)
		if row ~= nil then
			table.insert(rows, row)
		end
	end

	local sortedRows = RealmEntryPortalHubState.SortListingRows(rows)
	local boundedRows = {}
	for index, row in ipairs(sortedRows) do
		if index > limit then
			break
		end
		table.insert(boundedRows, row)
	end

	return {
		accepted = true,
		reason = "accepted",
		listings = boundedRows,
		entryMethod = entryMethod,
	}
end

function RealmEntryPortalHubState.ResolveEntryRequest(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "entry_request_invalid" }
	end

	local entryMethod = input.entryMethod
	if not isNonEmptyString(entryMethod) or validEntryMethodSet[entryMethod] ~= true then
		return { accepted = false, reason = "entry_method_invalid" }
	end

	local entryRole, roleReason = RealmEntryPortalHubState.ResolveEntryRole(entryMethod, input.entryRole)
	if entryRole == nil then
		return { accepted = false, reason = roleReason or "entry_role_invalid" }
	end

	local targetRealmId = input.targetRealmId
	if not isNonEmptyString(targetRealmId) then
		return { accepted = false, reason = "target_realm_id_invalid" }
	end

	local availability = if type(input.availability) == "table" then input.availability else {}
	local snapshot = LiveRealmHubRouting.FindAvailabilityByRealmId(availability, targetRealmId)
	if snapshot == nil then
		return { accepted = false, reason = "target_realm_unavailable" }
	end
	if not RealmEntryPortalHubState.IsDiscoverableForMethod(snapshot, entryMethod) then
		return { accepted = false, reason = "target_realm_not_discoverable" }
	end

	local admissionTarget = LiveRealmHubRouting.ResolveAdmissionTarget({
		targetRealmId = targetRealmId,
	}, availability)
	if admissionTarget.accepted ~= true then
		return {
			accepted = false,
			reason = admissionTarget.reason or "target_realm_unavailable",
		}
	end

	local realmOwnerUserId = RealmTransferState.ParseRealmOwnerUserId(targetRealmId)
	if realmOwnerUserId == nil then
		return { accepted = false, reason = "realm_target_invalid" }
	end

	local assignmentReason = RealmEntryPortalHubState.ResolveAssignmentReason(entryMethod, entryRole)
	local assignmentBeginOperation = RealmEntryPortalHubState.ResolveAssignmentBeginOperation(assignmentReason)
	if assignmentBeginOperation == nil then
		return { accepted = false, reason = "assignment_operation_invalid" }
	end

	return {
		accepted = true,
		reason = "accepted",
		entryMethod = entryMethod,
		entryRole = entryRole,
		entryRoleLabel = RealmEntryPortalHubState.ResolveEntryRoleLabel(entryRole),
		targetRealmId = targetRealmId,
		realmOwnerUserId = realmOwnerUserId,
		admissionEntryType = RealmEntryPortalHubState.ResolveAdmissionEntryType(entryMethod, entryRole),
		assignmentReason = assignmentReason,
		assignmentBeginOperation = assignmentBeginOperation,
		locationBeginOperation = LocationOps.BeginTransit,
		locationTransitReason = RealmEntryPortalHubState.ResolveTransitReason(entryMethod, entryRole),
		locationConfirmOperation = RealmEntryPortalHubState.ResolveConfirmLocationOperation(entryRole),
		resolverPath = admissionTarget.resolverPath,
	}
end

function RealmEntryPortalHubState.AssertClientSafeListingRow(row: any): (boolean, string?)
	if type(row) ~= "table" then
		return false, "listing_row_invalid"
	end
	for fieldName in pairs(FORBIDDEN_CLIENT_FIELDS) do
		if row[fieldName] ~= nil then
			return false, "forbidden_field_exposed"
		end
	end
	return true, nil
end

function RealmEntryPortalHubState.FormatListingRowLine(row: any): string
	if type(row) ~= "table" then
		return "Unavailable listing"
	end
	local population = string.format("%d/%d", row.playerCount or 0, row.capacity or 0)
	return string.format(
		"%s | %s | %s | %s | Enterable=%s",
		row.realmDisplayName or row.realmId or "Unknown",
		row.entryRoleLabel or "Unknown",
		row.accessModeLabel or "Unknown",
		population,
		tostring(row.isEnterable == true)
	)
end

return RealmEntryPortalHubState
