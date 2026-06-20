# TIN-254 Dyadic Job Scheduling Worker Rank Studio Evidence (2026-06-20)

**Linear:** [TIN-254](https://linear.app/spectranoir/issue/TIN-254/prefer-dyadic-favor-tinyfolk-in-job-scheduling-worker-order)

## Goal

Verify job scheduling prefers higher dyadic-favor Tinyfolk when multiple workers compete for the same demand.

## Preconditions

```powershell
rojo build default.project.json -o TinyfolkRealmOfGiants.rbxlx
```

Active Giant realm with TIN-31 scheduling enabled, two+ in-realm Tinyfolk with different projected dyadic favor (see TIN-251 capture/social event steps).

## Playtest steps

### 1. Higher favor wins specialist demand

- Ensure one open specialist station demand (e.g. woodcutter at `WorkStation_A`).
- Two eligible Tinyfolk: one with higher `SocialDyadicFavor`, one lower.

**Expected:** Higher-favor Tinyfolk receives scheduled specialist job attributes first (`TinyfolkScheduledJobKind`, station id).

### 2. Equal favor, lower control wins

- Two Tinyfolk with equal favor but different control.

**Expected:** Lower-control worker scheduled first when both eligible for same demand.

### 3. Debug snapshot rank fields

- Request job scheduling debug remote or query `_TinyfolkJobSchedulingService_QueryAPI.GetDebugSnapshot()`.

**Expected:** Worker rows include `scheduleRankFavor` / `scheduleRankControl` matching resolved rank inputs.

## Evidence table

| Step | Result | Notes |
|------|--------|-------|
| 1. Higher favor wins | PENDING | |
| 2. Control tie-break | PENDING | |
| 3. Debug snapshot ranks | PENDING | |
