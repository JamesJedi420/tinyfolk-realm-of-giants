--!nocheck

local RealmReservedServerAllocationService = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmReservedServerAllocationService"))
	else (require :: any)("./RealmReservedServerAllocationService")

local globalEnv: any = getfenv()

RealmReservedServerAllocationService.ConfigureForTests(nil)

globalEnv._RealmReservedServerAllocationService_QueryAPI = {
	EnsureAllocation = function(input: any): any
		return RealmReservedServerAllocationService.EnsureAllocation(input)
	end,
	ResolveAccessCodeForRealm = function(realmId: any): any
		return RealmReservedServerAllocationService.ResolveAccessCodeForRealm(realmId)
	end,
	BuildPersistenceState = function(ownerUserId: any): any?
		return RealmReservedServerAllocationService.BuildPersistenceState(ownerUserId)
	end,
	ApplyPersistenceState = function(saveRecord: any, ownerUserId: any): (boolean, string?)
		return RealmReservedServerAllocationService.ApplyPersistenceState(saveRecord, ownerUserId)
	end,
	GetDiagnostics = function(): any
		return RealmReservedServerAllocationService.GetDiagnostics()
	end,
	ConfigureForTests = function(config: any?)
		RealmReservedServerAllocationService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		RealmReservedServerAllocationService.ResetForTests()
	end,
}

if type(_G) == "table" then
	rawset(
		_G,
		"_RealmReservedServerAllocationService_QueryAPI",
		globalEnv._RealmReservedServerAllocationService_QueryAPI
	)
end

return globalEnv._RealmReservedServerAllocationService_QueryAPI
