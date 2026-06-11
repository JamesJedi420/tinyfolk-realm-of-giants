# TIN-242 Containment Skill Unlock Caller Closure (2026-06-11)

## Shipped

- Added catalog progression skill `custody_stewardship` for Giant containment reward outcomes.
- Wired `ContainmentRewardResolver` to call `_SkillProgressionService_QueryAPI.UnlockSkill` on main reward path, mirroring `EscapeOutcomeResolver.recordSkillUnlock`.
- Passed `custodianPlayer` from `CaptureService.resolveContainmentRewardForRecord`.
- Skill unlock is non-fatal (containment reward still completes when unlock API is unavailable or rejects).
- Duplicate containment operations skip unlock side effects via existing idempotency gate.
- Added `tests/containment_reward_skill_unlock_runtime_entrypoint.spec.luau`.

## Design decision

Minimal mapping for this slice:

| Event | Skill |
|-------|-------|
| Successful escape (TIN-67) | `realm_adaptation` |
| Containment reward granted | `custody_stewardship` |

Objective completion caller remains deferred.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/containment_reward_skill_unlock_runtime_entrypoint.spec.luau
lune run tests/containment_reward_resolver.spec.luau
.\scripts\run-tests.ps1
```

## Remaining scope

- Objective completion skill unlock caller.
- Skill levels, XP, and cooldown persistence.

## Studio follow-up

End custody with a score-granting containment reward as a loaded Giant player, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` contains `custody_stewardship`.
