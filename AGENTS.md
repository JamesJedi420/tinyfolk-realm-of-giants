# AGENTS.md — Tinyfolk: Realm of Giants

Read this file before starting implementation, review, harvest, or validation work in this repository.

## Identity

- **Project name:** Tinyfolk: Realm of Giants
- **Do not** refer to this repository as Containment Protocol.
- **Status:** prototype-scale Roblox game (Luau, Rojo, Lune tests)

## Required reads (in order)

1. `docs/GAME_SPEC.md` — design direction; separate **current prototype** from **long-term direction**
2. `docs/AGENT_RULES.md` — implementation guardrails, audit workflow, naming, economy/labor consistency
3. `docs/SYSTEM_BOUNDARIES.md` — canonical system buckets; fold-in vs new-issue guidance
4. Active slice docs — `docs/TIN-*` kickoff/closure/evidence for the issue you are working

Use slice docs and tests as durable context instead of re-explaining completed work in chat.

## Repository layout

| Path | Purpose |
|------|---------|
| `src/ReplicatedStorage/Shared/` | Pure deterministic logic, configs, topology validators |
| `src/ServerScriptService/Services/` | Server-authoritative services (`.server.luau` bootstraps) |
| `src/StarterPlayer/StarterPlayerScripts/Client/` | Client projection scripts |
| `src/Workspace/Map/` | Authored map as `Layout.model.json` folders |
| `tests/` | Lune specs (`*.spec.luau`); `tests/harness/`, `tests/mocks/` |
| `scripts/` | `run-validation.ps1`, `run-tests.ps1` |
| `default.project.json` | Canonical Rojo project file |

Generated artifacts (`sourcemap.json`, `TinyfolkRealmOfGiants.rbxlx`) are build output, not primary source.

## Architecture conventions

- **Server-authoritative** gameplay: role, interaction, escape, capture, scoring, resources.
- **Deterministic shared state** in `Shared/`; services orchestrate and expose `_ServiceName_QueryAPI` seams.
- **Bounded vertical slices** — implement only what the active issue contract requires.
- **Interaction key:** context-sensitive `F`; resolve by priority, then distance, then target id.
- **Persistence:** `ProfilePersistenceGateway` → `ProfileStoreOwnerLayer` (see `docs/PROFILE_OWNERSHIP_DECISION.md`).

## Validation (run before claiming done)

From repo root:

```powershell
.\scripts\run-validation.ps1 -ChangedOnly   # StyLua + Selene + luau-lsp on touched files
lune run tests/<relevant>.spec.luau           # most specific test first
.\scripts\run-tests.ps1                     # full suite when appropriate
```

Details and focused regression groups: `docs/TESTING.md`.

Studio build: `docs/ROJO_WORKFLOW.md`

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

If validation cannot run, state the exact command, why, and what remains unverified.

## Implementation session workflow

1. **Scope** — read the active TIN/slice issue, related `docs/TIN-*` files, and affected code/tests.
2. **Boundary** — identify the smallest correct change; do not expand scope or add speculative frameworks.
3. **Implement** — match existing patterns (naming, query APIs, shared-state modules, test fixtures).
4. **Test** — add or extend specs for changed behavior; prefer pure logic tests for `Shared/` modules.
5. **Audit** — follow the post-implementation checks in `docs/AGENT_RULES.md` (scope, edge cases, determinism, regression, docs).
6. **Document** — update slice kickoff/closure/evidence docs when the issue contract requires it.
7. **Ship** — always complete the mandatory loop in `.cursor/rules/pr-ship-workflow.mdc`:
   - commit on a slice branch
   - open PR against `master`
   - **always** babysit PR until CI is green (fix failures, re-push, repeat)
   - **always** merge when CI is green and slice criteria are met
   - **always** add a Linear comment (what shipped + validation + PR link)
   - move Linear issue to **Done** only when the full issue boundary is satisfied
   - checkout `master`, pull, plan next implementation (no coding)

Default branch: `master`.

## Issue tracking

Work is tracked as **TIN-###** issues with matching `docs/TIN-*` kickoff, evidence, and closure records. Link PRs and closure comments to the active issue when applicable.

## Policy-sensitive terminology

Use game-system terms: capture, containment, custody, rescue, escape, release, timeout, safe return. Avoid framing Tinyfolk as owned property or implying slavery, trafficking, or indefinite loss of agency. Containment/custody text must expose an escape, rescue, release, timeout, or safe-return path.

## Visual / map work

For environment concepts or map asset edits, use `docs/VISUAL_BIBLE_TEMPLATE.md` and report explicit PASS/FAIL per template checks.

## Where to go deeper

| Topic | Doc / location |
|-------|----------------|
| Game design rules | `docs/GAME_SPEC.md` |
| System ownership | `docs/SYSTEM_BOUNDARIES.md` |
| Agent guardrails | `docs/AGENT_RULES.md` |
| Testing | `docs/TESTING.md` |
| Rojo / Studio | `docs/ROJO_WORKFLOW.md` |
| Persistence | `docs/PROFILE_OWNERSHIP_DECISION.md` |
| Third-party deps | `docs/THIRD_PARTY.md` |
