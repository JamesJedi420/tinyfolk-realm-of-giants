# TIN-243 Objective Skill Unlock Caller Kickoff (2026-06-11)

## Scope

- Wire `RealmObjectiveService.RecordObjectiveCompletion` to call `_SkillProgressionService_QueryAPI.UnlockSkill` mirroring `EscapeOutcomeResolver.recordSkillUnlock`.
- Resolve player from `completedByUserId` via `Players:GetPlayerByUserId`.
- Add catalog progression skill `objective_craft` with minimal design mapping.
- Add `tests/objective_skill_unlock_runtime_entrypoint.spec.luau`.

## Design mapping

| Event | Skill |
|-------|-------|
| Successful escape (TIN-67) | `realm_adaptation` |
| Containment reward granted (TIN-242) | `custody_stewardship` |
| Objective completion (TIN-243) | `objective_craft` |

## Boundary

- One caller only (`RecordObjectiveCompletion`).
- Non-fatal unlock: objective completion still succeeds when unlock API is unavailable or rejects.
- Idempotent unlock semantics; duplicate site completions skip unlock via existing `site_already_completed` gate.

## Deferred

- Skill levels, XP, and cooldown persistence (separate issue after all three gameplay callers land).

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/objective_skill_unlock_runtime_entrypoint.spec.luau
lune run tests/realm_objective_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
