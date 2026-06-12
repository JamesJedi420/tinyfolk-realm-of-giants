--!nocheck

local fs = require("@lune/fs")

local GameplayMapAuthoringConfig = require("../src/ReplicatedStorage/Shared/Config/GameplayMapAuthoringConfig")

local function assertTrue(value: boolean, label: string)
	if not value then
		error("FAIL [" .. label .. "]")
	end
	print("PASS [" .. label .. "]")
end

local function readFile(path: string): string
	if not fs.isFile(path) then
		error("missing file " .. path)
	end
	return fs.readFile(path)
end

local function decodeJson(text: string): any
	local serde = require("@lune/serde")
	return serde.decode("json", text)
end

local function findChildByName(node: any, childName: string): any?
	if type(node) ~= "table" then
		return nil
	end
	if node.name == childName then
		return node
	end
	local children = node.children
	if type(children) ~= "table" then
		return nil
	end
	for _, child in children do
		local found = findChildByName(child, childName)
		if found ~= nil then
			return found
		end
	end
	return nil
end

local function nodeHasTag(node: any, expectedTag: string): boolean
	if type(node) ~= "table" then
		return false
	end
	local properties = node.properties
	if type(properties) == "table" and type(properties.Tags) == "table" then
		for _, tag in properties.Tags do
			if tag == expectedTag then
				return true
			end
		end
	end
	return false
end

local function nodeHasAttribute(node: any, attributeName: string): boolean
	if type(node) ~= "table" then
		return false
	end
	local attributes = node.attributes
	if type(attributes) ~= "table" then
		return false
	end
	return attributes[attributeName] == true
end

for index, requirement in ipairs(GameplayMapAuthoringConfig.RequiredTaggedRoots) do
	local root = decodeJson(readFile(requirement.layoutPath))
	local target = root
	if type(requirement.childName) == "string" then
		target = findChildByName(root, requirement.childName)
	end
	assertTrue(target ~= nil, string.format("requirement_%d_target_exists", index))
	assertTrue(nodeHasTag(target, requirement.tag), string.format("requirement_%d_tag_%s", index, requirement.tag))
	if type(requirement.attribute) == "string" then
		assertTrue(
			nodeHasAttribute(target, requirement.attribute),
			string.format("requirement_%d_attribute_%s", index, requirement.attribute)
		)
	end
end

print("gameplay_map_authoring_coverage.spec.luau: all checks passed")
