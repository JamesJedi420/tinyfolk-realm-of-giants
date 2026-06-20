# TIN-251 Dyadic Loyalty Inspect Studio Evidence (2026-06-19)

**Linear:** [TIN-251](https://linear.app/spectranoir/issue/TIN-251/project-dyadic-loyalty-to-tinyfolk-inspect)  
**PR:** https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/144  
**Merge:** `13a97296` (feature); StyLua hotfix `793b3565` on master

## Goal

Verify in Studio that Giant inspect shows per-Tinyfolk dyadic loyalty from server-projected attributes, clears on custody exit, and updates live.

## Preconditions

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

Play Solo with at least one Giant (realm owner) and one Tinyfolk.

## Playtest steps

### 1. Capture → loyalty line

- Capture a Tinyfolk (trophy/social event with target).
- Giant click-select the captive → open inspect panel.

**Expected:** `Loyalty: Favor N / Control N` (not `Unavailable`).

### 2. No dyadic entry

- Select a Tinyfolk with no dyadic relation / cleared attrs.

**Expected:** `Loyalty: Unavailable`.

### 3. Release / escape

- Release or escape the captive; keep inspect open or re-select.

**Expected:** Loyalty attrs cleared; inspect line returns to `Unavailable`.

### 4. Live refresh on social event

- With inspect open on a target Tinyfolk, trigger a trophy/social event that updates dyadic favor/control.

**Expected:** Loyalty line updates without re-selecting.

## Automated regression companion

```powershell
lune run tests/tinyfolk_inspect_state.spec.luau
lune run tests/social_economy_service_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Studio runtime evidence table

| Step | Result | Notes |
|------|--------|-------|
| Capture → loyalty shows Favor / Control | PENDING | |
| No dyadic entry → Unavailable | PENDING | |
| Release / escape → loyalty cleared | PENDING | |
| Social event → inspect loyalty refreshes live | PENDING | |
| **Overall Studio smoke** | **PENDING** | Mark PASS when all rows pass |

## Related docs

- [TIN-251 kickoff](TIN-251_PROJECT_DYADIC_LOYALTY_TO_TINYFOLK_INSPECT_KICKOFF_2026-06-19.md)
