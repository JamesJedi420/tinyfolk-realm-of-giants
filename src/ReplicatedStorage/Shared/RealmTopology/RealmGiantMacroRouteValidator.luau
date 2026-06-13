--!strict

local RealmTopologyValidator = require("./RealmTopologyValidator")

local RealmGiantMacroRouteValidator = {}

export type NamedGiantRoute = {
	name: string,
	position: RealmTopologyValidator.Vector3Data,
	widthStuds: number?,
	attributes: { [string]: any }?,
}

export type RealmDescriptor = RealmTopologyValidator.RealmDescriptor & {
	giantRoutes: { NamedGiantRoute }?,
}

export type GiantMacroRouteConfig = {
	minimumGiantMacroRouteWidthStuds: number,
	maximumGiantMacroRouteWidthStuds: number?,
	requireGiantOnlyRouteMetadata: boolean?,
	giantOnlyRouteAttribute: string?,
	routeEnabledAttribute: string?,
	routeWidthAttribute: string?,
}

export type CheckResult = {
	id: string,
	passed: boolean,
	reason: string?,
}

export type GiantMacroRouteValidationResult = {
	passed: boolean,
	results: { CheckResult },
}

local function getRouteAttribute(route: any, attributeName: string): any
	local attributes = route.attributes
	if type(attributes) == "table" then
		local attributeValue = attributes[attributeName]
		if attributeValue ~= nil then
			return attributeValue
		end
	end
	return route[attributeName]
end

local function nonEmptyStringOrFallback(value: any, fallback: string): string
	if type(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function resolveWidthStuds(route: any, widthAttribute: string): number?
	local width = route.widthStuds
	if type(width) == "number" then
		return width
	end
	width = getRouteAttribute(route, widthAttribute)
	if type(width) == "number" then
		return width
	end
	return nil
end

local function getGiantRoutes(descriptor: RealmDescriptor): { NamedGiantRoute }
	if type(descriptor.giantRoutes) ~= "table" then
		return {}
	end
	return descriptor.giantRoutes
end

local function checkGiantOnlyRouteMetadata(descriptor: RealmDescriptor, config: GiantMacroRouteConfig): CheckResult
	if config.requireGiantOnlyRouteMetadata ~= true then
		return { id = "giant_route_metadata", passed = true }
	end

	local giantOnlyAttribute = nonEmptyStringOrFallback(config.giantOnlyRouteAttribute, "GiantOnlyRoute")
	local routeEnabledAttribute = nonEmptyStringOrFallback(config.routeEnabledAttribute, "RouteEnabled")
	local tinyfolkOnlyAttribute = "TinyfolkOnlyRoute"
	local seenByName: { [string]: boolean } = {}
	local violations: { string } = {}

	for _, route in getGiantRoutes(descriptor) do
		local routeAny: any = route
		local routeName = routeAny.name
		if type(routeName) ~= "string" or routeName == "" then
			table.insert(violations, "route id missing")
			routeName = "<missing>"
		end

		if seenByName[routeName] == true then
			table.insert(violations, string.format("%s duplicate route id", routeName))
		end
		seenByName[routeName] = true

		if getRouteAttribute(routeAny, giantOnlyAttribute) ~= true then
			table.insert(violations, string.format("%s missing %s=true", routeName, giantOnlyAttribute))
		end
		if getRouteAttribute(routeAny, tinyfolkOnlyAttribute) == true then
			table.insert(violations, string.format("%s has conflicting %s=true", routeName, tinyfolkOnlyAttribute))
		end
		if getRouteAttribute(routeAny, routeEnabledAttribute) == false then
			table.insert(violations, string.format("%s is disabled", routeName))
		end
	end

	if #violations == 0 then
		return { id = "giant_route_metadata", passed = true }
	end

	return {
		id = "giant_route_metadata",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

local function checkGiantRouteWidthBounds(descriptor: RealmDescriptor, config: GiantMacroRouteConfig): CheckResult
	local giantRoutes = getGiantRoutes(descriptor)
	if #giantRoutes == 0 then
		return { id = "giant_route_width_bounds", passed = true }
	end

	local widthAttribute = nonEmptyStringOrFallback(config.routeWidthAttribute, "WidthStuds")
	local maximumWidth = config.maximumGiantMacroRouteWidthStuds
	local violations: { string } = {}

	for _, route in giantRoutes do
		local routeAny: any = route
		local widthStuds = resolveWidthStuds(routeAny, widthAttribute)
		if type(widthStuds) ~= "number" then
			table.insert(violations, string.format("%s missing width metadata", tostring(routeAny.name)))
		elseif widthStuds < config.minimumGiantMacroRouteWidthStuds then
			table.insert(
				violations,
				string.format(
					"%s width %.1f below minimum %.1f",
					tostring(routeAny.name),
					widthStuds,
					config.minimumGiantMacroRouteWidthStuds
				)
			)
		elseif type(maximumWidth) == "number" and widthStuds > maximumWidth then
			table.insert(
				violations,
				string.format("%s width %.1f exceeds maximum %.1f", tostring(routeAny.name), widthStuds, maximumWidth)
			)
		end
	end

	if #violations == 0 then
		return { id = "giant_route_width_bounds", passed = true }
	end

	return {
		id = "giant_route_width_bounds",
		passed = false,
		reason = table.concat(violations, "; "),
	}
end

function RealmGiantMacroRouteValidator.ValidateGiantMacroRoutes(
	descriptor: RealmDescriptor,
	config: GiantMacroRouteConfig
): GiantMacroRouteValidationResult
	local results: { CheckResult } = {
		checkGiantOnlyRouteMetadata(descriptor, config),
		checkGiantRouteWidthBounds(descriptor, config),
	}

	local allPassed = true
	for _, result in results do
		if not result.passed then
			allPassed = false
			break
		end
	end

	return { passed = allPassed, results = results }
end

return RealmGiantMacroRouteValidator
