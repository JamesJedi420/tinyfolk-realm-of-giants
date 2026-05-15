# Create Emergency Reinforcement Linear Issue
$apiKey = Get-Content ".env" | ForEach-Object { if ($_ -match '^LINEAR_API_KEY=(.*)$') { $Matches[1] } }

if ([string]::IsNullOrEmpty($apiKey)) {
    Write-Error "LINEAR_API_KEY not found in .env"
    exit 1
}

$teamId = "3bb0f127-b6ed-4013-944d-f48c26212569"
$query = @"
mutation {
  issueCreate(input: {
    teamId: "$teamId"
    title: "VHS: Emergency Reinforcement Call System"
    description: """
VHS NEW_ISSUE_CANDIDATE from mechanics survey.

**System:** One-time mid-match reinforcement call where Tinyfolk can summon a hero ally (Private or Army role with defined loadout) if the team is reduced.

**Acceptance Criteria:**
1. Reinforcement call is one-time per match, not repeatable
2. Deterministic spawn logic: summoned hero appears at designated spawn with role/traits initialized
3. Call is valid only if active Tinyfolk count < X (threshold TBD by design, suggest ≤2 Tinyfolk remain)
4. UI: radio icon + countdown timer displayed on HUD during call
5. Integration point: trigger is a special objective token (call-center control zone)
6. Cooldown: enforced server-side, cannot stack multiple calls
7. Summoned ally inherits shared team loadout and communication

**Design Scope:**
- Team-size threshold tuning
- Spawn safety validation using safe-zone rules
- Role/traits initialization for summoned hero

**Out of Scope:**
- Aesthetic/audio (radio static, alert beep)
- VFX for ally arrival
- Full HUD callout system (tracked by TIN-164/TIN-165)
- Persistence of call history
- Advanced anti-snowball mechanics

**Fold-In Note:**
Ties directly to TIN-72 (Rescue Contracts). If rescue-contract allies and reinforcement-call allies are unified systems, they must share role/trait initialization and spawn validation logic.

**Risk & Fairness:**
- Team-size threshold is game-balance critical
- Suggest playtesting multiple thresholds (1, 2, 3 Tinyfolk remain)
- Prevent abuse: reinforcement should not trigger at match start
- Validate against active player count, not total player count
- Ensure spawn does not place ally in trapped/unsafe zone; use safe-zone rules

**Evidence:**
See docs/SYSTEM_BOUNDARIES.md "VHS Mechanics Analysis and Translation Framework" section for full mechanic mapping, design boundaries, and fold-in guidance.
"""
  }) {
    issue {
      id
      identifier
      title
      state {
        name
      }
    }
  }
}
"@

$payload = @{ query = $query } | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "https://api.linear.app/graphql" `
        -Method Post `
        -Headers @{ 
            "Authorization" = $apiKey
            "Content-Type" = "application/json"
        } `
        -Body $payload `
        -TimeoutSec 30

    if ($response.errors) {
        Write-Error "GraphQL Error: $($response.errors | ConvertTo-Json)"
        exit 1
    }

    $issue = $response.data.issueCreate.issue
    Write-Host "✅ Emergency Reinforcement Issue Created"
    Write-Host "   Issue ID: $($issue.identifier)"
    Write-Host "   Title: $($issue.title)"
    Write-Host "   State: $($issue.state.name)"
    Write-Host ""
    Write-Host "Evidence saved in: docs/SYSTEM_BOUNDARIES.md"
    Write-Host "Next: Update TIN-72 (Rescue Contracts) with fold-in reference"
} catch {
    Write-Error "Failed to create issue: $($_.Exception.Message)"
    exit 1
}
