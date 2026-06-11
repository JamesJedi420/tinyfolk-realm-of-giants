# TIN-243 Objective Skill Unlock Caller Closure (2026-06-11)

## Shipped

- Added catalog progression skill `objective_craft` for realm objective completion outcomes.
- Wired `RealmObjectiveService.RecordObjectiveCompletion` to call `_SkillProgressionService_QueryAPI.UnlockSkill` on accepted completions, mirroring `EscapeOutcomeResolver.recordSkillUnlock`.
- Resolves completer via `Players:GetPlayerByUserId(completedByUserId)`.
- Skill unlock is non-fatal (objective completion still succeeds when unlock API is unavailable or rejects).
- Duplicate site completions skip unlock via existing `site_already_completed` gate.
- Added `tests/objective_skill_unlock_runtime_entrypoint.spec.luau`.

## Design decision

Minimal mapping for this slice:

| Event | Skill |
|-------|-------|
| Successful escape (TIN-67) | `realm_adaptation` |
| Containment reward granted (TIN-242) | `custody_stewardship` |
| Objective completion (TIN-243) | `objective_craft` |

All three gameplay unlock callers are now wired.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/objective_skill_unlock_runtime_entrypoint.spec.luau
lune run tests/realm_objective_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Remaining scope

- Skill levels, XP, and cooldown persistence.

## Studio follow-up

Complete a realm objective as a loaded Tinyfolk player, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` contains `objective_craft`.
