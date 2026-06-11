# TIN-67 Skills Persistence Kickoff (2026-06-11)

## Issue

- ID: TIN-67 (focused slice: skills profile hardening)
- Title: Implement Tinyfolk persistent profile
- Linear: https://linear.app/spectranoir/issue/TIN-67/implement-tinyfolk-persistent-profile

## Context

TIN-67 lists **skills** as a persistent profile field alongside tools, escape records, and party history. Other profile namespaces are now gateway-backed via `*ProfileState` modules in `Shared/`. Skills has **no schema, catalog, runtime writer, or gateway wiring** in the repository today.

This kickoff defines the smallest correct slice for skills persistence without conflating adjacent progression systems.

## Scope

- Add `SkillCatalogSchema` with canonical skill id records and persistability rules (structural parallel to `TinyfolkToolCatalogSchema`).
- Add `SkillsProfileState` for canonical normalize/unlock/copy helpers (`HasPersistedState`, `GetUnlockedSkillIds`, `CopyProfileField`, `ResolveUnlock`, `ApplyUnlockedSkillIds`).
- Extend `ProfilePersistenceGateway` clone/copy and load sanitization to round-trip `skillsProfileState` when present.
- Register `skillsProfileState` namespace ownership in `EventStateOwnershipModel`.
- Add `tests/skills_profile_state.spec.luau` and gateway sanitization coverage.

## Boundary

- Bounded `skillsProfileState` object only:
  - `schemaVersion` (number, default `1`)
  - `unlockedSkillIds` (sorted unique string list validated against `SkillCatalogSchema`)
- Initial catalog may ship with **zero progression skills**; gateway and profile-state helpers must still round-trip an empty unlocked set.
- **No runtime writer in this slice** unless a follow-on issue adds the first gameplay unlock seam in the same PR; there is no authoritative unlock producer in the codebase today.
- Distinct from:
  - `tinyfolkToolProgressionState` — tool unlock ids gated by tool catalog/progression source
  - `specialistPreference` — Giant-side specialist role and station assignment
  - `reputationState.unlockedLoadoutTraitIds` / `giantTraitState.unlockedTraitIds` — reputation/giant trait unlocks
  - **Skill Checks** (`SYSTEM_BOUNDARIES.md`) — timed QTE layers on objectives (TIN-154); UI/runtime behavior, not profile progression
- No skill levels, XP banks, cooldown persistence, or per-session skill runtime state.
- No cross-server transfer orchestration or load-failure routing.

## Proposed schema

Profile key: `skillsProfileState`

```luau
{
  schemaVersion = 1,
  unlockedSkillIds = { "skill_example" }, -- sorted, unique, catalog-validated
}
```

`SkillCatalogSchema` record shape (minimum):

```luau
{
  skillId: string,
  displayName: string,
  unlockSource: "starter" | "progression",
  availability: "available" | "locked",
  sourceId: string,
}
```

Persistability rule (mirror tool progression):

- Only `unlockSource == "progression"` and `availability == "available"` skills may appear in `unlockedSkillIds`.
- Starter skills are runtime defaults from catalog, not duplicated in profile unless a future slice explicitly requires it.

Deduping/idempotency:

- `ResolveUnlock(profileData, skillId)` rejects unknown ids, non-progression skills, and already-unlocked ids.
- `ApplyUnlockedSkillIds` replaces the normalized set (admin/test seam); gameplay should prefer `ResolveUnlock`.

## Structural reference

- Profile-state API shape: `src/ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolProgressionProfileState.luau`
- Catalog validation pattern: `src/ReplicatedStorage/Shared/Config/TinyfolkToolCatalogSchema.luau`
- Gateway wiring pattern: `discoveredRealms` / `escapeHistory` slices in `ProfilePersistenceGateway.luau`

## Open decisions (resolve before implementation)

1. **Catalog location** — prefer `Shared/Config/SkillCatalogSchema.luau` alongside other config schemas.
2. **First progression skill ids** — slice can ship with an empty catalog; gameplay unlock wiring is a separate seam once ids exist.
3. **Future writer ownership** — candidate owners once skills exist in design:
   - objective/QTE completion services (if skills reward successful contextual tasks)
   - escape/containment outcome resolvers (if skills reward realm outcomes)
   - dedicated `SkillProgressionService` (only if multiple writers appear)
   Decision deferred; this slice does not require picking a writer.

## Validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/skills_profile_state.spec.luau
lune run tests/profile_persistence_gateway.spec.luau
.\scripts\run-tests.ps1
```

## Deferred

- Party history persistence (separate TIN-67 slice; clearer admission write seam).
- Runtime skill unlock writers and gameplay coupling.
- Skill levels, XP, and cooldown persistence.
- Cross-server transfer and load-failure routing.
- Studio proof of unlock flow until at least one catalog progression skill and writer exist.

## Studio follow-up

After a future writer lands: perform the first in-game skill unlock, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` round-trips through profile load/save. For this slice, studio proof is limited to verifying empty/default profile load does not regress other namespaces.
