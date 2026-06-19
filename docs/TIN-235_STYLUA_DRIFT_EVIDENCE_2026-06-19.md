# TIN-235 StyLua Drift Evidence (2026-06-19)

**Issue:** [TIN-235](https://linear.app/spectranoir/issue/TIN-235/resolve-whole-tree-stylua-drift-blocking-full-validation)  
**Date:** 2026-06-19  
**Outcome:** **No-op remediation** — whole-tree StyLua already passes on current `master`; no `.luau` files required formatting changes.

## Baseline capture

Toolchain installed via `rokit install` (StyLua 2.4.1 per `rokit.toml`).

```powershell
rojo sourcemap default.project.json -o sourcemap.json
stylua --check --syntax Luau src tests
```

| Check | Exit code | Result |
|---|---|---|
| `stylua --check --syntax Luau src tests` | 0 | No drifted files reported |

## Full validation

```powershell
.\scripts\run-validation.ps1
```

| Gate | Exit code |
|---|---|
| stylua | 0 |
| selene | 0 |
| luau-lsp | 0 |

Full validation passed. Selene reported 15 warnings (pre-existing, allowed). luau-lsp reported unused-variable warnings (pre-existing, non-blocking).

## Changed-only validation

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
```

| Result | Exit code |
|---|---|
| No changed `.luau` files under `src/tests` | 0 |

## Regression guard

```powershell
.\scripts\run-tests.ps1
```

| Result | Exit code |
|---|---|
| Full Lune suite passed | 0 |

## Touched-file ledger

| path | classification | notes |
|---|---|---|
| *(none under `src/` or `tests/`)* | n/a | StyLua `--check` exit 0 on full tree; no formatting remediation applied |

## Docs-only changes in this slice

| path | classification | notes |
|---|---|---|
| `docs/TIN-235_STYLUA_DRIFT_KICKOFF_2026-06-19.md` | documentation | Kickoff record |
| `docs/TIN-235_STYLUA_DRIFT_EVIDENCE_2026-06-19.md` | documentation | This evidence record |
| `docs/TIN-235_STYLUA_DRIFT_CLOSURE_2026-06-19.md` | documentation | Closure record |

## Assessment

Historical StyLua drift cited during TIN-107 (e.g. `EscapeConfig.luau`) is no longer present on `master` as of 2026-06-19. Acceptance criteria are satisfied without `.luau` diffs: full validation StyLua gate passes, changed-only validation passes, and no behavior changes were introduced.
