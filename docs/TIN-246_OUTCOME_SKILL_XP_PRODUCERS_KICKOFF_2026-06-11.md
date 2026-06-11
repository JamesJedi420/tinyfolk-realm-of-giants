# TIN-246 Outcome Skill XP Producers Kickoff (2026-06-11)

## Issue

- ID: TIN-246
- Title: Wire escape/containment/objective-completion skill XP producers
- Deferred from: TIN-244 / TIN-245

## Context

TIN-245 added the first gameplay XP producer for objective QTE success. TIN-67/TIN-242/TIN-243 wired unlock callers on escape, containment, and objective completion seams. This slice adds matching XP producers on those same outcome paths.

## Scope

- Extend `SkillProgressionConfig` with design mappings for `escape_success`, `containment_reward`, and `objective_completion`.
- Add `OutcomeSkillXpProducer` with outcome-specific record helpers calling `AwardSkillXp`.
- Wire producers into `EscapeOutcomeResolver`, `ContainmentRewardResolver`, and `RealmObjectiveService` after unlock on accepted paths.
- Delegate `ObjectiveSkillXpProducer` through `OutcomeSkillXpProducer`.
- Add `tests/outcome_skill_xp_producer_runtime_entrypoint.spec.luau`.
- Extend `tests/skills_profile_state.spec.luau` with policy resolution coverage.

## Design mapping

| Outcome | Skill | XP |
|---------|-------|-----|
| Escape success | `realm_adaptation` | 100 |
| Containment reward granted | `custody_stewardship` | 50 |
| Objective completion | `objective_craft` | 50 |
| Objective QTE success (TIN-245) | `objective_craft` | 25 |

## Boundary

- No schema changes.
- Non-fatal XP award: outcome paths still proceed when progression API is unavailable or rejects.
- Unlock before XP on same outcome to satisfy `skill_not_unlocked` guard.
- Duplicate/idempotent outcome completions skip XP award.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/outcome_skill_xp_producer_runtime_entrypoint.spec.luau
lune run tests/skills_profile_state.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Per-skill catalog overrides for max level / thresholds.
- Studio TIN-243 objective unlock round-trip proof.
