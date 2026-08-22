# CanI V2 UI Specification

## Information architecture

Use a `TabView` with an independent `NavigationStack` per tab:

1. Home
2. Budgets
3. Transactions
4. Settings

Phase 3 activates Home reports and global transaction search/filtering. Do not expose disabled controls for receipt capture, recurrence, rollover, or transfer.

## First run and currency

- Explain `Budget → Budget Plan → Budget Item → Transaction` in plain language.
- Suggest the device-region currency and provide a searchable ISO 4217 list.
- Tapping a currency selects it and immediately returns to the surface that opened the picker.
- Continue to first-Budget creation or skip to the empty Budgets tab.
- First-Budget creation contains only the Budget name.
- If Budget creation is canceled after currency selection, ask whether to retain that currency.
- Later currency changes show the affected Budget count and warn that values are relabeled, not converted.
- In Settings, show that relabel warning inside the currency picker after the user taps a different currency. Confirming applies the change and returns to Settings. Canceling leaves the current currency unchanged and keeps the picker open.
- Display amounts with the selected currency's standard minor units. Invalid extra digits show inline and block Save.
- If exact stored components and a displayed rounded total appear inconsistent after a currency change, place an info icon beside the total. Its popover explains the mismatch with only the extra precision needed.

## Budgets

### Budgets tab

- Sort Budgets by creation date, newest first.
- A compact row shows Budget name and Plan count.
- Tapping the row header toggles an accordion-style expanded Budget surface. Persist the selected expanded Budget across tab visits and app launches.
- The expanded header shows Budget name, total funds, spending, and current balance.
- Show aggregate spending progress only when spending is above zero.
- Place Plan sorting directly above the Plan list.
- When no Budget is expanded, the toolbar Add button opens Add Budget directly. When a Budget is expanded, the same single Add button opens a menu with `Add Budget` and `Add Plan`; `Add Plan` targets the expanded Budget. The no-Budgets state also shows `Create Budget`.
- Budget rows have swipe Edit/Delete. Disable full-swipe deletion; require a tap on Delete.
- The expanded/detail overflow menu also exposes Edit/Delete.

### Create or edit Budget

- Present as a sheet with one field: name.
- Trim before saving. Require a non-empty name unique across Budgets after case-insensitive comparison.
- Show errors inline and show a summary alert when invalid Save is attempted.
- After rename, return to the surface that opened the editor.

### Delete Budget

- Confirm with the Budget name and affected Plan, Item, and Transaction counts.
- If deleting the open/expanded Budget, return to the Budgets root.

## Budget Plans

### Plan list and progress

- A Plan row shows name, progress bar, percentage, and `spent of total funds`, such as `RM 600 of RM 1,000`.
- Cap the bar at 100%. Above 100%, show `Overspent by <amount>`.
- With zero funds and expenses, show `Not funded` plus the expense amount.
- Tapping a row opens Plan detail.
- Sort by Date Added, Last Updated, Name, or Manual. Automatic sorts allow ascending/descending. Default: Date Added, newest first.
- Manual mode supports drag/drop and saves an arrangement per Budget.
- When returning to Manual, ask whether to restore the saved manual arrangement or replace it with the current sorted arrangement.
- Swipe Edit/Delete; disable full-swipe deletion and require a tap. Detail overflow also exposes Edit/Delete.

### Create or edit Plan

- Fields: name and starting amount.
- Starting amount accepts zero or a positive value.
- Name is trimmed and unique within its Budget after case-insensitive comparison.
- Add Plan appears in the toolbar and no-Plans empty state.
- Inline field errors remain visible; invalid Save also shows a summary alert.

### Delete Plan

- Confirm with affected Item and Transaction counts.
- Deleting an open Plan returns to its Budget parent.

## Budget Items

### Plan detail and Item rows

- Replace separate toolbar Add buttons with one Add menu containing `Add Item` and `Add Transaction`. Disable `Add Transaction` until the Plan has at least one Item. The no-Items empty state still offers Add Item.
- Sort Items only by remaining amount ascending/descending. Default: highest remaining first.
- Item progress compares expenses with planned amount plus effective income.
- Cap the bar at 100% and show the overspent amount when exceeded.
- If available amount is zero and expenses exist, show a full warning bar and the full overspent amount.
- Tapping an Item opens Item detail.
- Swipe Edit/Delete. Full swipe may initiate deletion, but confirmation remains mandatory. Detail overflow also exposes Edit/Delete.

### Create or edit Item

- Fields: name, unit amount, and multiplier.
- Unit amount accepts zero or a positive value.
- Multiplier accepts whole numbers greater than zero.
- Planned amount is `unit amount × multiplier`; a live preview may be shown.
- Name is trimmed and unique within its Plan after case-insensitive comparison.
- Show errors inline and a summary alert after an invalid Save attempt.

### Item detail

- Always show Planned, Income, Spent, and Remaining.
- Group transactions into local-calendar-date sections. Order sections newest first and entries within a section by `createdAt` newest first, then stable ID for deterministic ties.
- Use `Today · Tuesday` and `Yesterday · Monday` for the two relative sections. Older sections use the full weekday and date, for example `Sunday, 9 Aug 2026`. Localize the weekday and month text while preserving this structure.
- Add Transaction appears in the toolbar and the no-Transactions empty state.
- Item deletion confirmation shows affected Transaction count. Deleting an open Item returns to Plan detail.

## Transactions

### Global search and filters

- The Transactions root shows all transactions in local-calendar-date sections when no submitted search or applied filter narrows the result.
- Place search only in the Transactions tab. Search transaction notes, Item names, and Plan names; do not expose or search the generated internal Transaction name.
- Do not update results while typing. Submit the query with the keyboard Return/Search action.
- Place a Filters control above the results. Expanding it reveals Budget, Plan, Item, kind, date, and amount controls inline rather than opening a sheet or separate screen.
- Budget, Plan, and Item filters allow multiple selections. Show only valid descendants of the selected parents and clear incompatible child selections when a parent changes.
- Date options are Last 7 Days, Last 30 Days, Last 90 Days, Current Month, All Time, and Custom Range. A custom range uses inclusive local calendar days and requires start not later than end.
- Amount filtering accepts optional localized minimum and maximum positive magnitudes. Boundaries are inclusive; require minimum not greater than maximum.
- Filter edits remain drafts until Apply. Apply collapses the panel and shows removable active-filter chips above the result sections.
- Removing a chip immediately reapplies the remaining filters. Clear All removes the submitted search and every applied/draft filter.
- Preserve the submitted search and filters across tab changes in the running app until Clear All.
- Distinguish the empty database from a submitted query/filter with no matches. Keep correction and Clear All reachable.
- Tapping a result opens its Item detail, scrolls to the transaction, and visibly identifies the row. Back returns to the same Transactions result and scroll position.
- Search results retain the existing amount, note, future-income, color, VoiceOver, date-header, and deterministic-ordering behavior.

### Add and edit flow

- Use one Add Transaction action with a type selector.
- Form fields: type, amount, date, and optional note. Destination Item is selected in the flow.
- Default to Expense and today.
- Amount is always a positive magnitude; type determines direction.
- Expenses permit today or earlier. Income permits any date.
- Changing future income to Expense requires selecting today or earlier before Save.
- At Plan level, disable Add Transaction until an Item exists.
- From the destination picker, creating an Item automatically selects it and continues to the transaction form.
- A newly created transaction returns to the surface that started the flow.
- Editing may move a transaction only among Items in the same Plan. After a move, open the destination Item detail.

### Transaction rows and deletion

- Show amount, date, and optional note. Hide empty notes.
- Show income amount in green and expense amount in red without a visible type icon/label. Include the type in the VoiceOver label.
- Future income is dimmed and shows its future date. On that date it automatically becomes active and loses dimming.
- Swipe Edit/Delete. Full swipe may initiate deletion, but always show confirmation.

## Reporting

### Shared reporting period

- Home, Budget, Plan, and report-detail surfaces use one in-memory reporting period.
- Default to Last 30 Days on every app launch. Offer Last 7 Days, Last 30 Days, Last 90 Days, Current Month, and All Time.
- A period change updates every report surface immediately. Preserve the shared choice while the app remains running; do not persist it across launches.
- Format the selected period accessibly and state exact start/end dates in report-detail summaries.

### Home

- Replace the placeholder with a report-first scroll surface.
- Lead with period net cash flow across all Budgets. Show the amount in the header of its trend chart.
- Below it, show the three newest transactions in the period and a See All action.
- See All opens a temporary period-filtered Transactions result without overwriting the Transactions tab's submitted search or applied filters. Returning restores the prior Home state.
- Show up to three active Plans ordered by latest transaction activity. A Plan is active only if it has a transaction in the selected period.
- Tapping a transaction opens its Item detail with the transaction visible. Tapping a Plan opens Plan detail. Tapping the net-cash-flow report opens report detail.
- Use separate empty states for no data at all and no activity in the selected period.

### Budget reports

- Add a Reports section to Budget detail without displacing existing Plan management and sorting.
- Plan comparison includes only Plans with activity in the selected period and uses horizontal net-cash-flow bars extending from zero.
- Spending trend supports Day, Week, and Month. Choose Day initially for Last 7 Days, Last 30 Days, and Current Month; Week for Last 90 Days; Month for All Time.
- Remember a manual trend interval separately for each Budget and reporting period. When a different reporting period has no remembered override, use its automatic interval.
- Income versus expense shows localized totals and a time trend with income above zero and expenses below zero.
- Do not show a recurring report or placeholder until Phase 4.

### Plan reports

- Add allocated-versus-unallocated, spent-versus-remaining, Item-breakdown, and timeline report cards to Plan detail without removing existing Item management.
- Allocation uses one proportional horizontal bar comparing every Item's planned amount with funds available by the selected period end. Show negative unallocated value and an explicit overallocated state when applicable.
- Spent versus remaining uses one proportional horizontal bar comparing all expenses through the endpoint with remaining cash balance at that endpoint. Cap visual fill where needed and state overspending explicitly.
- Item breakdown includes only Items with activity in the period and uses horizontal period-net-cash-flow bars extending from zero.
- Timeline has one chart with a display-mode switch. Balance mode shows cumulative balance through the period. Flows mode shows income above zero and expenses below zero. Remember the selected mode separately per Plan.

### Report detail and charts

- Tapping any report card or chart opens a dedicated report-detail screen in the originating tab's navigation stack.
- Include the selected period, expanded chart, equivalent text summary, numerical breakdown, and contributing transactions.
- Group contributing transactions by local calendar day. Tapping one opens Item detail with that row visible; returning restores the report-detail state.
- Use native Swift Charts. Charts may convert snapshot Decimal values only for plotting; labels and summaries use Decimal/currency formatting.
- Charts expose a concise VoiceOver summary, accessible data-point values, and a complete text alternative. Never require color, axis reading, or gestures to understand the result.
- Positive/negative net cash flow uses horizontal bars around zero. Income is above zero and expenses below zero. Allocation and spent/remaining use proportional horizontal bars.
- Avoid decorative empty charts. Use a specific no-activity state with the active period and a recovery path.
- Support iPhone 17 portrait and landscape for the current Phase 3 verification pass. Keep production layout adaptive; broader iPhone/iPad/Dynamic Type verification remains deferred to hardening.

## Validation and destructive actions

- Store trimmed names and compare sibling uniqueness after trimming and case folding.
- Currency precision, duplicate-name, amount, multiplier, and date errors appear inline.
- Every numeric field accepts a plain localized number such as `1,234.50`. Allow temporary empty text or a trailing decimal separator while editing, but require a complete valid number before Save. Reject letters, currency symbols, malformed grouping/decimal separators, and other invalid characters from typing or paste. Preserve the previous valid edit state and show an inline error beneath the field. Apply the same rule to software and hardware keyboards.
- Invalid Save also presents a concise summary alert.
- Open Budget, Plan, and Item surfaces use toolbar overflow actions; parent rows retain swipe actions.
- Deleting the currently viewed record returns to its parent.
- Failed mutations leave data unchanged and provide a recovery action.

## Shared visual and accessibility rules

- Use native system/grouped backgrounds and semantic income, expense, warning, and error colors.
- Prefer lists for dense financial data and cards sparingly.
- Use 16-point content margins and at least 44-point tap targets.
- Support light/dark mode, Dynamic Type, VoiceOver, and Reduce Motion.
- Visible transaction rows may distinguish type by color alone only because the accessibility label explicitly announces Income or Expense.
- Progress states expose readable labels; do not require interpreting the bar or color.
- Do not add report charts in Phase 2.

## Adaptive layout

- Support all app screens in portrait and landscape without clipped fields, hidden actions, overlapping content, or inaccessible confirmation controls.
- Use adaptive layout information rather than hard-coded device model or orientation checks.
- On iPad, use two-column navigation for the manual hierarchy. The sidebar lists Budgets only. Selecting a Budget shows its Plan list in the detail column; selecting a Plan replaces that list with Plan detail; Item detail continues in the same detail column.
- On iPhone landscape, use the same two-column hierarchy when the available width supports it. Otherwise retain the compact stack.
- On compact widths, preserve the existing stack navigation.
- Preserve the selected Budget, open Plan or Item, draft form state, sheet state, and relevant scroll/list state as reasonably possible across rotation, Split View resizing, and column collapse/expansion. Do not duplicate screens or lose a pending edit.
- Toolbars expose the same actions in compact and expanded layouts. Menus and section headers have explicit VoiceOver labels and at least 44-point targets.
