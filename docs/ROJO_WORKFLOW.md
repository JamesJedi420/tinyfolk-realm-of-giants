# Rojo Workflow - Tinyfolk: Realm of Giants

This document defines the repo-specific Rojo workflow for Tinyfolk: Realm of Giants.

## Purpose

Use Rojo to turn the repository source tree into a Roblox place file for Studio validation and playtesting.

This file is for **repo-specific usage**, not general Rojo documentation.

## Canonical project file

The canonical Rojo project file is:

```text
default.project.json
```

Use this file unless a future issue explicitly introduces another supported project configuration.

## Primary build command

From the repo root, run:

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

This generates the current Studio-openable place file:

```text
TinyfolkRealmOfGiants.rbxlx
```

## Expected generated outputs

The repo may contain generated outputs such as:

* `TinyfolkRealmOfGiants.rbxlx`
* `sourcemap.json`

Treat these as **generated artifacts**, not primary authored source.

## When to rebuild

Rebuild the place file when:

* source files under Rojo-managed paths change
* model JSON files under `src/Workspace` change
* validator/test schema changes affect Studio runtime expectations
* a Studio validation run is about to happen
* you need a fresh `.rbxlx` for manual inspection or multiplayer test

If unsure, rebuild.

## Working directory rule

Run Rojo commands from the **repository root**.

Do not assume the current shell is already at the correct path.

## Repo-to-Roblox mapping rule

Assume Rojo is the source of truth for how repository files map into Roblox services.

Common repo areas in this project include:

* `src/ReplicatedStorage`
* `src/ServerScriptService`
* `src/Workspace`

Before adding a new file, make sure it lives under an existing mapped path or update the project configuration in a bounded issue.

Do not place gameplay source in arbitrary folders and assume Rojo will include it.

## Source of truth rule

Author source in the repository.

Do **not** treat manual Studio edits to generated instances as durable source unless the workflow for that asset explicitly says otherwise.

If a change matters long-term, it should exist in repo-managed source.

## Generated file rule

Do not hand-edit generated artifacts unless a bounded issue explicitly requires it.

In normal workflow:

* edit repo source
* rebuild with Rojo
* validate in Studio

## Typical workflow

1. Edit source files in the repository.
2. Run:

   ```powershell
   rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
   ```
3. Open `TinyfolkRealmOfGiants.rbxlx` in Studio.
4. Run the required validation or playtest flow.
5. If validation depends on test code or runtime logs, record the evidence in the relevant issue.

## Studio launch tasks

Studio launch helpers may be added as VS Code tasks or repo-local scripts.
The supported launch target is the generated place file:

```text
TinyfolkRealmOfGiants.rbxlx
```

VS Code tasks should invoke repo-local scripts instead of hard-coding machine paths in the task definition.
If a local Roblox Studio executable path is needed, use a user-local override such as `ROBLOX_STUDIO_EXE` or an untracked editor setting.
Do not commit user-specific absolute Studio paths.

Studio launch and script-navigation helpers are for opening the right place or source context.
They are not proof of runtime validation.
Manual runtime evidence still belongs in the TIN-157 Studio validation path described in `docs/TESTING.md`.

### Local build/open path

Use the local built place when validating repository source or Rojo-managed layout changes.

From the repo root:

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

Then open:

```text
TinyfolkRealmOfGiants.rbxlx
```

Opening the place file is an operator step unless a supported repo-local launch task exists.
If a launch helper is added later, it should rebuild or clearly state whether it uses the existing local `.rbxlx`.

### Local built place vs published place

Use the local built place for:

* source-layout and map changes under `src/Workspace`
* local Studio runtime checks before issue closure
* manual TIN-157 validation sweeps
* confirming Rojo output reflects repository source

Use the Studio-published place for:

* live-place investigation
* published-version rollback/open decisions
* checking behavior that depends on the deployed Roblox place version
* published-client teleport validation through `docs/PUBLISHED_CLIENT_TELEPORT_TEST_PLAN.md`

Do not use a published place revision as proof that current repository source is valid.
Do not use a local `.rbxlx` check as proof that a published Roblox place version is correct.

## Common failure modes

### 1. Wrong working directory

Symptom:

* Rojo cannot find `default.project.json`
* output path is created in the wrong place

Fix:

* change to repo root and rerun the build command

### 2. Stale place file

Symptom:

* Studio does not reflect recent source edits

Fix:

* rebuild `TinyfolkRealmOfGiants.rbxlx`
* reopen or reload the place file in Studio

### 3. File added outside mapped paths

Symptom:

* source file exists in repo but not in Studio output

Fix:

* move the file into a mapped source path
* or update Rojo project structure in a bounded issue

### 4. Sourcemap mismatch

Symptom:

* tools/tests/debugging reference old paths or stale generated structure

Fix:

* regenerate the sourcemap and rebuild the place file from repo root

### 5. Studio-only assumptions

Symptom:

* something appears to work only after hand-editing in Studio
* rebuild removes the change

Fix:

* move the change into repo-managed source
* avoid relying on manual Studio edits as durable implementation

## Validation boundary

Rojo build success does **not** prove gameplay correctness.

Rojo validates that the project can be assembled into a place file.
Gameplay still requires the appropriate validation path:

* pure-Luau/headless tests for deterministic logic
* Studio/runtime checks for physics, interaction timing, multiplayer behavior, UI behavior, and other runtime-dependent systems

For manual Studio evidence rules, use `docs/TESTING.md`.

### Known TIN-157 runtime blocker

Current source layout places `GiantUpgradeBoard_A` at `[24, 4, 0]` and `GiantSpawn` at `[12, 0.5, 0]`, approximately 12.5 studs apart.
This is within `UpgradeBoardConfig.InteractionRangeStuds = 16`.
Upgrade-board runtime validation no longer requires the documented teleport mitigation for this source layout.

## Publish and rollback records

Git rollback and Roblox place revision rollback are separate operations.
Rolling back source commits does not roll back a published Roblox place version.
Rolling back a Roblox place revision does not change repository source.

Rollback is relevant when the published Roblox place version is wrong, unsafe, or needs comparison against an earlier published version.
It is not the normal path for validating local source/layout changes.

For local source/layout issues, rebuild the local `.rbxlx` and validate in Studio.
For published-place concerns, use Roblox place revision open/rollback workflow in Studio or the Roblox creator tools available to the operator.
Record the outcome in the linked issue.

When a major Studio-side change is published, record:

* universe ID
* place ID
* Roblox place version
* Git commit
* linked issue

Use Roblox place revision rollback/open workflow for place-version recovery.
Use Git rollback only for repository source recovery.

## Safe agent behavior

When using Rojo in this repo, the agent should:

* prefer rebuilding over guessing whether outputs are current
* avoid editing generated `.rbxlx` as if it were authored source
* keep source changes inside mapped paths
* call out when a requested change appears to require project-structure changes
* treat Rojo as a build/sync layer, not as design truth

## Not covered here

This file does not define:

* full testing workflow
* issue-specific Studio runbooks
* asset intake/import policy
* high-level project architecture

Those belong in other docs such as:

* `docs/TESTING.md`
* `docs/GAME_SPEC.md`
* `docs/SYSTEM_BOUNDARIES.md`
* asset/process docs if added later
