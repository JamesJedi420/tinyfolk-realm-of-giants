# TIN-67 Skills Unlock Producer Closure (2026-06-11)

## Shipped

- Added `SkillProgressionService.server.luau` as the single authoritative gameplay unlock producer seam (`_SkillProgressionService_QueryAPI.UnlockSkill`, `GetUnlockedSkillIds`).
- Wired unlock writes through `ProfilePersistenceGateway.UpdateLoadedPlayerProfileData` → `SkillsProfileState.ResolveUnlock`.
- Added first default-catalog progression skill id `realm_adaptation` so the producer seam is exercisable without test-only catalog injection.
- Added `tests/skill_progression_service_runtime_entrypoint.spec.luau`.

## Validation

- `.\scripts\run-validation.ps1 -ChangedOnly` — pass
- `lune run tests/skills_profile_state.spec.luau` — pass
- `lune run tests/skill_progression_service_runtime_entrypoint.spec.luau` — pass
- `.\scripts\run-tests.ps1` — pass

## Remaining TIN-67 scope

- Gameplay callers that invoke `UnlockSkill` on objective/escape/containment outcomes (deferred until design assigns skill reward sources).
- Skill levels, XP, and cooldown persistence.

## Studio follow-up

Call `_SkillProgressionService_QueryAPI.UnlockSkill` for a loaded player with `realm_adaptation`, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` round-trips.
