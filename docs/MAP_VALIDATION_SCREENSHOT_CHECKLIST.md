# Map Validation Screenshot Checklist

Use the local Rojo-built place file and capture screenshots in Roblox Studio. This checklist is source-controlled so the validation path is repeatable, but the screenshots themselves are manual evidence.

This checklist validates the current primitive map blockout only. It does not validate gameplay balance, resource generation, save data, or external art intake.

## Build

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

## Required Views

- Overhead map: use `Workspace.Map.ValidationCameras.Layout.Shot_Overhead_Map`.
- Giant road readability: use `Workspace.Map.ValidationCameras.Layout.Shot_Giant_PlazaRoads`.
- Tinyfolk route-scale readability: use `Workspace.Map.ValidationCameras.Layout.Shot_Tinyfolk_RouteRead`.
- In Studio Play mode, `MapValidationScreenshotClient` shows **bottom-left buttons** for the three validation cameras and also accepts **H** / **G** / **T** when Studio is not paused. Number keys **1/2** remain role select via `RoleClient`.
- `MapScreenshotPresentationService` hides helper folders (`DistrictPads`, `RouteNodes`, zones, objectives, etc.) on server start during Play.
- After focusing a validation anchor, deselect it or select `Workspace.Map` before capturing so Studio selection outlines do not obscure the map.

## Helper Visibility Policy

- `Workspace.Map.ValidationCameras` parts are invisible anchors used only to frame manual screenshots.
- `Workspace.Map.ScaleMarkers` and `Workspace.Map.DebugLabels` are expected to be hidden or nearly hidden for screenshots.
- Screenshot helpers may carry `DoNotShip=true`, `VisualOnly=true`, or `HiddenForScreenshots=true`; these are documentation and workflow attributes, not gameplay contracts.
- Large blockout helpers should not dominate the overhead view. District readability should come from pads, roads, silhouettes, fences, creek edges, and route markers.

## Pass Criteria

- `Workspace.Map.GiantRoads` is the canonical macro-road layer.
- `Workspace.Map.Graybox.SupportingRoutes` is visibly treated as quarantined/reference-only if present.
- District pads match the coordinate blueprint labels and positions closely enough to guide later art replacement.
- Functional stations remain present under `Workspace.Map.Stations`.
- `map/stations/granary` remains the existing granary asset and `Granary_A` remains the station contract anchor.
- EscapeRoute_A, EscapeRoute_Dock, EscapeRoute_NorthTunnel, and fallback bands are readable and unobstructed.
- Tinyfolk routes remain marker-only or dashed. They should not read as full roads.
- Giant roads are broad enough to read as macro routes for 11-12 stud Giants.
- Primitive dressing remains low-risk: fences, creek banks, simple silhouettes, pads, and labels.
- Scale/debug helpers are present in source when useful, marked `DoNotShip=true`, and hidden or softened for screenshot clarity.
- No external assets are imported.

## Evidence Notes

- Record whether the overhead view shows the whole playable map without floating debug blocks, oversized translucent shells, or selection outlines.
- Record whether Giant-level screenshots show the plaza roads and nearby stations without losing the macro route shape.
- Record whether Tinyfolk-level screenshots show dashed route cues and escape/fallback readability without turning those routes into full roads.
- If a screenshot reveals a problem, prefer one small helper-only slice before changing station placement or gameplay systems.

## Current Limitation

Automated command-line validation can build the place and run tests, but actual Studio screenshots still require manual Studio capture.
