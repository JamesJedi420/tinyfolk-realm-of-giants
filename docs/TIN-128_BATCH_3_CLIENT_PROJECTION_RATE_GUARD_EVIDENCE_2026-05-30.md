# TIN-128 Batch 3 Closure-Style Evidence (2026-05-30)

## Issue
- ID: TIN-128
- Title: Global system announcement channel
- Batch: 3 (minimal client projection + announcement burst/rate-guard hardening)
- Date: 2026-05-30
- Branch/PR: master (local-only)

## Batch 3 Summary
- Added minimal client announcement projection and banner rendering via player attributes.
- Added server-owned announcement attribute projection updates on publish/clear transitions.
- Hardened notification rate-guard handling for burst announcement traffic by coalescing announcement message bursts instead of dropping immediately.
- Extended focused runtime/spec coverage for projection behavior and announcement burst handling.

## Implementation Evidence
- `src/ServerScriptService/Services/SystemAnnouncementService.server.luau`
  - Added player attribute projection fields for announcement state:
    - `SystemAnnouncementActive`
    - `SystemAnnouncementId`
    - `SystemAnnouncementMessage`
    - `SystemAnnouncementSeverity`
    - `SystemAnnouncementStartsAt`
    - `SystemAnnouncementEndsAt`
    - `SystemAnnouncementIssuedByUserId`
    - `SystemAnnouncementUpdatedAt`
  - Added projection application on successful `PublishAnnouncement` and `ClearAnnouncement`.
  - Added test seam hook (`projectionSink`) in `ConfigureForTests` for deterministic projection assertions.
- `src/StarterPlayer/StarterPlayerScripts/Client/SystemAnnouncementClient.client.luau`
  - New lightweight client banner consumes announcement attributes and displays:
    - severity-colored title accent
    - message body
    - optional expiry countdown
  - Uses existing lightweight attribute-driven client style (no new heavyweight HUD framework).
- `src/ServerScriptService/Services/NotificationRateGuard.luau`
  - Added announcement metadata extraction (`announcementId`) from publish inputs.
  - Added burst coalescing support for `announcement_*` message types.
  - Added deterministic coalesced summary type for announcement bursts: `announcement_summary`.
  - Extended diagnostics with `lastAnnouncementId` for parity and observability.
- `tests/system_announcement_service_runtime_entrypoint.spec.luau`
  - Added projection sink assertions for publish and clear projection payloads.
- `tests/notification_rate_guard.spec.luau`
  - Added burst announcement rate-guard coverage proving coalesced behavior and diagnostics parity.

## Validation Evidence

### Focused Specs (Batch 3)
- `lune run tests/system_announcement_service_runtime_entrypoint.spec.luau` -> pass
- `lune run tests/notification_rate_guard.spec.luau` -> pass

### Changed-file Validation
- `./scripts/run-validation.ps1 -ChangedOnly` -> pass
  - `stylua` pass
  - `selene` pass (warning-only output present but non-blocking)
  - `luau-lsp` pass

### Full Suite Regression
- `./scripts/run-tests.ps1` -> pass
- Explicit confirmation from suite output includes:
  - `messaging_service_adapter: all checks passed`
  - `notification_rate_guard: all checks passed`
  - `notification_message_schema: all checks passed`
  - `notification_reconciliation_service: all checks passed`
  - `notification_subscription_manager: all checks passed`
  - `queue_notification_fanout: all checks passed`
  - `system_announcement_service_runtime_entrypoint: all checks passed`
  - `headless_match_simulation: all checks passed`

## Boundary Notes
- Included in this batch:
  - minimal announcement projection path from server-owned announcement state to client display
  - announcement burst hardening in NotificationRateGuard with deterministic coalesce outcomes
  - focused projection and burst-rate-guard spec coverage
- Explicitly out of scope in this batch:
  - rich announcement center/history UI
  - localization/moderation/segmented targeting workflows
  - external telemetry dashboards or analytics sink integrations
  - durable announcement persistence beyond bounded runtime projection

## Pre-Closure Checklist (Batch 3 Evidence)

### 1. Implementation Gaps
- Checked: yes.
- Notes: bounded batch goals are implemented (minimal projection + burst hardening).
- Remaining gap for later slice: richer UX surface and durable historical announcement browsing remain deferred.

### 2. Missing Validation or Weak Evidence
- Checked: yes.
- Notes: focused specs plus changed-file validation plus full suite pass are present for this batch.
- Residual risk: low for bounded batch scope.

### 3. Required Document Updates
- Checked: yes.
- Notes: this document records batch evidence and validation trace for Batch 3.

### 4. Related Issue Boundary Problems
- Checked: yes.
- Notes: this evidence is scoped to TIN-128 Batch 3 only and does not claim unrelated issue closure.
- Dependency context used: existing notification schema/fanout/subscription/reconciliation/rate-guard seams.

### 5. Remaining Cleanup
- Checked: yes.
- Notes: no dead-code cleanup blockers identified in this bounded batch.
- Deferred items explicitly retained: full announcement center UX and long-range persistence/ops tooling.

## Final Batch 3 Decision
- Batch 3 status: complete and validated.
- Recommended next step: move to TIN-128 closure packaging if Batch 1-3 aggregate acceptance is satisfied, or run a final integration pass on announcement UX copy/tuning if desired.
