--!strict

local GiantRealmSaveSchema = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("GiantRealmSaveSchema"))
	else (require :: any)("./GiantRealmSaveSchema")

local GiantRealmLoadState: any = {}

GiantRealmLoadState.LoadOutcome = {
	LoadedExisting = "loaded_existing",
	CreatedDefault = "created_default",
	RecoveredCorrupt = "recovered_corrupt",
}

export type ResolveResult = {
	accepted: boolean,
	reason: string?,
	saveRoot: any?,
	loadOutcome: string?,
	recovered: boolean,
}

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

function GiantRealmLoadState.BuildDefaultStarterSaveRoot(ownerUserId: number): any
	return GiantRealmSaveSchema.BuildSaveRoot(ownerUserId, {}, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)
end

function GiantRealmLoadState.BuildRecoverySaveRoot(ownerUserId: number): any
	return GiantRealmLoadState.BuildDefaultStarterSaveRoot(ownerUserId)
end

local function isFreshTemplateRoot(rawSaveRoot: any, ownerUserId: number): boolean
	if type(rawSaveRoot) ~= "table" then
		return false
	end
	if rawSaveRoot.schemaVersion ~= GiantRealmSaveSchema.INITIAL_SCHEMA_VERSION then
		return false
	end
	if type(rawSaveRoot.placedStructures) ~= "table" then
		return false
	end
	if #rawSaveRoot.placedStructures > 0 then
		return false
	end
	if rawSaveRoot.ownerUserId == 0 or rawSaveRoot.ownerUserId == ownerUserId then
		return true
	end
	return false
end

function GiantRealmLoadState.ResolveSaveRootForSession(rawSaveRoot: any, ownerUserId: number): ResolveResult
	if not isPositiveInteger(ownerUserId) then
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
			saveRoot = nil,
			loadOutcome = nil,
			recovered = false,
		}
	end

	local valid, validationReason = GiantRealmSaveSchema.ValidateSaveRoot(rawSaveRoot)
	if valid == true and type(rawSaveRoot) == "table" and rawSaveRoot.ownerUserId == ownerUserId then
		return {
			accepted = true,
			reason = nil,
			saveRoot = rawSaveRoot,
			loadOutcome = GiantRealmLoadState.LoadOutcome.LoadedExisting,
			recovered = false,
		}
	end

	if isFreshTemplateRoot(rawSaveRoot, ownerUserId) then
		return {
			accepted = true,
			reason = "missing_or_template_realm",
			saveRoot = GiantRealmLoadState.BuildDefaultStarterSaveRoot(ownerUserId),
			loadOutcome = GiantRealmLoadState.LoadOutcome.CreatedDefault,
			recovered = true,
		}
	end

	return {
		accepted = true,
		reason = validationReason or "giant_realm_save_root_invalid",
		saveRoot = GiantRealmLoadState.BuildRecoverySaveRoot(ownerUserId),
		loadOutcome = GiantRealmLoadState.LoadOutcome.RecoveredCorrupt,
		recovered = true,
	}
end

return GiantRealmLoadState
