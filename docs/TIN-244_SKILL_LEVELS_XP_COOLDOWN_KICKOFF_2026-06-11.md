# TIN-244 Skill Levels, XP, and Cooldown Persistence Kickoff (2026-06-11)

## Issue

- ID: TIN-244
- Title: Skill levels, XP, and cooldown persistence
- Linear: https://linear.app/spectranoir/issue/TIN-244/skill-levels-xp-and-cooldown-persistence
- Deferred from: TIN-67 / TIN-243

## Context

TIN-67 established `skillsProfileState` with `unlockedSkillIds` only. TIN-242/TIN-243 wired the three gameplay unlock callers. This slice adds bounded per-skill level, XP, and cooldown persistence without new gameplay producers.

## Scope

- Bump `skillsProfileState.schemaVersion` to `2` with v1 → v2 migration on load/normalize.
- Add `skillProgressById` map keyed by catalog-valid unlocked progression skill ids.
- Extend `SkillCatalogSchema` with shared progression threshold helpers.
- Extend `SkillsProfileState` normalize/copy/award/cooldown helpers.
- Extend `SkillProgressionService` query API for progress read/write.
- Seed default progress (`level = 1`, `xp = 0`) on successful unlock.
- Do **not** change escape/containment/objective unlock callers.

## Proposed schema

Profile key: `skillsProfileState`

```luau
{
  schemaVersion = 2,
  unlockedSkillIds = { "realm_adaptation" },
  skillProgressById = {
    realm_adaptation = {
      level = 1,
      xp = 0,
      cooldownEndsAt = nil, -- optional finite unix timestamp
    },
  },
}
```

## Boundary

- Distinct from `tinyfolkToolProgressionState`, `reputationState.unlockedLoadoutTraitIds`, and `giantTraitState.unlockedTraitIds`.
- No gameplay XP award producers in this slice.
- Progress entries only persist for catalog-valid unlocked progression skills.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/skills_profile_state.spec.luau
lune run tests/skill_progression_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```

## Studio follow-up

Complete a realm objective as a loaded Tinyfolk player, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` contains `objective_craft` (TIN-243 studio proof; unchanged by this slice).
