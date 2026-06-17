# TIN-125 Realm-Status Notify Fanout — Linear Closure Comment

**Date:** 2026-06-17  
**Issue:** [TIN-125](https://linear.app/spectranoir/issue/TIN-125)  
**Shipped in:** [TIN-59 Slice B PR #108](https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/108)

## Linear comment (paste-ready)

TIN-125 closure — realm-status notify fanout shipped with TIN-59 Slice B.

**What shipped**
- `NotificationReconciliationService.ReconcileRealmStatus` fans out to `_RaidBoardHubService_QueryAPI.BroadcastNotify` after successful reconcile.
- `RaidBoardClient` coalesced refresh on `RaidBoardNotify` remote hints.
- Hub map anchor + F-key open path for raid board (`TIN-59 Slice B`).

**Validation**
- `lune run tests/notification_reconciliation_service.spec.luau`
- `.\scripts\run-tests.ps1` (CI green on PR #108)

**Evidence**
- Kickoff: `docs/TIN-59_SHARED_RAID_BOARD_SLICE_B_KICKOFF_2026-06-15.md`
- PR: https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/108

Ready for **Done**.
