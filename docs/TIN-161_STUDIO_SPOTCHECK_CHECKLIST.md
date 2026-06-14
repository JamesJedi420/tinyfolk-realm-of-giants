# TIN-161 Defensive Prop Studio Spot-Check Checklist

Use this checklist in Roblox Studio Play mode to validate defensive prop drop/break/barrier behavior after map sync.

## Setup

1. Build/sync map: `rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx` and open in Studio (or live Rojo sync).
2. Play with at least two clients (or Team Test): one Tinyfolk, one Giant.
3. Confirm authored anchors exist under `Workspace.Map.DefensiveProps.Layout` and zones under `Workspace.Map.DefensivePropZones.Layout`.

## Drop flow (Tinyfolk)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Tinyfolk approaches `DefensiveProp_A` (crate) within 12 studs | Drop interaction available |
| 2 | Request drop | Prop state → Dropped (startup); Giant macro route still traversable |
| 3 | Wait ~1s | Prop state → Blocked; linked Giant macro route blocked |
| 4 | Drop while holding active rescue contract OR with downed ally in zone | `RescueAccelerationActive` attribute set on dropper |

## Break flow (Giant)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Giant approaches dropped/blocked prop within 14 studs | Break start available |
| 2 | Start break | Break-in-progress window (~2s) |
| 3 | Complete break after duration | Prop → Broken → Resetting → Ready |
| 4 | Giant contacts prop during Blocked window while breaking | Break cancels; stagger attributes applied |

## Prop families

| Prop | Type | Zone | Notes |
|------|------|------|-------|
| `DefensiveProp_A` | crate | `DefensivePropZone_A` | Default timing; blocks `GiantRoute_PlazaToHearth` |
| `DefensiveProp_B` | shelf | `DefensivePropZone_B` | Longer active window (6s); blocks `GiantRoute_PlazaToWorkYard` |
| `DefensiveProp_C` | rope_gate | `DefensivePropZone_C` | Longer stagger (1s); blocks `GiantRoute_PlazaToStoneDistrict` |

## Evidence capture

- Note prop state attributes on anchor part after each phase.
- Note Giant `GiantBarrierStaggerActive` / `GiantBarrierStaggerUntil` during barrier contact.
- Note Tinyfolk `RescueAccelerationActive` after rescue-context drop.
- Record PASS/FAIL per row above in slice evidence doc.
