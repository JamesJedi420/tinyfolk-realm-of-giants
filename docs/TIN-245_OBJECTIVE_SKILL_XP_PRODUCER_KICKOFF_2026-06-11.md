# TIN-245 Objective Skill XP Producer Kickoff (2026-06-11)

## Issue

- ID: TIN-245
- Title: Wire objective QTE skill XP producer
- Deferred from: TIN-244

## Context

TIN-244 added `AwardSkillXp` persistence through `SkillProgressionService` without gameplay producers. TIN-243 wired objective completion unlock for `objective_craft`. This slice adds the first bounded gameplay writer that awards skill XP from objective contextual-task QTE success.

## Scope

- Add `SkillProgressionConfig` with design-assigned XP source mapping for `objective_qte_success` → `objective_craft`.
- Add shared `SkillXpAwardPolicy.ResolveXpAward` helper.
- Add `ObjectiveSkillXpProducer.RecordObjectiveQteSuccessXp` calling `_SkillProgressionService_QueryAPI.AwardSkillXp`.
- Wire producer into `ConstructionService`, `StationService`, and `ShrineService` on successful task QTE evaluation (TIN-154 parity).
- Add `tests/objective_skill_xp_producer_runtime_entrypoint.spec.luau`.
- Extend `tests/skills_profile_state.spec.luau` with policy resolution coverage.

## Design mapping

| Outcome | Skill | XP |
|---------|-------|-----|
| Objective QTE success | `objective_craft` | 25 |

## Boundary

- First gameplay XP producer only; no schema changes.
- Non-fatal XP award: QTE success path still proceeds when progression API is unavailable or rejects.
- Distinct from `tinyfolkToolProgressionState`, reputation tracks, and Giant level XP.
- XP requires unlocked progression skill (`skill_not_unlocked` rejects otherwise).

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/objective_skill_xp_producer_runtime_entrypoint.spec.luau
lune run tests/skills_profile_state.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Per-skill catalog overrides for max level / thresholds.
- Escape/containment/objective-completion XP producers.
- Studio TIN-243 objective unlock round-trip proof.
