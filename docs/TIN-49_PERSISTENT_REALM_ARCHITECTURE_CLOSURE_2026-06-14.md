# TIN-49 Persistent Realm Architecture Closure (2026-06-14)

## Shipped

- Canonical architecture record: `docs/TIN-49_PERSISTENT_REALM_ARCHITECTURE.md`
- Kickoff record: `docs/TIN-49_PERSISTENT_REALM_ARCHITECTURE_KICKOFF_2026-06-14.md`
- `docs/SYSTEM_BOUNDARIES.md` status pointer for TIN-49 architecture contract

## Architecture deliverables

- Defined shared Tinyfolk hub vs Giant personal realm server categories and spawn defaults.
- Defined durable identity keys (`PlayerProfile:{userId}`, `GiantRealmProfile:{ownerUserId}`, `giant_realm_{ownerUserId}`).
- Defined four persistence tiers: player profile, realm profile, ephemeral coordination, session runtime.
- Defined player-profile vs realm-profile ownership split aligned with `EventStateOwnershipModel` and `GiantRealmSaveSchema`.
- Defined controlled transfer pipeline shell and TeleportData security constraints for downstream TIN-106.
- Defined player `locationCategory` model (`shared_hub`, `giant_realm`, `transfer_in_flight`) with current field mapping and TIN-11 consolidation note.
- Documented downstream handoff boundaries for TIN-11, TIN-106, and TIN-241.

## Acceptance criteria review

| Criterion | Result | Evidence |
|---|---|---|
| Tinyfolk spawn into shared public server | PASS | Architecture § Server categories, § Player location category |
| Each Giant has a persistent personal realm profile | PASS | Architecture § Identity and keys, § Durable Giant realm profile |
| Realm state is separate from player profile state | PASS | Architecture § Persistence tiers, § Player profile vs realm profile |
| Tinyfolk enter a Giant realm through controlled transfer | PASS | Architecture § Controlled transfer architecture |
| Global state records current player location category | PASS | Architecture § Player location category |

## Validation

Doc/review gate only (no runtime tests required for this slice).

- Reviewed architecture doc against TIN-49 Linear acceptance criteria — all PASS.
- Cross-checked namespace ownership against `EventStateOwnershipModel` and gateway profile field list.
- Cross-checked coordination structures against `MemoryStoreStructurePolicy`.
- Confirmed no implementation scope leaked into TIN-11/TIN-106 boundaries.

## Out of scope (unchanged)

- Cross-server transfer runtime implementation.
- `realmAssignment` state machine (TIN-11).
- Handoff tokens and durable realm session records (TIN-106).
- Full matchmaking or profile-pipeline rework.

## Downstream handoff

Next implementation slices should read `docs/TIN-49_PERSISTENT_REALM_ARCHITECTURE.md` before starting:

1. **TIN-11** — server-owned `realmAssignment` state, validated transfer transitions, debug surfaces.
2. **TIN-106** — handoff tokens, durable realm session record keyed by `realmId`, lock consume on arrival.
