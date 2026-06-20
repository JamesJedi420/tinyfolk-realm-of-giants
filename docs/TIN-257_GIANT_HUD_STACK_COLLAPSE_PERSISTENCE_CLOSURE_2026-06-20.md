# TIN-257 Giant HUD Stack Collapse Persistence Closure (2026-06-20)

## Shipped

- `GiantHudStackPreferenceProfileState` — player profile key `giantHudStackPreference` with `expandedBySectionId` validated against `GiantHudStackConfig.SectionOrder`
- `GiantHudStackConfig` — preference remotes and JSON projection attribute
- `GiantHudStackPreferenceService` — Giant role gate, profile persist on toggle, attribute projection on join/role change
- `ProfilePersistenceGateway` + `EventStateOwnershipModel` wiring
- `GiantHudStackClient` — load preference before layout; save on section toggle via remote
- Pure tests in `tests/giant_hud_stack_preference_profile_state.spec.luau`
- `docs/SYSTEM_BOUNDARIES.md` TIN-257 note

## Validation

- `lune run tests/giant_hud_stack_preference_profile_state.spec.luau` — PASS (local)
- `.\scripts\run-validation.ps1 -ChangedOnly` — StyLua unavailable locally; CI source of truth
- Studio evidence — PENDING (see evidence doc)

## Deferred

- TIN-252 unified theming/animation
- Village Status dedupe
- Mobile/gamepad layout pass
