# TIN-245 Objective Skill XP Producer Closure (2026-06-11)

## Shipped

- Added `SkillProgressionConfig` with design mapping `objective_qte_success` → `objective_craft` (+25 XP).
- Added shared `SkillXpAwardPolicy.ResolveXpAward` for catalog-validated XP source resolution.
- Added `ObjectiveSkillXpProducer.RecordObjectiveQteSuccessXp` as the first gameplay writer calling `AwardSkillXp`.
- Wired producer into `ConstructionService`, `StationService`, and `ShrineService` on successful task QTE evaluation.
- Added `tests/objective_skill_xp_producer_runtime_entrypoint.spec.luau`.
- Extended `tests/skills_profile_state.spec.luau` with policy resolution coverage.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/objective_skill_xp_producer_runtime_entrypoint.spec.luau
lune run tests/skills_profile_state.spec.luau
.\scripts\run-tests.ps1
```

## Remaining scope

- Escape/containment/objective-completion XP producers.
- Per-skill catalog overrides for max level / thresholds.
- Studio TIN-243 objective unlock round-trip proof.
