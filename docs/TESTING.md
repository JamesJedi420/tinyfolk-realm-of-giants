# Testing

## Install Lune (Windows)

Run:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" install --id Lune.Lune --exact --source winget --accept-source-agreements --accept-package-agreements
```

## Run TIN-96 Phase 1 tests

From the repo root, run:

```powershell
.\scripts\run-tests.ps1
```

If `lune` is still not found right after install, open a new terminal so PATH updates are picked up.
