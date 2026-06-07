--!strict

local TraitRegistrySchema: any = {}

export type TraitRole = "Giant" | "Tinyfolk" | "Shared"
export type TraitCategory = "movement" | "utility" | "loadout" | "defense" | "social" | "resource" | "traversal"
export type TraitSlotType = "primary" | "secondary" | "passive" | "active" | "support"
export type TraitTier = "starter" | "common" | "uncommon" | "rare" | "epic" | "legendary"
export type TraitUnlockSource =
	"initial"
	| "account_mastery"
	| "role_mastery"
	| "reputation"
	| "milestone"
	| "quest"
	| "achievement"
export type TraitTrigger =
	"passive"
	| "manual_activation"
	| "route_crossing"
	| "spawn"
	| "on_carry"
	| "on_escape"
	| "on_release"
	| "on_rescue"
export type TraitDurationType = "instant" | "timed" | "persistent" | "toggle"
export type TraitStackingPolicy = "none" | "refresh" | "additive" | "replace" | "exclusive"
export type TraitVisibility = "hidden" | "loadout_only" | "role_select" | "public"
export type TraitUnlockOwner = "playerProfile" | "realmProfile"

export type TraitRecord = {
	traitId: string,
	name: string,
	description: string?,
	role: TraitRole,
	category: TraitCategory,
	slotType: TraitSlotType,
	tier: TraitTier,
	unlockSource: TraitUnlockSource,
	unlockOwner: TraitUnlockOwner?,
	unlockTrackId: string?,
	unlockSourceId: string?,
	trigger: TraitTrigger,
	durationType: TraitDurationType,
	durationSeconds: number?,
	cooldownSeconds: number,
	sharedCooldownKey: string?,
	stacking: TraitStackingPolicy,
	visibility: TraitVisibility,
	antiAbuseTags: { string },
	testCoverageHooks: { string },
	sourceId: string,
}

TraitRegistrySchema.SCHEMA_VERSION = 1

TraitRegistrySchema.Roles = {
	Giant = "Giant",
	Tinyfolk = "Tinyfolk",
	Shared = "Shared",
}

TraitRegistrySchema.Categories = {
	Movement = "movement",
	Utility = "utility",
	Loadout = "loadout",
	Defense = "defense",
	Social = "social",
	Resource = "resource",
	Traversal = "traversal",
}

TraitRegistrySchema.SlotTypes = {
	Primary = "primary",
	Secondary = "secondary",
	Passive = "passive",
	Active = "active",
	Support = "support",
}

TraitRegistrySchema.Tiers = {
	Starter = "starter",
	Common = "common",
	Uncommon = "uncommon",
	Rare = "rare",
	Epic = "epic",
	Legendary = "legendary",
}

TraitRegistrySchema.UnlockSources = {
	Initial = "initial",
	AccountMastery = "account_mastery",
	RoleMastery = "role_mastery",
	Reputation = "reputation",
	Milestone = "milestone",
	Quest = "quest",
	Achievement = "achievement",
}

TraitRegistrySchema.Triggers = {
	Passive = "passive",
	ManualActivation = "manual_activation",
	RouteCrossing = "route_crossing",
	Spawn = "spawn",
	OnCarry = "on_carry",
	OnEscape = "on_escape",
	OnRelease = "on_release",
	OnRescue = "on_rescue",
}

TraitRegistrySchema.DurationTypes = {
	Instant = "instant",
	Timed = "timed",
	Persistent = "persistent",
	Toggle = "toggle",
}

TraitRegistrySchema.StackingPolicies = {
	None = "none",
	Refresh = "refresh",
	Additive = "additive",
	Replace = "replace",
	Exclusive = "exclusive",
}

TraitRegistrySchema.Visibilities = {
	Hidden = "hidden",
	LoadoutOnly = "loadout_only",
	RoleSelect = "role_select",
	Public = "public",
}

TraitRegistrySchema.AntiAbuseTags = {
	AccountUnlockGuard = "account_unlock_guard",
	CooldownSpamGuard = "cooldown_spam_guard",
	DuplicateTraitGuard = "duplicate_trait_guard",
	PairFarming = "pair_farming",
	PairRepeatGuard = "pair_repeat_guard",
	ReputationGateGuard = "reputation_gate_guard",
	RoleSafeUse = "role_safe_use",
	SharedCooldownGuard = "shared_cooldown_guard",
	VisibilityGate = "visibility_gate",
}

local VALID_ROLES = {
	Giant = true,
	Tinyfolk = true,
	Shared = true,
}

local VALID_CATEGORIES = {
	movement = true,
	utility = true,
	loadout = true,
	defense = true,
	social = true,
	resource = true,
	traversal = true,
}

local VALID_SLOT_TYPES = {
	primary = true,
	secondary = true,
	passive = true,
	active = true,
	support = true,
}

local VALID_TIERS = {
	starter = true,
	common = true,
	uncommon = true,
	rare = true,
	epic = true,
	legendary = true,
}

local VALID_UNLOCK_SOURCES = {
	initial = true,
	account_mastery = true,
	role_mastery = true,
	reputation = true,
	milestone = true,
	quest = true,
	achievement = true,
}

local VALID_TRIGGERS = {
	passive = true,
	manual_activation = true,
	route_crossing = true,
	spawn = true,
	on_carry = true,
	on_escape = true,
	on_release = true,
	on_rescue = true,
}

local VALID_DURATION_TYPES = {
	instant = true,
	timed = true,
	persistent = true,
	toggle = true,
}

local VALID_STACKING = {
	none = true,
	refresh = true,
	additive = true,
	replace = true,
	exclusive = true,
}

local VALID_VISIBILITY = {
	hidden = true,
	loadout_only = true,
	role_select = true,
	public = true,
}

local VALID_ANTI_ABUSE_TAGS = {
	account_unlock_guard = true,
	cooldown_spam_guard = true,
	duplicate_trait_guard = true,
	pair_farming = true,
	pair_repeat_guard = true,
	reputation_gate_guard = true,
	role_safe_use = true,
	shared_cooldown_guard = true,
	visibility_gate = true,
}

TraitRegistrySchema.VALID_ROLES = VALID_ROLES
TraitRegistrySchema.VALID_CATEGORIES = VALID_CATEGORIES
TraitRegistrySchema.VALID_SLOT_TYPES = VALID_SLOT_TYPES
TraitRegistrySchema.VALID_TIERS = VALID_TIERS
TraitRegistrySchema.VALID_UNLOCK_SOURCES = VALID_UNLOCK_SOURCES
TraitRegistrySchema.VALID_TRIGGERS = VALID_TRIGGERS
TraitRegistrySchema.VALID_DURATION_TYPES = VALID_DURATION_TYPES
TraitRegistrySchema.VALID_STACKING = VALID_STACKING
TraitRegistrySchema.VALID_VISIBILITY = VALID_VISIBILITY
TraitRegistrySchema.VALID_ANTI_ABUSE_TAGS = VALID_ANTI_ABUSE_TAGS

local defaultTraitRegistry: { TraitRecord } = {
	{
		traitId = "Tinyfolk_PostCrossingBurst",
		name = "Post-Crossing Burst",
		description = "A short burst after an approved route crossing.",
		role = "Tinyfolk",
		category = "movement",
		slotType = "passive",
		tier = "starter",
		unlockSource = "initial",
		unlockOwner = nil,
		unlockTrackId = nil,
		unlockSourceId = nil,
		trigger = "route_crossing",
		durationType = "timed",
		durationSeconds = 1.25,
		cooldownSeconds = 6,
		sharedCooldownKey = "tinyfolk_post_crossing_burst",
		stacking = "refresh",
		visibility = "loadout_only",
		antiAbuseTags = { "cooldown_spam_guard", "pair_repeat_guard" },
		testCoverageHooks = { "trait.registry.tinyfolk_post_crossing_burst" },
		sourceId = "tin172_tinyfolk_post_crossing_burst",
	},
	{
		traitId = "Giant_ControlStationScan",
		name = "Control Station Scan",
		description = "A bounded Giant-side awareness pulse.",
		role = "Giant",
		category = "utility",
		slotType = "active",
		tier = "common",
		unlockSource = "role_mastery",
		unlockOwner = "playerProfile",
		unlockTrackId = "giant_role_mastery_track",
		unlockSourceId = "giant_role_mastery_1",
		trigger = "manual_activation",
		durationType = "timed",
		durationSeconds = 4,
		cooldownSeconds = 20,
		sharedCooldownKey = "giant_control_station_scan",
		stacking = "exclusive",
		visibility = "role_select",
		antiAbuseTags = { "cooldown_spam_guard", "role_safe_use" },
		testCoverageHooks = { "trait.registry.giant_control_station_scan" },
		sourceId = "tin172_giant_control_station_scan",
	},
	{
		traitId = "Shared_CampCoordination",
		name = "Camp Coordination",
		description = "A shared, passive registry example for loadout routing.",
		role = "Shared",
		category = "social",
		slotType = "support",
		tier = "uncommon",
		unlockSource = "account_mastery",
		unlockOwner = "playerProfile",
		unlockTrackId = "shared_account_mastery_track",
		unlockSourceId = "account_mastery_2",
		trigger = "passive",
		durationType = "persistent",
		durationSeconds = nil,
		cooldownSeconds = 0,
		sharedCooldownKey = nil,
		stacking = "none",
		visibility = "public",
		antiAbuseTags = { "account_unlock_guard" },
		testCoverageHooks = { "trait.registry.shared_camp_coordination" },
		sourceId = "tin172_shared_camp_coordination",
	},
}

TraitRegistrySchema.DEFAULT_TRAIT_REGISTRY = defaultTraitRegistry

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isPositiveNumber(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	return value > 0
end

local function isNonNegativeNumber(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	return value >= 0
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function isEnumValue(value: any, enumSet: { [string]: boolean }): boolean
	if type(value) ~= "string" then
		return false
	end
	return enumSet[value] == true
end

local function hasUniqueStrings(values: { string }): boolean
	local seen = {}
	for _, value in ipairs(values) do
		if seen[value] then
			return false
		end
		seen[value] = true
	end
	return true
end

local function cloneStringArray(source: { string }): { string }
	local copied = {}
	for _, value in ipairs(source) do
		table.insert(copied, value)
	end
	return copied
end

local function validateStringArray(values: any, reason: string, allowEmpty: boolean): (boolean, string?)
	if type(values) ~= "table" then
		return false, reason
	end
	if not allowEmpty and #values == 0 then
		return false, reason
	end
	for _, value in ipairs(values) do
		if not isNonEmptyString(value) then
			return false, reason
		end
	end
	if not hasUniqueStrings(values) then
		return false, reason
	end
	return true, nil
end

local function validateAntiAbuseTags(values: any): (boolean, string?)
	if type(values) ~= "table" then
		return false, "trait_anti_abuse_tags_invalid"
	end
	local seen = {}
	for _, tag in ipairs(values) do
		if not isNonEmptyString(tag) then
			return false, "trait_anti_abuse_tags_invalid"
		end
		if seen[tag] then
			return false, "trait_anti_abuse_tags_duplicate"
		end
		seen[tag] = true
		if VALID_ANTI_ABUSE_TAGS[tag] ~= true then
			return false, "trait_anti_abuse_tag_invalid"
		end
	end
	return true, nil
end

local function cloneRecord(record: TraitRecord): TraitRecord
	return {
		traitId = record.traitId,
		name = record.name,
		description = record.description,
		role = record.role,
		category = record.category,
		slotType = record.slotType,
		tier = record.tier,
		unlockSource = record.unlockSource,
		unlockOwner = record.unlockOwner,
		unlockTrackId = record.unlockTrackId,
		unlockSourceId = record.unlockSourceId,
		trigger = record.trigger,
		durationType = record.durationType,
		durationSeconds = record.durationSeconds,
		cooldownSeconds = record.cooldownSeconds,
		sharedCooldownKey = record.sharedCooldownKey,
		stacking = record.stacking,
		visibility = record.visibility,
		antiAbuseTags = cloneStringArray(record.antiAbuseTags),
		testCoverageHooks = cloneStringArray(record.testCoverageHooks),
		sourceId = record.sourceId,
	}
end

local function validateUnlockFields(record: any): (boolean, string?)
	if record.unlockSource == "initial" then
		if record.unlockOwner ~= nil then
			return false, "trait_unlock_owner_invalid"
		end
		if record.unlockSourceId ~= nil then
			return false, "trait_unlock_source_id_invalid"
		end
		return true, nil
	end

	if
		record.unlockSource == "account_mastery"
		or record.unlockSource == "role_mastery"
		or record.unlockSource == "reputation"
	then
		if not isNonEmptyString(record.unlockTrackId) then
			return false, "trait_unlock_track_id_invalid"
		end
		if not isEnumValue(record.unlockOwner, { playerProfile = true, realmProfile = true }) then
			return false, "trait_unlock_owner_invalid"
		end
		if record.unlockOwner ~= "playerProfile" then
			return false, "trait_unlock_owner_invalid"
		end
		return true, nil
	end

	if not isNonEmptyString(record.unlockSourceId) then
		return false, "trait_unlock_source_id_invalid"
	end
	if not isEnumValue(record.unlockOwner, { playerProfile = true, realmProfile = true }) then
		return false, "trait_unlock_owner_invalid"
	end

	return true, nil
end

function TraitRegistrySchema.ValidateTraitRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "trait_record_invalid"
	end
	if not isNonEmptyString(record.traitId) then
		return false, "trait_id_invalid"
	end
	if not isNonEmptyString(record.name) then
		return false, "trait_name_invalid"
	end
	if not isEnumValue(record.role, VALID_ROLES) then
		return false, "trait_role_invalid"
	end
	if not isEnumValue(record.category, VALID_CATEGORIES) then
		return false, "trait_category_invalid"
	end
	if not isEnumValue(record.slotType, VALID_SLOT_TYPES) then
		return false, "trait_slot_type_invalid"
	end
	if not isEnumValue(record.tier, VALID_TIERS) then
		return false, "trait_tier_invalid"
	end
	if not isEnumValue(record.unlockSource, VALID_UNLOCK_SOURCES) then
		return false, "trait_unlock_source_invalid"
	end
	local unlockOk, unlockReason = validateUnlockFields(record)
	if not unlockOk then
		return false, unlockReason
	end
	if not isEnumValue(record.trigger, VALID_TRIGGERS) then
		return false, "trait_trigger_invalid"
	end
	if not isEnumValue(record.durationType, VALID_DURATION_TYPES) then
		return false, "trait_duration_type_invalid"
	end
	if record.durationType == "timed" then
		if not isPositiveNumber(record.durationSeconds) then
			return false, "trait_duration_seconds_invalid"
		end
	elseif record.durationSeconds ~= nil then
		return false, "trait_duration_seconds_invalid"
	end
	if not isNonNegativeNumber(record.cooldownSeconds) then
		return false, "trait_cooldown_seconds_invalid"
	end
	if record.sharedCooldownKey ~= nil and not isNonEmptyString(record.sharedCooldownKey) then
		return false, "trait_shared_cooldown_key_invalid"
	end
	if not isEnumValue(record.stacking, VALID_STACKING) then
		return false, "trait_stacking_invalid"
	end
	if not isEnumValue(record.visibility, VALID_VISIBILITY) then
		return false, "trait_visibility_invalid"
	end
	if not isNonEmptyString(record.sourceId) then
		return false, "trait_source_id_invalid"
	end
	local antiAbuseOk, antiAbuseReason = validateAntiAbuseTags(record.antiAbuseTags)
	if not antiAbuseOk then
		return false, antiAbuseReason
	end
	local hooksOk, hooksReason =
		validateStringArray(record.testCoverageHooks, "trait_test_coverage_hooks_invalid", true)
	if not hooksOk then
		return false, hooksReason
	end
	return true, nil
end

function TraitRegistrySchema.ValidateTraitRegistry(registry: any): (boolean, string?)
	if type(registry) ~= "table" then
		return false, "trait_registry_invalid"
	end

	local seenTraitIds = {}
	for index, record in ipairs(registry) do
		local valid, reason = TraitRegistrySchema.ValidateTraitRecord(record)
		if not valid then
			return false, string.format("%s index=%d", reason or "trait_record_invalid", index)
		end
		if seenTraitIds[record.traitId] then
			return false, string.format("trait_id_duplicate index=%d", index)
		end
		seenTraitIds[record.traitId] = true
	end

	return true, nil
end

function TraitRegistrySchema.GetTraitRecord(traitId: any, registry: any?): (TraitRecord?, string?)
	if not isNonEmptyString(traitId) then
		return nil, "trait_id_invalid"
	end

	local source = if registry ~= nil then registry else TraitRegistrySchema.DEFAULT_TRAIT_REGISTRY
	for _, record in ipairs(source :: { any }) do
		if record.traitId == traitId then
			return cloneRecord(record :: TraitRecord), nil
		end
	end

	return nil, "trait_missing"
end

function TraitRegistrySchema.GetAllTraitRecords(registry: any?): { TraitRecord }
	local source = if registry ~= nil then registry else TraitRegistrySchema.DEFAULT_TRAIT_REGISTRY
	local copied = {}
	for _, record in ipairs(source :: { any }) do
		table.insert(copied, cloneRecord(record :: TraitRecord))
	end
	table.sort(copied, function(left: TraitRecord, right: TraitRecord)
		return left.traitId < right.traitId
	end)
	return copied
end

function TraitRegistrySchema.BuildTraitSnapshot(registry: any?): { TraitRecord }
	return TraitRegistrySchema.GetAllTraitRecords(registry)
end

return TraitRegistrySchema
