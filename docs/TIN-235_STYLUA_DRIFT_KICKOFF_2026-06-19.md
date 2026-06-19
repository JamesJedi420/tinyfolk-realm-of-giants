# TIN-235 StyLua Drift Kickoff (2026-06-19)

## Issue
- ID: TIN-235
- Title: Resolve whole-tree StyLua drift blocking full validation
- Linear: https://linear.app/spectranoir/issue/TIN-235/resolve-whole-tree-stylua-drift-blocking-full-validation
- Status: In Progress

## Why This Slice Exists
- Slices often validate with `.\scripts\run-validation.ps1 -ChangedOnly`, which only checks touched `.luau` files.
- Full validation (`.\scripts\run-validation.ps1`) and CI (`scripts/run-validation.sh`) scan all `src` + `tests` files.
- TIN-107 closure noted whole-tree StyLua drift (e.g. `EscapeConfig.luau`) blocked full validation outside active slices.

## Bounded Scope
- Identify files failing `stylua --check --syntax Luau src tests`.
- Apply formatting-only fixes via pinned StyLua (`rokit.toml` → StyLua 2.4.1).
- Minimal syntax repair only when StyLua cannot parse a file.
- Evidence doc with touched-file ledger.

## Out of Scope
- luau-lsp baseline debt remediation.
- Selene rule or warning cleanup.
- Behavior or logic changes.
- Editor format-on-save policy changes.

## Constraints
- Formatting-only unless inspection proves minimal syntax repair is required.
- No behavior changes.
- Use `stylua.toml` config (120 cols, tabs, Unix line endings, Luau syntax).

## Validation Plan
```powershell
rokit install
rojo sourcemap default.project.json -o sourcemap.json
stylua --check --syntax Luau src tests
.\scripts\run-validation.ps1
.\scripts\run-validation.ps1 -ChangedOnly
.\scripts\run-tests.ps1
```

## Baseline (2026-06-19)
- `stylua --check --syntax Luau src tests` → exit 0 (no drift on current `master`)
- `.\scripts\run-validation.ps1` → stylua/selene/luau-lsp exit 0
- Remediation skipped; evidence recorded in `docs/TIN-235_STYLUA_DRIFT_EVIDENCE_2026-06-19.md`
