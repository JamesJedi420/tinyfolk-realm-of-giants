# TIN-161 Defensive Prop Client Kickoff (2026-06-14)

## Issue

- ID: TIN-161 (follow-up slice)
- Title: Implement defensive prop obstacle system — F-key client wiring
- Linear: https://linear.app/spectranoir/issue/TIN-161/implement-defensive-prop-obstacle-system

## Goal

Make defensive prop drop/break playable from Studio without Query API command-bar helpers.

## In scope (this slice)

- `InteractionResolver` candidates for Tinyfolk drop and Giant timed break on `DefensiveProp_*` anchors.
- `DefensivePropService` ensures `DefensivePropRequest` remote exists under `ReplicatedStorage.Remotes`.
- Giant break uses start → delay → complete pattern (mirrors construction tasks).
- Client skips defensive drop when capture/carry interactions take precedence.

## Out of scope / deferred

- Portable props, HUD/VFX/audio polish.
- Live Studio spot-check evidence rows (manual after client lands).

## Validation plan

```powershell
.\scripts\run-validation.ps1 -ChangedOnly
lune run tests/defensive_prop_state.spec.luau
lune run tests/defensive_prop_service_runtime_entrypoint.spec.luau
.\scripts\run-tests.ps1
```
