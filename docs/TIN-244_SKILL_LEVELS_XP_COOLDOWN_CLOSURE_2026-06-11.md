# TIN-244 Skill Levels, XP, and Cooldown Persistence Closure (2026-06-11)

## Shipped

- Bumped `skillsProfileState.schemaVersion` to `2` with v1 → v2 migration and backfill on normalize.
- Added `skillProgressById` map (`level`, `xp`, `cooldownEndsAt`) bounded to catalog-valid unlocked progression skills.
- Extended `SkillCatalogSchema` with shared progression thresholds and level/xp helpers.
- Extended `SkillsProfileState` with progress read/write helpers and unlock seeding.
- Extended `_SkillProgressionService_QueryAPI` with `GetSkillProgressById`, `GetSkillProgress`, `AwardSkillXp`, `SetSkillCooldownEndsAt`.
- Left escape/containment/objective unlock callers unchanged.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/skills_profile_state.spec.luau
lune run tests/skill_progression_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

All passed locally.

## Remaining scope

- Gameplay XP award producers (objective QTE, skill checks, etc.).
- Studio proof for TIN-243 objective unlock round-trip.

## Studio follow-up

Complete a realm objective as a loaded Tinyfolk player, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` contains `objective_craft`.

Runbook: `docs/TIN-243_OBJECTIVE_SKILL_UNLOCK_STUDIO_EVIDENCE_2026-06-11.md`.
