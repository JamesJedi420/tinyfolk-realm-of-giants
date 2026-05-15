# Post evidence comment to TIN-226
$apiKey = Get-Content ".env" | ForEach-Object { if ($_ -match '^LINEAR_API_KEY=(.*)$') { $Matches[1] } }

# Query for issue ID
$issueIdQuery = 'query { issues(filter: { number: { eq: 226 } }) { nodes { id identifier } } }'
$payload = @{ query = $issueIdQuery } | ConvertTo-Json
$issueResp = Invoke-RestMethod -Uri "https://api.linear.app/graphql" -Method Post `
    -Headers @{ "Authorization"=$apiKey; "Content-Type"="application/json" } -Body $payload
$issueId = $issueResp.data.issues.nodes[0].id

Write-Host "Issue ID: $issueId"

# Post comment
$comment = @"
**Framework Integration Complete** 

Evidence integrated into system design boundaries.

**Framework:** VHS Mechanics Analysis → Tinyfolk Candidates translation mapped in `docs/SYSTEM_BOUNDARIES.md`

**Classification:** NEW_ISSUE_CANDIDATE (HIGH priority, game-impact)
- 6 FOLD_INTO_EXISTING candidates identified (Stamina, Tasks, QTE, Conditions, Dash, Traps)
- 2 ALREADY_REPRESENTED mechanics (Banishment, Perks)

**Acceptance Criteria:**
✓ One-time per match reinforcement call
✓ Deterministic spawn with role/traits (Private or Army hero)
✓ Valid only if Tinyfolk count < threshold (suggest ≤2)
✓ UI: radio icon + countdown
✓ Trigger: special objective token (call-center zone)
✓ Server-side cooldown enforcement
✓ Summoned ally inherits team loadout

**Design Risk:** Game-balance critical on team-size threshold; requires playtesting.

**Fold-In Note:** Ties to TIN-72 (Rescue Contracts) if unified with rescue-contract allies.

**Evidence:**
- Git commit: ebb145a ("Design: Integrate VHS mechanics framework...")
- Source: docs/SYSTEM_BOUNDARIES.md § VHS Mechanics Analysis and Translation Framework
- Original survey: provided in conversation with full mechanic triggers, actors, constraints, HUD elements
"@

$mutation = @"
mutation {
  commentCreate(input: {
    issueId: "$issueId"
    body: """$comment"""
  }) {
    comment {
      id
      body
    }
  }
}
"@

$commentPayload = @{ query = $mutation } | ConvertTo-Json
$commentResp = Invoke-RestMethod -Uri "https://api.linear.app/graphql" -Method Post `
    -Headers @{ "Authorization"=$apiKey; "Content-Type"="application/json" } -Body $commentPayload

if ($commentResp.errors) {
    Write-Error "GraphQL Error: $($commentResp.errors | ConvertTo-Json)"
} else {
    $commentId = $commentResp.data.commentCreate.comment.id
    Write-Host "✅ Evidence comment posted"
    Write-Host "   Comment ID: $commentId"
}
