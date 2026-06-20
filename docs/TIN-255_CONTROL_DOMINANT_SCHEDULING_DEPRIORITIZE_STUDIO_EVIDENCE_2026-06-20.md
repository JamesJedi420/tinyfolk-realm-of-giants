# TIN-255 Control-Dominant Scheduling Deprioritize Studio Evidence (2026-06-20)

**Linear:** [TIN-255](https://linear.app/spectranoir/issue/TIN-255/deprioritize-control-dominant-tinyfolk-in-job-scheduling-worker-order)

## Goal

Verify job scheduling deprioritizes control-dominant Tinyfolk when balanced or favor-dominant workers compete for the same demand.

## Preconditions

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

Active Giant realm with TIN-31 scheduling and TIN-251 dyadic projection. Two+ in-realm Tinyfolk with contrasting dyadic dominance (control-dominant vs balanced/favor-dominant).

## Playtest steps

### 1. Balanced beats control-dominant despite lower raw favor

- One open specialist or haul demand.
- Worker A: control-dominant dyadic (control > favor beyond threshold), slightly higher raw favor.
- Worker B: balanced dyadic (within threshold), lower raw favor.

**Expected:** Worker B receives scheduled job attributes first.

### 2. Favor-dominant beats control-dominant at equal raw favor

- Two workers with equal favor but different control dominance.

**Expected:** Favor-dominant worker scheduled first.

### 3. Debug snapshot dominance axis

- Query job scheduling debug snapshot.

**Expected:** Worker rows include `scheduleDominantAxis` (`favor`, `balanced`, or `control`).

## Evidence table

| Step | Result | Notes |
|------|--------|-------|
| 1. Balanced beats control-dominant | PENDING | |
| 2. Favor beats control at equal favor | PENDING | |
| 3. Debug dominance axis | PENDING | |
