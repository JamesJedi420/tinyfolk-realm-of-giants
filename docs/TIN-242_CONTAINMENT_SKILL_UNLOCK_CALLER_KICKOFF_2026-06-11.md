# TIN-242 Containment Skill Unlock Caller Kickoff (2026-06-11)

## Goal

Wire the second gameplay skill unlock caller (containment reward) after TIN-67 escape unlock and producer seam.

## Scope

- Add catalog progression skill `custody_stewardship` for Giant containment reward outcomes.
- Wire `ContainmentRewardResolver` to call `_SkillProgressionService_QueryAPI.UnlockSkill` mirroring `EscapeOutcomeResolver.recordSkillUnlock`.
- Pass custodian player from `CaptureService.resolveContainmentRewardForRecord`.
- Add `tests/containment_reward_skill_unlock_runtime_entrypoint.spec.luau`.

## Design decision

No formal skill-reward matrix exists yet. Minimal mapping for this slice:

| Event | Skill |
|-------|-------|
| Successful escape (TIN-67) | `realm_adaptation` |
| Containment reward granted | `custody_stewardship` |

Objective completion caller remains deferred.

## Boundary

- One caller only (containment reward).
- Non-fatal unlock (containment reward still completes when unlock API unavailable or rejects).
- Duplicate containment operations skip unlock via existing idempotency gate.
- Skill unlock on main reward path only (not pair cap / duplicate_completed).

## Source of truth

- `docs/TIN-67_ESCAPE_SKILL_UNLOCK_CALLER_CLOSURE_2026-06-11.md`
- `docs/TIN-67_SKILLS_UNLOCK_PRODUCER_CLOSURE_2026-06-11.md`

## Inspect first

- `src/ServerScriptService/Services/ContainmentRewardResolver.luau`
- `src/ServerScriptService/Services/CaptureService.server.luau`
- `src/ReplicatedStorage/Shared/Config/SkillCatalogSchema.luau`

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/containment_reward_skill_unlock_runtime_entrypoint.spec.luau
lune run tests/containment_reward_resolver.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Objective completion skill unlock caller.
- Skill levels, XP, and cooldown persistence.

## Studio follow-up

End custody with a score-granting containment reward as a loaded Giant player, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` contains `custody_stewardship`.
