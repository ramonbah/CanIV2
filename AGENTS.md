# CanI Repository Instructions

## Source of truth

Read `PRODUCT_SPEC.md`, `UI_SPEC.md`, `IMPLEMENTATION_PLAN.md`, and the implementation brief for the active phase before planning or changing product behavior. Phase 2 is complete and remains documented by `PHASE_2_IMPLEMENTATION_BRIEF.md`. Refinement 1 is accepted and remains the verified baseline documented by `REFINEMENT_1_IMPLEMENTATION_BRIEF.md`; it supersedes Phase 2 only where it explicitly changed interaction or adaptive-layout behavior. Phase 3 Search, Filters, and Reports is the certified baseline documented by `PHASE_3_IMPLEMENTATION_BRIEF.md`. Phase 3 Observation Refinement 1 is the certified observation baseline documented by `PHASE_3_OBSERVATION_REFINEMENT_1.md`. Phase 3 Observation Refinement 2 is the current source baseline documented by `PHASE_3_OBSERVATION_REFINEMENT_2.md`. The active bounded implementation scope is Phase 3 Observation Refinement 3, defined by `PHASE_3_OBSERVATION_REFINEMENT_3.md`; it supersedes Observation Refinement 2 only where it explicitly changes persistence startup safety and adds Time Effort behavior. If code and specification disagree, report the conflict before changing established behavior. Do not invent deferred features.

## Platform and architecture

- Target iOS 17 or later.
- Use SwiftUI for all app UI and SwiftData for local persistence.
- Use Swift Charts for reports and Vision for on-device receipt OCR.
- Use feature-first MVVM with Observation (`@Observable`) where appropriate.
- Views may bind to view models and invoke use cases, but must not contain persistence, OCR, recurrence, transfer-merge, or report aggregation logic.
- Depend on protocols at service and repository boundaries. Prefer actors for stateful concurrent services.
- Use structured concurrency. Avoid unstructured `Task` use unless lifecycle and cancellation are explicit.

## Data rules

- Use `Decimal` for money. Do not use `Double` or floating-point arithmetic for persisted or calculated currency values.
- UUIDs are stable identities and must survive transfer/import.
- Maintain `createdAt` and `updatedAt` on meaningful changes.
- Declare SwiftData inverse relationships and deletion rules explicitly.
- Centralize derived totals and transaction-sign rules.
- Transfer packages use separate versioned `Codable` DTOs; never encode SwiftData models directly as the external contract.
- Imports must be dependency-safe, atomic, user-selected, and must never silently overwrite local data.

## UI rules

- Provide loading, empty, content, and recoverable error states where applicable.
- Support light/dark mode, Dynamic Type, VoiceOver, Reduce Motion, and at least 44-point interactive targets.
- Every chart needs an equivalent accessible text summary.
- OCR results are suggestions. Keep them editable and require explicit save confirmation.
- Destructive actions show the entity name and affected descendants.
- Use semantic colors and never communicate state by color alone.

## Testing

- Use Swift Testing for domain, service, repository, calculation, recurrence, rollover, parser, and transfer tests.
- Use an in-memory `ModelContainer` for SwiftData integration tests.
- Use XCTest UI tests for critical end-to-end flows.
- Use fixed calendars, locales, dates, UUIDs, and fixtures in deterministic tests.
- Test error, cancellation, duplicate, empty, permission-denied, and conflict paths—not only the success path.

## Working method

- Implement only the requested phase or bounded change.
- Before editing, inspect the relevant files and state a short plan.
- Make small coherent changes and build after each group.
- For incremental changes, run only the narrowest relevant build and tests. Run the full available suite only for phase certification, persistent-schema changes, shared cross-cutting infrastructure changes, or when focused tests reveal a broader regression. Preserve the most recent clean full-suite result as the baseline between narrow patches. Do not repeat the full suite after every small refinement.
- Fix errors caused by the change. Report unrelated pre-existing failures instead of rewriting unrelated code.
- Do not add third-party dependencies without approval and a specific need.
- Do not rename public types, alter the data schema, or change the deployment target without calling out migration and compatibility effects.

## Current project status

Phase 1 and Phase 2 Core CRUD are implemented. Refinement 1 is accepted for the iPhone 17 observation build with 88 enabled tests. Phase 3 Search, Filters, and Reports is certified with 124 enabled passing tests. Phase 3 Observation Refinement 1 is certified with 134 enabled passing tests. Phase 3 Observation Refinement 3 is the accepted baseline. The active work is the bounded Phase 4 Rollover and Recurrence delivery in `PHASE_4_IMPLEMENTATION_BRIEF.md`.

Phase 4 must preserve the verified manual hierarchy, numeric editing, transaction grouping, adaptive navigation, submitted Transactions search and filters, exact-Decimal report snapshots, dedicated report screens, hierarchical filters, dynamic Item tabs, live entry previews, simplified Item-row presentation, derived Mark-as-Spent action, SwiftData optional relationship backing-storage corrections, explicit persistence startup failure handling, and Time Effort settings/calculation/lookup. It adds selected Item rollover, recurring transaction template management, idempotent recurrence generation, missing-destination repair, and the recurring Budget report. Receipt capture and transfer remain later phases. Current runtime verification is scoped to iPhone 17 portrait and landscape; production layout stays adaptive and broader device verification remains deferred.
