# CanI V2 — Refinement 1 Implementation Brief

## Status and objective

Phase 2 is implemented and verified. Implement this bounded post-Phase 2 usability and adaptive-layout refinement so the user can begin an observation period before Phase 3.

Preserve the approved SwiftData schema, architecture boundaries, calculations, scheduled-income behavior, sorting, deletion safeguards, accessibility behavior, and all verified Phase 2 tests. This brief supersedes Phase 2 only where it explicitly changes interaction or presentation.

## Scope boundary

Include only:

- immediate return from every currency picker
- contextual single-button toolbar Add menus
- strict localized numeric editing for every numeric field
- date-grouped Item transactions
- landscape support
- adaptive iPad support
- focused regression, accessibility, rotation/resizing, and UI tests

Do not implement Phase 3 search, filters, reports, charts, or any later-phase feature. Do not alter the SwiftData schema, deployment target, or app-wide single-currency model.

## Currency-picker navigation

- In every currency picker, tapping a currency completes the selection without requiring a separate Done or Continue action in that picker.
- Onboarding and other non-Settings pickers immediately return to the surface that opened the picker with the tapped currency selected.
- In Settings, tapping a different currency presents the existing affected-Budget relabel warning inside the currency picker before navigation changes.
- Confirming the Settings warning persists the currency and returns to Settings.
- Canceling the Settings warning preserves the existing currency and keeps the picker open.
- A failed Settings save keeps the picker open, preserves recoverable state, and shows the existing recoverable error behavior.
- Keep the rule that changing currency relabels values and never converts them.

## Contextual toolbar Add menus

### Budgets root

- Show one toolbar Add button.
- If no Budget is expanded, tapping it starts Add Budget immediately.
- If a Budget is expanded, tapping it opens a menu with exactly `Add Budget` and `Add Plan`.
- `Add Plan` targets the expanded Budget.
- Preserve the no-Budgets `Create Budget` and no-Plans `Add Plan` empty-state actions.

### Plan detail

- Replace the separate Add Item and Add Transaction toolbar buttons with one Add button.
- Tapping it opens a menu with exactly `Add Item` and `Add Transaction`.
- Disable `Add Transaction` when the Plan has no Items; retain the current accessibility explanation for the disabled state.
- Preserve the no-Items Add Item action and the existing Add Transaction flows.

- Use native `Menu` semantics, an unambiguous accessibility label such as `Add`, 44-point targeting, and action parity in compact and expanded layouts.

## Strict localized numeric editing

Apply one centralized editing/parser policy to every current numeric field, including:

- Plan starting amount
- Item unit amount
- Item multiplier
- Transaction amount

Rules:

- Accept plain numbers valid for the current locale, including valid localized grouping and decimal separators, such as `1,234.50` in an English locale.
- Permit temporary empty text and a single trailing locale decimal separator while the field is actively being edited so users can replace a value or enter a fraction. These are edit states, not saveable numbers; ordinary required/amount validation applies before Save.
- Do not accept letters, currency symbols, signs that conflict with the field's nonnegative/positive rule, malformed grouping, repeated decimal separators, or unrelated characters.
- Apply the same validation to software-keyboard editing, hardware-keyboard editing, dictation-produced edits, and paste.
- If a proposed edit is invalid, reject the complete edit, preserve the field's previous valid edit state and parsed value, and show an inline error beneath that field.
- Do not silently strip characters or reinterpret a malformed paste.
- A later valid edit clears the edit-format error.
- Parsing must produce `Decimal` directly and must not pass through `Double`.
- Existing semantic rules remain binding: Plan starting amount and Item unit amount allow zero; Transaction amount is positive; Item multiplier is a positive whole number; currency minor-unit precision still blocks invalid Save values.
- Keep numeric keyboard hints, but never rely on the keyboard type as validation.

## Date-grouped transactions

- In Item detail, group transactions by `Calendar` local day rather than by a formatted string.
- Order date sections newest first.
- Within a date section, order entries by `createdAt` newest first. Use stable UUID order as the final deterministic tie breaker.
- Use these English examples as the presentation structure:
  - `Today · Tuesday`
  - `Yesterday · Monday`
  - `Sunday, 9 Aug 2026`
- Localize weekday and month text using the app/device locale while retaining the relative-label separator and older-date structure.
- Date grouping must update correctly after a local-day, calendar, or time-zone change using the existing restartable day scheduler.
- Preserve future-income dimming, transaction VoiceOver labels, swipe actions, edit/move behavior, and deletion confirmation.
- Section headers must be readable with Dynamic Type and exposed as accessibility headers.

## Adaptive landscape and iPad layout

- Support portrait and landscape throughout onboarding, Budgets, Plan detail, Item detail, forms, pickers, menus, sheets, alerts, and Settings.
- Choose layouts from available width and SwiftUI environment, not hard-coded device model names or raw orientation checks.
- Preserve current compact `NavigationStack` behavior at compact widths.

### iPad and sufficiently wide iPhone landscape

- Use a two-column hierarchy.
- The sidebar lists Budgets only.
- Selecting a Budget shows its Plan list in the detail column.
- Selecting a Plan replaces the Plan list with Plan detail in the same detail column.
- Item detail continues within that detail column.
- Do not introduce a third persistent Item column.
- On iPhone landscape, enable this two-column layout only when available width supports it; otherwise retain compact stack navigation.

### State and resizing

- Preserve the selected Budget and the open Plan or Item when rotating, entering/leaving iPad Split View, or crossing the compact/expanded threshold.
- Preserve active sheets, confirmation context, and unsaved form input across ordinary size changes. Do not create duplicate presentations or save automatically because of rotation.
- Keep toolbar actions reachable in every size class.
- Avoid clipped currency values, totals, progress labels, numeric fields, date headers, and inline errors at supported Dynamic Type sizes.

## Architecture constraints

- Keep views declarative and driven by observable state/actions.
- Do not move persistence, validation policy, date grouping, sorting policy, or calculations into views.
- Put numeric edit parsing in a focused locale-aware service/type with deterministic tests.
- Put transaction day grouping/header generation behind focused, calendar/locale-injected logic.
- Model navigation selection explicitly so compact/expanded transitions preserve identity by UUID.
- Keep structured-concurrency task lifecycle and cancellation explicit.
- Add no third-party dependency.

## Required tests

### Currency

- onboarding currency tap returns immediately with the selection
- any other non-Settings picker returns immediately
- Settings confirm saves and returns
- Settings cancel preserves the old currency and stays in the picker
- Settings persistence failure stays recoverable in the picker

### Toolbar actions

- Budgets Add directly opens Add Budget when no Budget is expanded
- Budgets Add menu contains Add Budget and Add Plan when one is expanded
- Add Plan targets the expanded Budget
- Plan detail exposes one Add menu with Add Item and Add Transaction
- Add Transaction is disabled with zero Items and enabled with at least one Item
- empty-state actions remain available

### Numeric editing

- valid localized integer, grouping, decimal, temporary-empty, and trailing-decimal editing states for fixed English and at least one comma-decimal locale
- invalid letters, currency symbols, malformed/repeated separators, and mixed-content paste are rejected
- rejection preserves prior text and value and exposes an inline error
- subsequent valid input clears the edit-format error
- software/hardware/paste entry paths share the same parser policy
- direct `Decimal` parsing and existing zero/positive/whole-number/minor-unit rules remain correct

### Transaction grouping

- Today, Yesterday, and older header formats with fixed calendar, locale, time zone, and clock
- sections newest first
- entries newest-created first with deterministic UUID ties
- local midnight, calendar, and time-zone refresh regroup rows correctly
- future income, edit/move, swipe, deletion, and accessibility behavior remains intact

### Adaptive layout

- supported iPhone portrait remains compact stack navigation
- sufficiently wide iPhone landscape uses two columns; narrower landscape falls back safely
- iPad portrait and landscape use Budget-only sidebar plus detail
- Budget selection shows Plans; Plan selection replaces the Plan list; Item detail remains in detail navigation
- rotation and Split View resizing preserve selected IDs, open destination, draft input, and active presentation without duplication
- no clipping or inaccessible actions at representative Dynamic Type sizes
- VoiceOver labels exist for Add menus and transaction section headers

### Regression

- Keep all 63 verified Phase 2 tests enabled and passing.
- Extend the critical UI flow to exercise the contextual Add menus and grouped transaction surface.

## Exit condition

- All targets build without new warnings.
- All existing 63 tests and the new Refinement 1 tests pass.
- The six requested refinements work on supported iPhone portrait/landscape and iPad configurations.
- Phase 2 behavior outside the explicit supersessions remains unchanged.
- No Phase 3 or later feature is implemented.
