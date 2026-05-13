--!strict

local ProfileStoreOwnerLayer = require("../src/ServerScriptService/Services/ProfileStoreOwnerLayer")
local fs = require("@lune/fs")

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function makeFakeProfileStoreModule(): any
	local module = {
		newCalls = {},
	}

	function module.New(storeName: string, template: any): any
		table.insert(module.newCalls, {
			storeName = storeName,
			template = template,
		})

		local store = {}
		function store:StartSessionAsync(_profileKey: string, _params: any): any
			local profile = {
				Data = {
					schemaVersion = template.schemaVersion,
				},
			}
			function profile:EndSession()
			end
			return profile
		end

		return store
	end

	return module
end

local requiredOwnerMethods = {
	LoadPlayerProfile = true,
	SavePlayerProfile = true,
	ReleasePlayerProfile = true,
	LoadGiantRealmProfile = true,
	SaveGiantRealmProfile = true,
}

local thirdPartyPath = "src/ServerScriptService/Services/ThirdParty/ProfileStore.luau"
local thirdPartySource = fs.readFile(thirdPartyPath)

assertTrue(string.find(thirdPartySource, "ProfileStore", 1, true) ~= nil, "vendored ProfileStore source present")
assertTrue(string.find(thirdPartySource, "StartSessionAsync", 1, true) ~= nil, "vendored ProfileStore session API present")

local thirdPartyDocPath = "docs/THIRD_PARTY.md"
local thirdPartyDoc = fs.readFile(thirdPartyDocPath)

assertTrue(string.find(thirdPartyDoc, "ProfileStore", 1, true) ~= nil, "third-party doc dependency name")
assertTrue(
	string.find(thirdPartyDoc, "https://github.com/MadStudioRoblox/ProfileStore", 1, true) ~= nil,
	"third-party doc upstream"
)
assertTrue(
	string.find(thirdPartyDoc, "45c9847cbcf1fc260369c50eb335aba7c35aecdd", 1, true) ~= nil,
	"third-party doc pinned SHA"
)
assertTrue(string.find(thirdPartyDoc, thirdPartyPath, 1, true) ~= nil, "third-party doc vendored path")
assertTrue(string.find(thirdPartyDoc, "Apache-2.0", 1, true) ~= nil, "third-party doc license")
assertTrue(string.find(thirdPartyDoc, "2026-05-13", 1, true) ~= nil, "third-party doc retrieval date")
assertTrue(string.find(thirdPartyDoc, "Local modifications: none", 1, true) ~= nil, "third-party doc modifications")
assertTrue(string.find(thirdPartyDoc, "Gameplay code must not require this dependency directly", 1, true) ~= nil, "third-party doc gameplay restriction")

assertTrue(type(ProfileStoreOwnerLayer.CreateDefault) == "function", "CreateDefault exposed")

local fakeProfileStore = makeFakeProfileStoreModule()
local ownerLayer = ProfileStoreOwnerLayer.CreateDefault(fakeProfileStore)

for methodName in pairs(requiredOwnerMethods) do
	assertTrue(type(ownerLayer[methodName]) == "function", "CreateDefault owner exposes " .. methodName)
end

assertEqual(#fakeProfileStore.newCalls, 1, "CreateDefault calls ProfileStore.New once")
assertEqual(fakeProfileStore.newCalls[1].storeName, "TinyfolkPlayerProfiles", "CreateDefault store name")
assertEqual(fakeProfileStore.newCalls[1].template.schemaVersion, 1, "CreateDefault template schema")

local loadResult = ownerLayer.LoadPlayerProfile("PlayerProfile:1234", 1234)
assertEqual(loadResult.ok, true, "CreateDefault owner load ok")
assertEqual(loadResult.operation, "LoadPlayerProfile", "CreateDefault owner load operation")
assertEqual(loadResult.profileKey, "PlayerProfile:1234", "CreateDefault owner load key")
assertEqual(loadResult.data.schemaVersion, 1, "CreateDefault owner load data")

print("profile_store_dependency_intake: all checks passed")
