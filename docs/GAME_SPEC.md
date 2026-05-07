# Tinyfolk: Realm of Giants - Game Spec

## Project Identity
- Project name: Tinyfolk: Realm of Giants.
- This repository should not be framed as or referred to as Containment Protocol.
- Current codebase status: prototype-scale implementation.

## Scope Markers
Use these markers consistently in design and implementation discussions:
- Current prototype: implemented now in this repository.
- Long-term direction: intended future structure, not fully implemented yet.

## Current Prototype (High Level)
- Server-authoritative role, interaction, escape, and upgrade flows.
- Primary interaction key is context-sensitive `F` for current bounded interaction surfaces.
- Giant upgrade board progression is deterministic and ordered by configured sequence for the current prototype board.
- Giant upgrade board interaction is next-step-only: `F` at a valid board advances only the next valid upgrade in sequence.
- Role selection is pre-spawn and server-authoritative.
- First valid role selection wins for the session and locks role switching.
- Deterministic shrine Essence generation and WorkStation_A Wood generation.
- Bounded Giant session Essence pool linked to current upgrade spending.
- Server-owned Tinyfolk specialist assignment state (single assignment slot).
- WorkStation_A is Woodcutter-gated at runtime and feeds bounded session Wood production.
- Server-owned canonical Wood/Stone flow state tracks Produced, InTransit, and Stored totals.
- Manual interaction flow moves Produced -> InTransit by workstation interaction, then InTransit -> Stored by Warehouse_A interaction.
- Interaction resolution for current bounded surfaces is deterministic by priority, then distance, then target id.
- Granary_A is reserved for future food/crop resources.
- Stored Wood/Stone totals are the current usable realm totals.
- Prototype construction spending uses stored Wood/Stone only.
- Produced and InTransit material totals are not spendable for construction.
- Prototype map and interaction surfaces for playtest validation.

## Long-Term World Model Direction
- Shared Tinyfolk world exists as the primary Tinyfolk social/economic layer.
- Per-Giant realms are future destinations/layers.
- Capture moves Tinyfolk from the shared world into a Giant realm.
- Escape returns Tinyfolk from a Giant realm back to the shared Tinyfolk world.
- Trade can later move Tinyfolk between Giant realms.

Important:
- This is directional architecture only.
- Full realm transfer/instancing is not part of the current prototype.

## Giant End-Game Direction
Design rule:
- The Giant should become a distinct realm ruler, not an unbeatable stat stack.

Design consequence:
- Tinyfolk must retain meaningful agency, counterplay, and reasons to stay, work, resist, or escape.

Future realm identity vectors (exploratory, not locked):
- Favor
- Fear
- Covenant
- Miracle
- Domain Expansion
- Essence Economy

## Resource Model Direction
- Essence: spiritual, ritual, miracle resource.
- Wood: material resource for building, repairs, and structures.
- Stone: material resource for walls, infrastructure, and expansion.

Rules:
- Not every system should use Essence.
- Essence must remain distinct from material resources.

## Labor and Logistics Direction
- Specialist roles produce resources at local stations.
- Implemented specialist roles:
	- None
	- Woodcutter
	- Miner
	- Worshipper
- A Tinyfolk can hold only one specialist assignment at a time.
- Specialist assignment is Tinyfolk-only.
- Specialist assignment clears automatically on role change away from Tinyfolk.
- Specialist assignment is session state.
- Implemented assignment reasons:
	- Initial
	- Assigned
	- ClearedManual
	- ClearedRoleChange
- Hauling is general labor and does not require a specialist role.
- Hauling is not a specialist role.
- Hauling does not consume the specialist assignment slot.
- WorkStation_A currently requires Woodcutter specialist assignment at runtime to activate production.
- Shrine_A currently requires Worshipper specialist assignment at runtime to activate Essence generation.
- Station interaction is assignment-driven: `F` resolves to specialist assignment when needed, and to station pickup/activation when already correctly assigned.
- Shrine interaction is assignment-driven: `F` resolves to Worshipper assignment/activation only.
- Shrine interaction has no hauling path.
- WorkStation_A in this slice is bounded Wood production, not generic/infinite workstation output.
- Haulers move produced goods to storage.
- Hauling is implemented as deterministic general labor flow, not specialist assignment.
- Only stored resources count as usable realm resources in the current prototype.

Future scope note:
- Station gating by specialist assignment is implemented for current specialist stations.
- Full labor AI behavior and full job scheduling are not implemented in the current prototype.
- Additional specialist-gated station paths beyond WorkStation_A remain future scope.

Operational state model:
- Produced: created at source station.
- In transit: being hauled between source and storage.
- Stored: available to realm-level spend/use systems.

## Implementation Guidance for Future Slices
- Keep systems deterministic and server-authoritative.
- Prefer bounded vertical slices over broad generic frameworks.
- Add only the smallest surface required to validate each issue contract.
- Separate prototype implementation details from long-term directional notes.
- Keep server services authoritative for role/range/cooldown/material validation; client interaction resolution is only request routing.

## Role Selection Rules (Current Prototype)
- Players must select Giant or Tinyfolk before normal playable spawn.
- Server stores selected role as session state and keeps `Role` as the gameplay compatibility attribute.
- Once selected and spawned, role is locked for the session; in-session role swapping is not supported.
- Respawn preserves selected role and role lock state.
- Role selection and realm assignment are separate systems in the current prototype.
