# TIN-246 Outcome Skill XP Producers Closure (2026-06-11)

## Shipped

- Extended `SkillProgressionConfig` with `escape_success`, `containment_reward`, and `objective_completion` XP mappings.
- Added `OutcomeSkillXpProducer` with shared `RecordOutcomeXp` and outcome-specific helpers.
- Wired XP producers into `EscapeOutcomeResolver`, `ContainmentRewardResolver`, and `RealmObjectiveService` after unlock on accepted paths.
- Delegated `ObjectiveSkillXpProducer` through `OutcomeSkillXpProducer`.
- Exposed non-fatal `skillXpAccepted` / `skillXpReason` / `skillXpId` on outcome responses.
- Added `tests/outcome_skill_xp_producer_runtime_entrypoint.spec.luau`.
- Extended `tests/skills_profile_state.spec.luau` with policy resolution coverage for new outcomes.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/outcome_skill_xp_producer_runtime_entrypoint.spec.luau
lune run tests/skills_profile_state.spec.luau
.\scripts\run-tests.ps1
```

All passed locally.

## Remaining scope

- Per-skill catalog threshold overrides.
- Studio TIN-243 objective unlock round-trip proof.
