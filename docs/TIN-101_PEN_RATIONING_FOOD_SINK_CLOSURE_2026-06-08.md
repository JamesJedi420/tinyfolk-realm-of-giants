# TIN-101 Pen Rationing Food Sink — Closure

**Date:** 2026-06-08  
**Parent:** [TIN-101](https://linear.app/spectranoir/issue/TIN-101)  
**Branch:** `tin-101-pen-rationing-food-sink`

## Goal

Add ongoing Granary Food consumption while pens hold active custody captives.

## Shipped

- `PenRationingConfig` — interval (1s) and food-per-captive-per-interval (1).
- `PenRationingState` — pure cost and accumulator tick math.
- `PenRationingService` — heartbeat reads active captures via `_CaptureService_QueryAPI`, spends stored Food, mirrors state on `Pen_A` attributes.
- Shortfall when granary is empty sets `PenRationingLastFoodShortfall`; captives are not auto-released in this slice.

## Validation

```powershell
lune run tests/pen_rationing_state.spec.luau
lune run tests/pen_rationing_service_runtime_entrypoint.spec.luau
lune run tests/tin_food_pen_rationing_runtime_entrypoint.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```
