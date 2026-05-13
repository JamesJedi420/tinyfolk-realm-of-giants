# System Boundaries - Tinyfolk: Realm of Giants

This document defines canonical system buckets, fold-in vs new-issue guidance, and cross-system rules. Use it to reduce drift during backlog reconciliation and to keep issue scope narrow.

## Canonical System Buckets

### Escape and Route System
- Route graph validation (node types, edge integrity, reachability)
- Fallback escape route triggering and resolution
- Final exit phase state machine (Dormant → Powered → Opening → Open → Blocked → Resolved)
- Safe-zone rules at exits and spawn points

**Fold into this bucket:** escape node tier rules, route blocking checks, fallback cue behavior, final exit interruption logic, exit camp prevention rules.

### Capture and Containment System
- Carry state and grab mechanics
- Escape minigame progress (build, decay, reset rules)
- Containment structure rules (capacity, camera, rescue access)
- Anti-guarding pressure and counterplay outcomes
- Post-rescue protection state
- Maximum no-agency duration enforcement

**Fold into this bucket:** custody transfer rules, contained-player agency requirements, rescue acceleration, protection cancellation conditions.

### Warning, Tracking, and Stealth System
- Giant warning cue design (pressure, rough closeness — not exact location)
- Tinyfolk movement trail behavior (directional pressure — not wallhacks)
- Hiding and trail suppression rules
- Stealth must trade certainty for uncertainty, not create permanent safety
- Bounded and counterable hiding

**Fold into this bucket:** trail decay rules, hiding zone rules, proximity alert tuning, stealth interaction with rescue protection.

### Score and Reward System
- Category-based score rules for Tinyfolk and Giants
- Data-driven score events
- Repeated-action depreciation and caps
- Anti-abuse detection (repeated targeting, custody duration, forced interaction patterns)
- Live score feedback

**Fold into this bucket:** per-category score weights, decay curves, reward triggers for escape/containment/objective events.

### Realm Identity and Assembly System
- Chunk schema, socket compatibility, and assembly I/O contract
- World-space socket resolution
- Connection graph stitching and integrity checks
- Chunk footprint and occupied-space contract (bridge to district placement)
- Realm descriptor adapter (assembly → validator-ready descriptor)

**Fold into this bucket:** assembly validator rules, socket world-space math, chunk placement conventions.

### Realm Metadata and Theme Family System
- Realm metadata registry
- Theme family schema
- Palette, lighting, landmark, district, route, and audio vocabulary
- Accessibility and readability requirements tied to realm family identity

**Fold into this bucket:** recurring structure families, landmark identity rules, theme-consistent district growth, realm selection influence rules.

### District and Placement Validation System (TIN-175)
- District placement legality against assembled space
- Occupied space and footprint overlap rejection
- Zone placement rules (control zones, capture zones, spawn zones)
- Validator-enforceable placement constraints from GAME_SPEC

**Current implementation status:** Runtime validation gate is implemented and test-backed. Accepted placements now materialize explicit world-state payloads on the accepted registry entry and exactly one minimal Workspace artifact under the district container. Repeated accepted placements for the same districtId deterministically replace that artifact in place. Rejected placements still create no registry or Workspace artifact mutation. DistrictPlacementService exposes a public read-only query API (GetPlacedDistrict, GetPlacedDistrictsByPlayer, GetAllPlacedDistricts, IsDistrictPlaced) via `_G._DistrictPlacementService_QueryAPI` for downstream systems (construction, debug tools, analytics) to inspect accepted placement state without mutating the registry. Broader Workspace world-content breadth remains deferred to future work.

**Fold into this bucket:** zone separation checks, cluster density caps, total caps, spatial constraint rules derived from GAME_SPEC.

### Giant Realm Build Mode Placement Boundary (TIN-56)
- Dedicated giant structure placement request ingress with a distinct remote contract
- Server-side payload validation boundary for structure placement requests
- Server-owned structure definition catalog for allowed `structureId` values
- Deterministic rejection reasons for malformed/out-of-bounds/invalid occupied-space payloads
- Accepted placement registry as server-owned in-memory state for current session
- Minimal Workspace artifact materialization for accepted giant structure placements

**Current implementation status:** The request contract and validation boundary are implemented and runtime-test-backed. `GiantBuildModeService.server.luau` binds `GiantStructurePlacementRequest`, validates `structureId` and `proposedOccupiedSpace` payload shape/ranges, rejects unknown `structureId` values against the server-owned `GiantStructureCatalog`, rejects duplicates by `structureId`, enforces an in-memory session-owner placement policy before occupied-space collision, affordability debit, and placement acceptance, rejects occupied-space overlaps against accepted Giant structures before affordability debit and placement acceptance, performs server-authoritative affordability checks, and spends stored Wood/Stone through `ResourceFlowState` before accepting placement. Accepted placements materialize one minimal artifact under `Workspace.Map.GiantStructures`. `GiantStructureCatalog` is now the durable source of truth for allowed structure IDs plus structure metadata fields (`displayName`, `category`, `woodCost`, `stoneCost`). Query-only `_G._GiantBuildModeService_QueryAPI` exposes `GetPlacedStructure`, `GetAllPlacedStructures`, and `IsStructurePlaced` for downstream read access without mutation.

**Deferred in this slice:** ownership authorization policy beyond duplicate rejection, district/realm legality validation against assembly topology, footprint-derived server placement defaults, and any persistent save/load schema or DataStore I/O.

**Fold into this bucket:** additional structure validation constraints, legal placement topology checks, ownership/cost policy once specified, and persistence integration after schema boundary is defined.

**Persistence schema status:** Giant realm persistence now has an initial pure-Luau save schema plus deterministic serialization/validation helpers for accepted Giant structure records. A read-only live snapshot assembly surface now builds and validates a schema-valid save root from accepted Giant build-mode structures, and a bounded apply surface now replaces live accepted Giant build-mode state from a schema-valid save root. DataStore reads/writes, load orchestration, and migration upgrades remain deferred.

**Durable persistence ownership decision:** Durable Giant realm and player profile persistence is owned by a profile-locking persistence layer, reached through a thin server-only Tinyfolk compatibility gateway. Gameplay systems must not write directly to raw `DataStoreService`. Giant build mode remains the live-state owner and exposes snapshot/apply surfaces; it does not own durable profile sessions, autosave, load orchestration, or session locks.

**Profile persistence gateway status:** A server-only `ProfilePersistenceGateway` skeleton defines the Tinyfolk compatibility gateway boundary, typed success/failure result shape, and injected profile-locking owner-layer seam. The gateway itself does not import or call ProfileStore/ProfileService/raw DataStore persistence, and no gameplay service is wired to it yet. Giant realm save/load handoff is limited to the existing `BuildSaveSnapshot` / `ApplySaveSnapshot` query API surface.

**Profile owner-layer adapter status:** A server-only `ProfileStoreOwnerLayer` adapter now defines the first real profile-locking owner-layer implementation behind `ProfilePersistenceGateway` for player profiles only, using an injected ProfileStore-shaped dependency. The adapter does not wire gameplay services, does not call raw `DataStoreService`, and returns deterministic unsupported failures for Giant realm profile methods until a later realm-profile slice.

**ProfileStore dependency intake status:** ProfileStore is now vendored as pinned third-party server-only source under `ServerScriptService.Services.ThirdParty`, with source, license, pinned commit, retrieval date, and gameplay-access restriction recorded in `docs/THIRD_PARTY.md`. `ProfileStoreOwnerLayer.CreateDefault` constructs the player-profile owner adapter through the existing `Create` path using bounded default intake config only. Gameplay services remain unwired, and Giant realm profile persistence remains deferred.

**Profile lifecycle wiring status:** A server-only `ProfilePersistenceLifecycle` bootstrap now configures `ProfileStoreOwnerLayer.CreateDefault()` behind `ProfilePersistenceGateway` and owns player join, leave, and shutdown save/release calls through the gateway only. Gameplay services still do not depend on raw persistence details. Giant realm real profile lifecycle remains deferred.

**Profile data consumption status:** `ProfilePersistenceGateway` now exposes gameplay-safe loaded player profile data access and update entrypoints. Callers can read cloned snapshots and commit mutations only through the gateway update function; they cannot receive ProfileStore profile/session objects or mutate active profile data by reference. `RoleService` consumes this surface in a bounded way for role preference only (`rolePreference.preferredRole`), and `SpecialistAssignmentService` consumes this surface in a bounded way for specialist preference fields (`specialistPreference.specialistRole` and `specialistPreference.assignedStationId`) while preserving existing specialist state-machine validation. These integrations restore valid stored preference values during setup and persist accepted gameplay transitions through gateway updates while save timing remains lifecycle-owned. Giant realm real profile persistence remains deferred.

### Trait and Loadout Framework
- Role-shaped loadout slots (intentionally capped)
- Data-driven trait definitions
- Starter/common trait teach-first ordering
- Tier tuning: bounded value adjustment, not core rule override
- Shared registry/schema for traits, cooldowns, tokens, active abilities, anti-abuse rules

**Fold into this bucket:** trait effect definitions, cooldown schema, token schemas, ability registry entries.

### Economy and Labor System
- Specialist role assignment (Woodcutter, Miner, Worshipper, None)
- Produced → InTransit → Stored resource flow
- Station interaction and hauling flow
- Essence generation (Shrine → Giant session pool)
- Construction spending from stored totals only
- Warehouse delivery point

**Current implementation status:** ConstructionService performs startup discovery from `_G._DistrictPlacementService_QueryAPI.GetAllPlacedDistricts` and initializes minimal district build-state entries. DistrictPlacementService remains placement authority and query-only provider. ConstructionService owns build-state initialization only in this slice. ConstructionConfig is cost authority for district defaults via `DistrictDefaultCost`; `DistrictBuildState` entries carry resolved `woodCost` and `stoneCost` at startup; cost is not derived from placement state. ConstructionService routes `ConstructionBuildRequest` through both `siteStateById` (existing site-backed path) and `districtBuildStateById` (district path); district build mutation is server-owned and spends startup cost fields; range check for districts is deferred (no Workspace part reference in this slice); DistrictPlacementService is not modified. `handleDebugRequest` now covers both site and district IDs in both the targeted (string payload) and snapshot-all (nil payload) paths; district entries use a `districtId` field to distinguish them from site entries; unknown IDs in both paths continue to produce `site_not_found`.

**Fold into this bucket:** new specialist station couplings, resource state transition rules, additional assignment reasons, new hauling paths.

### Role and Session System
- Pre-spawn role selection (Giant / Tinyfolk)
- First valid choice wins; role locked for session
- Respawn preserves role lock
- Specialist assignment clears on role change away from Tinyfolk

**Fold into this bucket:** future role addition work, session state persistence rules, role-gated system checks.

### Developer Workflow and Studio Tooling
- Studio launch tasks from VS Code
- Roblox place revision rollback/open workflow
- Issue-to-Studio script navigation pattern

**Create separate issues for:** VS Code Studio launch tasks, Roblox place revision rollback/open workflow, and issue-to-Studio script navigation.

**Fold into this bucket:** separate hub / Giant place launch tasks, local Studio executable path config, line/range highlight handoff for bug reports, revision-aware publish log.

**Validation boundary:** Studio-open smoke test checklist work belongs in TIN-157, not a separate workflow.

---

## Cross-System Rules

| Rule | Bucket |
|---|---|
| Rescue protection is one boundary | Capture and Containment |
| Final-exit phase is one boundary | Escape and Route |
| Hiding is one boundary | Warning, Tracking, and Stealth |
| Warning system is one boundary | Warning, Tracking, and Stealth |
| Trait/loadout framework is one boundary | Trait and Loadout |
| Backlog structure changes may require doc updates | Cross-cutting rule |
| Asset sourcing is not gameplay backlog | See below |

---

## Asset Sourcing Boundary

External assets, plugins, frameworks, and reference games are **sourcing inputs**, not implementation backlog.

Create issues only for:
- license evaluation
- intake / import pipeline
- concrete integration work
- bounded implementation tasks derived from an asset

Do not create issues for reference game titles, rankings, acquisition notes, or exploratory research by default.

---

## Fold-In vs New Issue

**Fold in when:**
- The candidate is a rule, parameter, sub-behavior, acceptance detail, or example for an existing system bucket.
- It does not introduce a new durable implementation surface.
- It would not produce a separate test file or module boundary.

**Create a new issue when:**
- The candidate is a genuinely missing system bucket with its own module, schema, or test surface.
- It crosses a clear implementation boundary that cannot safely merge into an existing issue without expanding scope.
- It introduces new data contracts that other systems depend on.

**When in doubt:** fold in. Keep the issue count small.
