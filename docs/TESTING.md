# Testing

## Local script prerequisites

Local PowerShell test scripts require script execution to be allowed for the process.
If direct script execution is blocked, run the same script with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-tests.ps1
```

Headless Luau test scripts require `lune` to be installed and available on `PATH`.

## Run lint and typecheck validation

From the repo root, run:

```powershell
.\scripts\run-validation.ps1
```

This command runs StyLua, Selene, and luau-lsp with repository configuration (`stylua.toml`, `selene.toml`) and Roblox definitions (`types/roblox-definitions.d.luau`).

For touched-file validation only:

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
```

To fail on Selene warnings as well:

```powershell
.\scripts\run-validation.ps1 -AllowSeleneWarnings:$false
```

## Install Lune (Windows)

Run:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" install --id Lune.Lune --exact --source winget --accept-source-agreements --accept-package-agreements
```

## Run TIN-96 Phase 1 tests

From the repo root, run:

```powershell
.\scripts\run-tests.ps1
```

If `lune` is still not found right after install, open a new terminal so PATH updates are picked up.

## Studio/runtime validation boundary

Studio Play Solo and Test -> Start runtime evidence currently requires manual interaction in Roblox Studio and manual Output capture.
Do not treat Rojo build success or Roblox Studio launch success as gameplay validation evidence.
Roblox Studio CLI use in this repository is launch/navigation support only.
Do not claim Roblox Studio CLI replaces the manual Play Solo or multi-client Output capture path unless a concrete supported command path is documented and verified.
Fold Studio-open smoke test checklist work into TIN-157 instead of creating a separate validation workflow.

## Issue-to-workflow mapping

Use pure-Luau tests for deterministic validator/spec work.
Start in `tests/`, then run the relevant local script from the repo root.

Use Rojo build/open workflow for source-layout and map changes.
Start in `docs/ROJO_WORKFLOW.md`, rebuild `TinyfolkRealmOfGiants.rbxlx`, then open the local built place in Studio.

Use manual Studio runtime validation for behavior that depends on live Roblox runtime state, player input, multiplayer clients, physics, Output logs, or Explorer state.
For the current batched manual Studio sweep, use TIN-157 as the evidence path.

Use published-place rollback/open workflow only for published Roblox place concerns.
Do not use rollback/open steps as a substitute for local source validation.

## Navigation quick start

* Rebuild: `docs/ROJO_WORKFLOW.md` -> Primary build command
* Local runtime validation: `docs/ROJO_WORKFLOW.md` -> Local build/open path
* Manual Studio sweep: TIN-157 runbook, with this document defining validation boundaries
* Rollback/open decisions: `docs/ROJO_WORKFLOW.md` -> Publish and rollback records

## Known TIN-157 upgrade-board runtime blocker

Current source positions:

* `GiantUpgradeBoard_A`: `[24, 4, 0]`
* `GiantSpawn`: `[12, 0.5, 0]`

The positions are approximately 12.5 studs apart.
This is within `UpgradeBoardConfig.InteractionRangeStuds = 16`.
Upgrade-board runtime validation no longer requires the TIN-157 teleport mitigation for this source layout.
