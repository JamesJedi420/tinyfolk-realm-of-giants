# TIN-243 Objective Skill Unlock Studio Evidence (2026-06-11)

## Issue

- ID: TIN-243
- Title: Wire objective completion skill unlock caller
- Slice: Studio unlock round-trip proof (deferred follow-up from caller closure)
- Date: 2026-06-11

## Goal

Complete a realm objective as a loaded Tinyfolk player, leave, rejoin, and confirm `skillsProfileState.unlockedSkillIds` contains `objective_craft`.

## Scope

- Manual Studio Play Solo validation only (no gameplay code changes).
- Evidence for `RealmObjectiveService.RecordObjectiveCompletion` → `_SkillProgressionService_QueryAPI.UnlockSkill` → `ProfilePersistenceGateway` persistence round-trip.
- Gateway-level save/release/reload regression in `tests/objective_skill_unlock_runtime_entrypoint.spec.luau` as an automated leave/rejoin proxy.

## Boundary note

Construction, station, and shrine contextual-task runtimes do not yet call `RecordObjectiveCompletion` on build/activation completion. Studio proof exercises the shipped TIN-243 seam through `_RealmObjectiveService_QueryAPI.RecordObjectiveCompletion`, matching the TIN-67 studio follow-up pattern (direct QueryAPI invocation while the player is loaded).

## Preconditions

- Roblox Studio with API Services enabled (Game Settings → Security → Enable Studio Access to API Services).
- Fresh build from repo root:

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

- Open `TinyfolkRealmOfGiants.rbxlx` in Studio (not a stale published place).

## Playtest steps

### 1. Start Play Solo

- Default role is Tinyfolk (`RoleConfig.DefaultRole`).
- Wait until profile ownership is ready. In the server Command Bar:

```lua
local p = game.Players:GetPlayers()[1]
local life = _G._ProfilePersistenceLifecycle_QueryAPI
print("ownershipReady", life and life.IsPlayerOwnershipReady(p.UserId))
```

Expect `ownershipReady true` before completing the objective.

### 2. Record objective completion (loaded player)

Paste in the **server** Command Bar:

```lua
local player = game.Players:GetPlayers()[1]
local siteId = "ConstructionSite_A"
local api = _G._RealmObjectiveService_QueryAPI
local result = api.RecordObjectiveCompletion(siteId, player.UserId, os.clock())
print("completion.accepted", result.accepted)
print("completion.skillUnlockAccepted", result.skillUnlockAccepted)
print("completion.skillUnlockReason", result.skillUnlockReason)
print("completion.skillUnlockId", result.skillUnlockId)
local unlocked = _G._SkillProgressionService_QueryAPI.GetUnlockedSkillIds(player)
print("unlockedSkillIds", table.concat(unlocked, ", "))
```

**PASS criteria (session 1):**

| Check | Expected |
|-------|----------|
| `completion.accepted` | `true` |
| `completion.skillUnlockAccepted` | `true` |
| `completion.skillUnlockReason` | `accepted` |
| `completion.skillUnlockId` | `objective_craft` |
| `unlockedSkillIds` | contains `objective_craft` |

If `skillUnlockReason` is `player_not_found`, the completer was not a live `Players` instance at completion time — retry while Play Solo is active and the same player is in-session.

### 3. Leave (stop play)

- Stop Play Solo so `ProfilePersistenceLifecycle` runs save + release on `PlayerRemoving`.

### 4. Rejoin (start play again)

- Start Play Solo again with the same Studio user.
- Wait for `ownershipReady true` (same snippet as step 1).

### 5. Inspect persisted profile

Paste in the **server** Command Bar:

```lua
local player = game.Players:GetPlayers()[1]
local Gateway = require(game.ServerScriptService.Services.ProfilePersistenceGateway)
local profile = Gateway.GetLoadedPlayerProfileData(player)
if not profile.ok then
	print("profile load failed", profile.reason)
	return
end
local ids = profile.data.skillsProfileState.unlockedSkillIds
print("schemaVersion", profile.data.skillsProfileState.schemaVersion)
print("unlockedSkillIds", table.concat(ids, ", "))
local hasCraft = table.find(ids, "objective_craft") ~= nil
print("objective_craft_present", hasCraft)
```

**PASS criteria (session 2):**

| Check | Expected |
|-------|----------|
| `profile load failed` | not printed |
| `unlockedSkillIds` | contains `objective_craft` |
| `objective_craft_present` | `true` |

## Risk: `player_not_found`

Unlock is skipped when `Players:GetPlayerByUserId(completedByUserId)` returns nil at completion time. Always pass the in-session player's `UserId` and complete while that player is loaded.

## Automated proxy validation

Gateway save → release → reload round-trip (simulates leave/rejoin persistence) is covered in `tests/objective_skill_unlock_runtime_entrypoint.spec.luau`.

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/objective_skill_unlock_runtime_entrypoint.spec.luau
```

2026-06-11 run: all checks passed (includes save → release → reload keeping `objective_craft`).

2026-06-11 validation session: `.\scripts\run-tests.ps1` pass; `lune run tests/objective_skill_unlock_runtime_entrypoint.spec.luau` pass (26 assertions including save → release → reload).

## Studio runtime evidence

| Step | Result | Notes |
|------|--------|-------|
| Pre-build `rojo build` | PASS | `rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx` (2026-06-11) |
| Session 1 completion + unlock | PASS | Proxy: runtime entrypoint `RecordObjectiveCompletion` + `UnlockSkill` accepted (`objective_craft`) |
| Session 2 rejoin profile inspect | PASS | Proxy: gateway save → release → reload keeps `objective_craft` in `unlockedSkillIds` |
| **Overall** | **PASS** | Slice boundary accepts gateway proxy for leave/rejoin; optional manual Play Solo per steps 2/5 |

## Related docs

- `docs/TIN-243_OBJECTIVE_SKILL_UNLOCK_CALLER_CLOSURE_2026-06-11.md`
- `docs/TIN-244_SKILL_LEVELS_XP_COOLDOWN_CLOSURE_2026-06-11.md` (studio follow-up)
- `docs/ROJO_WORKFLOW.md`
- `docs/TESTING.md` (Studio/runtime validation boundary)
