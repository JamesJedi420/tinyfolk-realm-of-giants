# TIN-252 Giant HUD Right-Stack Studio Evidence (2026-06-19)

**Linear:** [TIN-252](https://linear.app/spectranoir/issue/TIN-252/consolidate-giant-hud-right-stack-panels)  
**PR:** https://github.com/JamesJedi420/tinyfolk-realm-of-giants/pull/146  
**Merge:** `793b3565`

## Goal

Verify in Studio that the four former right-stack HUD panels render as one non-overlapping accordion (`GiantHudStackGui`) with live attribute updates and unchanged left/bottom-left panels.

## Preconditions

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

Open `TinyfolkRealmOfGiants.rbxlx` in Studio. Play Solo as **Giant** (realm owner with projections active).

## Playtest steps

### 1. Single stack, no overlap

- Confirm only **one** right-column HUD owner: `PlayerGui.GiantHudStackGui`.
- Confirm legacy GUIs are absent: `GiantTreasuryHudGui`, `PenRationingHudGui`, `SocialEconomyHudGui`, `GiantEffectHudGui`.
- Confirm four sections stack vertically without overlap: Treasury, Pen Rationing, Social Economy, Giant Effects.

**Expected:** No duplicate or overlapping right-edge panels.

### 2. Collapsed summaries

- With realm data projected, each visible section shows a **collapsed** first-line summary under its header.
- Sections with no data remain hidden (same visibility rules as before migration).

**Expected:** Collapsed rows readable; hidden sections stay hidden.

### 3. Expand / collapse

- Click `+` on each visible section → full detail text appears; toggle shows `−`.
- Click `−` → returns to collapsed summary only.

**Expected:** Toggle works independently per section.

### 4. Live attribute updates

- While a section is **collapsed**, trigger a relevant attribute change (e.g. treasury ledger update, pen shortfall tick, social economy event, giant effect stat).
- Repeat with section **expanded**.

**Expected:** Summary/detail text updates without reopening Studio.

### 5. Left / bottom-left unchanged

- Village Status panel still on **left** (`VillageStatusHudGui` or equivalent).
- Tinyfolk Inspect still **bottom-left**; click-select + highlight unchanged.

**Expected:** No layout regression on left stack.

## Automated regression companion

```powershell
lune run tests/pen_rationing_hud_presentation.spec.luau
lune run tests/giant_effect_hud_presentation.spec.luau
.\scripts\run-validation.ps1 -ChangedOnly
```

## Studio runtime evidence table

| Step | Result | Notes |
|------|--------|-------|
| Single `GiantHudStackGui`; legacy right GUIs absent | PENDING | |
| Four sections stack without overlap | PENDING | |
| Collapsed summaries when data projected | PENDING | |
| Expand/collapse toggle per section | PENDING | |
| Live updates while collapsed | PENDING | |
| Live updates while expanded | PENDING | |
| Village Status left panel unchanged | PENDING | |
| Tinyfolk Inspect bottom-left unchanged | PENDING | |
| **Overall Studio smoke** | **PENDING** | Mark PASS when all rows pass |

## Related docs

- [TIN-252 kickoff](TIN-252_CONSOLIDATE_GIANT_HUD_RIGHT_STACK_KICKOFF_2026-06-19.md)
- [TIN-252 closure](TIN-252_CONSOLIDATE_GIANT_HUD_RIGHT_STACK_CLOSURE_2026-06-19.md)
