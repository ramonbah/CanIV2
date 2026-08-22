# CanI V2 Implementation Plan

Build one phase at a time. At the end of each phase, run the app, build all targets, and run the relevant tests before starting the next phase.

## Phase 1 — Foundation

- Create the iOS 17+ SwiftUI app and SwiftData container.
- Add feature-first folders and dependency composition.
- Implement domain models, enums, inverse relationships, deletion rules, timestamps, and money helpers.
- Add in-memory preview/test containers and realistic sample data.
- Add the four-tab navigation shell and placeholder root screens.
- Add tests for relationships, deletion behavior, and calculated totals.

Exit condition: the project builds; previews load; sample data appears; model tests pass.

## Phase 2 — Core CRUD

- Implement repositories and use cases for Budgets, Plans, Items, and Transactions.
- Add first-run currency selection, first-Budget creation, skip behavior, and later currency relabel warnings.
- Build the expandable Budgets surface, Budget/Plan/Item detail, create/edit flows, automatic sorting, saved manual Plan ordering, and confirmed deletion.
- Build the unified income/expense transaction flow, including Item selection/creation, same-Plan moves, and scheduled future income.
- Make income date-aware: future income is visible but excluded from current calculations until its local calendar date arrives.
- Add currency-minor-unit validation, exact-Decimal calculations, rounding-mismatch disclosures, normalized sibling-name uniqueness, inline field errors, and summary alerts.
- Add cascading-delete impact previews and the agreed full-swipe safeguards.
- Add deterministic domain, repository, view-model, and UI tests for the complete manual hierarchy flow.

Exit condition: a user can create and maintain the complete hierarchy and totals stay correct.

The binding behavior and acceptance criteria for this phase are in `PHASE_2_IMPLEMENTATION_BRIEF.md`.

## Refinement 1 — Post-Phase 2 usability and adaptive layout

- Make every currency picker return immediately after selection, while keeping the Settings relabel confirmation inside the picker before save and return.
- Consolidate contextual toolbar Add actions into one button and menu without changing empty-state actions.
- Centralize strict localized numeric edit parsing for every numeric field; reject invalid typing and paste while preserving the previous valid value and showing an inline error.
- Group Item transactions by local calendar date with the approved relative/date headers and newest-first ordering.
- Add adaptive two-column Budget navigation for iPad and sufficiently wide iPhone landscape layouts, with compact stack fallback and stable navigation state across size changes.
- Add deterministic parser, grouping, navigation, rotation/resizing, accessibility, and regression tests. Retain all 63 verified Phase 2 tests.

Exit condition: every Refinement 1 acceptance criterion passes on supported iPhone portrait/landscape and iPad configurations, all Phase 2 behavior remains intact, and no Phase 3 feature is introduced.

The binding behavior and acceptance criteria for this bounded change are in `REFINEMENT_1_IMPLEMENTATION_BRIEF.md`.

## Phase 3 — Search, filters, and reports

- Replace the Transactions placeholder with a submitted global search over transaction notes, Item names, and Plan names plus staged multi-select filters.
- Support Budget, Plan, Item, kind, preset/custom date, and inclusive amount filters; preserve the applied query across tab changes until Clear All.
- Add exact-Decimal `ReportService` snapshot DTOs and one session-wide reporting period that defaults to Last 30 Days.
- Replace the Home placeholder and add Home, Budget, Plan, and report-detail cards and Swift Charts using the approved net-cash-flow, balance, allocation, and timeline rules.
- Add chart text equivalents, accessible breakdowns, contributing-transaction lists, and deterministic drill-in/navigation behavior.
- Test search submission, dependent filters, aggregation boundaries, local-day date ranges, future income, negative values, ordering, preferences, accessibility, and empty datasets.

Exit condition: all targets build, all existing 88 tests plus Phase 3 tests pass, search/filter results and report snapshots agree with deterministic fixtures, every chart has a text equivalent, and the complete flow is verified on iPhone 17 portrait and landscape. Broader device verification remains deferred while functionality is evolving.

The binding behavior and acceptance criteria for this phase are in `PHASE_3_IMPLEMENTATION_BRIEF.md`.

## Phase 4 — Rollover and recurrence

- Implement the rollover picker and selected-item copy operation.
- Implement recurring template management.
- Implement an idempotent recurrence engine that processes due entries while the app is active.
- Handle deleted or unresolved destination items without losing the template.
- Add deterministic date, duplicate-prevention, and rollover tests.

Exit condition: selected items roll over without transactions and each due occurrence is generated exactly once.

## Phase 5 — Receipt capture

- Add camera/photo-library input, crop/rotate handling, and permission states.
- Define ReceiptScanningService and implement on-device Vision OCR in an actor.
- Parse merchant, date, total, and line candidates using testable heuristics.
- Build review, partial-line selection, subtotal, correction, and transaction confirmation screens.
- Test Malaysian receipt samples and ambiguous decimal/date formats without treating OCR as authoritative.

Exit condition: a user can scan, correct, partially select, and explicitly save an accurate transaction offline.

## Phase 6 — Device transfer

- Define versioned transfer DTOs separately from SwiftData models.
- Implement package creation, dependency-safe diffs, and atomic merge application.
- Implement nearby discovery, verification, progress, cancellation, and error recovery.
- Build send selection, incoming review, conflict comparison, and result screens.
- Add integration tests for new, newer, same, older, conflicting, missing-parent, and interrupted imports.

Exit condition: two devices can transfer selected data without duplicate IDs or silent overwrites.

## Phase 7 — Hardening and release readiness

- Complete accessibility checks in both appearance modes and large text sizes.
- Test storage growth and transfer size with and without receipt images.
- Review privacy strings and permission denial paths.
- Add migration fixtures for the initial schema version.
- Run unit, integration, and UI suites on supported iPhone/iPad configurations.
- Remove debug data and confirm no deferred-feature placeholders are exposed.

## Definition of done for every change

- The change matches `PRODUCT_SPEC.md`, `UI_SPEC.md`, and the implementation brief for the active phase.
- Domain and persistence logic is not embedded in SwiftUI views.
- New nontrivial logic has deterministic tests.
- Empty, error, and accessibility behavior is considered.
- The project builds without new warnings.
- Unrelated phases and deferred V2+ features are not implemented opportunistically.
