# Profile Ownership Decision

## Status
Chosen path: ProfileStore-backed profile-locking owner layer behind `ProfilePersistenceGateway`.

Rejected default: custom/raw DataStore adapter as the gameplay-facing owner.

## Decision Summary
Tinyfolk uses one server-only gateway and one profile-locking owner-layer path for durable persistence. Gameplay systems talk to `ProfilePersistenceGateway`, and that gateway forwards durable profile ownership to `ProfileStoreOwnerLayer` rather than exposing raw persistence primitives to gameplay code.

## Options Compared
- ProfileStore-backed owner layer: server-only, session-locking, gateway-mediated, and aligned with the current Giant realm snapshot/apply model.
- Custom/raw DataStore adapter: direct persistence ownership with bespoke session, autosave, and release logic.

## Decision Matrix
| Acceptance dimension | ProfileStore-backed owner layer | Custom/raw DataStore adapter |
|---|---|---|
| Session locking | Native profile-locking lifecycle is the core behavior. | Must be rebuilt and maintained manually. |
| Autosave | Can be layered on top of owned profile sessions. | Requires custom autosave orchestration and release timing. |
| Player profiles | Supported behind the gateway with session ownership. | Supported only through custom adapter code. |
| Giant realm profiles | Supported as owned profile sessions with schema validation. | Supported only through a second bespoke path. |
| Trading and custody safety | Lower duplication and handoff risk because one owner controls sessions. | Higher duplication and custody-adjacent risk because ownership must be coordinated manually. |
| Testing | Easier to isolate behind gateway and owner-layer seams. | More surface area to mock, replicate, and keep in sync. |
| Migration risk | Lower, because runtime behavior already matches the gateway/owner split. | Higher, because it would introduce parallel ownership and new lifecycle behavior. |

## Chosen Integration Path
- Gameplay systems call `ProfilePersistenceGateway`.
- `ProfilePersistenceGateway` calls `ProfileStoreOwnerLayer`.
- `ProfileStoreOwnerLayer` owns ProfileStore-shaped player and Giant realm sessions.
- Giant realm live state persists only through `BuildSaveSnapshot` / `ApplySaveSnapshot`.
- Raw `DataStoreService` is not a gameplay-facing owner.

## Rejected Option Rationale
The custom/raw DataStore adapter is not the default because it would remove native profile-locking lifecycle safety, increase teleport/custody/trading-adjacent duplication risk, and create a second ownership path that gameplay code would need to understand. It also shifts autosave, session release, and ownership reconciliation into custom code that would be harder to test and easier to diverge from the gateway contract.

## Current Runtime Evidence
- [src/ServerScriptService/Services/ProfilePersistenceGateway.luau](../src/ServerScriptService/Services/ProfilePersistenceGateway.luau)
- [src/ServerScriptService/Services/ProfileStoreOwnerLayer.luau](../src/ServerScriptService/Services/ProfileStoreOwnerLayer.luau)
- [src/ServerScriptService/Services/ProfilePersistenceLifecycle.server.luau](../src/ServerScriptService/Services/ProfilePersistenceLifecycle.server.luau)
- [src/ServerScriptService/Services/RoleService.server.luau](../src/ServerScriptService/Services/RoleService.server.luau)
- [docs/SYSTEM_BOUNDARIES.md](SYSTEM_BOUNDARIES.md)
- [docs/THIRD_PARTY.md](THIRD_PARTY.md)
- [tests/profile_persistence_gateway.spec.luau](../tests/profile_persistence_gateway.spec.luau)
- [tests/profile_store_owner_layer.spec.luau](../tests/profile_store_owner_layer.spec.luau)
- [tests/profile_store_dependency_intake.spec.luau](../tests/profile_store_dependency_intake.spec.luau)
- [tests/profile_persistence_lifecycle.spec.luau](../tests/profile_persistence_lifecycle.spec.luau)
- [tests/role_service_runtime_entrypoint.spec.luau](../tests/role_service_runtime_entrypoint.spec.luau)

## Deferred Work
- Autosave policy.
- Schema migration utilities.
- Shrine persistence.
- Rescue/handoff persistence.
- Cross-server handoff.
- Multi-realm support.

## Contradiction Check
No gameplay system should write directly to raw `DataStoreService`. The required no-match search excludes owner-layer, bootstrap, and vendored dependency paths, so any result there would indicate a boundary violation rather than an allowed persistence implementation detail.