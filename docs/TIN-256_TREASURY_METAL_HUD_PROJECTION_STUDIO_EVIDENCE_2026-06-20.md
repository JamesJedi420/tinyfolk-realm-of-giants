# TIN-256 Treasury Metal HUD Projection Studio Evidence (2026-06-20)

**Linear:** [TIN-256](https://linear.app/spectranoir/issue/TIN-256/project-session-metal-into-giant-treasury-hud)

## Goal

Verify Giant treasury HUD shows session Metal after warehouse delivery.

## Preconditions

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

Play Solo as Giant realm owner. Metal flow path available (forge refine → haul → warehouse deliver per TIN-27).

## Playtest steps

### 1. Session Metal visible after warehouse delivery

- Complete forge→warehouse Metal delivery chain.
- Open Giant HUD right-stack Treasury section.

**Expected:** Summary includes `M` with value > 0 (e.g. `Session E0 W… S… M15`).

### 2. Session Wood/Stone reflect stored flow

- Deliver Wood or Stone to warehouse.

**Expected:** Session W/S values update in treasury summary (not stuck at 0).

### 3. Live refresh after delivery

- Note treasury summary before delivery, deliver Metal, check again without rejoin.

**Expected:** Metal count updates without session restart.

## Evidence table

| Step | Result | Notes |
|------|--------|-------|
| 1. Session Metal after delivery | PENDING | |
| 2. Session W/S from flow | PENDING | |
| 3. Live refresh | PENDING | |
