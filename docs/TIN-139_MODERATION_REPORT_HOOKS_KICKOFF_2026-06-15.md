# TIN-139 Moderation Report Hooks Kickoff (2026-06-15)

## Issue

- ID: TIN-139
- Title: Implement moderation report hooks
- Milestone: Validation and Governance
- Linear: https://linear.app/spectranoir/issue/TIN-139/implement-moderation-report-hooks

## Goal

Give players a server-authoritative report path for high-friction capture, custody, ransom, and repeated-blocking interactions with moderation-safe context export.

## Scope

- Add `ModerationReportState` for metadata sanitization and report context assembly.
- Add `ModerationReportConfig` for surface kinds, blocked metadata keys, and remotes/attributes.
- Add `ModerationReportService` export/query API consuming capture, custody transfer, ransom, rescue-blocking, and TIN-75 abuse snapshots.
- Project report affordance attributes and raid HUD support line; minimal `ModerationReportClient` remote helper.

## Boundary

- Report plumbing and export only; no moderation judgment automation.
- Exclude private profile data and secure tokens from exported context.
- Consume `_RepeatedTargetingAbuseService_QueryAPI`; do not re-implement abuse detection.
- Defer full report UI polish and Roblox native report widget integration.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/moderation_report_state.spec.luau
lune run tests/moderation_report_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
