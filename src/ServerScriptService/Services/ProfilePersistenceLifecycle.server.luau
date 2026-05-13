--!strict

local ProfilePersistenceLifecycle = require(script.Parent.ProfilePersistenceLifecycle)
local ProfilePersistenceGateway = require(script.Parent.ProfilePersistenceGateway)
local ProfileStoreOwnerLayer = require(script.Parent.ProfileStoreOwnerLayer)

ProfilePersistenceLifecycle.Start({
	gateway = ProfilePersistenceGateway,
	ownerLayer = ProfileStoreOwnerLayer.CreateDefault(),
})
