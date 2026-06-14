--!nocheck
-- Hides map helper geometry tagged for screenshot clarity at runtime (Play + Studio test).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapScreenshotPresentationPolicy =
	require(Shared:WaitForChild("Map"):WaitForChild("MapScreenshotPresentationPolicy"))

local function isBasePart(node: any): boolean
	return node ~= nil and type(node.IsA) == "function" and node:IsA("BasePart")
end

local function isLight(node: any): boolean
	return node ~= nil and type(node.IsA) == "function" and node:IsA("Light")
end

local function getAttribute(instance: any, attributeName: string): any
	if instance == nil or type(instance.GetAttribute) ~= "function" then
		return nil
	end
	return instance:GetAttribute(attributeName)
end

local function hideLight(light: any)
	if getAttribute(light, "_ScreenshotHelperHidden") == true then
		return
	end
	light:SetAttribute("_ScreenshotHelperHidden", true)
	light.Enabled = false
end

local function hideGuiLayer(gui: any)
	if getAttribute(gui, "_ScreenshotHelperHidden") == true then
		return
	end
	gui:SetAttribute("_ScreenshotHelperHidden", true)
	if type(gui.Enabled) == "boolean" then
		gui.Enabled = false
	end
end

local function hideBasePart(part: any)
	if getAttribute(part, "_ScreenshotHelperHidden") == true then
		return
	end
	part:SetAttribute("_ScreenshotHelperHidden", true)
	part:SetAttribute("_ScreenshotHelperOriginalTransparency", part.Transparency)
	part.Transparency = 1
	if type(part.CastShadow) == "boolean" then
		part.CastShadow = false
	end
	if type(part.IsA) == "function" and part:IsA("SpawnLocation") and type(part.Enabled) == "boolean" then
		part.Enabled = false
	end
	if type(part.GetDescendants) == "function" then
		for _, descendant in ipairs(part:GetDescendants()) do
			if isLight(descendant) then
				hideLight(descendant)
			elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
				hideGuiLayer(descendant)
			elseif descendant:IsA("ParticleEmitter") and type(descendant.Enabled) == "boolean" then
				descendant.Enabled = false
			end
		end
	end
end

local function applyToInstance(instance: any, mapRoot: any)
	if isBasePart(instance) and MapScreenshotPresentationPolicy.shouldHidePart(instance, mapRoot) then
		hideBasePart(instance)
		return
	end
	if isLight(instance) then
		local parent = instance.Parent
		if parent ~= nil and MapScreenshotPresentationPolicy.shouldHideInstance(parent, mapRoot) then
			hideLight(instance)
		end
	end
end

local function applyToMapRoot(mapRoot: any)
	if mapRoot == nil or type(mapRoot.GetDescendants) ~= "function" then
		return
	end
	for _, descendant in ipairs(mapRoot:GetDescendants()) do
		applyToInstance(descendant, mapRoot)
	end
	for _, child in ipairs(mapRoot:GetChildren()) do
		applyToInstance(child, mapRoot)
	end
end

local function hookMapRoot(mapRoot: any)
	applyToMapRoot(mapRoot)
	if type(mapRoot.DescendantAdded) == "function" then
		mapRoot.DescendantAdded:Connect(function(descendant: any)
			task.defer(function()
				applyToInstance(descendant, mapRoot)
			end)
		end)
	end
end

local function applyWhenMapReady()
	local mapRoot = Workspace:FindFirstChild("Map")
	if mapRoot == nil then
		mapRoot = Workspace:WaitForChild("Map", 30)
	end
	if mapRoot ~= nil then
		hookMapRoot(mapRoot)
	end
end

applyWhenMapReady()
task.defer(applyWhenMapReady)

return {
	ApplyToMapRoot = applyToMapRoot,
}
