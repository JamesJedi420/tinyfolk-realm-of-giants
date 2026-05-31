# Map Validation Screenshot Checklist

Use the local Rojo-built place file and capture screenshots in Roblox Studio. This checklist is source-controlled so the validation path is repeatable, but the screenshots themselves are manual evidence.

## Build

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

## Required Views

- Overhead map: use `Workspace.Map.ValidationCameras.Shot_Overhead_Map`.
- Giant road readability: use `Workspace.Map.ValidationCameras.Shot_Giant_PlazaRoads`.
- Tinyfolk route-scale readability: use `Workspace.Map.ValidationCameras.Shot_Tinyfolk_RouteRead`.
- After focusing a validation anchor, deselect it or select `Workspace.Map` before capturing so Studio selection outlines do not obscure the map.

## Pass Criteria

- `Workspace.Map.GiantRoads` is the canonical macro-road layer.
- `Workspace.Map.Graybox.SupportingRoutes` is visibly treated as quarantined/reference-only if present.
- District pads match the coordinate blueprint labels and positions.
- Functional stations remain present under `Workspace.Map.Stations`.
- `map/stations/granary` remains the existing granary asset and `Granary_A` remains the station contract anchor.
- EscapeRoute_A, EscapeRoute_Dock, EscapeRoute_NorthTunnel, and fallback bands are readable and unobstructed.
- Scale markers are present and marked `DoNotShip=true`.
- No external assets are imported.

## Current Limitation

Automated command-line validation can build the place and run tests, but actual Studio screenshots still require manual Studio capture.
