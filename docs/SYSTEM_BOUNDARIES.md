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

**Current implementation status:** Runtime validation gate is implemented and test-backed. Validator blocks placement before any registry mutation. Workspace world-content creation is deferred to future work.

**Fold into this bucket:** zone separation checks, cluster density caps, total caps, spatial constraint rules derived from GAME_SPEC.

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
