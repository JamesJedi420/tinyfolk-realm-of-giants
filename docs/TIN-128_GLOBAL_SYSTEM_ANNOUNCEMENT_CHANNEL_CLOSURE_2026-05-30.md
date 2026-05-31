# TIN-128 Global System Announcement Channel Closure (2026-05-30)

## Issue
- ID: TIN-128
- Title: Global system announcement channel
- Date Closed: 2026-05-30
- Owner: James Dye
- Branch/PR: master (local-only)

## Summary
- Delivered a bounded global system announcement channel across schema, publish fanout, subscription defaults, reconciliation routing, and rate-guard burst hardening.
- Added a server-owned announcement service seam with deterministic validation/reason contracts and read-only query surfaces.
- Added minimal client projection and lightweight banner rendering via player attributes (no heavyweight UI surface).
- Extended focused runtime/spec coverage and verified full-suite regression safety.

## Root Cause / Motivation
- Notification infrastructure had matured (schema, adapter, subscriptions, reconciliation, rate guarding), but there was no dedicated global announcement delivery path.
- Operational/system-wide notices needed a bounded, deterministic channel without expanding into broad UI/ops platform scope.

## Scope Delivered (Batch Rollup)

### Batch 1: Contract + Owner Service
- Added announcement topic key and mapping in notification schema.
- Added server-owned `SystemAnnouncementService` query seam with deterministic request validation, active-window evaluation, and diagnostics.
- Added focused runtime spec and test-suite wiring.

### Batch 2: Fanout + Subscription + Reconciliation
- Added announcement publish path to queue notification fanout.
- Added announcement topic to default subscription set.
- Added announcement channel routing + reconcile surface to notification reconciliation service, including diagnostics counters and `HandleNotification` routing.
- Extended focused specs for fanout/subscription/reconciliation parity.

### Batch 3: Client Projection + Rate-Guard Hardening
- Added server-to-client announcement projection via bounded player attributes.
- Added minimal client announcement banner (`SystemAnnouncementClient`) consuming projected attributes.
- Hardened notification rate guard for burst announcement traffic (`announcement_*`) using coalesced outcomes and deterministic summary payloads.
- Added focused spec coverage for projection and burst coalescing diagnostics parity.

## Implementation Evidence
- `src/ServerScriptService/Services/NotificationMessageSchema.luau`
  - Added topic mapping: `systemAnnouncement -> tin_announcement_v1`.
- `src/ServerScriptService/Services/SystemAnnouncementService.server.luau`
  - Added query APIs:
    - `PublishAnnouncement`
    - `ClearAnnouncement`
    - `GetActiveAnnouncement`
    - `GetAnnouncementDiagnostics`
  - Added deterministic reason taxonomy for invalid request/window/ids and not-found/not-active paths.
  - Added projection update behavior for announcement attributes on publish/clear.
- `src/ServerScriptService/Services/QueueNotificationFanout.luau`
  - Added `PublishSystemAnnouncement(eventName, payload)`.
- `src/ServerScriptService/Services/NotificationSubscriptionManager.luau`
  - Added announcement topic to default subscriptions.
- `src/ServerScriptService/Services/NotificationReconciliationService.luau`
  - Added `systemAnnouncement` channel diagnostics bucket.
  - Added `ReconcileSystemAnnouncement` and `HandleNotification` routing for `announcement_*`.
  - Added announcement channel into `ReconcileAll` aggregate.
- `src/ServerScriptService/Services/NotificationRateGuard.luau`
  - Added coalescing support for `announcement_*` burst traffic.
  - Added deterministic `announcement_summary` coalesced summary type.
  - Added `announcementId` extraction and diagnostics parity field (`lastAnnouncementId`).
- `src/StarterPlayer/StarterPlayerScripts/Client/SystemAnnouncementClient.client.luau`
  - Added minimal client banner projection consumer and display logic.

## Test Evidence
- Updated/added focused specs:
  - `tests/notification_message_schema.spec.luau`
  - `tests/system_announcement_service_runtime_entrypoint.spec.luau`
  - `tests/queue_notification_fanout.spec.luau`
  - `tests/notification_subscription_manager.spec.luau`
  - `tests/notification_reconciliation_service.spec.luau`
  - `tests/notification_rate_guard.spec.luau`
- Suite wiring:
  - `scripts/run-tests.ps1` includes `tests/system_announcement_service_runtime_entrypoint.spec.luau`.

## Validation Evidence

### Focused Runtime/Seam Coverage
- `lune run tests/notification_message_schema.spec.luau` -> pass
- `lune run tests/system_announcement_service_runtime_entrypoint.spec.luau` -> pass
- `lune run tests/queue_notification_fanout.spec.luau` -> pass
- `lune run tests/notification_subscription_manager.spec.luau` -> pass
- `lune run tests/notification_reconciliation_service.spec.luau` -> pass
- `lune run tests/notification_rate_guard.spec.luau` -> pass

### Changed-file Validation Gate
- `./scripts/run-validation.ps1 -ChangedOnly` -> pass
  - `stylua` pass
  - `selene` pass (warning-only, non-blocking)
  - `luau-lsp` pass

### Full Regression Suite
- `./scripts/run-tests.ps1` -> pass
- Relevant explicit pass lines include:
  - `messaging_service_adapter: all checks passed`
  - `notification_rate_guard: all checks passed`
  - `notification_message_schema: all checks passed`
  - `notification_reconciliation_service: all checks passed`
  - `notification_subscription_manager: all checks passed`
  - `queue_notification_fanout: all checks passed`
  - `system_announcement_service_runtime_entrypoint: all checks passed`
  - `headless_match_simulation: all checks passed`

## Supporting Docs
- Kickoff plan: `docs/TIN-128_GLOBAL_SYSTEM_ANNOUNCEMENT_CHANNEL_KICKOFF_2026-05-30.md`
- Batch 3 closure-style evidence detail: `docs/TIN-128_BATCH_3_CLIENT_PROJECTION_RATE_GUARD_EVIDENCE_2026-05-30.md`

## Pre-Closure Checklist

### 1. Implementation Gaps
- Checked: yes.
- Covered:
  - channel contract + schema mapping
  - server announcement owner seam
  - fanout/subscription/reconciliation integration
  - bounded client projection
  - burst/rate-guard hardening
- Deferred (explicitly out of this issue scope):
  - rich announcement center/history UX
  - moderation/segmented targeting
  - long-range durable announcement history

### 2. Missing Validation or Weak Evidence
- Checked: yes.
- Evidence strength:
  - focused seam/runtime specs for each delivered surface
  - changed-file validation gate
  - full suite regression pass
- Residual testing risk: low for bounded TIN-128 scope.

### 3. Required Document Updates
- Checked: yes.
- Added/updated:
  - kickoff plan artifact
  - batch 3 evidence artifact
  - this aggregate closure rollup

### 4. Related Issue Boundary Problems
- Checked: yes.
- No sibling scope borrowing required for acceptance evidence.
- Work remains bounded to notification pipeline + minimal projection within existing system boundaries.

### 5. Remaining Cleanup
- Checked: yes.
- No dead code/TODO blockers identified in delivered slice.
- Deferred follow-up areas are explicitly documented and bounded.

## Risk Assessment
- Functional risk: low.
- Regression risk: low.
- Basis: deterministic contracts and focused specs across schema/fanout/subscription/reconciliation/rate-guard/projection, plus full-suite pass.

## Final Decision
- Ready for Done: yes.
- Recommended Linear state: Done.
- Basis: Batch 1-3 scope complete, validation gates green, full regression suite green, and closure checklist fully addressed.
