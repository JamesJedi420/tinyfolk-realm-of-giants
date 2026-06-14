# TIN-61 Containment Structure System Closure (2026-06-14)

## Issue

- ID: TIN-61
- Title: Implement containment structure system
- Linear: https://linear.app/spectranoir/issue/TIN-61/implement-containment-structure-system

## Shipped

- `ContainmentStructureConfig` + shared `ContainmentStructureState` for capacity, occupants, escape/rescue eligibility, and structure status.
- `ContainmentStructureService` with structure/zone registry, occupant assign/remove, rescue checks, and `_ContainmentStructureService_QueryAPI`.
- `CaptureService.PromoteTargetToContained` assigns structure occupants when registered; custody end and timeout pruning clear occupants via `clearStructureOccupantForTarget`.
- Authored anchors: `ContainmentStructure_A` (cage, capacity 2) + `ContainmentStructureZone_A` at Pen choke.
- Build-mode placement follow-up: `ContainmentStructurePlacementState`, `GiantBuildModeService` materialization, and realm save/load persistence for placed cage/jar entries.
- Giant reward-over-time: `ContainmentRewardResolver` awards proportional score/realm resources at custody end from `heldSeconds / custodyWindowSeconds` (clamped), with pair diminishing returns.
- Max no-agency duration: `CaptivityDurationState` enforces `MaxCapturedDurationSeconds` and `MaxContainedDurationSeconds`; `CaptureService` timeout pruning applies `safe_return` fallback via `CaptivitySafeReturnCaller`.

## Acceptance criteria

| Criterion | Status |
|-----------|--------|
| Containment structures have capacity | PASS — `ContainmentStructureState.AssignOccupant` + authored `ContainmentStructure_A` |
| Contained Tinyfolk can interact with escape points | PASS — escape interaction eligibility on cage/jar; TIN-87 `ContainmentZoneInteractionService` |
| Other Tinyfolk can rescue contained players | PASS — `CanRescueOccupant` + structure zone range checks |
| Containment contributes to Giant rewards over time | PASS — `ContainmentRewardResolver` proportional terminal awards |
| Containment cannot exceed max no-agency duration | PASS — `CaptivityDurationState` + `CaptureService` timeout/safe-return |

## PRs

- https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/85 — Authored containment structures with capacity and capture wiring
- https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/89 — Wire build-mode containment placements into registry
- https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/90 — Persist containment build-mode placements across realm save/load

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/containment_structure_state.spec.luau
lune run tests/containment_structure_service_runtime_entrypoint.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/captivity_duration_state.spec.luau
lune run tests/containment_reward_resolver.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Additional structure catalog families beyond cage/jar (tower, terrarium, drawer, birdcage, glass_box catalog stubs exist; gameplay anchors deferred).
- HUD/VFX/audio polish for containment structures and escape/rescue interactions.
- Cross-session persistence of active structure occupant runtime (placement persistence shipped; live occupant state remains session-local).
