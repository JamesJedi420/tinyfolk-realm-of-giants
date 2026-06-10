# System Boundaries - Tinyfolk: Realm of Giants

This document defines canonical system buckets, fold-in vs new-issue guidance, and cross-system rules. Use it to reduce drift during backlog reconciliation and to keep issue scope narrow.

## Canonical System Buckets

### Escape and Route System
- Route graph validation (node types, edge integrity, reachability)
- Fallback escape route triggering and resolution
- Final exit phase state machine (Dormant → Powered → Opening → Open → Blocked → Resolved)
- Tinyfolk-only route access metadata and query surfaces
- Safe-zone rules at exits and spawn points

**Current implementation status:** TIN-186 implements a bounded server-owned through-gap reach validation slice on `EscapeService.validateThroughGapReach`. Reach attempts now require an explicit route identifier and route metadata (`ThroughGapReachAllowed=true`) plus a supported route type (`TraversalGap`) before validation can pass. Validation also requires caller/target root data, Tinyfolk crossing-phase truth (`CrossingPhase=MidCrossing`), safe-zone rejection (`InSafeZone=true` rejects), and a non-bypassed line-of-sight callback (runtime raycast or injected check). Generic world-position-only requests and non-gap routes are rejected by design. TIN-185 adds server-owned temporary traversal-gap block state in `EscapeService`, backed by deterministic shared block-state logic. Giant dash requests (`EscapeService.requestDash`) are gated by explicit `TraversalGap` metadata, caller role/root/range checks, dash radius/cooldown config, and safe-zone route rejection. Backward-compatible `requestTraversalGapBlock` calls use the same server-owned block-state path. Block state exposes readable route attributes and escape debug snapshot fields for Startup, Active, expiration timing, blocker user id, and explicit exemption. Active blocks reject Tinyfolk traversal and through-gap reach unless a route has the explicit exemption flag; Startup remains traversable as the bounded Tinyfolk timing counterplay. Blocks expire automatically and do not permanently destroy routes. TIN-221 now adds a bounded server-authoritative final-exit raid escalation layer owned by `EscapeService` and backed by deterministic shared logic in `Shared/GiantRealm/FinalExitState`. Managed final-exit routes now move through `Dormant -> Powered -> Opening -> Open -> Blocked -> Resolved`, activating only after the objective-threshold query reports ready, rejecting route escapes until the route is actually `Open`, resolving permanently after a successful route extraction, and exposing readable phase/timestamp attributes plus EscapeService query/debug snapshots. Direct route escape now also respects the shared safe-zone policy, rejecting SharedHub, RealmExit, and active RealmEntry protection with canonical reasons. Active traversal-gap blocks now interrupt final exits once the block reaches its active phase, pushing the route into `Blocked` and then deterministic reopening when the block window expires. Transport departures now resolve managed final-exit routes when the transport outcome includes a route id and at least one boarded Tinyfolk escapes. TIN-90 adds a bounded Tinyfolk-only route metadata layer: registered escape routes expose `TinyfolkOnlyRoute`, route access queries reject Giants and disabled/actively blocked routes, route-graph validation can opt into authored Tinyfolk-only metadata checks, and objective consumers can query redacted route metadata without exact Tinyfolk position or actor identity.

**Current implementation status:** TIN-217 adds bounded Giant remote-control station route pressure through `RemoteControlStationService` and deterministic shared logic in `Shared/GiantRealm/RemoteControlStationState`. The first slice is route-id based and authored-zone scoped: `GiantControlStation_A` can pressure valid Tinyfolk routes inside `GiantControlZone_A`, spends recoverable station energy, projects warning/active/expiry route attributes, rejects safe-zone protected routes, local traversal-block windows, block-exempt routes, stale/removed route records, and requests that would leave no eligible Tinyfolk route unpressured. `EscapeService` consumes the remote-barrier query seam so warning remains traversable and active remote barriers reject route access/escape with `remote_barrier_active`. Tinyfolk sabotage drains station energy and applies a temporary station lockout. Free camera placement, arbitrary wall placement, portable/emergency control mode, overclocking, persistence, full UI polish, and broad analytics remain deferred.

**Current implementation status:** TIN-215 Batch 2 adds a bounded player-created route ownership layer on `EscapeService` for existing authored routes only. `RequestUpsertPlayerCreatedRoute` now rejects final-exit-managed, fallback-candidate, and rescue-entry routes, rejects invalid marker metadata, and enforces owner-only updates. `RequestDisablePlayerCreatedRoute` enforces owner-only disable and rejects invalid marker metadata. `requestEscapeAttempt` now treats marker-invalid routes as `player_created_route_invalid`, marker-disabled routes as `route_disabled`, and marker-expired/future routes as `player_created_route_inactive`; non-player-created route behavior remains unchanged.

**Fold into this bucket:** escape node tier rules, route blocking checks, fallback cue behavior, final exit interruption logic, exit camp prevention rules.

### Realm Objective System
- Realm objective site discovery and registry
- Required completion threshold scaling
- Objective progress, interruption, disruption, regression, blocking, and rule-lock states
- Objective completion alerts and escape-readiness query surface

**Current implementation status:** TIN-153/TIN-154 now provide a bounded server-authoritative realm objective model owned by `RealmObjectiveService` and deterministic shared logic in `Shared/GiantRealm/RealmObjectiveState`. The service discovers objective sites from `Workspace.Map.Objectives`, tracks unresolved/completed sites, scales required completions by active Tinyfolk count, and exposes escape-readiness queries for `EscapeService`. Site-scoped objective state supports `idle`, `progressing`, `contested`, `regressing`, `blocked`, `rule_locked`, and `completed`, with deterministic progress application, retreat without progress erasure, Giant disruption, passive regression to a stabilization floor, capped major regression events, temporary blocks, and rule locks. Completion alerts expose objective/site progress and threshold counts without exact Tinyfolk positions.

**Fold into this bucket:** objective-site metadata, objective-state tuning, progress/disruption rules, temporary objective blocking, rule-lock reasons, objective completion alert shape.

### Capture and Containment System
- Carry state and grab mechanics
- Escape minigame progress (build, decay, reset rules)
- Containment structure rules (capacity, camera, rescue access)
- Anti-guarding pressure and counterplay outcomes
- Post-rescue protection state
- Maximum no-agency duration enforcement

**Current implementation status:** TIN-184 now includes a bounded server-authoritative nonlethal downed-state slice owned by `RoleService` and pure deterministic shared logic in `Shared/GiantRealm/DownedState`. Tinyfolk-only downed entry is source-validated, safe-zone aware, duration-bounded, and exposes readable debug/teammate attributes (`DownedState`, `DownedIsDowned`, self-recovery progress/cap, timing, source/reason). Self recovery is capped and cannot fully restore normal play in this slice. `EscapeService` rejects downed Tinyfolk escape attempts through a narrow query-API compatibility check. Expiration resolves to a safe nonlethal state, preventing indefinite helplessness. Full combat, carry/custody conversion, containment delivery, rescue contracts, HUD/VFX/audio polish, and persistence coupling remain explicitly out of scope for this slice.

**Current implementation status:** TIN-84 adds a bounded server-authoritative Giant grab/carry entry path owned by `GrabService`, backed by deterministic shared carried-state logic in `Shared/GiantRealm/GrabState`. Giant grabs validate caller/target roles, current carry state, character/root/humanoid health, range, cooldown, safe-zone protection, and Downed/SelfRecoveryCapped compatibility before setting readable carried attributes. Carried Tinyfolk cannot use escape/traversal interactions, can perform deterministic carried counterplay, and release when the counterplay threshold is reached. The physical carry primitive remains encapsulated behind server-owned immobilization helpers. Full custody, containment structures, rescue contracts, carry capacity/encumbrance, scoring rewards, follower/snapshot/ranged variants, protected post-release escape polish, HUD/VFX/audio, and persistence remain deferred.

**Current implementation status:** TIN-86 adds bounded server-authoritative carry load rules owned by `GrabService`, backed by deterministic shared carry-load logic in `Shared/GiantRealm/CarryLoadState`. The first slice defaults to one configurable carry slot, exposes readable carrier attributes for slots, capacity, encumbrance, speed multiplier, and overload state, applies movement speed pressure while carrying, rejects capacity-full grab attempts, restricts carrying Giants from free traversal-gap and through-gap interactions, and resolves releases through requested place, deterministic nearby drop candidates, or the validated pre-grab fallback. Multi-target physical carrying, containment delivery, custody duration, rescue contracts, scoring rewards, follower/ally transfer rules, and full physics ownership remain deferred.

**Current implementation status:** TIN-72 now has a bounded server-authoritative rescue-contract route/realm slice owned by `RescueContractService` and pure deterministic contract state in `Shared/GiantRealm/RescueContractState`. Contracts store rescuer, target, target Giant realm owner, rescue entry route id/kind, timing, and acceleration state. `RoleService` projects the active Giant realm owner id to players after a successful Giant realm profile load, and `EscapeService` owns the `ResolveRescueEntryRoute` query seam for matching safe rescue-entry routes. Completion keeps the existing local rescue flow and emits score-event metadata with target, realm, and route context. A bounded in-session rescue queue surface now exists through `Shared/GiantRealm/RescueContractQueueState` and service seams (`_RescueContractService_QueryAPI.GetRescueQueueEntries`, `_RescueContractService_QueryAPI.AcceptRescueQueueEntry`, and `_RescueContractHubSurface_QueryAPI.GetPendingRescueQueueEntries` / `AcceptRescueQueueEntry`) so hub-style consumers can list pending queue items and request acceptance through the same handoff-lock gate. Queue acceptance remains lock-gated by `_RescueHandoffService_QueryAPI.CreateHandoffLock` and does not bypass transfer coordination. Optional expiration callback contract is supported as `_RescueHandoffService_QueryAPI.OnRescueQueueExpired(payload)` when present; callback payload is bounded to queue entry id, captured user id, realm id, session id, reason, and timestamp, and queue expiry still succeeds if the callback is absent or faults. Bounded rescue queue durability is now implemented through deterministic save/apply persistence, restored-entry lifecycle handling (acceptance and expiry pruning), and collision-safe queue-entry id generation after restore. Reserved-server transfer execution, full containment/custody persistence, and teleport execution remain deferred.

**Fold into this bucket:** custody transfer rules, contained-player agency requirements, rescue acceleration, protection cancellation conditions.

### Warning, Tracking, and Stealth System
- Giant warning cue design (pressure, rough closeness — not exact location)
- Tinyfolk movement trail behavior (directional pressure — not wallhacks)
- Hiding and trail suppression rules
- Stealth must trade certainty for uncertainty, not create permanent safety
- Bounded and counterable hiding

**Current implementation status:** TIN-164 adds a bounded Giant proximity warning cue folded through the existing Tinyfolk status/fear pipeline. Runtime publishes only a coarse warning band (`none`, `watch`, `near`, `danger`) and HUD projection entries use redacted opposing-role privacy; exact Giant identity, exact distance, route progress, and location are not part of the cue contract. The warning clears when no alive Giant source is currently valid, even if fear exposure or panic recovery continues. TIN-223 adds bounded Giant staged threat progression through `Shared/TinyfolkStatus/GiantThreatStageLogic` and `TinyfolkStatusService`: raid threat stage escalates from warning pressure, decays one stage at a time on configured hold windows, and remains visibility-safe through coarse stage labels (`calm`, `watch`, `pressure`, `critical`) without exact tracking or automatic capture outcomes. A bounded movement-trail pressure slice is now folded through `TinyfolkStatusService` and deterministic shared logic in `Shared/TinyfolkStatus/TrailPressureLogic`: recent Tinyfolk movement is sampled with bounded distance/interval/history/lifetime rules, exposed only through read-only coarse directional snapshots, and suppressed for fresh sampling while `_TinyfolkHiding_QueryAPI` reports the Tinyfolk hidden. If the optional hiding query seam faults, trail sampling falls back deterministically to non-hidden behavior instead of failing the status tick. Trail/status state now clears deterministically for non-Tinyfolk role transitions and disconnected players, preventing stale trail carryover across role changes. `TinyfolkHidingService` now owns bounded hiding zones, timed hiding state, and reveal conditions for timeout and Giant proximity. Exact path replay, wall-penetrating reveals, persistent trail state, full Giant-facing HUD treatment, and stealth VFX/audio polish remain deferred.

Closure evidence for the 2026-05-22 timed-condition runtime seam fix is recorded in `docs/TINYFOLK_STATUS_REQUIRE_SEAM_CLOSURE_2026-05-22.md`.
Closure evidence for the 2026-05-22 Giant staged threat progression slice is recorded in `docs/TIN-223_GIANT_THREAT_STAGE_CLOSURE_2026-05-22.md`.

**Fold into this bucket:** trail decay rules, hiding zone rules, proximity alert tuning, stealth interaction with rescue protection.

### Score and Reward System
- Category-based score rules for Tinyfolk and Giants
- Data-driven score events
- Repeated-action depreciation and caps
- Anti-abuse detection (repeated targeting, custody duration, forced interaction patterns)
- Live score feedback

**Current implementation status:** TIN-65 adds bounded containment custody-end reward resolution through `ContainmentRewardResolver` and `CaptureService` integration, including deterministic diminishing returns for repeated Giant/Tinyfolk pair outcomes plus durable operation idempotency (`containmentRewardIdempotency`). Pair anti-farming history is currently maintained in resolver memory and is therefore scoped to a single active server instance. If product requirements call for cross-server anti-farming continuity, fold in a durable shared pair-history store (atomic read/merge/write keyed by Giant/Tinyfolk pair with bounded retention) and treat that as required scope for the reward slice.

### Event Log and Runtime Observability System
- Structured runtime event recording for simulation/debug readability
- Bounded event schema (`timestamp`, `category`, `message`, `severity`)
- Recent-event query surface for debug/UI consumers

**Current implementation status:** TIN-93 adds a bounded server-owned event-log surface backed by deterministic shared logic in `Shared/GiantRealm/EventLogState` and runtime service orchestration in `EventLogService`. Game systems can emit events through service seams, required event fields are validated deterministically, recent events are retained in a bounded window, and test harness/runtime query seams expose recent events and state snapshots for debug and UI-consumer paths. Final UI polish, analytics/history expansion, and durable event persistence remain deferred.

Closure evidence for the 2026-05-22 event-log slice is recorded in `docs/TIN-93_EVENT_LOG_CLOSURE_2026-05-22.md`.

**Current implementation status:** TIN-170 adds a bounded server-authoritative raid score event model owned by `ScoreService` and deterministic shared logic in `Shared/GiantRealm/ScoreState`. Score events are data-driven through `ScoreConfig`, with explicit role-scoped categories, reward buckets (`normal`, `bonus`, `hidden`, `compensation`), fixed or proportional value rules, repeat depreciation, repeat caps, normal-category caps, and display-safe feedback keys. Normal category totals remain the compatibility surface for existing score attributes, while bucket-separated totals keep tutorial, hidden, and compensation rewards from distorting normal session caps. Score event authoring is schema-validated at resolution time so malformed categories, buckets, value rules, point values, decay settings, repeat caps, or category/role pairings reject deterministically instead of silently awarding or bypassing caps. `ScoreService` keeps the existing remote/query request shapes, returns expanded score records, projects last-score feedback attributes, and exposes read-only category, bucket, and recent-event query surfaces. A lightweight client overlay now consumes the live score feedback attributes through `ScoreFeedbackClient`, and a session-end recognition overlay now consumes the projected final-exit attributes plus the live score snapshot through `SessionEndRecognitionClient`, while full HUD rendering, persistence of score ledgers, and broader analytics remain deferred.

**Fold into this bucket:** per-category score weights, decay curves, reward triggers for escape/containment/objective events.

### Realm Identity and Assembly System
- Chunk schema, socket compatibility, and assembly I/O contract
- World-space socket resolution
- Connection graph stitching and integrity checks
- Chunk footprint and occupied-space contract (bridge to district placement)
- Realm descriptor adapter (assembly → validator-ready descriptor)

**Current implementation status:** TIN-173 slices A-C now include a bounded assembly input contract validator in `Shared/RealmAssembly/RealmChunkAssemblySchema` (`ValidateAssemblyInputContract`) with deterministic rejection reasons for malformed chunk-library shape, placement identity collisions, missing chunk references, invalid transform metadata, malformed socket/content/occupied-space metadata, invalid structural enum fields, and invalid route-transition metadata. `DistrictPlacementService` consumes this contract at startup assembly-selection time and falls back to prototype input on invalid registry/config-derived payloads before building runtime assembly output. Assembly output now preserves world-space sockets, occupied-space boxes, structural chunk metadata, route-transition metadata, stitched connection graph integrity, and validator handoff data for downstream validators to inspect deterministically. Scope remains limited to schema/selection contract hardening and prototype descriptor handoff into existing topology validation; authoring tools, procedural generation, map-specific route-layout logic, parallel topology validation, and dynamic runtime assembly generation remain deferred.

**Fold into this bucket:** assembly validator rules, socket world-space math, chunk placement conventions.

### Realm Metadata and Theme Family System
- Realm metadata registry
- Theme family schema
- Palette, lighting, landmark, district, route, and audio vocabulary
- Accessibility and readability requirements tied to realm family identity

**Current implementation status:** TIN-178 now provides the canonical realm metadata registry and deterministic selection/lookup seams in `Shared/RealmAssembly/RealmMetadataRegistry`, and TIN-179 adds bounded theme-family schema authority in `Shared/RealmAssembly/RealmThemeFamilySchema` with deterministic cross-validation of metadata theme links (theme id, palette, lighting, audio, district vocabulary, landmark vocabulary, variant rules, and accessibility defaults). Metadata candidate selection now also supports bounded realm selection influence filters (theme id, district tag, and variant rule) in the same registry seam. Runtime consumption remains read-only through assembly selection seams; broad content-authoring tooling and expanded theme catalogs remain deferred.

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

**Persistence schema status:** Giant realm persistence now has an initial pure-Luau save schema plus deterministic serialization/validation helpers for accepted Giant structure records. A read-only live snapshot assembly surface builds and validates a schema-valid save root from accepted Giant build-mode structures, and a bounded apply surface replaces live accepted Giant build-mode state from a schema-valid save root. Migration upgrades remain deferred.

Closure evidence for the 2026-05-22 GiantBuild persistence hardening slice is recorded in `docs/TIN-228_GIANT_BUILD_PERSISTENCE_CLOSURE_2026-05-22.md`.

**Durable persistence ownership decision:** Durable Giant realm and player profile persistence is owned by a profile-locking persistence layer, reached through a thin server-only Tinyfolk compatibility gateway. Gameplay systems must not write directly to raw `DataStoreService`. Giant build mode remains the live-state owner and exposes snapshot/apply surfaces; it does not own durable profile sessions, autosave, load orchestration, or session locks.

**Profile persistence gateway status:** A server-only `ProfilePersistenceGateway` defines the Tinyfolk compatibility gateway boundary, typed success/failure result shape, and injected profile-locking owner-layer seam. The gateway itself does not import or call ProfileStore/ProfileService/raw DataStore persistence. Giant realm save/load handoff is limited to the existing `BuildSaveSnapshot` / `ApplySaveSnapshot` query API surface, with explicit release available for ending realm profile sessions.

**Profile owner-layer adapter status:** A server-only `ProfileStoreOwnerLayer` adapter defines the profile-locking owner-layer implementation behind `ProfilePersistenceGateway` for player profiles and Giant realm profiles, using an injected ProfileStore-shaped dependency. The adapter owns profile sessions, validates Giant realm save roots through `GiantRealmSaveSchema`, and does not wire gameplay services or call raw `DataStoreService` directly.

See `docs/PROFILE_OWNERSHIP_DECISION.md` for the full ownership decision record.

**ProfileStore dependency intake status:** ProfileStore is now vendored as pinned third-party server-only source under `ServerScriptService.Services.ThirdParty`, with source, license, pinned commit, retrieval date, and gameplay-access restriction recorded in `docs/THIRD_PARTY.md`. `ProfileStoreOwnerLayer.CreateDefault` constructs player-profile and Giant-realm owner adapters through the existing `Create` path using bounded default intake config only.

**Profile lifecycle wiring status:** A server-only `ProfilePersistenceLifecycle` bootstrap configures `ProfileStoreOwnerLayer.CreateDefault()` behind `ProfilePersistenceGateway` and owns player join, leave, and shutdown save/release calls through the gateway only. `RoleService` explicitly loads a Giant realm profile when a player locks in as Giant, then saves and releases that realm profile on player removal or shutdown. Gameplay services still do not depend on raw persistence details. A bounded lifecycle-owned autosave loop is now implemented with configurable interval and bounded retry/backoff policy over gateway save operations. Shrine persistence and rescue/handoff persistence are now implemented through the giant-realm save-root snapshot/apply handoff path. TIN-132 now adds teleport-aware profile ownership readiness projection (`_ProfilePersistenceLifecycle_QueryAPI`) and RoleService spawn deferral until ownership is valid. A bounded `ProfileTeleportHandoffService` now gates release-before-transfer, destination ownership confirmation, and safe fallback signaling without introducing direct gameplay DataStore ownership. Multi-realm support and schema migration remain deferred.

**Profile data consumption status:** `ProfilePersistenceGateway` exposes gameplay-safe loaded player profile data access and update entrypoints. Callers can read cloned snapshots and commit mutations only through the gateway update function; they cannot receive ProfileStore profile/session objects or mutate active profile data by reference. `RoleService` consumes this surface for role preference (`rolePreference.preferredRole`) and explicit Giant realm load/save/release, and `SpecialistAssignmentService` consumes this surface for specialist preference fields (`specialistPreference.specialistRole`, `specialistPreference.assignedStationId`, and `specialistPreference.lastAssignedAt`) while preserving existing specialist state-machine validation. These integrations restore valid stored preference values during setup and persist accepted gameplay transitions through gateway-owned persistence timing.

**TIN-174 state ownership model status:** A bounded deterministic contract now defines persistent-vs-session ownership partitions, write-back scope routing for capture/escape/defense/return outcomes, and reconnect restoration actions without introducing new save-pipeline behavior. The contract is implemented in `Shared/GiantRealm/EventStateOwnershipModel` with focused coverage in `tests/event_state_ownership_model.spec.luau`, and keeps player-profile ownership separate from giant-realm profile ownership and session-runtime projections.

### Ephemeral Cross-Server Coordination System
- MemoryStore structure policy for live realm registry, admission queue, party matchmaking queue, transfer locks, active realm capacity, rescue contract queue, and capture timers
- Deterministic structure names, key prefixes, key-part requirements, expiration policy, and payload-size caps
- Server-only MemoryStore adapter boundary; gameplay systems must not call raw `MemoryStoreService` directly
- Durable profile and Giant realm persistence remain ProfileStore-backed and separate from ephemeral MemoryStore coordination

**Current implementation status:** TIN-116 adds a pure server-side `MemoryStoreStructurePolicy` module that defines the first bounded MemoryStore structure/expiration policy without making live MemoryStore calls. The policy fixes structure names, structure kinds (`SortedMap`, `Queue`, `HashMap`), key prefixes, required key parts, per-structure TTLs, per-structure encoded payload caps, and platform guardrails for structure names, keys, expiration seconds, and value bytes. Runtime callers may request shorter TTLs, but cannot extend a record beyond the structure policy default. TIN-118 adds deterministic active-realm capacity state and an injected server-only capacity store boundary for the `activeRealmCapacity` hash-map policy. Capacity entries track realm id, live Tinyfolk/Giant occupancy, reserved Tinyfolk slots, max capacity, and update time; reservation, arrival commit, release, refresh, validation, and stale detection are tested without live MemoryStore calls. TIN-115 now adds the bounded server-only `MemoryStoreAdapter` runtime boundary plus `MemoryStoreAdapterService` seam publishing, so gameplay services can consume `MemoryStoreService` through validated queue/hash-map operations without calling the platform API directly. `ActiveRealmCapacityService` now resolves the published adapter seam and falls back to a default live adapter when available, and `RealmAdmissionQueueService` does the same for runtime admission queue processing. TIN-117 now includes the full bounded admission queue delivery path: runtime startup/bootstrap, enqueue/read/process query seams, transfer lock and party resolver seams, dispatcher member-resolution handoff, deterministic party-member lifecycle cleanup behavior, and first live producer enqueue wiring from rescue acceptance. TIN-229 hardens party admission target-realm resolution behind an explicit resolver seam, and TIN-230 adds bounded producer rollout through party-matchmaking producer normalization and profile handoff enqueue-edge rejection hardening. TIN-231 now extends that rollout with a second party-matchmaking ingress surface (`RequestPartyMatchAdmission`), migrates profile handoff admission ingress through the party-matchmaking query seam, and adds bounded queue-processing diagnostics via `RealmAdmissionQueueService.GetProcessingDiagnostics` with cumulative counters and cloned last-outcome snapshots. TIN-233 is now in progress with a concrete `RescueAdmissionService` query seam (`_RescueAdmissionService_QueryAPI`) that owns rescue-contract admission payload normalization and queue enqueue reason semantics through `AdmissionQueueProducer`; `RescueContractService` now consumes that seam as primary ingress with bounded producer fallback compatibility. TIN-233 now also adds concrete `ProfileTeleportAdmissionService` ingress normalization (`_ProfileTeleportAdmissionService_QueryAPI`) for handoff admission payload ownership, with `ProfileTeleportHandoffService` consuming that seam as primary ingress while retaining deterministic compatibility fallback to `RequestPartyMatchAdmission` when the primary seam is unavailable. `ProfileTeleportAdmissionService` now also exposes bounded enqueue diagnostics snapshots (`GetAdmissionDiagnostics`) so focused runtime coverage can assert service-local enqueue attempt-success-failure counters and last-reason parity with `ProfileTeleportHandoffService` primary ingress diagnostics on success and explicit rejection paths. Teleport handoff ingress observability parity now includes bounded primary/fallback attempt-success-failure counters plus deterministic last-path and last-reason snapshots through `ProfileTeleportHandoffService.GetAdmissionIngressDiagnostics`, with focused runtime coverage across primary success, fallback success, unavailable dependencies, and primary exception outcomes. Party admission observability parity now includes bounded resolver/enqueue diagnostics snapshots through `PartyMatchmakingAdmissionService.GetAdmissionDiagnostics`, covering resolver attempt-success-failure counters, direct-target fallback usage, enqueue attempt-success-failure counters, and deterministic last-path/last-reason snapshots for resolver and enqueue outcomes. Rescue ingress observability parity now extends `RescueContractService.GetAdmissionIngressDiagnostics` with total-attempt and per-path last-reason snapshots (`lastPrimaryReason`, `lastFallbackReason`), and focused runtime coverage now asserts deterministic cross-service reason consistency for rescue primary/fallback success and failure paths. `RescueAdmissionService` now also exposes bounded enqueue diagnostics snapshots (`GetAdmissionDiagnostics`) so focused runtime coverage can assert service-local enqueue attempt-success-failure counters plus last-reason parity against `RescueContractService` primary ingress outcomes. TIN-233 scheduler telemetry hardening now extends queue diagnostics with process-loop schedule/tick attempt-success-failure counters plus bounded last schedule/tick timestamps and last error reason snapshots, with focused runtime coverage for both successful cadence and schedule-failure paths. Runtime behavior remains covered by focused admission/dispatcher/lock/rescue/runtime handoff specs with deterministic unavailable-dependency reasons and bounded enqueue rejection handling. Rescue queue durability is now implemented through the rescue persistence/query seams, and bounded MessagingService notification fanout is now implemented through `QueueNotificationFanout` plus non-blocking queue lifecycle publish hooks in admission and rescue services.

Closure evidence for the full TIN-117 delivery continuity is recorded in `docs/TIN-117_REALM_ADMISSION_QUEUE_CLOSURE_2026-05-25.md`.
TIN-230 closure evidence is recorded in `docs/TIN-230_PRODUCER_ROLLOUT_CLOSURE_2026-05-30.md`.
TIN-231 closure evidence is recorded in `docs/TIN-231_PRODUCER_ROLLOUT_SCHEDULER_CLOSURE_2026-05-30.md`.
TIN-233 active follow-up kickoff is recorded in `docs/TIN-233_INGRESS_ROLLOUT_SCHEDULER_HARDENING_KICKOFF_2026-05-30.md`.

### Trait and Loadout Framework
- Role-shaped loadout slots (intentionally capped)
- Data-driven trait definitions
- Starter/common trait teach-first ordering
- Tier tuning: bounded value adjustment, not core rule override
- Shared registry/schema for traits, cooldowns, tokens, active abilities, anti-abuse rules

**Current implementation status:** TIN-187 adds a narrow post-crossing Tinyfolk movement trait slice, not a full trait/loadout framework. A server-owned `TinyfolkMovementTraitService` consumes accepted route-crossing hooks and applies a bounded, cooldown-gated speed burst only when `TinyfolkTrait_PostCrossingBurst` is enabled. The first valid crossing hook is the accepted `EscapeService` route crossing path. The slice exposes debug/trace attributes for readability; full trail rendering, animation/audio, rescue/adjacent burst systems, and traversal-gap runtime remain deferred.

**Fold into this bucket:** trait effect definitions, cooldown schema, token schemas, ability registry entries.

### Economy and Labor System
- Specialist role assignment (Woodcutter, Miner, Worshipper, None)
- Produced → InTransit → Stored resource flow
- Station interaction and hauling flow
- Essence generation (Shrine → Giant session pool)
- Construction spending from stored totals only
- Warehouse delivery point
- Server-owned Tinyfolk inventory and minimal crafting input/output

**Current implementation status:** TIN-22 adds a bounded server-owned Tinyfolk inventory and crafting foundation through deterministic shared logic in `Shared/InventoryCraft/InventoryCraftState`, config authority in `Shared/Config/InventoryCraftConfig`, and runtime orchestration in `InventoryCraftService`. Inventory is session-only (no persistence), supports a small material/crafted item catalog plus two starter recipes, rejects non-Tinyfolk craft requests, clears inventory on role change away from Tinyfolk, and exposes query/debug surfaces through `_InventoryCraftService_QueryAPI` and inventory debug remotes/attributes. Full item variety, final UX polish, persistence, and specialist-visual equip coupling remain deferred.

**Current implementation status:** TIN-40 expands the canonical inventory craft catalog to six recipes and twelve items, including craft-chain recipes that consume prior crafted outputs (`rope_anchor`, `field_kit`, `spike_wedge`), crafted-item consumption flow (`ConsumeItems`), craftable-recipe listing (`ListCraftableRecipes`), catalog cross-validation helpers, and debug snapshot/attribute exposure for craftable recipe counts. Public query API craft paths remain canonical-catalog guarded. Final UX polish, persistence, labor/resource-flow item grants, and specialist-visual equip coupling remain deferred.

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

## VHS Mechanics Analysis and Translation Framework

To identify design patterns and establish boundaries for future mechanics, we surveyed core systems from *Video Horror Society* (VHS) and mapped them to Tinyfolk candidates. This section documents the framework for future backlog reconciliation.

### VHS Mechanics Categories

VHS provides nine core mechanic categories with distinct triggers, actors, constraints, and failure modes:

| VHS Mechanic | Description | Tinyfolk Candidate | Bucket(s) | Classification | Priority |
|---|---|---|---|---|---|
| **Maneuvers** | Movement actions (walk, run, sprint, crouch, vault, climb) | Bounded Sprint/Stamina | Escape/Movement (TIN-81) | FOLD_INTO_EXISTING | High |
| **Actions** | Interactive object usage (doors, phones, items, traps) | Contextual Tasks | Objectives (TIN-153/154) | FOLD_INTO_EXISTING | High |
| **Skill Checks** | Timed mini-games (QTEs, single-tap, rapid-press, timing-bar) | Timed Task QTE | Objectives (TIN-154) | FOLD_INTO_EXISTING | Medium |
| **Status Effects** | Conditions altering state (Fear, Panic, Bleed, Stun, Flux) | Timed Condition States | Status/HUD (TIN-165/164) | FOLD_INTO_EXISTING | High |
| **Stigmas** | Monster health/immunities (weapon-type based damage layers) | Banishment Meter | (Not directly applicable) | ALREADY_REPRESENTED | Low |
| **Perks** | Player buffs (pre-match stat bonuses, ability loadouts, multi-level) | Role Perk Loadouts | Loadout (TIN-171) | ALREADY_REPRESENTED | Low |
| **Teleport/Shift** | Monster mobility (short-range dash, terrain traversal) | Dash Maneuver | Block/Movement (TIN-185) | FOLD_INTO_EXISTING | Medium |
| **Traps/Snares** | Monster deployable hazards (immobilization, instant defeat) | Temporary Snare Traps | Snare System (TIN-216) | ALREADY_REPRESENTED | Medium |
| **Communication** | Reinforcement call (radio spawn ally, one-time use) | Emergency Reinforcement | Rescue Contracts (TIN-72) | NEW_ISSUE_CANDIDATE | High |

### Fold-Into-Existing Mechanics (6 candidates)

These mechanics extend existing Tinyfolk buckets without introducing new system boundaries:

1. **Bounded Sprint/Stamina (TIN-81):** VHS stamina depletion on sprint and noise from running translate directly to Tinyfolk movement rules. Fold in by adding a stamina gauge that depletes on sprint, exhaustion causes a "breathless" state, and UI cue (radial stamina bar above hotbar, red when low).

**Current implementation status:** TIN-81 now has a bounded server-authoritative sprint/stamina slice owned by `TinyfolkMovementTraitService`, backed by pure deterministic shared logic in `Shared/TinyfolkMovement/SprintStaminaLogic`. Sprint requests drain stamina over time, exhaustion blocks sprint until recovery, and the service exposes readable sprint attributes for stamina, active/requested state, exhaustion, breathlessness, recovery threshold, and speed multiplier. Full HUD treatment, hold-to-sprint input polish, and any broader locomotion rewrite remain deferred.

2. **Contextual Tasks (TIN-153/154):** VHS object interactions (press key, progress meter, interrupt resets progress) map to Tinyfolk objective framework. Reuse objective nodes for door-opening, item pickups; add progress bars, noise-on-failure alerts, and allow cancellation.

**Current implementation status:** TIN-153 now has a bounded server-authoritative contextual-task slice backed by deterministic shared logic in `Shared/Construction/ContextualTaskProgressLogic`, with parity integrated across `ConstructionService`, `StationService`, and `ShrineService`. Interaction routing supports hold-to-interact begin/cancel/complete for construction, station activation, and shrine activation; task state is shared per objective id (not per player); cancel bypasses request cooldown for input-release reliability; and readable task attributes expose active objective id, progress ratio/seconds, objective state, regression count, and regressing window. TIN-154 objective-state transitions (`idle`, `progressing`, `regressing`, `contested`, `blocked`, `completed`) plus passive regression windows, stabilization threshold floor, and capped major regression events are now folded into these bounded objective interactions. TIN-154 also now includes a bounded optional single-tap QTE completion window with deterministic success bonus/failure disruption behavior and readable per-task QTE result attributes. TIN-165/164 now has a bounded server-owned status-state slice backed by deterministic shared logic in `Shared/TinyfolkStatus/TimedConditionStateLogic` and refreshed through `TinyfolkStatusService`, with fear exposure/panic derived from nearby Giant proximity plus readable bleed/stun/flux timers and summary attributes. TIN-165 adds a deterministic HUD projection layer in `Shared/TinyfolkStatus/RaidStatusProjection` plus client-facing `TinyfolkRaidHud*` attributes, and the Tinyfolk raid HUD renderer now consumes those attributes through `TinyfolkRaidHudClient`. The projection taxonomy covers personal effects, teammate activity, custody/capture/downed/escape state, coarse threat cues, and score feedback. Visibility is intentionally lossy: opposing-role actor ids and exact hidden Giant progress are redacted from HUD summaries, while Tinyfolk teammate ids may appear for team activity. Broader HUD visual polish and unrelated UI widget layout remain deferred.

3. **Timed Task QTE (TIN-154):** VHS skill checks (single-tap, rapid-press, timing-bar windows) extend TIN-154 as optional layers on interactive actions. Offer bonus speed on success, noise penalty on failure. Visual: moving target bar with success zone; failed attempt shakes screen edge.

4. **Timed Condition States (TIN-165/164):** VHS conditions (Fear rising near monster, Bleed from weapons, Stun from traps) fold into Tinyfolk status effects. Add "Exposure meter" for proximity feedback, panic triggers (e.g. scream attract allies), effect icons (heart for bleed, face for fear). Example UI: pulsating overlay or vignette when fear is high.

5. **Dash Maneuver (TIN-185):** VHS monster dash/teleport maps to Giant phase mobility as a grounded shockwave-landing move with clear travel-time arc. Use gap-block state for temporary traversal denial. Visual: ghost trajectory line or flashing footprints during dash.

6. **Temporary Snare Traps (TIN-216):** VHS trap mechanics (place -> trigger -> immobilize -> rescue/timeout) fold into the existing Giant build and Tinyfolk timed-condition paths. Current scope is runtime-only, server-authoritative, non-persistent, and nonlethal: traps reuse `stun`, emit coarse event-log alerts, and rely on protected-anchor anti-camp validation rather than a new client alert or map-zone subsystem.

### Already-Represented Mechanics (2 candidates)

These mechanics are already covered by existing Tinyfolk systems and require no new issues:

1. **Banishment Meter (Stigmas):** VHS stigma removal (weapon-type layers depleting monster health) applies only if Tinyfolk had boss-fight mechanics. Given Tinyfolk's escape-focused design, stigmas are not directly needed. If a future monster-escort win condition emerges, reuse multi-charge health system concepts.

2. **Role Perk Loadouts (Perks):** VHS perk slots (pre-match stat bonuses, multi-level, point budget) map exactly to Tinyfolk TIN-171 loadout framework. Role-specific ability traits (Vault Expert, Sprint Specialist) already exist. No changes to core system needed.

### New Issue Candidate (1 candidate)

1. **Emergency Reinforcement (Communication):** VHS Tommy Jarvis radio call spawns a powerful ally mid-match under player control. Tinyfolk candidate: a one-time summoned Tinyfolk hero (Private or Army ally with defined loadout) enters mid-match if team is reduced. Classification: **NEW_ISSUE_CANDIDATE**, scope requires: (a) deterministic spawn logic, (b) cooldown on use (valid only if <X Tinyfolk remain), (c) summoned ally initialization with role/traits, (d) "call center" objective token trigger, (e) HUD radio icon and countdown. Acceptance: fairness tuning for team-size reduction thresholds, anti-snowball safeguards. Ties to TIN-72 (Rescue Contracts) if rescue-contract allies are merged with reinforcement-call allies. **Priority: High novelty** (adds strategy depth) but implement with clear fairness boundaries.

**Current implementation status:** Slice A, Slice B pass 1, Slice B pass 2, Slice C pass 1, Slice C pass 2 lifecycle coupling, and follow-up giant-realm persistence are now implemented and test-backed. `Shared/GiantRealm/EmergencyReinforcementState` owns deterministic eligibility and one-time-use transition rules; `EmergencyReinforcementService` owns runtime orchestration, objective-range/spawn/candidate probing, player initialization, and bounded persistence export/apply of reinforcement call state. Runtime boundary hardening now enforces stable request/query payload contracts and deterministic failure handling (`state_transition_failed`) even under injected transition faults. Readiness precedence is now explicitly test-backed and ordered as: missing objective → missing spawn → protected spawn → missing candidate. Slice C pass 1 adds objective token consume seam integration via `_G._RealmObjectiveService_QueryAPI.RequestConsumeEmergencyToken`, called after state transition succeeds but before spawn init. Objective-token APIs are now required for reinforcement token handshake; missing token APIs reject deterministically as `objective_token_api_unavailable` (no permissive consume fallback). Token consume rejection is exception-safe (wrapped in pcall) and does NOT consume the one-time-use; token consume must succeed before state is persisted. Token reject then request cooldown applies via reject-cooldown gate; one-time-use remains available for retry. Token-stage rejection reasons are now also projected into reinforcement snapshot state (`snapshot.lastReason` and `snapshot.lastObjectiveId`) so callers and diagnostics retain deterministic failure parity across snapshot/consume gate failures. Token accept then spawn failure returns "reinforcement_spawn_failed" for compensation-trace scenarios. Compensation-trace test validates token-consumed-then-spawn-failed path and one-time-use preservation on token rejection. Slice C pass 2 adds a pre-consume `_RealmObjectiveService_QueryAPI.GetEmergencyTokenSnapshot` lifecycle gate that deterministically rejects revoked/exhausted tokens, lifecycle-inactive snapshots, next-available timing gates, expired windows, and out-of-schedule windows while preventing consume calls when snapshot gating fails. A bounded client HUD slice now renders radio reinforcement readiness and cooldown countdown from existing response/snapshot contracts and the debug snapshot remote. Giant-realm persistence now flows through `GiantRealmSaveSchema`, `GiantBuildModeService.BuildSaveSnapshot` / `ApplySaveSnapshot`, `ProfilePersistenceGateway`, and ProfileStore-backed giant realm sessions, so one-time-use reinforcement state restores through the same giant-realm owner path instead of player-profile data.

Closure evidence for the 2026-05-30 Emergency Reinforcement closure is recorded in `docs/TIN-226_EMERGENCY_REINFORCEMENT_CLOSURE_2026-05-30.md`.

### Fold-In Implementation Guidance

When folding mechanics into existing issues:

1. **Do not expand scope:** A fold-in is a parameter tweak, UI detail, or example for an existing system—not a new module or test file.
2. **Validate bucket boundaries:** Ensure the candidate does not cross a clear implementation boundary (e.g., Skill Checks are UI-layer QTE details on Objectives, not a separate system).
3. **Reference the VHS pattern:** Use VHS triggers, constraints, and failure modes as concrete examples to clarify acceptance criteria.
4. **Test surface remains unchanged:** Fold-in candidates should not require new test files; they extend existing test suites with additional cases.

### When to Create a New Issue

Create a new issue only for Emergency Reinforcement or future mechanics that:

1. Introduce a new durable implementation surface (new module, schema, or persistent state).
2. Cross a clear system boundary that cannot merge without scope expansion.
3. Require test files or query API surfaces not already present in existing buckets.

For all other candidates, default to folding in.

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
