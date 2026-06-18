--!strict

local RealmAdmissionLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAdmissionLocationState")
local PlayerLocationState = require("../src/ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
local RealmAssignmentProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

assertEqual(
	RealmAdmissionLocationState.ResolveTransitReason({ entryType = "standard" }),
	PlayerLocationState.TransitReason.PartyAdmission,
	"standard entry transit"
)
assertEqual(
	RealmAdmissionLocationState.ResolveTransitReason({ entryType = "rescue_contract" }),
	PlayerLocationState.TransitReason.Rescue,
	"rescue contract transit"
)
assertEqual(
	RealmAdmissionLocationState.ResolveConfirmOperation({
		assignmentReason = RealmAssignmentProfileState.AssignmentReason.EscapeReturn,
	}),
	PlayerLocationState.Operations.ConfirmHubReturn,
	"escape return confirm"
)
assertEqual(
	RealmAdmissionLocationState.ResolveConfirmOperation({
		transitReason = PlayerLocationState.TransitReason.Raid,
	}),
	PlayerLocationState.Operations.ConfirmRealmInvader,
	"raid confirm invader"
)

local matchingSnapshot = {
	location = PlayerLocationState.Location.Transit,
	realmId = "giant_realm_9001",
	transitReason = PlayerLocationState.TransitReason.PartyAdmission,
}
assertEqual(
	RealmAdmissionLocationState.IsMatchingTransit(
		matchingSnapshot,
		"giant_realm_9001",
		PlayerLocationState.TransitReason.PartyAdmission
	),
	true,
	"matching transit snapshot"
)

print("realm_admission_location_state.spec.luau passed")
