# TIN-51 Realm Entry Portal System - Kickoff

**Date:** 2026-06-17  
**Issue:** [TIN-51](https://linear.app/spectranoir/issue/TIN-51/implement-realm-entry-portal-system)  
**Milestone:** Admission and Queueing  
**Related:** [TIN-50](https://linear.app/spectranoir/issue/TIN-50), [TIN-57](https://linear.app/spectranoir/issue/TIN-57)

## Goal

Let Tinyfolk enter Giant realms from the shared hub through controlled portal entry methods with server-validated availability, role classification, session handoff records, and safe failure rollback.

## In scope

- Portal hub list/enter remotes at `RealmPortalHub_*` anchors with F-key open path.
- Pure `RealmEntryPortalHubState` for entry-method/role classification and availability validation.
- `RealmEntryPortalHubService` orchestration: handoff session record, location transit, assignment begin, admission enqueue.
- Failed entry rollback to shared hub via handoff abort + location/assignment safe paths.
- Client panel for listing and entering eligible realms.

## Out of scope

- Full invitation UX and contract negotiation flows.
- Published-client multi-server portal spot-check.
- Prisoner-transfer live orchestration beyond admission classification seam.

## Acceptance mapping

| Criterion | Target |
|---|---|
| Choose eligible Giant realm | `RealmEntryPortalHubService` list remote |
| Validate realm availability | `LiveRealmHubRouting.ResolveAdmissionTarget` |
| Entry method determines realm role | `RealmEntryPortalHubState.ResolveEntryRole` |
| Entry creates realm session record | `_RealmTransferHandoffService_QueryAPI.BeginHandoff` |
| Failed transfer returns safely | `rollbackFailedEntry` + hub safe transitions |

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/realm_entry_portal_hub_state.spec.luau
lune run tests/realm_entry_portal_hub_service_runtime_entrypoint.spec.luau
```

## Deferred

- Contract/invitation producer integrations beyond classification hooks.
- Studio evidence runbook for multi-method portal entry.
