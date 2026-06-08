#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v lune >/dev/null 2>&1; then
	echo "lune is not installed. Install via rokit: rokit install" >&2
	exit 1
fi

test_files=(
	tests/event_log_state.spec.luau
	tests/event_log_service_runtime_entrypoint.spec.luau
	tests/published_client_teleport_evidence.spec.luau
	tests/profile_teleport_admission_service_runtime_entrypoint.spec.luau
	tests/profile_teleport_handoff_service_runtime_entrypoint.spec.luau
	tests/profile_teleport_handoff_admission_ingress_runtime_entrypoint.spec.luau
	tests/profile_persistence_gateway_runtime_entrypoint.spec.luau
	tests/event_state_ownership_model.spec.luau
	tests/role_service_event_routing_runtime_entrypoint.spec.luau
	tests/role_service_runtime_entrypoint.spec.luau
	tests/role_loadout_service_runtime_entrypoint.spec.luau
	tests/specialist_assignment_service_runtime_entrypoint.spec.luau
	tests/station_service_runtime_entrypoint.spec.luau
	tests/shrine_service_runtime_entrypoint.spec.luau
	tests/warehousing_service_runtime_entrypoint.spec.luau
	tests/upgrade_progression_logic.spec.luau
	tests/remote_control_station_state.spec.luau
	tests/remote_control_station_service_runtime_entrypoint.spec.luau
	tests/emergency_reinforcement_state.spec.luau
	tests/emergency_reinforcement_service_runtime_entrypoint.spec.luau
	tests/capture_state.spec.luau
	tests/trait_registry_schema.spec.luau
	tests/giant_trait_state.spec.luau
	tests/role_loadout_state.spec.luau
	tests/reputation_state.spec.luau
	tests/reputation_presentation.spec.luau
	tests/tinyfolk_tool_catalog_schema.spec.luau
	tests/tinyfolk_tool_loadout_state.spec.luau
	tests/tinyfolk_tool_loadout_service_runtime_entrypoint.spec.luau
	tests/containment_reward_resolver.spec.luau
	tests/giant_realm_resource_state.spec.luau
	tests/giant_realm_resource_resolver.spec.luau
	tests/giant_realm_resource_pair_history_state.spec.luau
	tests/realm_resource_pair_history_store.spec.luau
	tests/giant_realm_treasury_presentation.spec.luau
	tests/village_worksite_upgrade_state.spec.luau
	tests/capture_service_runtime_entrypoint.spec.luau
	tests/score_state.spec.luau
	tests/score_service_runtime_entrypoint.spec.luau
	tests/front_desk_hub_presentation.spec.luau
	tests/realm_objective_state.spec.luau
	tests/realm_objective_service_runtime_entrypoint.spec.luau
	tests/tinyfolk_giant_proximity_warning.spec.luau
	tests/tinyfolk_raid_status_projection.spec.luau
	tests/giant_threat_stage_logic.spec.luau
	tests/timed_condition_states_runtime_entrypoint.spec.luau
	tests/fallback_escape_state.spec.luau
	tests/final_exit_state.spec.luau
	tests/player_created_route_state.spec.luau
	tests/snare_trap_state.spec.luau
	tests/escape_outcome_resolver.spec.luau
	tests/escape_service_runtime_entrypoint.spec.luau
	tests/tinyfolk_status_service_runtime_entrypoint.spec.luau
	tests/memory_store_adapter.spec.luau
	tests/messaging_service_adapter.spec.luau
	tests/notification_rate_guard.spec.luau
	tests/notification_message_schema.spec.luau
	tests/notification_reconciliation_service.spec.luau
	tests/notification_subscription_manager.spec.luau
	tests/queue_notification_fanout.spec.luau
	tests/system_announcement_service_runtime_entrypoint.spec.luau
	tests/wildlife_state.spec.luau
	tests/neutral_wildlife_service_runtime_entrypoint.spec.luau
	tests/memorystore_structure_policy.spec.luau
	tests/transfer_lock_service_runtime_entrypoint.spec.luau
	tests/realm_teleport_dispatcher_runtime_entrypoint.spec.luau
	tests/realm_admission_party_resolver_service_runtime_entrypoint.spec.luau
	tests/queue_processing_idempotency_store.spec.luau
	tests/realm_admission_queue_state.spec.luau
	tests/realm_admission_queue_store.spec.luau
	tests/realm_admission_queue_processor.spec.luau
	tests/realm_admission_queue_service_runtime_entrypoint.spec.luau
	tests/party_matchmaking_realm_resolver_service_runtime_entrypoint.spec.luau
	tests/party_matchmaking_admission_service_runtime_entrypoint.spec.luau
	tests/rescue_admission_service_runtime_entrypoint.spec.luau
	tests/realm_metadata_registry.spec.luau
	tests/realm_theme_family_schema.spec.luau
	tests/realm_chunk_assembly_schema.spec.luau
	tests/district_placement_assembly_selection_runtime_entrypoint.spec.luau
	tests/active_realm_capacity_state.spec.luau
	tests/active_realm_capacity_store.spec.luau
	tests/rescue_contract_state.spec.luau
	tests/rescue_contract_admission_ingress_runtime_entrypoint.spec.luau
	tests/rescue_contract_service_runtime_entrypoint.spec.luau
	tests/headless_match_simulation.spec.luau
)

for test_file in "${test_files[@]}"; do
	echo "[tests] lune run ${test_file}"
	lune run "$test_file"
done

echo "[tests] all specs passed"
