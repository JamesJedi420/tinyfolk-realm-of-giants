# TIN-257 Giant HUD Stack Collapse Persistence Studio Evidence (2026-06-20)

| Check | Result | Notes |
|-------|--------|-------|
| Play Solo as Giant — expand Treasury + Social Economy | PENDING | |
| Leave session and rejoin same Giant account | PENDING | |
| Treasury + Social Economy sections restore expanded | PENDING | |
| Collapse Pen Rationing, rejoin — section stays collapsed | PENDING | |
| Play as Tinyfolk — no preference mutation / no stack preference errors | PENDING | |

## Validation commands (automated)

```powershell
lune run tests/giant_hud_stack_preference_profile_state.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
