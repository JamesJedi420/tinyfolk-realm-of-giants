# TIN-253 Loyalty-tone Inspect Highlight Studio Evidence (2026-06-20)

**Linear:** [TIN-253](https://linear.app/spectranoir/issue/TIN-253/loyalty-tone-inspect-selection-highlight)

## Goal

Verify highlight color reflects dyadic loyalty axis while panel accent stays custody-based.

## Preconditions

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

Play Solo as Giant with dyadic relations projected (see TIN-251 evidence steps).

## Playtest steps

### 1. Favor-dominant dyadic

- Select Tinyfolk with favor > control (beyond balance threshold).

**Expected:** Highlight green-teal (`positive`); panel left accent stays neutral gray if free.

### 2. Control-dominant dyadic

- Select Tinyfolk with control > favor.

**Expected:** Highlight amber (`warning`); panel accent neutral if free.

### 3. Custody overrides dyadic

- Select captured/carried Tinyfolk that also has high favor.

**Expected:** Highlight warning/critical from custody; not favor green.

### 4. Live dyadic refresh

- With inspect open, trigger social event updating dyadic attrs.

**Expected:** Highlight color updates without re-select; panel accent unchanged unless custody attrs change.

### 5. Cleared dyadic

- Release/escape clears dyadic attrs.

**Expected:** Highlight reverts to neutral or custody-only tone.

## Studio runtime evidence table

| Step | Result | Notes |
|------|--------|-------|
| Favor-dominant → positive highlight | PENDING | |
| Control-dominant → warning highlight | PENDING | |
| Captured/custody overrides favor highlight | PENDING | |
| Social event → highlight updates live | PENDING | |
| Dyadic cleared → highlight reverts | PENDING | |
| **Overall Studio smoke** | **PENDING** | Mark PASS when all rows pass |
