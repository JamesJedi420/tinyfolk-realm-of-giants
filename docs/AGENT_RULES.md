# Agent Rules - Tinyfolk: Realm of Giants

## Identity and Naming
- Always refer to the project as Tinyfolk: Realm of Giants.
- Do not use Containment Protocol naming for this repository.

## Source of Truth
- Treat `docs/GAME_SPEC.md` as the primary design direction document.
- Treat `docs/VISUAL_BIBLE_TEMPLATE.md` as the required output contract for AI-generated visual design proposals and visual map/asset edits.
- Keep issue work bounded to the current slice contract.

## Documentation Style
- Keep docs concise, implementation-useful, and explicit.
- Separate current prototype behavior from long-term direction.
- Prefer concrete rules and constraints over long narrative prose.
- Do not overcommit to details that are not yet decided.

## Implementation Guardrails
- Server-authoritative and deterministic behavior is preferred.
- Favor minimal, targeted changes over broad refactors.
- Do not introduce speculative generic frameworks unless required by the issue contract.
- Do not add unrelated systems in bounded slices.
- Use `F` as the primary context-sensitive interaction key for current bounded interaction surfaces.
- Resolve interaction deterministically by priority, then distance, then target id.
- Giant upgrade board progression is deterministic and ordered in the current prototype.
- Giant upgrade board interaction is next-step-only for the current prototype; free-pick upgrade selection is out of scope.
- Role selection should be pre-spawn, with first valid choice winning for the current session.
- Keep `Role` as the gameplay compatibility attribute for role-gated systems.
- Do not implement in-session role swapping unless a future issue explicitly requires it.

## Post-Implementation Pre-Commit Rule
- After every implementation and before any commit, audit the current implementation against the active issue, fix all in-boundary gaps and edge cases until validation is clean, then prepare an implementation plan for the next issue without coding that next issue.
- Use the active Linear/GitHub issue, issue comments with durable scope or acceptance notes, repository docs, tests, existing architecture, and current code as the source of truth. Preserve the issue boundary and do not expand scope.
- Before coding, inspect relevant files, tests, docs, routes, state models, schemas, fixtures, and existing patterns; identify the smallest correct implementation boundary; determine whether the issue is complete, partial, incorrect, or blocked; and report relevant files, current behavior, expected behavior, implementation boundary, risks, validation plan, and required docs updates.
- Re-run these audit passes iteratively, fixing and re-auditing until no in-boundary issues remain: scope/integration, edge cases, determinism/state, regression, documentation/authoring, and cleanup.
- Validation must run the most specific test command first, then broader relevant validation. When available, include typecheck, lint, unit tests, and affected integration tests. If validation fails, fix and rerun until clean or a real blocker is identified.
- If validation cannot be run, state the exact command, the reason it could not run, and what evidence remains unverified. Do not claim completion without that caveat.
- An issue is ready for review only when the implementation matches the issue boundary, edge cases are addressed or explicitly deferred, changed behavior is covered by tests, required docs are updated, validation passes, no unrelated scope is added, and the final diff is clean and explainable.
- After the post-implementation pre-commit rule passes all required tests and validation, commit all in-boundary changes, then check out `master`. Do not commit or switch branches if any validation gate is failing or blocked.
- After checkout to `master`, use Linear as the source of truth to determine the next issue to implement, then switch to planning mode and prepare a concise implementation plan formatted for handoff to an AI agent in another session. The handoff plan must include issue id/title, durable scope and constraints, relevant source-of-truth links or notes, expected implementation boundary, key files/tests/docs to inspect, validation commands, known risks, and explicit deferred work. Do not start coding the next issue in this planning step.

## World Model Direction (for consistency)
- Shared Tinyfolk world is the long-term social/economic base.
- Future per-Giant realms are distinct layers.
- Capture -> Giant realm.
- Escape -> shared Tinyfolk world.
- Trade between Giant realms is future scope.

## Economy and Labor Direction (for consistency)
- Essence is spiritual/ritual/miracle resource.
- Wood and Stone are material resources and should remain distinct from Essence.
- Specialist assignment model uses roles: None, Woodcutter, Miner, Worshipper.
- Specialist station work is single-assignment per Tinyfolk.
- Specialist assignment is Tinyfolk-only and clears on role change away from Tinyfolk.
- Specialist assignment uses reason terminology: Initial, Assigned, ClearedManual, ClearedRoleChange.
- Specialist assignment is session state unless a future issue explicitly adds persistence.
- WorkStation_A currently uses runtime-enforced specialist gating and requires Woodcutter.
- WorkStation_A currently represents bounded Wood production in this slice.
- Station interaction is assignment-driven: assign specialist when needed, otherwise activate/pickup when correctly assigned.
- Shrine interaction is assignment-driven Worshipper interaction and has no hauling path.
- Hauling is general labor.
- Hauling is not a specialist role and does not consume the specialist assignment slot.
- Resource state should distinguish produced, in transit, and stored.
- Canonical server-owned Wood/Stone flow state is the source of truth for produced/in-transit/stored totals.
- Stored totals are the usable realm totals.
- Wood and Stone delivery point: Warehouse_A.
- Granary_A is reserved for future food/crop resources.
- Workstation interaction moves produced material to in-transit; warehouse interaction moves in-transit to stored.
- Essence is not hauled; Shrines produce Essence directly to Giant session pool.
- Prototype construction spending must use stored Wood/Stone totals only.
- Produced and in-transit material totals are not spendable for construction.
- Server-side services remain authoritative for interaction validation (role/range/cooldown/material checks).

## Future Labor Scope Boundary
- Do not document or imply implemented full AI labor behavior or full job scheduling unless those systems are actually shipped in code.
- Do not document specialist-gated production beyond WorkStation_A as implemented until those runtime couplings exist.

## Visual Design AI Contract
- For any environment visual concept, graybox replacement, or visual map asset edit, AI outputs should be structured using `docs/VISUAL_BIBLE_TEMPLATE.md`.
- AI should include explicit PASS/FAIL outcomes for the template checks before proposing completion.
- If any hard-stop check in the template fails, AI should return FAIL with revision actions instead of presenting the design as done.
