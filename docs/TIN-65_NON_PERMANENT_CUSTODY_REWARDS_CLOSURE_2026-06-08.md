# TIN-65 Non-Permanent Tinyfolk Custody Rewards Closure (2026-06-08)

## Issue
- ID: TIN-65
- Title: Implement non-permanent Tinyfolk custody rewards
- Linear: https://linear.app/spectranoir/issue/TIN-65/implement-non-permanent-tinyfolk-custody-rewards

## Shipped
- `ContainmentRewardResolver` grants bounded score (and optional realm resource) on custody end.
- Diminishing returns via pair multipliers (1× / 0.5× / 0.25×) and custody-held ratio.
- Pair reward cap (3 scored outcomes per Giant/Tinyfolk pair per retention window).
- Durable `containmentRewardIdempotency` prevents duplicate awards.
- Wired from `CaptureService`, `EscapeService`, and `RescueContractService` for release, timeout, logout, escape, rescue, and safe-return paths.
- Tinyfolk account progression is never transferred—only custodian-side score/reputation/resources update.

## Deferred
- Cross-server durable pair anti-farming history (documented in `docs/SYSTEM_BOUNDARIES.md`).

## Key files
- `src/ServerScriptService/Services/ContainmentRewardResolver.luau`
- `src/ServerScriptService/Services/CaptureService.server.luau`
- `src/ServerScriptService/Services/GiantRealmResourceResolver.luau`

## Validation
```powershell
lune run tests/containment_reward_resolver.spec.luau
lune run tests/capture_service_runtime_entrypoint.spec.luau
lune run tests/giant_realm_resource_resolver.spec.luau
```
