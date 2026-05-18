# Read the original file
$lines = @(Get-Content "src/ReplicatedStorage/Shared/GiantRealm/CaptureState.luau")

# Find where to insert the constant
$insertIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^local function validCustodyWindow") {
        # Find the end of this function
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j] -match "^end$") {
                $insertIdx = $j
                break
            }
        }
        break
    }
}

# Insert the constant
if ($insertIdx -gt 0) {
    $lines = $lines[0..($insertIdx)] + "local MAX_CUSTODY_DURATION_SECONDS = 12" + "" + $lines[($insertIdx+1)..($lines.Count-1)]
}

# Convert back to string and write
$content = $lines -join "`n"

# Find and replace the custodian check
$old_check = 'if nextState.custodianByTarget[input.custodianUserId] ~= nil then
		nextState.lastReason = "custodian_already_holding"
		return { accepted = false, reason = "custodian_already_holding", state = nextState, record = nil }
	end'

$new_check = 'for _, record in pairs(nextState.captureByTarget) do
		if record ~= nil and record.custodianUserId == input.custodianUserId then
			nextState.lastReason = "custodian_already_holding"
			return { accepted = false, reason = "custodian_already_holding", state = nextState, record = nil }
		end
	end'

$content = $content -replace [regex]::Escape($old_check), $new_check

# Add the userId validations before the now check
$now_check = 'if not validNow(input.now) then'
$userid_checks = 'if not validUserId(input.custodianUserId) then
		nextState.lastReason = "invalid_custodian_user_id"
		return { accepted = false, reason = "invalid_custodian_user_id", state = nextState, record = nil }
	end

	if not validUserId(input.targetUserId) then
		nextState.lastReason = "invalid_target_user_id"
		return { accepted = false, reason = "invalid_target_user_id", state = nextState, record = nil }
	end

	if input.custodianUserId == input.targetUserId then
		nextState.lastReason = "self_capture_not_allowed"
		return { accepted = false, reason = "self_capture_not_allowed", state = nextState, record = nil }
	end

	if not validNow(input.now) then'

$content = $content -replace [regex]::Escape($now_check), $userid_checks

# Write the file
$content | Set-Content "src/ReplicatedStorage/Shared/GiantRealm/CaptureState.luau"

Write-Host "File updated successfully"
