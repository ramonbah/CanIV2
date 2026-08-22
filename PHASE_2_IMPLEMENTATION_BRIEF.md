# CanI V2 — Phase 2 Implementation Brief

## Objective

Implement the complete manual budgeting path on top of the approved Phase 1 SwiftData foundation:

`Onboarding → Budget → Budget Plan → Budget Item → Transaction`

The result must let a user create, inspect, edit, sort, and permanently delete every record in that hierarchy while all displayed totals remain consistent.

## Scope boundary

Include:

- first-run currency setup and first-Budget flow
- Budget, Budget Plan, Budget Item, and Transaction repositories/use cases
- list, expanded/detail, create, edit, sorting, manual Plan ordering, and deletion flows
- currency-aware amount entry and display
- current versus scheduled income behavior
- validation, empty states, deletion-impact previews, and UI tests

Do not implement receipt capture, recurring transactions, rollover, transaction search/filtering, reports/charts, import/export, device transfer, accounts, categories, multiple currencies, cloud sync, authentication, or notifications.

## Architecture constraints

- Target iOS 17 or later. Use SwiftUI, SwiftData, Observation, and structured concurrency.
- Keep the existing Phase 1 model schema. Do not rename public model types or add a migration in this phase.
- Use feature-first MVVM. Views must not access `ModelContext` or implement persistence, validation, sorting policy, deletion counting, or money calculations.
- Add repository protocols with SwiftData implementations and focused use-case types for all mutations.
- Use `Decimal` for persisted and calculated money. Never convert money through `Double`.
- Centralize the current-day/effective-income rule behind an injected clock or `asOf` date so tests are deterministic.
- Keep `descriptiveDate`, Plan notes, `sourceItemID`, recurrence relationships, receipt relationships, and other deferred-schema fields intact but do not expose deferred UI.

## Approved schema seams

- `BudgetItem.multiplier` remains stored as `Decimal`, but the form and validation accept only whole numbers greater than zero.
- `Transaction.name` remains a required stored field, but it is not a Phase 2 form field. Generate a non-empty internal value from the transaction kind (`Income` or `Expense`) and update it when the kind changes. Do not show it in Phase 2 rows.
- `BudgetPlan.descriptiveDate` and `notes` remain stored but are not fields in the Phase 2 create/edit form.
- UI preferences that do not belong to the financial domain—onboarding completion, expanded Budget ID, Plan sort mode/direction, saved manual Plan arrangement, and Item sort direction—may use an app-preference store such as `@AppStorage` or a dedicated settings service keyed by stable UUID. The restore/replace choice itself is never persisted; prompt again on every automatic-to-Manual transition.

## Money and date rules

- Item planned amount = `unitAmount × multiplier`.
- Effective income includes income transactions whose calendar day is today or earlier.
- Future-dated income is scheduled and excluded from current funds, balances, remaining amounts, and progress until its date arrives.
- Item remaining = planned amount + effective income − expenses.
- Plan total funds received = starting amount + effective income.
- Plan spending = expenses.
- Plan current balance = total funds received − expenses.
- Budget totals aggregate the equivalent Plan totals.
- Calculations always use exact stored values.
- Currency display follows the selected ISO 4217 currency’s standard minor-unit precision.
- New input with excess fractional digits shows an inline error and blocks saving. Do not round it silently.
- Changing to a currency with fewer minor units preserves stored values and rounds only display.
- When rounded components cannot reproduce a displayed total, show an info icon beside that total. Its popover explains the mismatch and reveals only the additional decimal digits needed to demonstrate it.

## First launch and currency

- Suggest the device-region currency and provide a searchable list of supported ISO 4217 currencies.
- The user may continue to create a first Budget or skip to the empty Budgets tab.
- Budget creation contains one field: name.
- If the user selected currency and then cancels first-Budget creation, ask whether to keep the selected currency.
- The empty Budgets tab shows a clear `Create Budget` button. Later creation uses the toolbar Add button.
- Settings may change the app-wide currency after Budgets exist.
- Before changing currency, show the affected Budget count and require confirmation. State that values are relabeled, not converted.

## Budgets tab

- Show Budgets newest first.
- A compact Budget row shows only its name and Plan count.
- Use an accordion-style expanded Budget surface; persist the selected expanded Budget across tab visits and app launches.
- The expanded header shows Budget name, total funds, spending, and current balance.
- Show aggregate spending progress only after spending is above zero.
- The expanded Plan list has its sorting menu immediately above the list.
- Budget row swipe actions provide Edit and Delete. Disable destructive full swipe; reveal Delete and require a tap.
- Budget detail/expanded actions also appear in a toolbar overflow menu.
- Renaming returns to the surface that opened the editor.
- Deleting a Budget requires confirmation showing affected Plan, Item, and Transaction counts. Deleting an open Budget returns to the Budgets root.

## Budget Plans

- Create/edit fields: name and starting amount.
- Starting amount accepts zero or a positive value.
- Add Plan appears in the toolbar and in the no-Plans empty state.
- Plan row shows name, a progress bar, percentage, and `spent of total funds` (for example, `RM 600 of RM 1,000`).
- Cap the visual bar at 100%.
- Above 100%, replace the normal secondary label with `Overspent by <amount>`.
- With zero funds and expenses, show `Not funded` plus the expense amount.
- Tapping a Plan row opens Plan detail.
- Plan sorting modes are Date Added, Last Updated, Name, and Manual. Every automatic mode supports ascending and descending. Default is Date Added, newest first.
- Manual mode supports drag and drop and stores a stable arrangement per Budget.
- When returning to Manual after using an automatic sort, ask whether to restore the saved manual arrangement or replace it with the currently displayed arrangement.
- Swipe actions provide Edit and Delete. Disable destructive full swipe; reveal Delete and require a tap.
- The detail toolbar overflow also provides Edit and Delete.
- Plan deletion confirmation shows affected Item and Transaction counts. Deleting an open Plan returns to its Budget parent.

## Budget Items and Plan detail

- Plan detail shows its Items and relevant totals. Add Item is available from the toolbar and the no-Items empty state.
- Create/edit Item fields: name, unit amount, and multiplier.
- Unit amount accepts zero or a positive value.
- Multiplier accepts whole numbers greater than zero only, even though it remains stored as `Decimal`.
- Show a live planned-amount preview where useful.
- Item rows sort only by remaining amount, ascending or descending. Default is highest remaining first.
- Item row progress compares expenses against planned amount plus effective income.
- Cap the bar at 100%. When over, show the overspent amount.
- If planned amount plus effective income is zero and expenses exist, show a full warning bar and the full overspent amount.
- Tapping an Item opens Item detail.
- Item detail always shows Planned, Income, Spent, and Remaining above the transaction list.
- Swipe actions provide Edit and Delete. Full swipe may initiate deletion, but confirmation is still mandatory.
- The detail toolbar overflow also provides Edit and Delete.
- Item deletion confirmation shows the affected Transaction count. Deleting an open Item returns to Plan detail.
- Add Transaction appears in the Plan and Item toolbars and in relevant empty states, but is disabled at Plan level until at least one Item exists.

## Transactions

- One Add Transaction action handles both types.
- Create/edit fields: type, amount, date, and optional note. Destination Item is selected as part of the entry flow rather than treated as an additional free-form field.
- Default a new transaction to Expense and today.
- Amount entry accepts a positive magnitude only; type determines income or expense.
- Expenses may use today or an earlier date. Income may use any date.
- If a future-dated income is changed to Expense, block saving until the user selects today or an earlier date.
- A newly created transaction returns to the screen that started the flow.
- Editing may move a transaction only to another Item in the same Plan. After a move, open the destination Item detail.
- From a destination picker, the user may create an Item. After saving it, select it automatically and continue to the transaction form.
- Order Item transactions by transaction date, newest first, with deterministic tie breakers.
- Each row shows amount, date, and note when present. Hide the note when empty.
- Use green for income amounts and red for expense amounts. Keep visible rows free of a redundant type label/icon, but include `Income` or `Expense` in the accessibility label so meaning is not color-only for assistive technology.
- Future income appears dimmed with its future date. It automatically loses dimming and begins affecting totals when its date arrives; do not mutate the transaction merely to activate it.
- Swipe actions provide Edit and Delete. Full swipe may initiate deletion, but confirmation is still mandatory.
- Transaction deletion always requires confirmation. Receipt-cascade wording can remain generic because receipt capture is not implemented in this phase.

## Validation and naming

- Trim surrounding whitespace before saving names.
- Budget names are unique among Budgets; Plan names are unique within their Budget; Item names are unique within their Plan.
- Compare uniqueness after trimming and case folding.
- Empty, duplicate-name, amount, multiplier, and date errors appear inline beneath the affected field.
- When Save is tapped with invalid data, retain the inline errors and also show a concise summary alert.
- Transaction notes are optional and omitted from rows when empty.
- Failed saves and failed deletions must leave the store unchanged and offer recovery.

## Shared interaction rules

- Parent rows retain swipe actions; open Budget, Plan, and Item surfaces also expose Edit/Delete in a toolbar overflow.
- Deleting the record currently being viewed returns to its parent.
- All destructive confirmations name the record and show the agreed descendant counts.
- Use loading, empty, content, and recoverable-error states where applicable.
- Support light/dark mode, Dynamic Type, VoiceOver, Reduce Motion, and 44-point minimum tap targets.
- Do not add charts in Phase 2. Progress bars are status indicators, not report charts.

## Suggested implementation order

1. Add a clock/effective-date abstraction, currency metadata/formatting service, normalized-name validator, and Phase 2 calculation tests.
2. Implement repository protocols and SwiftData repositories.
3. Implement mutation use cases, sibling uniqueness, atomic save/rollback behavior, and deletion-impact queries.
4. Implement onboarding and currency setup/change flows.
5. Implement the Budgets accordion, Budget forms, totals, persisted expansion, and deletion.
6. Implement Plan forms, sorting/manual ordering, progress states, detail, and deletion.
7. Implement Item forms, remaining sort, progress states, detail, and deletion.
8. Implement Transaction creation/edit/move/delete, destination selection, and scheduled-income presentation.
9. Add focused UI tests and run the full suite.

## Required tests

- device-currency suggestion, skip flow, canceled first Budget, and retained/discarded currency choice
- currency minor-unit validation for zero-, two-, and three-decimal currencies
- currency relabel confirmation and precision-mismatch disclosure
- trimmed/case-insensitive sibling-name uniqueness at Budget, Plan, and Item levels
- Plan and Item zero-value acceptance; positive whole-number multiplier enforcement
- effective income before, on, and after its date using a fixed calendar/time zone
- future-income exclusion from Item, Plan, and Budget totals and progress
- expense future-date rejection and type-change correction
- every Plan sort mode/direction, manual reorder, and restore/replace choice
- Item remaining ascending/descending order and deterministic ties
- normal, overspent, and unfunded progress states
- transaction creation return path and same-Plan move destination path
- deletion counts, cancellation, failure rollback, and post-delete navigation
- accessibility labels for colored transaction rows and progress states
- end-to-end UI flow: currency → Budget → Plan → Item → expense/income → edit/move → confirmed deletions

## Exit condition

- The app builds all targets without new warnings.
- Existing Phase 1 tests and all new Phase 2 tests pass.
- A user can complete and maintain the full manual hierarchy offline.
- Totals use exact `Decimal` values and scheduled income becomes effective on the correct local calendar day.
- The implementation matches `PRODUCT_SPEC.md`, `UI_SPEC.md`, this brief, and the CanI Google Sheet.
