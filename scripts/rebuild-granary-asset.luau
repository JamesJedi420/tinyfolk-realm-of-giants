-- Roblox Studio utility: rebuild the Tinyfolk granary visual model in place.
--
-- ModuleScript usage:
--   local buildGranary = require(path.to.RebuildGranaryAsset)
--   buildGranary(workspace.Map.Stations.Granary)
--
-- Command Bar usage after pasting the full script:
--   The script auto-runs once against workspace.Map.Stations.Granary.
--   To run it again manually:
--   _G.buildGranary(workspace.Map.Stations.Granary)
--
-- Contract:
--   * Granary_A remains the only BasePart whose name starts with "Granary_".
--   * Granary_A remains the only collidable gameplay/query part.
--   * All generated visual parts are non-collidable, non-touching, and non-queryable.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ASSET_TYPE = "Granary"
local BUILD_CATEGORY = "Economy"
local VISUAL_VERSION = 7

local DEFAULT_PATH = { "Map", "Stations", "Granary" }
local LAYOUT_NAME = "Layout"
local ANCHOR_NAME = "Granary_A"
local ANCHOR_LOCAL_CENTER = Vector3.new(4, 6, 0)
local ANCHOR_SIZE = Vector3.new(24, 12, 18)

local PALETTE = {
	Stone = Color3.fromRGB(64, 61, 56),
	StoneLip = Color3.fromRGB(102, 97, 84),
	WallFront = Color3.fromRGB(130, 122, 102),
	WallSide = Color3.fromRGB(120, 115, 97),
	WallInset = Color3.fromRGB(110, 105, 89),
	RoofA = Color3.fromRGB(51, 54, 59),
	RoofB = Color3.fromRGB(56, 59, 64),
	RoofMetal = Color3.fromRGB(87, 87, 92),
	Wood = Color3.fromRGB(140, 100, 54),
	WoodDark = Color3.fromRGB(74, 50, 28),
	WoodMid = Color3.fromRGB(102, 70, 38),
	WoodLight = Color3.fromRGB(171, 130, 74),
	Metal = Color3.fromRGB(115, 115, 117),
	Iron = Color3.fromRGB(31, 31, 33),
	Sack = Color3.fromRGB(161, 128, 71),
	SackDark = Color3.fromRGB(143, 112, 64),
	Grain = Color3.fromRGB(214, 173, 82),
	Lantern = Color3.fromRGB(255, 184, 71),
	TrimCream = Color3.fromRGB(214, 198, 160),
	BannerRed = Color3.fromRGB(168, 62, 49),
	BannerBlue = Color3.fromRGB(79, 118, 163),
	BannerGold = Color3.fromRGB(214, 173, 82),
	Leaf = Color3.fromRGB(94, 133, 74),
	FlowerPink = Color3.fromRGB(201, 106, 127),
}

local PART_SPECS = {
	Foundation = {
		{
			"Foundation_Base",
			"Part",
			Vector3.new(25.5, 1.2, 19.5),
			Vector3.new(4, 0.6, 0),
			nil,
			Enum.Material.Slate,
			PALETTE.Stone,
		},
		{
			"Foundation_LipFront",
			"Part",
			Vector3.new(23, 0.7, 1.2),
			Vector3.new(4, 1.45, 9.85),
			nil,
			Enum.Material.Concrete,
			PALETTE.StoneLip,
		},
		{
			"Foundation_LipBack",
			"Part",
			Vector3.new(23, 0.7, 1.2),
			Vector3.new(4, 1.45, -9.85),
			nil,
			Enum.Material.Concrete,
			Color3.fromRGB(87, 84, 77),
		},
		{
			"Foundation_LoadingDock",
			"Part",
			Vector3.new(10, 0.8, 4),
			Vector3.new(4, 1.95, 11.25),
			nil,
			Enum.Material.WoodPlanks,
			Color3.fromRGB(135, 99, 56),
		},
		{
			"Foundation_TinyStep",
			"Part",
			Vector3.new(3.2, 0.35, 1.2),
			Vector3.new(-3.4, 0.35, 10.65),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodDark,
		},
	},
	Walls = {
		{
			"Walls_Front",
			"Part",
			Vector3.new(24, 10.5, 0.8),
			Vector3.new(4, 6.35, 9),
			nil,
			Enum.Material.Concrete,
			PALETTE.WallFront,
		},
		{
			"Walls_Back",
			"Part",
			Vector3.new(24, 10.5, 0.8),
			Vector3.new(4, 6.35, -9),
			nil,
			Enum.Material.Concrete,
			Color3.fromRGB(115, 110, 94),
		},
		{
			"Walls_Left",
			"Part",
			Vector3.new(0.8, 10.5, 18),
			Vector3.new(-8, 6.35, 0),
			nil,
			Enum.Material.Concrete,
			PALETTE.WallSide,
		},
		{
			"Walls_Right",
			"Part",
			Vector3.new(0.8, 10.5, 18),
			Vector3.new(16, 6.35, 0),
			nil,
			Enum.Material.Concrete,
			PALETTE.WallSide,
		},
		{
			"Walls_InsetFrontLeft",
			"Part",
			Vector3.new(5.5, 5.7, 0.3),
			Vector3.new(-3.4, 6.1, 9.45),
			nil,
			Enum.Material.Concrete,
			PALETTE.WallInset,
		},
		{
			"Walls_InsetFrontRight",
			"Part",
			Vector3.new(5.5, 5.7, 0.3),
			Vector3.new(11.4, 6.1, 9.45),
			nil,
			Enum.Material.Concrete,
			PALETTE.WallInset,
		},
		{
			"Walls_VentLeftSlats",
			"Part",
			Vector3.new(0.35, 2.2, 4.8),
			Vector3.new(-8.45, 8.1, -3.2),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodDark,
		},
		{
			"Walls_VentRightSlats",
			"Part",
			Vector3.new(0.35, 2.2, 4.8),
			Vector3.new(16.45, 8.1, 3.2),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodDark,
		},
		{
			"Walls_BackServiceDoorFrame",
			"Part",
			Vector3.new(5.6, 4.4, 0.45),
			Vector3.new(0.1, 4.25, -9.55),
			nil,
			Enum.Material.Wood,
			Color3.fromRGB(128, 92, 51),
		},
		{
			"Walls_BackServiceDoor",
			"Part",
			Vector3.new(4.6, 3.5, 0.35),
			Vector3.new(0.1, 4.05, -9.85),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodDark,
		},
		{
			"Walls_BackHighVent",
			"Part",
			Vector3.new(7.8, 1.2, 0.35),
			Vector3.new(8.7, 8.9, -9.72),
			nil,
			Enum.Material.WoodPlanks,
			Color3.fromRGB(79, 54, 33),
		},
		{
			"Walls_BackHighVentSlatA",
			"Part",
			Vector3.new(8.2, 0.18, 0.4),
			Vector3.new(8.7, 9.25, -9.95),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodLight,
		},
		{
			"Walls_BackHighVentSlatB",
			"Part",
			Vector3.new(8.2, 0.18, 0.4),
			Vector3.new(8.7, 8.55, -9.95),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodLight,
		},
		{
			"Walls_LeftBarnSign",
			"Part",
			Vector3.new(0.35, 2.6, 5.8),
			Vector3.new(-8.5, 5.4, 3.6),
			nil,
			Enum.Material.WoodPlanks,
			Color3.fromRGB(125, 87, 46),
		},
		{
			"Walls_RightGrainLedger",
			"Part",
			Vector3.new(0.35, 1.1, 10.5),
			Vector3.new(16.5, 4.8, -1.6),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Walls_RightGrainLedgerPins",
			"Part",
			Vector3.new(0.45, 0.35, 7.8),
			Vector3.new(16.75, 5.45, -1.6),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(140, 130, 107),
		},
	},
	Roof = {
		{
			"Roof_WestPlane",
			"Part",
			Vector3.new(12.6, 0.55, 19.4),
			Vector3.new(-1.5, 13.55, 0),
			Vector3.new(0, 0, 20),
			Enum.Material.Slate,
			Color3.fromRGB(109, 74, 63),
		},
		{
			"Roof_EastPlane",
			"Part",
			Vector3.new(13.2, 0.55, 20.2),
			Vector3.new(9.5, 14.15, 0),
			Vector3.new(0, 0, -20),
			Enum.Material.Slate,
			Color3.fromRGB(72, 96, 122),
		},
		{
			"Roof_RidgeCap",
			"Part",
			Vector3.new(20.5, 0.45, 0.45),
			Vector3.new(4, 16.7, 0),
			nil,
			Enum.Material.Metal,
			PALETTE.RoofMetal,
		},
		{
			"Roof_FrontEave",
			"Part",
			Vector3.new(27.2, 0.42, 0.55),
			Vector3.new(4, 12.35, 10.15),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Roof_FrontCanopy",
			"Part",
			Vector3.new(12.5, 0.35, 4.2),
			Vector3.new(4, 8.55, 11.65),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodMid,
		},
		{
			"Roof_FrontCanopyBraceLeft",
			"Part",
			Vector3.new(0.45, 2.9, 0.45),
			Vector3.new(-1.85, 7.4, 10.95),
			Vector3.new(0, 0, 22),
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Roof_FrontCanopyBraceRight",
			"Part",
			Vector3.new(0.45, 2.9, 0.45),
			Vector3.new(9.85, 7.4, 10.95),
			Vector3.new(0, 0, -22),
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Roof_BackEave",
			"Part",
			Vector3.new(24.8, 0.42, 0.55),
			Vector3.new(4, 11.85, -9.95),
			nil,
			Enum.Material.Wood,
			Color3.fromRGB(59, 41, 26),
		},
		{
			"Roof_WeatherVane",
			"Part",
			Vector3.new(0.14, 1.1, 0.14),
			Vector3.new(4, 16.45, 0),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(115, 107, 84),
		},
		{
			"Roof_WeatherVaneArrow",
			"Part",
			Vector3.new(1.7, 0.1, 0.1),
			Vector3.new(4, 16.95, 0),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(115, 107, 84),
		},
		{
			"Roof_FrontGableTrim",
			"Part",
			Vector3.new(0.4, 4.2, 0.45),
			Vector3.new(1.9, 13.95, 9.82),
			Vector3.new(0, 0, -32),
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Roof_FrontGableTrimMirror",
			"Part",
			Vector3.new(0.4, 4.2, 0.45),
			Vector3.new(6.1, 13.95, 9.82),
			Vector3.new(0, 0, 32),
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Roof_BackGableTrim",
			"Part",
			Vector3.new(0.35, 4, 0.4),
			Vector3.new(1.95, 13.9, -9.82),
			Vector3.new(0, 0, -32),
			Enum.Material.Wood,
			Color3.fromRGB(92, 61, 36),
		},
		{
			"Roof_BackGableTrimMirror",
			"Part",
			Vector3.new(0.35, 4, 0.4),
			Vector3.new(6.05, 13.9, -9.82),
			Vector3.new(0, 0, 32),
			Enum.Material.Wood,
			Color3.fromRGB(92, 61, 36),
		},
	},
	GiantLoadingFace = {
		{
			"Door_FrameGiant",
			"Part",
			Vector3.new(9.8, 8.1, 0.8),
			Vector3.new(4, 6.1, 9.65),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodLight,
		},
		{
			"Door_LeftSlab",
			"Part",
			Vector3.new(3.55, 6.7, 0.45),
			Vector3.new(1.95, 5.65, 10.05),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodDark,
		},
		{
			"Door_RightSlab",
			"Part",
			Vector3.new(3.55, 6.7, 0.45),
			Vector3.new(6.05, 5.65, 10.05),
			nil,
			Enum.Material.WoodPlanks,
			Color3.fromRGB(77, 51, 28),
		},
		{
			"Door_ThresholdBeam",
			"Part",
			Vector3.new(9.6, 0.45, 0.7),
			Vector3.new(4, 9.05, 10.15),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Door_CenterIron",
			"Part",
			Vector3.new(0.28, 5.9, 0.55),
			Vector3.new(4, 5.2, 10.16),
			nil,
			Enum.Material.Metal,
			PALETTE.Iron,
		},
		{
			"Upper_GrainHatch",
			"Part",
			Vector3.new(6.8, 2.9, 0.6),
			Vector3.new(4, 9.65, 9.9),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodDark,
		},
		{
			"GrainChute_Spout",
			"Part",
			Vector3.new(1.25, 3.4, 1.25),
			Vector3.new(4, 7.35, 10.75),
			Vector3.new(-18, 0, 0),
			Enum.Material.Wood,
			PALETTE.Wood,
		},
		{
			"Hoist_Beam",
			"Part",
			Vector3.new(8.8, 0.5, 0.7),
			Vector3.new(4, 10.7, 10.35),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Hoist_Hook",
			"Part",
			Vector3.new(0.32, 1.6, 0.32),
			Vector3.new(4, 9.65, 10.85),
			nil,
			Enum.Material.Metal,
			PALETTE.Metal,
		},
	},
	TinyfolkAccess = {
		{
			"Tinyfolk_HatchFrame",
			"Part",
			Vector3.new(2.8, 2.6, 0.45),
			Vector3.new(-3.4, 2.9, 9.78),
			nil,
			Enum.Material.Wood,
			Color3.fromRGB(158, 117, 64),
		},
		{
			"Tinyfolk_HatchDoor",
			"Part",
			Vector3.new(2.1, 1.9, 0.35),
			Vector3.new(-3.4, 2.8, 10.05),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.WoodDark,
		},
		{
			"Tinyfolk_ServiceLantern",
			"Part",
			Vector3.new(0.45, 0.6, 0.35),
			Vector3.new(-1.75, 4.15, 10.05),
			nil,
			Enum.Material.Neon,
			PALETTE.Lantern,
		},
		{
			"Tinyfolk_RailLeft",
			"Part",
			Vector3.new(0.25, 1.4, 0.25),
			Vector3.new(-5.1, 1.4, 10.55),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Tinyfolk_RailRight",
			"Part",
			Vector3.new(0.25, 1.4, 0.25),
			Vector3.new(-1.7, 1.4, 10.55),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Tinyfolk_RailTop",
			"Part",
			Vector3.new(3.65, 0.22, 0.22),
			Vector3.new(-3.4, 2.1, 10.55),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
	},
	TimberFrame = {
		{
			"Timber_PostFrontLeft",
			"Part",
			Vector3.new(1.2, 10.8, 1.2),
			Vector3.new(-7.55, 6.55, 9.5),
			nil,
			Enum.Material.Wood,
			PALETTE.Wood,
		},
		{
			"Timber_PostFrontRight",
			"Part",
			Vector3.new(1.2, 10.8, 1.2),
			Vector3.new(15.55, 6.55, 9.5),
			nil,
			Enum.Material.Wood,
			PALETTE.Wood,
		},
		{
			"Timber_PostBackLeft",
			"Part",
			Vector3.new(1.2, 10.8, 1.2),
			Vector3.new(-7.55, 6.55, -9.5),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Timber_PostBackRight",
			"Part",
			Vector3.new(1.2, 10.8, 1.2),
			Vector3.new(15.55, 6.55, -9.5),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Timber_BandFrontBase",
			"Part",
			Vector3.new(24.2, 0.8, 0.75),
			Vector3.new(4, 2.25, 9.55),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Timber_BandFrontUpper",
			"Part",
			Vector3.new(23, 0.65, 0.75),
			Vector3.new(4, 10.9, 9.55),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Timber_CrossbraceLeft",
			"Part",
			Vector3.new(0.75, 8.2, 0.65),
			Vector3.new(-5.8, 6.4, 9.75),
			Vector3.new(0, 0, -31),
			Enum.Material.Wood,
			Color3.fromRGB(115, 79, 43),
		},
		{
			"Timber_CrossbraceRight",
			"Part",
			Vector3.new(0.75, 8.2, 0.65),
			Vector3.new(13.8, 6.4, 9.75),
			Vector3.new(0, 0, 31),
			Enum.Material.Wood,
			Color3.fromRGB(115, 79, 43),
		},
	},
	HarvestProps = {
		{
			"Props_CrateStackLeft",
			"Part",
			Vector3.new(3, 2.8, 3),
			Vector3.new(-4.4, 2.9, 6.9),
			nil,
			Enum.Material.WoodPlanks,
			Color3.fromRGB(110, 77, 43),
		},
		{
			"Props_CrateStackTop",
			"Part",
			Vector3.new(2.4, 2, 2.4),
			Vector3.new(-4.7, 5.3, 7.2),
			nil,
			Enum.Material.WoodPlanks,
			Color3.fromRGB(128, 92, 51),
		},
		{
			"Props_SackGrainA",
			"Part",
			Vector3.new(2.3, 1.2, 1.8),
			Vector3.new(11.2, 2.55, 7.9),
			nil,
			Enum.Material.Fabric,
			PALETTE.Sack,
		},
		{
			"Props_SackGrainB",
			"Part",
			Vector3.new(1.8, 1, 1.5),
			Vector3.new(12.9, 2.45, 7.35),
			Vector3.new(0, 18, 0),
			Enum.Material.Fabric,
			PALETTE.SackDark,
		},
		{
			"Props_GrainSpill",
			"Part",
			Vector3.new(3.2, 0.12, 2.1),
			Vector3.new(4, 2.42, 12.05),
			nil,
			Enum.Material.Sand,
			PALETTE.Grain,
		},
		{
			"Props_TinyBarrel",
			"Part",
			Vector3.new(0.9, 1.2, 0.9),
			Vector3.new(-5.6, 1.25, 10.15),
			nil,
			Enum.Material.Wood,
			Color3.fromRGB(107, 71, 38),
		},
		{
			"Props_HandcartBed",
			"Part",
			Vector3.new(3.5, 0.35, 2.1),
			Vector3.new(9.7, 1.2, 11.3),
			Vector3.new(0, 12, 0),
			Enum.Material.WoodPlanks,
			Color3.fromRGB(97, 64, 36),
		},
		{
			"Props_HandcartHandle",
			"Part",
			Vector3.new(0.35, 0.35, 3.2),
			Vector3.new(11.6, 1.25, 12.2),
			Vector3.new(0, 12, 0),
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"Props_HandcartWheelLeft",
			"Part",
			Vector3.new(0.35, 1, 1),
			Vector3.new(8.6, 0.75, 10.45),
			Vector3.new(0, 0, 90),
			Enum.Material.Wood,
			Color3.fromRGB(46, 31, 20),
			Enum.PartType.Cylinder,
		},
		{
			"Props_HandcartWheelRight",
			"Part",
			Vector3.new(0.35, 1, 1),
			Vector3.new(10.8, 0.75, 10.9),
			Vector3.new(0, 0, 90),
			Enum.Material.Wood,
			Color3.fromRGB(46, 31, 20),
			Enum.PartType.Cylinder,
		},
		{
			"Props_BackBarrel",
			"Part",
			Vector3.new(1.6, 1.8, 1.8),
			Vector3.new(13.4, 1.65, -10.6),
			Vector3.new(0, 0, 90),
			Enum.Material.Wood,
			Color3.fromRGB(87, 56, 31),
			Enum.PartType.Cylinder,
		},
	},
	GrainSilos = {
		{
			"Silos_TallBin",
			"Part",
			Vector3.new(3.4, 10.2, 3.4),
			Vector3.new(-10.7, 6.1, -4.9),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(126, 124, 112),
			Enum.PartType.Cylinder,
		},
		{
			"Silos_TallBinCap",
			"Part",
			Vector3.new(3.75, 1.4, 3.75),
			Vector3.new(-10.7, 11.75, -4.9),
			nil,
			Enum.Material.Slate,
			Color3.fromRGB(57, 58, 61),
			Enum.PartType.Ball,
		},
		{
			"Silos_TallBinBandUpper",
			"Part",
			Vector3.new(3.55, 0.18, 3.55),
			Vector3.new(-10.7, 8.7, -4.9),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(76, 73, 68),
			Enum.PartType.Cylinder,
		},
		{
			"Silos_TallBinBandLower",
			"Part",
			Vector3.new(3.55, 0.18, 3.55),
			Vector3.new(-10.7, 4.25, -4.9),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(76, 73, 68),
			Enum.PartType.Cylinder,
		},
		{
			"Silos_ShortBin",
			"Part",
			Vector3.new(2.7, 7.6, 2.7),
			Vector3.new(-10.65, 4.8, 3.8),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(145, 139, 119),
			Enum.PartType.Cylinder,
		},
		{
			"Silos_ShortBinCap",
			"Part",
			Vector3.new(3, 1.1, 3),
			Vector3.new(-10.65, 9.1, 3.8),
			nil,
			Enum.Material.Slate,
			Color3.fromRGB(62, 62, 64),
			Enum.PartType.Ball,
		},
		{
			"Silos_CrossPipe",
			"Part",
			Vector3.new(0.5, 0.5, 7.8),
			Vector3.new(-9.05, 8.25, -0.5),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(99, 96, 88),
		},
		{
			"Silos_ServiceLadder",
			"Part",
			Vector3.new(0.22, 7.4, 0.22),
			Vector3.new(-8.8, 5.7, -6.85),
			nil,
			Enum.Material.Metal,
			Color3.fromRGB(63, 61, 58),
		},
	},
	RoofDetail = {
		{
			"RoofDetail_PennantPole",
			"Part",
			Vector3.new(0.16, 2.6, 0.16),
			Vector3.new(6.8, 17.45, 0.2),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodDark,
		},
		{
			"RoofDetail_PennantFlag",
			"WedgePart",
			Vector3.new(1.8, 1, 0.18),
			Vector3.new(7.7, 17.2, 0.2),
			Vector3.new(0, 0, 90),
			Enum.Material.Fabric,
			PALETTE.BannerRed,
		},
		{
			"RoofDetail_ShingleRibWestA",
			"Part",
			Vector3.new(10.8, 0.12, 0.18),
			Vector3.new(-1.8, 14.1, -5.8),
			Vector3.new(0, 0, 20),
			Enum.Material.Metal,
			Color3.fromRGB(78, 82, 88),
		},
		{
			"RoofDetail_ShingleRibWestB",
			"Part",
			Vector3.new(11.4, 0.12, 0.18),
			Vector3.new(-1.55, 13.6, 0),
			Vector3.new(0, 0, 20),
			Enum.Material.Metal,
			Color3.fromRGB(72, 76, 82),
		},
		{
			"RoofDetail_ShingleRibWestC",
			"Part",
			Vector3.new(10.8, 0.12, 0.18),
			Vector3.new(-1.8, 14.1, 5.8),
			Vector3.new(0, 0, 20),
			Enum.Material.Metal,
			Color3.fromRGB(78, 82, 88),
		},
		{
			"RoofDetail_ShingleRibEastA",
			"Part",
			Vector3.new(10.8, 0.12, 0.18),
			Vector3.new(9.8, 14.1, -5.8),
			Vector3.new(0, 0, -20),
			Enum.Material.Metal,
			Color3.fromRGB(78, 82, 88),
		},
		{
			"RoofDetail_ShingleRibEastB",
			"Part",
			Vector3.new(11.4, 0.12, 0.18),
			Vector3.new(9.55, 13.6, 0),
			Vector3.new(0, 0, -20),
			Enum.Material.Metal,
			Color3.fromRGB(72, 76, 82),
		},
		{
			"RoofDetail_ShingleRibEastC",
			"Part",
			Vector3.new(10.8, 0.12, 0.18),
			Vector3.new(9.8, 14.1, 5.8),
			Vector3.new(0, 0, -20),
			Enum.Material.Metal,
			Color3.fromRGB(78, 82, 88),
		},
	},
	WallDressing = {
		{
			"Wall_BuntingLeft",
			"Part",
			Vector3.new(3.2, 0.16, 0.16),
			Vector3.new(0.4, 10.75, 10.12),
			Vector3.new(0, 0, -12),
			Enum.Material.Fabric,
			PALETTE.BannerBlue,
		},
		{
			"Wall_BuntingCenter",
			"Part",
			Vector3.new(3.4, 0.16, 0.16),
			Vector3.new(4, 10.15, 10.12),
			nil,
			Enum.Material.Fabric,
			PALETTE.BannerGold,
		},
		{
			"Wall_BuntingRight",
			"Part",
			Vector3.new(3.2, 0.16, 0.16),
			Vector3.new(7.6, 10.75, 10.12),
			Vector3.new(0, 0, 12),
			Enum.Material.Fabric,
			PALETTE.BannerRed,
		},
		{
			"Wall_FrontBattenLeft",
			"Part",
			Vector3.new(0.28, 7.8, 0.28),
			Vector3.new(-4.9, 6.4, 9.82),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Wall_FrontBattenRight",
			"Part",
			Vector3.new(0.28, 7.8, 0.28),
			Vector3.new(12.9, 6.4, 9.82),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Wall_FrontSignBoard",
			"Part",
			Vector3.new(4.7, 0.55, 0.35),
			Vector3.new(4, 11.45, 10.05),
			nil,
			Enum.Material.WoodPlanks,
			PALETTE.TrimCream,
		},
		{
			"Wall_FrontSignGrainMark",
			"Part",
			Vector3.new(1.4, 0.18, 0.4),
			Vector3.new(4, 11.5, 10.3),
			nil,
			Enum.Material.Neon,
			Color3.fromRGB(219, 174, 75),
		},
		{
			"Wall_FlowerBox",
			"Part",
			Vector3.new(4.8, 0.4, 0.7),
			Vector3.new(4, 7.95, 10.05),
			nil,
			Enum.Material.Wood,
			PALETTE.WoodMid,
		},
		{
			"Wall_FlowerBushLeft",
			"Part",
			Vector3.new(1.15, 0.7, 0.7),
			Vector3.new(2.6, 8.35, 10.25),
			nil,
			Enum.Material.Grass,
			PALETTE.Leaf,
			Enum.PartType.Ball,
		},
		{
			"Wall_FlowerBushCenter",
			"Part",
			Vector3.new(1.3, 0.8, 0.7),
			Vector3.new(4, 8.45, 10.25),
			nil,
			Enum.Material.Grass,
			PALETTE.Leaf,
			Enum.PartType.Ball,
		},
		{
			"Wall_FlowerBushRight",
			"Part",
			Vector3.new(1.15, 0.7, 0.7),
			Vector3.new(5.4, 8.35, 10.25),
			nil,
			Enum.Material.Grass,
			PALETTE.Leaf,
			Enum.PartType.Ball,
		},
		{
			"Wall_FlowerBloomLeft",
			"Part",
			Vector3.new(0.3, 0.3, 0.3),
			Vector3.new(2.2, 8.65, 10.45),
			nil,
			Enum.Material.Neon,
			PALETTE.FlowerPink,
			Enum.PartType.Ball,
		},
		{
			"Wall_FlowerBloomRight",
			"Part",
			Vector3.new(0.3, 0.3, 0.3),
			Vector3.new(5.8, 8.65, 10.45),
			nil,
			Enum.Material.Neon,
			PALETTE.FlowerPink,
			Enum.PartType.Ball,
		},
		{
			"Wall_BackBattenA",
			"Part",
			Vector3.new(0.25, 8, 0.25),
			Vector3.new(-5.8, 6.4, -9.82),
			nil,
			Enum.Material.Wood,
			Color3.fromRGB(92, 61, 36),
		},
		{
			"Wall_BackBattenB",
			"Part",
			Vector3.new(0.25, 8, 0.25),
			Vector3.new(14, 6.4, -9.82),
			nil,
			Enum.Material.Wood,
			Color3.fromRGB(92, 61, 36),
		},
	},
}

local FOLDER_ORDER = {
	"Foundation",
	"Walls",
	"Roof",
	"GiantLoadingFace",
	"TinyfolkAccess",
	"TimberFrame",
	"HarvestProps",
	"GrainSilos",
	"RoofDetail",
	"WallDressing",
}

local function safeGetFullName(instance)
	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)
	return if ok then fullName else instance.Name
end

local function resolveDefaultParent()
	local current = Workspace
	for _, childName in ipairs(DEFAULT_PATH) do
		local nextChild = current:FindFirstChild(childName)
		if nextChild == nil then
			error(string.format("Missing default granary path child %s under %s", childName, safeGetFullName(current)))
		end
		current = nextChild
	end
	return current
end

local function getOrCreateModel(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing:IsA("Model") then
		return existing
	end
	if existing ~= nil then
		error(string.format("Expected %s to be a Model, found %s", safeGetFullName(existing), existing.ClassName))
	end
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local GENERATED_CONTAINER_NAMES = {
	Visual = true,
	Collision = true,
	AttachmentPoints = true,
	ScaleReferences_DoNotShip = true,
	PreservedGameplayParts = true,
}

local function isGeneratedGeometryChild(child)
	if child.Name == ANCHOR_NAME then
		return false
	end
	if GENERATED_CONTAINER_NAMES[child.Name] then
		return true
	end
	if child:IsA("BasePart") then
		return true
	end
	return false
end

local function clearBasePartsRecursively(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:Destroy()
		end
	end
end

local function getOrCreateFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if not existing:IsA("Folder") then
			error(string.format("Expected %s to be a Folder, found %s", safeGetFullName(existing), existing.ClassName))
		end
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function clearGeneratedContent(layout)
	local preserved = {}
	local removed = {}

	local archive = layout:FindFirstChild("PreservedGameplayParts")
	if archive ~= nil then
		clearBasePartsRecursively(archive)
	end

	for _, child in ipairs(layout:GetChildren()) do
		if child.Name == ANCHOR_NAME then
			table.insert(preserved, child.Name)
		elseif isGeneratedGeometryChild(child) then
			child:Destroy()
			table.insert(removed, child.Name)
		else
			table.insert(preserved, child.Name)
		end
	end

	return preserved, removed
end

local function setVisualPartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = true
end

local function setAnchorDefaults(anchor)
	anchor.Name = ANCHOR_NAME
	anchor.Size = ANCHOR_SIZE
	anchor.Anchored = true
	anchor.CanCollide = true
	anchor.CanTouch = false
	anchor.CanQuery = true
	anchor.Transparency = 1
	anchor.CastShadow = false
	anchor.Material = Enum.Material.SmoothPlastic
	anchor.Color = Color3.new(1, 1, 1)
	anchor:SetAttribute("AssetType", ASSET_TYPE)
	anchor:SetAttribute("BuildCategory", BUILD_CATEGORY)
	anchor:SetAttribute("VisualVersion", VISUAL_VERSION)
end

local function getRootCFrameFromAnchor(anchor)
	if anchor == nil then
		return CFrame.new()
	end
	return anchor.CFrame * CFrame.new(-ANCHOR_LOCAL_CENTER)
end

local function getSpecCFrame(rootCFrame, localPosition, localRotationDegrees)
	local localCFrame = CFrame.new(localPosition)
	if localRotationDegrees ~= nil then
		localCFrame *= CFrame.Angles(
			math.rad(localRotationDegrees.X),
			math.rad(localRotationDegrees.Y),
			math.rad(localRotationDegrees.Z)
		)
	end
	return rootCFrame * localCFrame
end

local function createPart(parent, rootCFrame, spec)
	local name, className, size, localPosition, localRotation, material, color, shape = table.unpack(spec)
	local part = Instance.new(className)
	part.Name = name
	part.Size = size
	part.CFrame = getSpecCFrame(rootCFrame, localPosition, localRotation)
	part.Material = material
	part.Color = color
	if shape ~= nil and part:IsA("Part") then
		part.Shape = shape
	end
	part.Parent = parent
	setVisualPartDefaults(part)
	return part
end

local function buildVisuals(layout, rootCFrame)
	local visual = getOrCreateFolder(layout, "Visual")
	clearBasePartsRecursively(visual)
	for _, folderName in ipairs(FOLDER_ORDER) do
		local folder = getOrCreateFolder(visual, folderName)
		clearBasePartsRecursively(folder)
		for _, spec in ipairs(PART_SPECS[folderName]) do
			createPart(folder, rootCFrame, spec)
		end
	end
end

local function buildScaleReferences(layout, rootCFrame)
	local refs = getOrCreateFolder(layout, "ScaleReferences_DoNotShip")
	clearBasePartsRecursively(refs)

	local giant = Instance.new("Part")
	giant.Name = "Giant_Scale_Reference_2_25"
	giant.Size = Vector3.new(1, 11.5, 1)
	giant.CFrame = rootCFrame * CFrame.new(-12.8, 5.75, 0)
	giant.Material = Enum.Material.Neon
	giant.Color = Color3.fromRGB(255, 80, 80)
	giant.Transparency = 0.35
	giant:SetAttribute("DoNotShip", true)
	giant.Parent = refs
	setVisualPartDefaults(giant)

	local tinyfolk = Instance.new("Part")
	tinyfolk.Name = "Tinyfolk_Scale_Reference_0_85"
	tinyfolk.Size = Vector3.new(0.7, 4.35, 0.7)
	tinyfolk.CFrame = rootCFrame * CFrame.new(-3.4, 2.175, 12.6)
	tinyfolk.Material = Enum.Material.Neon
	tinyfolk.Color = Color3.fromRGB(80, 160, 255)
	tinyfolk.Transparency = 0.35
	tinyfolk:SetAttribute("DoNotShip", true)
	tinyfolk.Parent = refs
	setVisualPartDefaults(tinyfolk)
end

local function countGeneratedVisualParts(layout)
	local visual = layout:FindFirstChild("Visual")
	if visual == nil then
		return 0
	end

	local count = 0
	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function copyTagsToReport(instance)
	local ok, tags = pcall(function()
		return CollectionService:GetTags(instance)
	end)
	return if ok then tags else {}
end

local function buildGranary(parent, cframe, options)
	options = options or {}
	parent = parent or resolveDefaultParent()

	local layout
	if parent:IsA("Model") and parent.Name == LAYOUT_NAME then
		layout = parent
	else
		layout = getOrCreateModel(parent, LAYOUT_NAME)
	end

	local existingAnchor = layout:FindFirstChild(ANCHOR_NAME)
	local rootCFrame = cframe
		or getRootCFrameFromAnchor(if existingAnchor and existingAnchor:IsA("BasePart") then existingAnchor else nil)

	local preserved, removed = clearGeneratedContent(layout)

	local anchor = layout:FindFirstChild(ANCHOR_NAME)
	if anchor ~= nil and not anchor:IsA("BasePart") then
		error(string.format("%s exists but is %s, expected BasePart", safeGetFullName(anchor), anchor.ClassName))
	end
	if anchor == nil then
		anchor = Instance.new("Part")
		anchor.Name = ANCHOR_NAME
		anchor.Parent = layout
	end
	anchor.CFrame = rootCFrame * CFrame.new(ANCHOR_LOCAL_CENTER)
	setAnchorDefaults(anchor)

	layout:SetAttribute("AssetType", ASSET_TYPE)
	layout:SetAttribute("BuildCategory", BUILD_CATEGORY)
	layout:SetAttribute("VisualVersion", VISUAL_VERSION)

	buildVisuals(layout, rootCFrame)
	if options.createReferenceDummies == true then
		buildScaleReferences(layout, rootCFrame)
	end

	local tags = {
		layout = copyTagsToReport(layout),
		anchor = copyTagsToReport(anchor),
	}

	print("[GranaryBuilder] Rebuilt granary visual model at " .. safeGetFullName(layout))
	print("[GranaryBuilder] Preserved root children: " .. table.concat(preserved, ", "))
	if #removed > 0 then
		print("[GranaryBuilder] Removed generated root children: " .. table.concat(removed, ", "))
	end
	print(
		"[GranaryBuilder] Preserved tags layout={"
			.. table.concat(tags.layout, ", ")
			.. "} anchor={"
			.. table.concat(tags.anchor, ", ")
			.. "}"
	)
	print("[GranaryBuilder] Contract check: Granary_A is the only Granary_ visual name and only collider.")
	print(
		"[GranaryBuilder] Dimensions: anchor 24x12x18, roof peak approx 17 studs, side silos and Tinyfolk hatch included."
	)
	print(
		string.format(
			"[GranaryBuilder] Generated visual part count=%d visualVersion=%d",
			countGeneratedVisualParts(layout),
			VISUAL_VERSION
		)
	)

	return layout
end

_G.buildGranary = buildGranary

if script ~= nil and script:IsA("ModuleScript") then
	return buildGranary
end

if _G.GRANARY_BUILDER_AUTO_RUN ~= false then
	buildGranary(resolveDefaultParent(), nil, { createReferenceDummies = false })
end
