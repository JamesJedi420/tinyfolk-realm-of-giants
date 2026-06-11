# TIN-67 Escape Skill Unlock Caller Closure (2026-06-11)

## Shipped

- Wired `EscapeOutcomeResolver` to call `_SkillProgressionService_QueryAPI.UnlockSkill` on successful escape outcomes.
- First gameplay mapping: escape success unlocks catalog progression skill `realm_adaptation`.
- Skill unlock is non-fatal (escape still completes when unlock API is unavailable or rejects).
- Duplicate escape operations skip unlock side effects via existing idempotency gate.
- Added `tests/escape_outcome_skill_unlock_runtime_entrypoint.spec.luau`.

## Design decision

No formal skill-reward matrix exists yet. Minimal mapping chosen for this slice:

| Event | Skill |
|-------|-------|
| Successful escape | `realm_adaptation` |

Objective QTE and containment reward callers remain deferred.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/escape_outcome_skill_unlock_runtime_entrypoint.spec.luau
lune run tests/escape_outcome_resolver.spec.luau
.\scripts\run-tests.ps1
```

## Remaining TIN-67 scope

- Additional gameplay unlock callers (objective completion, containment reward).
- Skill levels, XP, and cooldown persistence.

## Studio follow-up

Escape a realm as a loaded Tinyfolk player, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` contains `realm_adaptation`.
