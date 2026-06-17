# TIN-121 Rescue Contract Queue - Closure

**Date:** 2026-06-17  
**Issue:** [TIN-121](https://linear.app/spectranoir/issue/TIN-121/implement-rescue-contract-queue)  
**Milestone:** Admission and Queueing  
**Status:** Draft closure package (Studio evidence follow-up documented below)
**Linear status sync:** Issue is `Done`; comment posted (`63ea0ec0-0ba0-478b-bece-822f1b9e09be`).

## Shipped

- **Cross-server rescue queue path:** Added `RescueContractQueueStore` and `RescueContractQueueService` for enqueue, reconcile ingest, and explicit receipt cleanup.
- **Authoritative rescue integration:** `RescueContractService` publishes queue entries for eligible rescue requests, reconciles external entries, and handles accept/expiry resolution with idempotency guards.
- **Hub board server surface:** `RescueContractHubService` exposes list/accept remotes with Tinyfolk role and hub-activity gating.
- **Client + interaction path:** `RescueContractClient` renders board list/accept UI and `InteractionResolver` opens the panel via F-key around `RescueContractBoardHub_*` anchors.
- **Map + reconciliation support:** `TinyfolkWorld` includes `RescueContractBoardHub_A`; `NotificationReconciliationService.ReconcileRescueQueue` refreshes authoritative queue visibility before fanout hints.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/rescue_contract_hub_service_runtime_entrypoint.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
```

Local rerun on 2026-06-17: all commands passed.

## Acceptance mapping

| Criterion | Status | Implementation |
|---|---|---|
| Captured Tinyfolk generates queue item | PASS | `RescueContractService.requestRescueContract` -> queue publish path |
| Queue item includes required fields | PASS | `RescueContractQueueState.QueueEntry` validation + publish payload |
| Hub server surfaces eligible contracts | PASS | `RescueContractHubService` list request + `RescueContractHubState.ProjectContracts` |
| Accept creates handoff lock and resolves queue item | PASS | `acceptRescueQueueEntry` handoff + admission enqueue + queue mark/remove |
| Expired contracts resolve safely | PASS | `PruneExpired` + safe non-pending rejection behavior on stale accepts |

## Risk notes and boundary outcomes

- **Contract expiry vs accept race with capture state:** Accept flow re-checks pending status after lock and rejects stale rows (`queue_entry_not_pending`), covering race-like windows without duplicating queue side effects.
- **Multi-hub queue visibility:** Queue behavior remains ephemeral and reconcile/fanout-based; this slice does not introduce durable cross-server party state.

## Deferred

- Published-client multi-server spot-check for hub-to-hub queue visibility remains a validation follow-up.
- Cross-server party persistence remains out of scope for TIN-121.
- Rich board/matchmaking UX tuning remains deferred.

## Studio evidence follow-up

- Evidence runbook: `docs/TIN-121_RESCUE_CONTRACT_HUB_FKEY_STUDIO_EVIDENCE_2026-06-17.md`
- Keep this closure draft aligned with evidence outcomes (pass/fail table and final notes).

## Linear comment

- Posted to TIN-121 on 2026-06-17.
- Comment id: `63ea0ec0-0ba0-478b-bece-822f1b9e09be`
- Issue: https://linear.app/spectranoir/issue/TIN-121/implement-rescue-contract-queue

### Posted content

TIN-121 rescue contract queue shipped with hub board integration.

**What shipped**
- Added MemoryStore-backed rescue queue publish/reconcile/remove flow (`RescueContractQueueStore`, `RescueContractQueueService`).
- Wired `RescueContractService` queue publish + accept/expiry resolution with idempotency/handoff safeguards.
- Added rescue board list/accept remotes and client panel with F-key open path at `RescueContractBoardHub_*` anchors.
- Extended rescue queue reconciliation fanout path for authoritative refresh before notify hints.

**Validation**
- `.\scripts\run-validation.ps1 -ChangedOnly`
- `lune run tests/rescue_contract_hub_service_runtime_entrypoint.spec.luau`
- `lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau`

**Evidence**
- Kickoff: `docs/TIN-121_RESCUE_CONTRACT_QUEUE_KICKOFF_2026-06-17.md`
- Closure: `docs/TIN-121_RESCUE_CONTRACT_QUEUE_CLOSURE_2026-06-17.md`
- Studio evidence: `docs/TIN-121_RESCUE_CONTRACT_HUB_FKEY_STUDIO_EVIDENCE_2026-06-17.md`
- PR: https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/120
