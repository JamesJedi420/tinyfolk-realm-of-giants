--!nocheck
-- ContainmentStructureService: bounded authored containment structures for TIN-61.

local function resolveDependency(parent: any, childName: string, fallbackRequirePath: string): any
	if parent ~= nil and type(parent.WaitForChild) == "function" then
		local child = parent:WaitForChild(childName)
		if child ~= nil then
			local childAny = child :: any
			if type(childAny) == "table" then
				return childAny
			end
			local ok, requiredOrError = pcall(function()
				return require(childAny)
			end)
			if ok then
				return requiredOrError
			end
		end
	end
	return require(fallbackRequirePath)
end

local function getService(gameRef: any, serviceName: string): any
	local colonOk, colonValue = pcall(function()
		return gameRef:GetService(serviceName)
	end)
	if colonOk and colonValue ~= nil then
		return colonValue
	end
	local dotOk, dotValue = pcall(function()
		return gameRef.GetService(serviceName)
	end)
	if dotOk and dotValue ~= nil then
		return dotValue
	end
	return nil
end

local function createContainmentStructureService(runtimeGame: any?, options: any?)
	local globalEnv: any = getfenv()
	local gameRef = runtimeGame or game
	local _Players = getService(gameRef, "Players")
	local ReplicatedStorage = getService(gameRef, "ReplicatedStorage")
	local Workspace = getService(gameRef, "Workspace")

	local Shared = if ReplicatedStorage ~= nil and type(ReplicatedStorage.WaitForChild) == "function"
		then ReplicatedStorage:WaitForChild("Shared")
		else nil
	local Config = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("Config")
		else nil
	local GiantRealm = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("GiantRealm")
		else nil

	local ContainmentStructureConfig = resolveDependency(
		Config,
		"ContainmentStructureConfig",
		"../../ReplicatedStorage/Shared/Config/ContainmentStructureConfig"
	)
	local RoleConfig = resolveDependency(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	local ContainmentStructureState = resolveDependency(
		GiantRealm,
		"ContainmentStructureState",
		"../../ReplicatedStorage/Shared/GiantRealm/ContainmentStructureState"
	)

	local function now(): number
		if options ~= nil and type(options.now) == "function" then
			return options.now()
		end
		return os.clock()
	end

	local structurePartById: { [string]: any } = {}
	local zonePartById: { [string]: any } = {}
	local structureRecordById: { [string]: any? } = {}

	local function getNestedRoot(folderPath: { string }): any
		if Workspace == nil or type(Workspace.FindFirstChild) ~= "function" then
			return nil
		end
		local current: any = Workspace
		for _, childName in folderPath do
			current = current:FindFirstChild(childName)
			if current == nil then
				return nil
			end
		end
		return current
	end

	local function startsWithPrefix(name: string, prefix: string): boolean
		return string.match(name, "^" .. prefix) ~= nil
	end

	local function isBasePart(node: any): boolean
		return node ~= nil and type(node.IsA) == "function" and node:IsA("BasePart")
	end

	local function getDescendants(root: any): { any }
		if root == nil or type(root.GetDescendants) ~= "function" then
			return {}
		end
		local ok, result = pcall(function()
			return root:GetDescendants()
		end)
		return if ok and type(result) == "table" then result else {}
	end

	local function getCoordinate(position: any, keyUpper: string, keyLower: string): number?
		if type(position) ~= "table" then
			return nil
		end
		if type(position[keyUpper]) == "number" then
			return position[keyUpper]
		end
		if type(position[keyLower]) == "number" then
			return position[keyLower]
		end
		return nil
	end

	local function getPosition(part: any): any
		return if part ~= nil then part.Position else nil
	end

	local function distanceBetween(a: any, b: any): number?
		local ax = getCoordinate(a, "X", "x")
		local ay = getCoordinate(a, "Y", "y")
		local az = getCoordinate(a, "Z", "z")
		local bx = getCoordinate(b, "X", "x")
		local by = getCoordinate(b, "Y", "y")
		local bz = getCoordinate(b, "Z", "z")
		if ax == nil or ay == nil or az == nil or bx == nil or by == nil or bz == nil then
			return nil
		end
		local dx = ax - bx
		local dy = ay - by
		local dz = az - bz
		return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
	end

	local function readNumberValueChild(part: any, childName: string): number?
		if part == nil or type(part.FindFirstChild) ~= "function" then
			return nil
		end
		local child = part:FindFirstChild(childName)
		if child ~= nil and type(child.Value) == "number" then
			return child.Value
		end
		return nil
	end

	local function partInsideZone(part: any, zonePart: any): boolean
		local radius = readNumberValueChild(zonePart, "Radius")
		if type(radius) == "number" then
			local px = getCoordinate(getPosition(part), "X", "x")
			local pz = getCoordinate(getPosition(part), "Z", "z")
			local zx = getCoordinate(getPosition(zonePart), "X", "x")
			local zz = getCoordinate(getPosition(zonePart), "Z", "z")
			if px == nil or pz == nil or zx == nil or zz == nil then
				return false
			end
			local dx = px - zx
			local dz = pz - zz
			return math.sqrt((dx * dx) + (dz * dz)) <= radius
		end

		local px = getCoordinate(getPosition(part), "X", "x")
		local py = getCoordinate(getPosition(part), "Y", "y")
		local pz = getCoordinate(getPosition(part), "Z", "z")
		local zx = getCoordinate(getPosition(zonePart), "X", "x")
		local zy = getCoordinate(getPosition(zonePart), "Y", "y")
		local zz = getCoordinate(getPosition(zonePart), "Z", "z")
		local sx = getCoordinate(zonePart.Size, "X", "x")
		local sy = getCoordinate(zonePart.Size, "Y", "y")
		local sz = getCoordinate(zonePart.Size, "Z", "z")
		if px == nil or py == nil or pz == nil or zx == nil or zy == nil or zz == nil or sx == nil or sy == nil or sz == nil then
			return false
		end
		return math.abs(px - zx) <= (sx / 2)
			and math.abs(py - zy) <= (sy / 2)
			and math.abs(pz - zz) <= (sz / 2)
	end

	local function positionInsideZone(position: any, zonePart: any): boolean
		return partInsideZone({ Position = position }, zonePart)
	end

	local function encodeOccupantUserIds(userIds: { number }): string
		if #userIds == 0 then
			return ""
		end
		local parts: { string } = {}
		for _, userId in ipairs(userIds) do
			table.insert(parts, tostring(userId))
		end
		return table.concat(parts, ",")
	end

	local function resolveStructureType(structurePart: any): string
		if type(structurePart.GetAttribute) == "function" then
			local attr = structurePart:GetAttribute(ContainmentStructureConfig.StructureTypeAttribute)
			if type(attr) == "string" and ContainmentStructureState.ValidateStructureType(ContainmentStructureConfig, attr) then
				return attr
			end
		end
		return "cage"
	end

	local function resolveZoneId(structurePart: any): string
		if type(structurePart.GetAttribute) == "function" then
			local attr = structurePart:GetAttribute(ContainmentStructureConfig.ZoneIdAttribute)
			if type(attr) == "string" and attr ~= "" then
				return attr
			end
		end
		local suffix = string.gsub(structurePart.Name, "^" .. ContainmentStructureConfig.StructureNamePrefix, "")
		return ContainmentStructureConfig.ZoneNamePrefix .. suffix
	end

	local function resolveCapacity(structurePart: any, structureType: string): number
		if type(structurePart.GetAttribute) == "function" then
			local attr = structurePart:GetAttribute(ContainmentStructureConfig.CapacityAttribute)
			if type(attr) == "number" and attr > 0 then
				return math.floor(attr)
			end
		end
		return ContainmentStructureState.ResolveStructureTypeNumber(
			ContainmentStructureConfig,
			structureType,
			"defaultCapacity",
			ContainmentStructureConfig.DefaultCapacity
		)
	end

	local function resolveEnabled(structurePart: any): boolean
		if type(structurePart.GetAttribute) == "function" then
			local attr = structurePart:GetAttribute(ContainmentStructureConfig.EnabledAttribute)
			if attr == false then
				return false
			end
		end
		return true
	end

	local function resolveEscapeInteractionEnabled(structurePart: any, structureType: string): boolean
		if type(structurePart.GetAttribute) == "function" then
			local attr = structurePart:GetAttribute(ContainmentStructureConfig.EscapeInteractionAttribute)
			if attr == true then
				return true
			end
			if attr == false then
				return false
			end
		end
		local catalog = ContainmentStructureConfig.StructureTypes[structureType]
		return type(catalog) == "table" and catalog.escapeInteractionEnabled == true
	end

	local function applyStructureAttributes(structureId: string)
		local structurePart = structurePartById[structureId]
		local record = structureRecordById[structureId]
		if structurePart == nil or type(structurePart.SetAttribute) ~= "function" then
			return
		end
		local snapshot = ContainmentStructureState.Snapshot(ContainmentStructureConfig, record)
		if snapshot == nil then
			return
		end
		local attrs = ContainmentStructureConfig.Attributes
		structurePart:SetAttribute(attrs.State, snapshot.status)
		structurePart:SetAttribute(attrs.StructureType, snapshot.structureType)
		structurePart:SetAttribute(attrs.ZoneId, snapshot.zoneId)
		structurePart:SetAttribute(attrs.Capacity, snapshot.capacity)
		structurePart:SetAttribute(attrs.OccupantCount, snapshot.occupantCount)
		structurePart:SetAttribute(attrs.OccupantUserIds, encodeOccupantUserIds(snapshot.occupantUserIds))
		structurePart:SetAttribute(attrs.EscapeInteractionEnabled, snapshot.escapeInteractionEnabled)
	end

	local function registerStructures()
		local root = getNestedRoot(ContainmentStructureConfig.StructuresFolderPath)
		for _, descendant in ipairs(getDescendants(root)) do
			if isBasePart(descendant) and startsWithPrefix(descendant.Name, ContainmentStructureConfig.StructureNamePrefix) then
				structurePartById[descendant.Name] = descendant
				if structureRecordById[descendant.Name] == nil then
					local structureType = resolveStructureType(descendant)
					structureRecordById[descendant.Name] = ContainmentStructureState.NewRecord(
						descendant.Name,
						structureType,
						resolveZoneId(descendant),
						resolveCapacity(descendant, structureType),
						resolveEnabled(descendant),
						resolveEscapeInteractionEnabled(descendant, structureType),
						ContainmentStructureConfig
					)
				end
				applyStructureAttributes(descendant.Name)
			end
		end
	end

	local function registerZones()
		local root = getNestedRoot(ContainmentStructureConfig.ZonesFolderPath)
		for _, descendant in ipairs(getDescendants(root)) do
			if isBasePart(descendant) and startsWithPrefix(descendant.Name, ContainmentStructureConfig.ZoneNamePrefix) then
				zonePartById[descendant.Name] = descendant
			end
		end
	end

	local function refreshRegistries()
		structurePartById = {}
		zonePartById = {}
		registerZones()
		registerStructures()
		for structureId in pairs(structureRecordById) do
			if structurePartById[structureId] == nil then
				structureRecordById[structureId] = nil
			else
				applyStructureAttributes(structureId)
			end
		end
	end

	local function getStructureIdsInZone(custodianPosition: any, targetPosition: any): { string }
		local ids: { string } = {}
		for structureId, record in pairs(structureRecordById) do
			if record ~= nil and record.enabled == true then
				local zonePart = zonePartById[record.zoneId]
				if zonePart ~= nil then
					local custodianInside = positionInsideZone(custodianPosition, zonePart)
					local targetInside = positionInsideZone(targetPosition, zonePart)
					if custodianInside or targetInside then
						table.insert(ids, structureId)
					end
				end
			end
		end
		table.sort(ids)
		return ids
	end

	local function resolveStructureForPositions(custodianPosition: any, targetPosition: any): string?
		refreshRegistries()
		local candidates = getStructureIdsInZone(custodianPosition, targetPosition)
		for _, structureId in ipairs(candidates) do
			local record = structureRecordById[structureId]
			local snapshot = ContainmentStructureState.Snapshot(ContainmentStructureConfig, record)
			if snapshot ~= nil and snapshot.hasCapacity == true then
				return structureId
			end
		end
		return candidates[1]
	end

	local function findStructureIdForTargetUserId(targetUserId: number): string?
		for structureId, record in pairs(structureRecordById) do
			if record ~= nil and ContainmentStructureState.IsOccupant(record, targetUserId) then
				return structureId
			end
		end
		return nil
	end

	local service: any = {}

	function service.getRegisteredStructureCount(): number
		refreshRegistries()
		local count = 0
		for _ in pairs(structureRecordById) do
			count += 1
		end
		return count
	end

	function service.getStructureSnapshot(structureId: string): any
		refreshRegistries()
		return ContainmentStructureState.Snapshot(ContainmentStructureConfig, structureRecordById[structureId])
	end

	function service.getStructureIdForTargetUserId(targetUserId: number): string?
		refreshRegistries()
		return findStructureIdForTargetUserId(targetUserId)
	end

	function service.resolveAssignOccupantForCapture(input: any): any
		refreshRegistries()
		if type(input) ~= "table" then
			return { accepted = false, reason = "assign_input_invalid", structureId = nil }
		end
		local targetUserId = input.targetUserId
		if type(targetUserId) ~= "number" then
			return { accepted = false, reason = "target_user_id_invalid", structureId = nil }
		end

		if service.getRegisteredStructureCount() == 0 then
			return { accepted = true, reason = "structures_unregistered", structureId = nil, skipped = true }
		end

		local structureId = input.structureId
		if type(structureId) ~= "string" or structureId == "" then
			structureId = resolveStructureForPositions(input.custodianPosition, input.targetPosition)
		end
		if structureId == nil then
			return { accepted = false, reason = "containment_structure_not_in_range", structureId = nil }
		end

		local record = structureRecordById[structureId]
		local assign = ContainmentStructureState.AssignOccupant(record, targetUserId)
		if assign.accepted ~= true or assign.record == nil then
			return {
				accepted = false,
				reason = assign.reason,
				structureId = structureId,
				snapshot = ContainmentStructureState.Snapshot(ContainmentStructureConfig, record),
			}
		end

		structureRecordById[structureId] = assign.record
		applyStructureAttributes(structureId)
		return {
			accepted = true,
			reason = "accepted",
			structureId = structureId,
			snapshot = ContainmentStructureState.Snapshot(ContainmentStructureConfig, assign.record),
		}
	end

	function service.removeOccupantByTargetUserId(targetUserId: number): any
		refreshRegistries()
		local structureId = findStructureIdForTargetUserId(targetUserId)
		if structureId == nil then
			return { accepted = false, reason = "occupant_not_found", structureId = nil }
		end
		local record = structureRecordById[structureId]
		local removed = ContainmentStructureState.RemoveOccupant(record, targetUserId)
		if removed.accepted ~= true or removed.record == nil then
			return { accepted = false, reason = removed.reason, structureId = structureId }
		end
		structureRecordById[structureId] = removed.record
		applyStructureAttributes(structureId)
		return {
			accepted = true,
			reason = "accepted",
			structureId = structureId,
			snapshot = ContainmentStructureState.Snapshot(ContainmentStructureConfig, removed.record),
		}
	end

	function service.canRescueOccupant(rescuerUserId: number, targetUserId: number, rescuerPosition: any): any
		refreshRegistries()
		local structureId = findStructureIdForTargetUserId(targetUserId)
		if structureId == nil then
			return { accepted = false, reason = "occupant_not_found", structureId = nil }
		end
		local record = structureRecordById[structureId]
		local zonePart = zonePartById[record.zoneId]
		local inRange = false
		if zonePart ~= nil then
			inRange = positionInsideZone(rescuerPosition, zonePart)
		end
		return ContainmentStructureState.CanRescueOccupant(
			ContainmentStructureConfig,
			record,
			rescuerUserId,
			targetUserId,
			true,
			inRange,
			nil
		)
	end

	function service.hasEscapeInteractionForTarget(targetUserId: number): boolean
		refreshRegistries()
		local structureId = findStructureIdForTargetUserId(targetUserId)
		if structureId == nil then
			return false
		end
		return ContainmentStructureState.HasEscapeInteraction(
			ContainmentStructureConfig,
			structureRecordById[structureId]
		)
	end

	function service.ResetForTests()
		structureRecordById = {}
		refreshRegistries()
	end

	local function initialize()
		refreshRegistries()
	end

	globalEnv._ContainmentStructureService_QueryAPI = {
		GetRegisteredStructureCount = function(): number
			return service.getRegisteredStructureCount()
		end,
		GetStructureSnapshot = function(structureId: string): any
			return service.getStructureSnapshot(structureId)
		end,
		GetStructureIdForTargetUserId = function(targetUserId: number): string?
			return service.getStructureIdForTargetUserId(targetUserId)
		end,
		ResolveAssignOccupantForCapture = function(input: any): any
			return service.resolveAssignOccupantForCapture(input)
		end,
		RemoveOccupantByTargetUserId = function(targetUserId: number): any
			return service.removeOccupantByTargetUserId(targetUserId)
		end,
		CanRescueOccupant = function(rescuerUserId: number, targetUserId: number, rescuerPosition: any): any
			return service.canRescueOccupant(rescuerUserId, targetUserId, rescuerPosition)
		end,
		HasEscapeInteractionForTarget = function(targetUserId: number): boolean
			return service.hasEscapeInteractionForTarget(targetUserId)
		end,
		ResetForTests = function()
			service.ResetForTests()
		end,
	}

	if type(_G) == "table" then
		rawset(_G, "_ContainmentStructureService_QueryAPI", globalEnv._ContainmentStructureService_QueryAPI)
	end

	if options == nil or options.autoInitialize ~= false then
		local ok, errorOrNil = pcall(initialize)
		if not ok then
			warn(string.format("[ContainmentStructureService] Initialization skipped: %s", tostring(errorOrNil)))
		end
	end

	return service
end

return createContainmentStructureService
