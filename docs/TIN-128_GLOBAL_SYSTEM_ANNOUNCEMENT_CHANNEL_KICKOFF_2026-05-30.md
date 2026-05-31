# TIN-128 Global System Announcement Channel Kickoff (2026-05-30)

## Issue
- ID: TIN-128
- Title: Global system announcement channel
- Status: Backlog

## Why This Slice Exists
- Notification foundations are now in place and test-backed: message schema normalization/validation, MessagingService adapter, subscription manager, reconciliation service, and publish rate guard.
- Current channels cover admission, rescue, realm, and return-recovery notifications, but there is no bounded global announcement path for operational/system-wide notices.
- This kickoff defines a narrow first delivery slice that adds announcement delivery without broad UI/dashboard expansion.

## Confirmed Existing Foundations (In Repo)
- Envelope schema and topic key resolution are available through NotificationMessageSchema.
- Publish and subscribe safety boundaries are available through MessagingServiceAdapter and NotificationSubscriptionManager.
- Reconcile-on-receive and periodic reconcile loop are available through NotificationReconciliationService.
- Rate limiting/coalescing guardrails are available through NotificationRateGuard.
- Queue fanout publishing pattern is available through QueueNotificationFanout.

## Proposed Bounded Scope
- Add a dedicated global announcement channel contract with deterministic message taxonomy and bounded payload shape.
- Add a server-owned announcement ingress/query seam for creating and reading active/recent announcements.
- Publish announcement events through existing messaging adapter + rate guard path.
- Subscribe and reconcile announcement notifications through existing subscription and reconciliation seams.
- Add a minimal client projection seam (read-only attributes or existing UI hook) for displaying latest active announcement text and severity.
- Add focused runtime and seam specs for message contract, publish/subscribe routing, reconcile behavior, and rate-guard outcomes.

## Out of Scope
- Full announcement center UI, history pages, or moderation tooling.
- Rich formatting, localization pipeline, attachments, or role-targeted segmented campaigns.
- Durable long-term announcement persistence beyond bounded runtime/ephemeral coordination scope.
- Broad telemetry dashboards or external analytics sinks.

## Initial Implementation Plan
1. Channel contract and schema extension
- Add topic key for system announcements in NotificationMessageSchema (for example: systemAnnouncement -> tin_announcement_v1).
- Define bounded announcement message types:
  - announcement_created
  - announcement_updated
  - announcement_cleared
- Define bounded announcement payload contract:
  - announcementId (string)
  - message (string, bounded length)
  - severity (info | warning | critical)
  - startsAt (number)
  - endsAt (number or nil)
  - issuedByUserId (number or nil)

2. Server announcement owner seam
- Add a dedicated service module (SystemAnnouncementService) with query API:
  - PublishAnnouncement(request)
  - ClearAnnouncement(request)
  - GetActiveAnnouncement(now?)
  - GetAnnouncementDiagnostics()
- Keep state server-owned with cloned snapshots on reads.
- Reject invalid windows/payloads deterministically with stable reason taxonomy.

3. Fanout and adapter integration
- Extend QueueNotificationFanout with PublishAnnouncement(eventName, payload).
- Route publish requests through MessagingServiceAdapter so NotificationRateGuard remains authoritative.
- Preserve deterministic publish result semantics (accepted, coalesced, rate_limited, publish_failed).

4. Subscription and reconciliation integration
- Add the announcement topic to NotificationSubscriptionManager defaults.
- Extend NotificationReconciliationService with:
  - ReconcileSystemAnnouncement(input?)
  - announcement channel counters in diagnostics
  - HandleNotification routing for announcement_* message types
- Reconcile behavior should query server-owned announcement snapshot and return deterministic accepted/failure reasons.

5. Client projection (minimal)
- Add a bounded client-facing projection seam (attribute or existing lightweight client module) that surfaces:
  - latest message
  - severity
  - active flag
  - expiresAt
- Avoid introducing a new heavyweight HUD in this slice.

6. Test coverage and suite wiring
- Extend/adjust existing specs:
  - tests/notification_message_schema.spec.luau
  - tests/queue_notification_fanout.spec.luau
  - tests/notification_subscription_manager.spec.luau
  - tests/notification_reconciliation_service.spec.luau
  - tests/notification_rate_guard.spec.luau
- Add focused runtime spec:
  - tests/system_announcement_service_runtime_entrypoint.spec.luau
- Add new spec to scripts/run-tests.ps1 explicit list.

## Suggested Bounded Delivery Batches

### Batch 1: Contract + Owner Service
- Deliver schema/topic/message/payload contract and SystemAnnouncementService query seam.
- Focused tests: schema + service runtime.
- Exit check: create/update/clear/get active all deterministic and test-backed.

### Batch 2: Fanout + Subscription + Reconciliation
- Wire announcement publish path and subscription defaults.
- Add reconciliation channel and message routing.
- Focused tests: fanout + subscription + reconciliation.
- Exit check: fanout publish and reconcile-on-receive both green with stable reasons.

### Batch 3: Client Projection + Hardening
- Add minimal client projection and diagnostics parity checks.
- Harden rate-guard behavior for announcement burst scenarios.
- Focused tests: rate guard + projection behavior.
- Exit check: no unbounded spam, deterministic coalesced/rate-limited outcomes, projection updates correctly.

## Validation Expectations
- scripts/run-validation.ps1 -ChangedOnly
- Targeted specs for all touched seams and the new system announcement runtime spec
- Full suite run: scripts/run-tests.ps1

## Risks and Controls
- Risk: announcement spam floods channels.
  - Control: preserve rate-guard enforcement and add explicit burst tests.
- Risk: stale announcement display after clear/update.
  - Control: reconciliation snapshot authority and active-window validation tests.
- Risk: contract drift across publish/subscribe/reconcile surfaces.
  - Control: lock message type/payload schema in seam tests and runtime entrypoint spec.

## Exit Criteria (for TIN-128 closure)
- Global announcement channel contract exists and is test-backed.
- Server-owned publish/query seam exists with deterministic reason taxonomy.
- Announcement fanout, subscription, and reconciliation are integrated and covered by focused tests.
- Minimal client projection is wired without broad UI scope creep.
- Boundary docs and closure checklist are updated with explicit in-scope/out-of-scope evidence.
