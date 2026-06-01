# Map External Asset Intake Checklist

Use this only after the primitive blockout is validated in Studio. Do not import external assets until every item below has a named owner and evidence.

The current map pass is still primitive-only. External assets must replace visual placeholders carefully; they must not replace functional station models, anchors, scripts, prompts, tags, pivots, or attributes.

## Intake Gates

- License and creator/source recorded.
- Asset purpose maps to an existing placeholder folder or district pad.
- Asset does not replace functional station anchors such as `Granary_A`, `WorkStation_A`, `MiningStation_A`, `Warehouse_A`, `Shrine_A`, `GiantControlStation_A`, or `GiantUpgradeBoard_A`.
- `Workspace.Map.Stations.Granary` remains the existing functional granary asset unless a future station-specific issue explicitly migrates it.
- Collision is explicit and separated from visual mesh content.
- Tinyfolk routes remain marker/path readable after dressing.
- Giant macro roads remain readable for an 11-12 stud Giant.
- Escape, rescue, and fallback readability markers remain unobstructed.
- Asset remains under Rojo-managed source paths.
- Asset does not introduce broad translucent shells, floating debug blocks, or oversized helper geometry into validation screenshots.

## Folder Convention

- `Workspace.Map.ExternalDressingPlaceholder.FolderConvention_StaticMeshes`
- `Workspace.Map.ExternalDressingPlaceholder.FolderConvention_Textures`
- `Workspace.Map.ExternalDressingPlaceholder.FolderConvention_Collision`

## Replacement Order

1. Replace low-risk visual dressing first: fences, creek banks, small silhouettes, and nonfunctional props.
2. Replace district pad dressing only after the current pad coordinate remains readable from overhead.
3. Replace station-adjacent visuals only after confirming the whole station `Layout` model and its contract children remain intact.
4. Defer collision-heavy assets until the visual pass is approved from overhead, Giant-level, and Tinyfolk-level screenshots.

## Current Status

No external assets are imported. The current map pass uses primitive placeholders only.
