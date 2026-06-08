--!strict

local TraitRegistrySchema = require("../Config/TraitRegistrySchema")

local ReputationState: any = {}

local PROFILE_KEY = "reputationState"

ReputationState.Tracks = {
	Escapist = "Escapist",
	Saboteur = "Saboteur",
	Rescuer = "Rescuer",
	Scout = "Scout",
	Thief = "Thief",
	Diplomat = "Diplomat",
	FolkHero = "FolkHero",
}

ReputationState.OutcomeKinds = {
	EscapeSuccess = "escape_success",
	ContainmentCustodyEnd = "containment_custody_end",
}

ReputationState.UnlockKinds = {
	CosmeticTitle = "cosmetic_title",
	LoadoutTrait = "loadout_trait",
}

local TRACK_ORDER = {
	ReputationState.Tracks.Escapist,
	ReputationState.Tracks.Saboteur,
	ReputationState.Tracks.Rescuer,
	ReputationState.Tracks.Scout,
	ReputationState.Tracks.Thief,
	ReputationState.Tracks.Diplomat,
	ReputationState.Tracks.FolkHero,
}

local TRACK_SET = {
	[ReputationState.Tracks.Escapist] = true,
	[ReputationState.Tracks.Saboteur] = true,
	[ReputationState.Tracks.Rescuer] = true,
	[ReputationState.Tracks.Scout] = true,
	[ReputationState.Tracks.Thief] = true,
	[ReputationState.Tracks.Diplomat] = true,
	[ReputationState.Tracks.FolkHero] = true,
}

local TRACK_RULES = {
	[ReputationState.Tracks.Escapist] = { cooldownSeconds = 45, repeatWindowSeconds = 90, dailyCap = 120 },
	[ReputationState.Tracks.Saboteur] = { cooldownSeconds = 60, repeatWindowSeconds = 120, dailyCap = 80 },
	[ReputationState.Tracks.Rescuer] = { cooldownSeconds = 45, repeatWindowSeconds = 120, dailyCap = 80 },
	[ReputationState.Tracks.Scout] = { cooldownSeconds = 30, repeatWindowSeconds = 75, dailyCap = 90 },
	[ReputationState.Tracks.Thief] = { cooldownSeconds = 60, repeatWindowSeconds = 120, dailyCap = 75 },
	[ReputationState.Tracks.Diplomat] = { cooldownSeconds = 90, repeatWindowSeconds = 180, dailyCap = 70 },
	[ReputationState.Tracks.FolkHero] = { cooldownSeconds = 75, repeatWindowSeconds = 150, dailyCap = 65 },
}

local TRACK_UNLOCKS = {
	[ReputationState.Tracks.Escapist] = {
		{ threshold = 25, kind = ReputationState.UnlockKinds.CosmeticTitle, unlockId = "title_escapist_pathfinder" },
		{
			threshold = 60,
			kind = ReputationState.UnlockKinds.LoadoutTrait,
			unlockId = "Tinyfolk_Loadout_EvasiveMarker",
		},
	},
	[ReputationState.Tracks.Saboteur] = {
		{ threshold = 30, kind = ReputationState.UnlockKinds.CosmeticTitle, unlockId = "title_saboteur_shadow" },
	},
	[ReputationState.Tracks.Rescuer] = {
		{ threshold = 30, kind = ReputationState.UnlockKinds.CosmeticTitle, unlockId = "title_rescuer_oathkeeper" },
	},
	[ReputationState.Tracks.Scout] = {
		{ threshold = 20, kind = ReputationState.UnlockKinds.CosmeticTitle, unlockId = "title_scout_trailcaller" },
	},
	[ReputationState.Tracks.Thief] = {
		{ threshold = 20, kind = ReputationState.UnlockKinds.CosmeticTitle, unlockId = "title_thief_quickpockets" },
	},
	[ReputationState.Tracks.Diplomat] = {
		{ threshold = 25, kind = ReputationState.UnlockKinds.CosmeticTitle, unlockId = "title_diplomat_bridgebinder" },
	},
	[ReputationState.Tracks.FolkHero] = {
		{ threshold = 40, kind = ReputationState.UnlockKinds.CosmeticTitle, unlockId = "title_folk_hero_giantslayer" },
	},
}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local cloneTable: (value: any) -> any
cloneTable = function(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local output = {}
	for key, child in pairs(value) do
		output[cloneTable(key)] = cloneTable(child)
	end
	return output
end

local function ensureStringList(value: any): { string }
	local output: { string } = {}
	local seen: { [string]: boolean } = {}
	if type(value) ~= "table" then
		return output
	end
	for _, entry in ipairs(value) do
		if isNonEmptyString(entry) and seen[entry] ~= true then
			seen[entry] = true
			table.insert(output, entry)
		end
	end
	return output
end

local function ensureTrackRecord(value: any, trackId: string): any
	local record: any = if type(value) == "table" then cloneTable(value) else {}
	record.trackId = trackId
	record.points = if isFiniteNumber(record.points) and record.points > 0 then math.floor(record.points) else 0
	record.lastGrantedAt = if isFiniteNumber(record.lastGrantedAt) and record.lastGrantedAt >= 0
		then record.lastGrantedAt
		else nil
	record.cooldownReadyAt = if isFiniteNumber(record.cooldownReadyAt) and record.cooldownReadyAt >= 0
		then record.cooldownReadyAt
		else nil
	record.dayIndex = if isFiniteNumber(record.dayIndex) then math.floor(record.dayIndex) else nil
	record.awardedInDay = if isFiniteNumber(record.awardedInDay) and record.awardedInDay >= 0
		then math.floor(record.awardedInDay)
		else 0
	return record
end

local function ensureProfileState(profileData: any): any
	local nextProfile = if type(profileData) == "table" then cloneTable(profileData) else {}
	if type(nextProfile[PROFILE_KEY]) ~= "table" then
		nextProfile[PROFILE_KEY] = {}
	end

	local rep = nextProfile[PROFILE_KEY]
	rep.schemaVersion = 1
	if type(rep.byTrackId) ~= "table" then
		rep.byTrackId = {}
	end
	if type(rep.recentOutcomeAtByKey) ~= "table" then
		rep.recentOutcomeAtByKey = {}
	end
	rep.unlockedCosmeticIds = ensureStringList(rep.unlockedCosmeticIds)
	rep.unlockedLoadoutTraitIds = ensureStringList(rep.unlockedLoadoutTraitIds)

	for _, trackId in ipairs(TRACK_ORDER) do
		rep.byTrackId[trackId] = ensureTrackRecord(rep.byTrackId[trackId], trackId)
	end

	for key, value in pairs(rep.recentOutcomeAtByKey) do
		if not isNonEmptyString(key) or not isFiniteNumber(value) or value < 0 then
			rep.recentOutcomeAtByKey[key] = nil
		end
	end

	return nextProfile
end

local function readTrackPoints(profileData: any, trackId: string): number
	local rep = if type(profileData) == "table" then profileData[PROFILE_KEY] else nil
	if type(rep) ~= "table" or type(rep.byTrackId) ~= "table" then
		return 0
	end
	local track = rep.byTrackId[trackId]
	if type(track) ~= "table" or not isFiniteNumber(track.points) then
		return 0
	end
	return math.max(0, math.floor(track.points))
end

local function containsString(list: { string }, needle: string): boolean
	for _, value in ipairs(list) do
		if value == needle then
			return true
		end
	end
	return false
end

local function isEmptyTable(value: any): boolean
	if type(value) ~= "table" then
		return true
	end
	for _, _ in pairs(value) do
		return false
	end
	return true
end

function ReputationState.IsLoadoutSafeReputationTraitRecord(record: any): (boolean, string?)
	if type(record) ~= "table" then
		return false, "trait_record_invalid"
	end
	if record.unlockSource ~= TraitRegistrySchema.UnlockSources.Reputation then
		return false, "trait_unlock_source_not_reputation"
	end
	if
		record.visibility ~= TraitRegistrySchema.Visibilities.LoadoutOnly
		and record.visibility ~= TraitRegistrySchema.Visibilities.RoleSelect
	then
		return false, "trait_visibility_not_safe"
	end
	if record.tier ~= TraitRegistrySchema.Tiers.Starter and record.tier ~= TraitRegistrySchema.Tiers.Common then
		return false, "trait_tier_not_safe"
	end
	if record.modifiers ~= nil and not isEmptyTable(record.modifiers) then
		return false, "trait_modifiers_not_safe"
	end

	local hasRoleSafeUse = false
	local hasReputationGuard = false
	if type(record.antiAbuseTags) == "table" then
		for _, tag in ipairs(record.antiAbuseTags) do
			if tag == TraitRegistrySchema.AntiAbuseTags.RoleSafeUse then
				hasRoleSafeUse = true
			elseif tag == TraitRegistrySchema.AntiAbuseTags.ReputationGateGuard then
				hasReputationGuard = true
			end
		end
	end
	if not hasRoleSafeUse then
		return false, "trait_role_safe_use_tag_missing"
	end
	if not hasReputationGuard then
		return false, "trait_reputation_guard_tag_missing"
	end

	return true, nil
end

local function buildEscapeCandidates(input: any): { any }
	local candidates = {}
	local sourceId = if isNonEmptyString(input.sourceId)
		then input.sourceId
		else if isNonEmptyString(input.routeId)
			then input.routeId
			else if isNonEmptyString(input.endpointId) then input.endpointId else "unknown"
	local difficulty = if isFiniteNumber(input.difficulty) and input.difficulty > 0 then input.difficulty else 1
	local lootValue = if isFiniteNumber(input.lootValue) and input.lootValue > 0 then math.floor(input.lootValue) else 0
	local sourceKind = if isNonEmptyString(input.sourceKind) then input.sourceKind else "escape"

	table.insert(candidates, {
		trackId = ReputationState.Tracks.Escapist,
		points = 12 + math.max(0, math.floor((difficulty - 1) * 4 + 0.5)),
		repeatKey = string.format("escape:%s", sourceId),
	})
	table.insert(candidates, {
		trackId = ReputationState.Tracks.Scout,
		points = 6,
		repeatKey = string.format("scout:%s", sourceId),
	})

	if lootValue > 0 then
		table.insert(candidates, {
			trackId = ReputationState.Tracks.Thief,
			points = math.min(20, lootValue * 2),
			repeatKey = string.format("loot:%s", sourceId),
		})
	end

	if sourceKind == "transport" then
		table.insert(candidates, {
			trackId = ReputationState.Tracks.Saboteur,
			points = 5,
			repeatKey = string.format("transport:%s", sourceId),
		})
	end

	if difficulty >= 2 then
		table.insert(candidates, {
			trackId = ReputationState.Tracks.FolkHero,
			points = 4,
			repeatKey = string.format("hero_escape:%s", sourceId),
		})
	end

	return candidates
end

local function buildContainmentCandidates(input: any): { any }
	local candidates = {}
	local endReason = if isNonEmptyString(input.endReason) then input.endReason else ""
	local pairKey = string.format("%s|%s", tostring(input.custodianUserId or "?"), tostring(input.targetUserId or "?"))

	if endReason == "released" or endReason == "safe_return" then
		table.insert(candidates, {
			trackId = ReputationState.Tracks.Diplomat,
			points = 10,
			repeatKey = string.format("diplomat:%s", pairKey),
		})
	elseif endReason == "rescued" then
		table.insert(candidates, {
			trackId = ReputationState.Tracks.Rescuer,
			points = 12,
			repeatKey = string.format("rescuer:%s", pairKey),
		})
	elseif endReason == "escaped" then
		table.insert(candidates, {
			trackId = ReputationState.Tracks.Saboteur,
			points = 8,
			repeatKey = string.format("saboteur:%s", pairKey),
		})
	elseif endReason == "timeout" or endReason == "logout" then
		table.insert(candidates, {
			trackId = ReputationState.Tracks.Scout,
			points = 4,
			repeatKey = string.format("timeout:%s", pairKey),
		})
	end

	return candidates
end

local function buildCandidates(input: any): { any }
	if input.outcomeKind == ReputationState.OutcomeKinds.EscapeSuccess then
		return buildEscapeCandidates(input)
	end
	if input.outcomeKind == ReputationState.OutcomeKinds.ContainmentCustodyEnd then
		return buildContainmentCandidates(input)
	end
	return {}
end

function ReputationState.ApplyOutcome(profileData: any, input: any, traitRegistry: any?): any
	if type(input) ~= "table" then
		return {
			accepted = false,
			reason = "input_invalid",
			profileData = ensureProfileState(profileData),
			trackUpdates = {},
			unlockUpdates = {},
		}
	end

	local nextProfile = ensureProfileState(profileData)
	if not isNonEmptyString(input.outcomeKind) then
		return {
			accepted = false,
			reason = "outcome_kind_invalid",
			profileData = nextProfile,
			trackUpdates = {},
			unlockUpdates = {},
		}
	end
	if not isFiniteNumber(input.now) or input.now < 0 then
		return {
			accepted = false,
			reason = "timestamp_invalid",
			profileData = nextProfile,
			trackUpdates = {},
			unlockUpdates = {},
		}
	end

	local dayIndex = math.floor(input.now / 86400)
	local rep = nextProfile[PROFILE_KEY]
	local trackUpdates = {}
	local candidates = buildCandidates(input)

	for _, candidate in ipairs(candidates) do
		local trackId = candidate.trackId
		local points = if isFiniteNumber(candidate.points) then math.floor(candidate.points) else 0
		local repeatKey = candidate.repeatKey
		local rule = TRACK_RULES[trackId]
		local track = rep.byTrackId[trackId]
		local update: any = {
			trackId = trackId,
			requestedPoints = points,
			awardedPoints = 0,
			accepted = false,
			reason = "track_invalid",
		}

		if TRACK_SET[trackId] ~= true or rule == nil or type(track) ~= "table" or points <= 0 then
			table.insert(trackUpdates, update)
			continue
		end

		if type(track.dayIndex) ~= "number" or track.dayIndex ~= dayIndex then
			track.dayIndex = dayIndex
			track.awardedInDay = 0
		end

		if type(track.cooldownReadyAt) == "number" and input.now < track.cooldownReadyAt then
			update.reason = "cooldown_active"
			update.cooldownReadyAt = track.cooldownReadyAt
			table.insert(trackUpdates, update)
			continue
		end

		if isNonEmptyString(repeatKey) then
			local lastAt = rep.recentOutcomeAtByKey[repeatKey]
			if type(lastAt) == "number" and (input.now - lastAt) < rule.repeatWindowSeconds then
				update.reason = "repeat_window_active"
				update.repeatWindowRemaining = rule.repeatWindowSeconds - (input.now - lastAt)
				table.insert(trackUpdates, update)
				continue
			end
		end

		local remaining = math.max(0, rule.dailyCap - track.awardedInDay)
		if remaining <= 0 then
			update.reason = "daily_cap_reached"
			table.insert(trackUpdates, update)
			continue
		end

		local awarded = math.min(points, remaining)
		if awarded <= 0 then
			update.reason = "daily_cap_reached"
			table.insert(trackUpdates, update)
			continue
		end

		track.points += awarded
		track.lastGrantedAt = input.now
		track.cooldownReadyAt = input.now + rule.cooldownSeconds
		track.awardedInDay += awarded
		if isNonEmptyString(repeatKey) then
			rep.recentOutcomeAtByKey[repeatKey] = input.now
		end

		update.accepted = true
		update.reason = "accepted"
		update.awardedPoints = awarded
		update.totalPoints = track.points
		update.cooldownReadyAt = track.cooldownReadyAt
		table.insert(trackUpdates, update)
	end

	local unlockedCosmeticIds = rep.unlockedCosmeticIds
	local unlockedLoadoutTraitIds = rep.unlockedLoadoutTraitIds
	local unlockUpdates = {}

	for trackId, unlocks in pairs(TRACK_UNLOCKS) do
		local points = readTrackPoints(nextProfile, trackId)
		for _, unlock in ipairs(unlocks) do
			if points < unlock.threshold then
				continue
			end
			if unlock.kind == ReputationState.UnlockKinds.CosmeticTitle then
				if containsString(unlockedCosmeticIds, unlock.unlockId) then
					continue
				end
				table.insert(unlockedCosmeticIds, unlock.unlockId)
				table.insert(unlockUpdates, {
					trackId = trackId,
					kind = unlock.kind,
					unlockId = unlock.unlockId,
					accepted = true,
					reason = "accepted",
				})
			elseif unlock.kind == ReputationState.UnlockKinds.LoadoutTrait then
				if containsString(unlockedLoadoutTraitIds, unlock.unlockId) then
					continue
				end
				local traitRecord, lookupReason = TraitRegistrySchema.GetTraitRecord(unlock.unlockId, traitRegistry)
				if traitRecord == nil then
					table.insert(unlockUpdates, {
						trackId = trackId,
						kind = unlock.kind,
						unlockId = unlock.unlockId,
						accepted = false,
						reason = lookupReason or "trait_missing",
					})
					continue
				end
				local safe, safeReason = ReputationState.IsLoadoutSafeReputationTraitRecord(traitRecord)
				if not safe then
					table.insert(unlockUpdates, {
						trackId = trackId,
						kind = unlock.kind,
						unlockId = unlock.unlockId,
						accepted = false,
						reason = safeReason or "trait_not_loadout_safe",
					})
					continue
				end
				table.insert(unlockedLoadoutTraitIds, unlock.unlockId)
				table.insert(unlockUpdates, {
					trackId = trackId,
					kind = unlock.kind,
					unlockId = unlock.unlockId,
					accepted = true,
					reason = "accepted",
				})
			end
		end
	end

	return {
		accepted = true,
		reason = "accepted",
		profileData = nextProfile,
		trackUpdates = trackUpdates,
		unlockUpdates = unlockUpdates,
	}
end

function ReputationState.GetTrackPoints(profileData: any, trackId: any): number
	if not isNonEmptyString(trackId) then
		return 0
	end
	return readTrackPoints(ensureProfileState(profileData), trackId)
end

function ReputationState.GetUnlockedLoadoutTraitSet(profileData: any): { [string]: boolean }
	local nextProfile = ensureProfileState(profileData)
	local set: { [string]: boolean } = {}
	for _, traitId in ipairs(nextProfile[PROFILE_KEY].unlockedLoadoutTraitIds) do
		set[traitId] = true
	end
	return set
end

function ReputationState.GetUnlockedCosmeticIds(profileData: any): { string }
	local nextProfile = ensureProfileState(profileData)
	return cloneTable(nextProfile[PROFILE_KEY].unlockedCosmeticIds)
end

function ReputationState.EnsureProfileState(profileData: any): any
	return ensureProfileState(profileData)
end

return ReputationState
