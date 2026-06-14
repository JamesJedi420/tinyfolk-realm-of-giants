--!strict

local MapScreenshotPresentationPolicy = {}

local HIDE_FOLDER_NAMES: { [string]: boolean } = {
	DistrictPads = true,
	RouteNodes = true,
	CaptureZones = true,
	ControlZones = true,
	DefensivePropZones = true,
	ContainmentStructureZones = true,
	Objectives = true,
	EscapeReadability = true,
	ValidationCameras = true,
	ScaleMarkers = true,
	DebugLabels = true,
	Spawns = true,
	Construction = true,
	RouteGraph = true,
}

local HIDE_ATTRIBUTE_NAMES = {
	"HiddenForScreenshots",
	"ScreenshotSoftened",
	"DebugMarkerSoftened",
}

MapScreenshotPresentationPolicy.HIDE_FOLDER_NAMES = HIDE_FOLDER_NAMES
MapScreenshotPresentationPolicy.HIDE_ATTRIBUTE_NAMES = HIDE_ATTRIBUTE_NAMES

function MapScreenshotPresentationPolicy.getAttribute(instance: Instance, attributeName: string): unknown
	local ok, value = pcall(function()
		return instance:GetAttribute(attributeName)
	end)
	if ok then
		return value
	end
	return nil
end

function MapScreenshotPresentationPolicy.shouldHideByAttribute(instance: Instance): boolean
	for _, attributeName in HIDE_ATTRIBUTE_NAMES do
		if MapScreenshotPresentationPolicy.getAttribute(instance, attributeName) == true then
			return true
		end
	end
	if
		MapScreenshotPresentationPolicy.getAttribute(instance, "DoNotShip") == true
		and MapScreenshotPresentationPolicy.getAttribute(instance, "VisualOnly") == true
	then
		return true
	end
	return false
end

function MapScreenshotPresentationPolicy.isUnderHideFolder(instance: Instance, mapRoot: Instance?): boolean
	local current: Instance? = instance
	while current ~= nil do
		if mapRoot ~= nil and current == mapRoot then
			break
		end
		if HIDE_FOLDER_NAMES[current.Name] == true then
			return true
		end
		if current.Name == "SupportingRoutes" then
			local parent = current.Parent
			if parent ~= nil and parent.Name == "Graybox" then
				return true
			end
		end
		current = current.Parent
	end
	return false
end

function MapScreenshotPresentationPolicy.shouldHidePart(part: BasePart, mapRoot: Instance?): boolean
	return MapScreenshotPresentationPolicy.shouldHideByAttribute(part)
		or MapScreenshotPresentationPolicy.isUnderHideFolder(part, mapRoot)
end

function MapScreenshotPresentationPolicy.shouldHideInstance(instance: Instance, mapRoot: Instance?): boolean
	if instance:IsA("BasePart") then
		local part = instance :: BasePart
		return MapScreenshotPresentationPolicy.shouldHidePart(part, mapRoot)
	end
	return MapScreenshotPresentationPolicy.shouldHideByAttribute(instance)
		or MapScreenshotPresentationPolicy.isUnderHideFolder(instance, mapRoot)
end

return MapScreenshotPresentationPolicy
