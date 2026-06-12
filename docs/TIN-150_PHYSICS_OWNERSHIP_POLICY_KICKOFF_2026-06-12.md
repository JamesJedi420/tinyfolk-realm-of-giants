# TIN-150 Physics Ownership Policy Kickoff (2026-06-12)

## Issue

- ID: TIN-150
- Title: Implement physics ownership policy
- Milestone: Capture, Rescue, and Routing
- Linear: https://linear.app/spectranoir/issue/TIN-150/implement-physics-ownership-policy

## Goal

Keep capture/escape/custody/reward-critical physics server-authoritative so client-owned assemblies cannot grant critical outcomes.

## Scope

- Add `GameplayPhysicsOwnershipConfig` classifying assemblies into `Server`, `Automatic`, and `Client` tiers.
- Add pure `GameplayPhysicsOwnershipPolicy` resolver for character profiles and authored world parts.
- Add `PhysicsOwnershipService` module + server bootstrap enforcing network ownership and debug attributes.
- Refresh ownership on role/capture/carry/hold attribute changes, `CharacterAdded`, and periodic re-enforcement for server-critical players.
- Assign world ownership under `Workspace.Map` at startup (containment, traps, trigger zones, doors, loot, build preview).
- Expose `_PhysicsOwnershipService_QueryAPI` for tests/debug.
- Add Studio-only `PhysicsOwnershipDebugClient` for ownership snapshot logging.

## Assembly policy

| Assembly | Tier | Notes |
|----------|------|-------|
| `CarriedTinyfolk` | Server | Grab/carry custody |
| `ContainedTinyfolk` | Server | Capture-active custody |
| `CarryingGiant` | Server | Active carrier while holding target |
| `FreeCharacter` | Automatic | Default player locomotion |
| `ContainmentStructure` | Server | Containment district geometry |
| `SnareTrap` | Server | Runtime trap artifacts |
| `GameplayDoor` | Server | Movable gameplay doors |
| `RewardLoot` | Server | Loot containers affecting rewards |
| `TriggerZone` | Server | Touch volumes with gameplay outcomes |
| `BuildPreview` | Client | Non-authoritative preview ghosts |
| `WorldGeometry` | Automatic | General map collision |

## Boundary

- Policy + enforcement wiring only; no changes to capture/escape outcome authority.
- TIN-149 Studio collision matrix spot-check runbook remains deferred.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/gameplay_physics_ownership_policy.spec.luau
lune run tests/physics_ownership_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

Studio spot-check: verify `GameplayPhysicsOwnershipTier` / `GameplayPhysicsOwnershipAssembly` attributes on carried Tinyfolk, carrying Giant, containment map parts, and snare trap artifacts via Output from `PhysicsOwnershipDebugClient`.
