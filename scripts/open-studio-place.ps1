param(
	[string]$PlaceFile = "TinyfolkRealmOfGiants.rbxlx",
	[switch]$Build
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if ($Build) {
	Write-Host "[studio] building place file..."
	rojo build default.project.json -o $PlaceFile
}

$placePath = Join-Path $repoRoot $PlaceFile
if (-not (Test-Path $placePath)) {
	throw "Place file not found: $placePath (run with -Build or rojo build first)"
}

$studioExe = $env:ROBLOX_STUDIO_EXE
if ([string]::IsNullOrWhiteSpace($studioExe)) {
	$versionsRoot = Join-Path $env:LOCALAPPDATA "Roblox\Versions"
	$studioExe = Get-ChildItem $versionsRoot -Filter "RobloxStudioBeta.exe" -Recurse -ErrorAction SilentlyContinue |
		Select-Object -First 1 -ExpandProperty FullName
}

if ([string]::IsNullOrWhiteSpace($studioExe) -or -not (Test-Path $studioExe)) {
	throw "Roblox Studio not found. Set ROBLOX_STUDIO_EXE or install Studio."
}

Write-Host "[studio] opening $placePath"
Start-Process -FilePath $studioExe -ArgumentList "`"$placePath`""
