# TIN-119 Queue Processing Idempotency Closure (2026-06-08)

## Issue
- ID: TIN-119
- Title: Implement queue processing idempotency
- Linear: https://linear.app/spectranoir/issue/TIN-119/implement-queue-processing-idempotency

## Shipped
- `QueueProcessingIdempotencyStore` with MemoryStore-backed `TryBegin` / `MarkCompleted` / duplicate detection.
- Admission queue processing (`RealmAdmissionQueueProcessor`) gates dispatch on idempotency; tolerates remove failures via `cleanupDeferred`.
- Rescue queue acceptance (`RescueContractService`) prevents duplicate handoff/enqueue on repeated accept.
- Required `operationId` on admission and rescue queue entries.
- Outcome-specific idempotency maps for escape and containment rewards share the same store module.

## Deferred
- Dedicated return-flow idempotency spec (transfer/return inherits admission `operationId` propagation).
- Unified durable-transaction layer across all outcome types.

## Key files
- `src/ServerScriptService/Services/QueueProcessingIdempotencyStore.luau`
- `src/ServerScriptService/Services/RealmAdmissionQueueProcessor.luau`
- `src/ServerScriptService/Services/RescueContractService.server.luau`

## Validation
```powershell
lune run tests/queue_processing_idempotency_store.spec.luau
lune run tests/realm_admission_queue_processor.spec.luau
lune run tests/rescue_contract_service_runtime_entrypoint.spec.luau
lune run tests/realm_admission_queue_state.spec.luau
```
