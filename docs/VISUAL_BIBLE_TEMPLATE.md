# Visual Bible Template - AI Consumption

Use this one-page template for any environment or prop visual design task in Tinyfolk: Realm of Giants.

## Required output contract

When an AI agent proposes or edits visuals, it should output all sections below in order and include a final PASS/FAIL verdict.

## 1) Scope

- Asset or area:
- Owner issue or slice:
- Design intent (one sentence):

## 2) World pillars

- Monumental Scale: giant-built first, tinyfolk adaptation second.
- Functional Fantasy: form communicates purpose.
- Worn Civilization: weathered, repaired, used.

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Monumental Scale is visible.
- [ ] PASS [ ] FAIL: Functional Fantasy is visible.
- [ ] PASS [ ] FAIL: Worn Civilization is visible.

## 3) Aesthetic snapshot

- Mood keyword set (3 to 5 words):
- Time-of-day target:
- Story beat (one sentence):

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Mood reads within 2 seconds at gameplay distance.
- [ ] PASS [ ] FAIL: Story beat is inferable from forms and materials.

## 4) Shape language

- Primary silhouette:
- Secondary forms:
- Hero feature:

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Primary silhouette is readable from distance.
- [ ] PASS [ ] FAIL: Exactly one hero feature is obvious.
- [ ] PASS [ ] FAIL: Decorative noise does not break readability.

## 5) Scale and adaptation

- Giant reference dimensions:
- Tinyfolk adaptation element:
- Scale ratio notes:

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Structure reads giant-scale first.
- [ ] PASS [ ] FAIL: Tinyfolk adaptation is visibly distinct.
- [ ] PASS [ ] FAIL: No accidental human-scale ambiguity.

## 6) Material and wear plan

- Primary materials:
- Secondary materials:
- Wear zones:

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Contact points show wear.
- [ ] PASS [ ] FAIL: Hardware zones show oxidation or grime.
- [ ] PASS [ ] FAIL: Base edges show dirt accumulation.

## 7) Color script

- Base palette:
- Accent A (utility):
- Accent B (engineering):
- Accent C (harvest/storage):

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Accent usage is sparse and intentional.
- [ ] PASS [ ] FAIL: Interactables have strong contrast readability.
- [ ] PASS [ ] FAIL: Palette matches world style and avoids drift.

## 8) Gameplay readability and collision

- Interactable anchors:
- Traversal readability notes:
- Collision simplification notes:

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Interactables are identifiable without UI hints.
- [ ] PASS [ ] FAIL: Traversal routes are readable at speed.
- [ ] PASS [ ] FAIL: Collision remains simple and intentional.

## 9) Script and naming compatibility

- Script-bound names preserved:
- Required attributes preserved:
- Path compatibility preserved:

Pass/Fail checks:
- [ ] PASS [ ] FAIL: Script-facing names and ids unchanged.
- [ ] PASS [ ] FAIL: Required attributes retained.
- [ ] PASS [ ] FAIL: Asset remains under mapped Rojo paths.

## 10) Final gate

- Failing checks list:
- Required revisions:
- Final verdict: PASS or FAIL

Hard-stop rule:
- If any check in sections 2, 5, 8, or 9 fails, final verdict must be FAIL.

## Filled Example - Granary Visual Pass

Use this as a reference implementation for AI-generated environment visuals.

## 1) Scope

- Asset or area: Workspace.Map.Stations.Granary
- Owner issue or slice: Visual-only map pass
- Design intent (one sentence): Replace graybox granary volume with a giant-scale functional granary silhouette while preserving script-facing anchor compatibility.

## 2) World pillars

- Monumental Scale: Main mass, roof span, and silos are giant-first proportions.
- Functional Fantasy: Readable grain storage body, loading catwalk, and chute feature.
- Worn Civilization: Aged timber, oxidized metal, and dirt-biased lower surfaces.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Monumental Scale is visible.
- [x] PASS [ ] FAIL: Functional Fantasy is visible.
- [x] PASS [ ] FAIL: Worn Civilization is visible.

## 3) Aesthetic snapshot

- Mood keyword set (3 to 5 words): Titanic agrarian ruin, weathered utility
- Time-of-day target: Late afternoon
- Story beat (one sentence): An old giant granary still in service has been repeatedly reinforced by practical repairs.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Mood reads within 2 seconds at gameplay distance.
- [x] PASS [ ] FAIL: Story beat is inferable from forms and materials.

## 4) Shape language

- Primary silhouette: Broad timber barn mass with oversized pitched roof.
- Secondary forms: Twin side silos and elevated utility catwalk.
- Hero feature: Front loading gantry and chute assembly.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Primary silhouette is readable from distance.
- [x] PASS [ ] FAIL: Exactly one hero feature is obvious.
- [x] PASS [ ] FAIL: Decorative noise does not break readability.

## 5) Scale and adaptation

- Giant reference dimensions: Main body near 28x14x22 studs with oversized roof span.
- Tinyfolk adaptation element: Side ladder and small repair platform attached as secondary read.
- Scale ratio notes: Giant shell first read, tinyfolk additions remain visibly improvised.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Structure reads giant-scale first.
- [x] PASS [ ] FAIL: Tinyfolk adaptation is visibly distinct.
- [x] PASS [ ] FAIL: No accidental human-scale ambiguity.

## 6) Material and wear plan

- Primary materials: WoodPlanks, Wood, Slate.
- Secondary materials: Metal for bands, silos, and catwalk elements.
- Wear zones: Door/entry frame, roof edges, base trim, and exposed metal seams.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Contact points show wear.
- [x] PASS [ ] FAIL: Hardware zones show oxidation or grime.
- [x] PASS [ ] FAIL: Base edges show dirt accumulation.

## 7) Color script

- Base palette: Warm timber browns and muted roof slate gray.
- Accent A (utility): Muted red at loading marks only.
- Accent B (engineering): Oxidized metal cool gray.
- Accent C (harvest/storage): Controlled ochre near storage features.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Accent usage is sparse and intentional.
- [x] PASS [ ] FAIL: Interactables have strong contrast readability.
- [x] PASS [ ] FAIL: Palette matches world style and avoids drift.

## 8) Gameplay readability and collision

- Interactable anchors: Granary_A remains the canonical script-facing BasePart id.
- Traversal readability notes: Front face and side attachments are readable from approach routes.
- Collision simplification notes: Keep one simple gameplay anchor plus a limited set of large collision parts.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Interactables are identifiable without UI hints.
- [x] PASS [ ] FAIL: Traversal routes are readable at speed.
- [x] PASS [ ] FAIL: Collision remains simple and intentional.

## 9) Script and naming compatibility

- Script-bound names preserved: Granary_A unchanged.
- Required attributes preserved: No required granary-specific attributes removed.
- Path compatibility preserved: Asset stays under src/Workspace mapped paths.

Pass/Fail checks:
- [x] PASS [ ] FAIL: Script-facing names and ids unchanged.
- [x] PASS [ ] FAIL: Required attributes retained.
- [x] PASS [ ] FAIL: Asset remains under mapped Rojo paths.

## 10) Final gate

- Failing checks list: none
- Required revisions: none
- Final verdict: PASS
