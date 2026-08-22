# CanI V2 Product Specification

## Product definition

CanI V2 is an offline-first personal budgeting app for iOS. It is built entirely with SwiftUI and stores financial data locally with SwiftData. It uses one app-wide currency. Accounts, authentication, cloud sync, categories, multiple currencies, and notifications are deferred.

The hierarchy is:

`Budget → Budget Plan → Budget Item → Transaction`

- A Budget groups plans and recurring transaction templates.
- A Budget Plan is a free-form plan. It may represent a month, an itinerary, or another purpose; its single descriptive date is optional.
- A Budget Item is an allocation line within a plan.
- A Transaction is an expense or income assigned to one Budget Item. Future-dated income is scheduled and does not affect current totals until its date arrives.

## Domain models

### Budget

- `id: UUID`
- `name: String`
- `createdAt: Date`
- `updatedAt: Date`
- `budgetPlans: [BudgetPlan]`
- `recurringTemplates: [RecurringTransactionTemplate]`

### BudgetPlan

- `id: UUID`
- `name: String`
- `startingAmount: Decimal` with a default of zero
- `descriptiveDate: Date?` used only for sorting and display
- `notes: String?`
- `sortOrder: Int`
- `createdAt: Date`
- `updatedAt: Date`
- `budget: Budget`
- `budgetItems: [BudgetItem]`

### BudgetItem

- `id: UUID`
- `name: String`
- `unitAmount: Decimal`
- `multiplier: Decimal` with a default of one; Phase 2 input and validation restrict it to positive whole numbers
- `sortOrder: Int`
- `sourceItemID: UUID?` for rollover provenance
- `createdAt: Date`
- `updatedAt: Date`
- `budgetPlan: BudgetPlan`
- `transactions: [Transaction]`
- `destinationRecurringTemplates: [RecurringTransactionTemplate]`

### Transaction

- `id: UUID`
- `name: String` retained as an internal required value; Phase 2 manual entry generates it from the transaction kind and does not expose it as a form field
- `amount: Decimal` stored as a positive magnitude
- `kind: TransactionKind` (`expense` or `income`)
- `date: Date`
- `notes: String?`
- `budgetItem: BudgetItem`
- `receipt: ReceiptCapture?`
- `createdAt: Date`
- `updatedAt: Date`
- `sourceTemplateID: UUID?`

### RecurringTransactionTemplate

- `id: UUID`
- `budget: Budget`
- `name: String`
- `amount: Decimal`
- `kind: TransactionKind`
- `frequency: RecurrenceFrequency` (`daily`, `weekly`, `monthly`, `yearly`)
- `interval: Int`
- `startDate: Date`
- `endDate: Date?`
- `destinationBudgetItem: BudgetItem?`
- `nextOccurrence: Date`
- `isEnabled: Bool`
- `createdAt: Date`
- `updatedAt: Date`
- A paused/enabled state must be modeled because the UI requires pause and resume.

Recurring transactions are scoped to one Budget. The recurrence engine processes due occurrences while the app is active. It must be idempotent and must not generate the same occurrence twice.

### ReceiptCapture

- `id: UUID`
- `imageData: Data?`
- `merchant: String?`
- `date: Date?`
- `total: Decimal?`
- `lineItems: [ReceiptLineItem]`
- `transaction: Transaction`
- `createdAt: Date`
- `updatedAt: Date`

### ReceiptLineItem

- `id: UUID`
- `rawText: String`
- `name: String?`
- `amount: Decimal?`
- `isSelected: Bool`
- `receiptCapture: ReceiptCapture`
- `createdAt: Date`
- `updatedAt: Date`

### AppSettings

- `id: UUID`
- `currencyCode: String` containing one supported ISO 4217 code
- `createdAt: Date`
- `updatedAt: Date`

The application maintains one settings record through a centralized fetch-or-create operation. First launch suggests the device-region currency and offers a searchable ISO 4217 list. Changing the code relabels existing amounts and does not convert them; the UI shows the affected Budget count and requires confirmation.

Selecting a currency returns immediately to the surface that opened the picker. In Settings, tapping a different currency first presents the required relabel confirmation within the picker; confirming saves and returns, while canceling keeps the picker open with the existing currency unchanged.

## Relationship deletion rules

- Budget → Budget Plans: cascade.
- Budget → Recurring Templates: cascade.
- Budget Plan → Budget Items: cascade.
- Budget Item → Transactions: cascade.
- Transaction → Receipt Capture: cascade.
- Receipt Capture → Receipt Line Items: cascade.
- Budget Item → destination Recurring Templates: nullify the template destination and preserve the template.

All parent relationships are required except `RecurringTransactionTemplate.destinationBudgetItem`, which is optional so an unresolved template can remain visible but ineligible for generation until repaired. Receipt one-to-one behavior and the AppSettings singleton are enforced through the mutation layer, not assumed to be database uniqueness constraints.

## Calculations

All money calculations must use `Decimal`, not `Double`.

- Item planned amount = `unitAmount × multiplier`.
- Item expense total = sum of expense transactions.
- Item effective income total = sum of income transactions dated today or earlier in the app's local calendar.
- Item scheduled income total = sum of future-dated income transactions; it is visible but excluded from current totals.
- Item net remaining = planned amount + effective income total − expense total.
- Plan planned total = sum of item planned amounts.
- Plan income total = sum of item effective income totals.
- Plan expense total = sum of item expense totals.
- Plan total funds received = `startingAmount + income total`.
- Plan unallocated amount = total funds received − planned total.
- Plan current cash balance = total funds received − expense total.
- Budget totals are sums of equivalent plan totals.

Negative unallocated and cash-balance values are valid and indicate over-allocation or overspending. Derived totals are never persisted. Date-sensitive calculations accept an injected `asOf` date/calendar so tests are deterministic. Scheduled income becomes effective through calculation, not by mutating the transaction.

Centralize these rules so views and reports do not implement competing versions.

## Required capabilities

### Core data management

- Create, rename, list, expand, and delete Budgets.
- Create, edit, sort, manually reorder, list, and delete Budget Plans.
- Create, edit, sort by remaining amount, list, and delete Budget Items.
- Create, edit, move within the same Plan, list, and delete Transactions.
- Show the affected child records before a cascading deletion.

Phase 2 names are trimmed before saving and must be unique among siblings after case-insensitive comparison. Amount input follows the selected currency's standard minor-unit precision; excess digits block saving. Calculations retain exact stored precision after a currency relabel, while display uses the new currency precision and discloses component/total rounding mismatches.

Every numeric editor accepts plain localized numbers, including valid localized grouping and decimal separators. Temporary empty text or a trailing decimal separator may exist while actively editing so users can replace a value or enter a fraction, but only a complete valid number can be saved. Letters, currency symbols, malformed separators, and other invalid characters are rejected for software-keyboard, hardware-keyboard, and paste edits. A rejected edit preserves the previous valid edit state and shows an inline field error. Existing value, sign, whole-number, and currency-minor-unit rules still apply.

Item-detail transactions are grouped by their local calendar date. Date sections and transactions within each section are newest first; within a date, creation time provides the primary entry-order tie breaker followed by a stable deterministic identity. Headers use `Today · <weekday>`, `Yesterday · <weekday>`, then `<weekday>, <day> <abbreviated month> <year>`.

The manual Budget hierarchy supports adaptive two-column navigation. On iPad, the sidebar contains Budgets only. Selecting a Budget shows its Plans in the detail column; selecting a Plan replaces that list with Plan detail, and Item detail continues in that column. iPhone landscape uses the same two-column pattern when the available width supports it. Compact widths retain stack navigation and preserve the user's selection through rotation and resizing.

### Rollover

From a plan, the user chooses an earlier plan within the same Budget, reviews its items, and copies only selected items. Copy the item's name, unit amount, multiplier, and order. Do not copy its transactions. Record the source item ID.

### Search and filtering

Phase 3 global search exists only in the Transactions tab. It performs a case- and diacritic-insensitive contains match over transaction notes, the destination Item name, and the parent Plan name. It does not search the generated internal Transaction name. Receipt merchant, recognized receipt text, and receipt-attached filtering are added with receipt capture in Phase 5 rather than exposed as placeholders.

Search executes only when the user submits with Return/Search. An empty submitted query matches all transactions subject to the applied filters. Results use the same local-calendar-date grouping and deterministic ordering as Item detail.

Filters include:

- zero or more Budgets, Plans, and Items, with multiple selections permitted in each category;
- transaction kind;
- Last 7 Days, Last 30 Days, Last 90 Days, Current Month, All Time, or a custom inclusive local-day date range;
- an inclusive minimum and/or maximum positive transaction magnitude.

Plan choices are limited to descendants of the selected Budgets, and Item choices are limited to descendants of the selected Plans and Budgets. Changing a parent selection clears incompatible descendant selections. Filter edits are staged and affect results only after Apply. Applied filters collapse into individually removable chips; removing a chip updates the applied result immediately, while Clear All removes the submitted search and every filter. The submitted query and applied filters survive tab changes within the running app until cleared.

Tapping a result opens its Item detail, scrolls to the transaction, and makes that row visibly identifiable. Future income remains visible and uses its existing scheduled presentation.

### Receipt capture

- Accept a camera capture or photo-library image.
- Allow retake, crop, rotate, or cancellation.
- Run OCR entirely on-device with Vision.
- Suggest merchant, date, total, and line items, but keep every result editable.
- Let the user use the whole receipt or select only the lines they are paying for.
- Recalculate the selected subtotal before showing the ordinary transaction confirmation form.
- A receipt must never create a transaction without explicit confirmation.

### Device-to-device transfer

- Transfer selected Budgets and their descendants between nearby devices running CanI.
- Use a versioned `Codable` package with stable UUIDs and timestamps.
- Show a review before import and classify records as new, newer incoming, same, older incoming, or conflicting.
- Let the receiver choose which records to add or update.
- Never silently overwrite local records.
- Apply imports atomically and preserve relationship dependencies.
- Allow the sender to choose whether receipt images are included.
- Use a local peer-to-peer transport such as MultipeerConnectivity with encryption and a user-visible verification step.

### Reports

Phase 3 uses one reporting period shared across Home, Budget, Plan, and report-detail surfaces. It resets to Last 30 Days on each app launch. Available periods are Last 7 Days, Last 30 Days, Last 90 Days, Current Month, and All Time; Phase 3 does not offer a custom report period.

Rolling periods include today and the preceding 6, 29, or 89 complete local calendar days through the injected `asOf` instant. Current Month begins at the first local-calendar day of the current month and ends at `asOf`. All Time begins with the earliest relevant record and ends at `asOf`. Period income and expense include transactions whose effective transaction dates fall within the interval. Balance-style figures are snapshots as of the period end: include starting funds for Plans created by that point, all income effective by the endpoint, and all expenses dated by the endpoint. Future income after the endpoint is excluded.

All report calculations use `Decimal` and the existing injected clock/calendar rules. Snapshot DTOs retain Decimal values. Conversion to plottable numeric values may occur only at the chart-rendering boundary and must not feed financial calculations or displayed totals.

- Home: show period net cash flow across all Budgets as a trend chart with the amount in its header. Show the three most recent transactions in the period. Show up to three active Plans, where active means having at least one transaction in the selected period, ordered by latest transaction activity. See All opens a temporary period-filtered Transactions result without replacing the user's saved Transactions query.
- Budget: include only Plans with transaction activity in the selected period. Compare their period net cash flow with horizontal bars extending from zero. Provide an expense trend and income-versus-expense totals and time trends, with income above zero and expenses below zero. Spending aggregation can be Day, Week, or Month; the initial interval is Day for Last 7 Days, Last 30 Days, and Current Month, Week for Last 90 Days, and Month for All Time. A manual interval is remembered per Budget and reporting period. Recurring overview is deferred to Phase 4 and has no Phase 3 placeholder.
- Budget Plan: allocated versus unallocated compares the sum of all Item planned amounts with funds available by the period end and uses a proportional horizontal bar. Spent versus remaining compares all expenses through the endpoint with the remaining cash balance at the endpoint and uses a proportional horizontal bar with explicit over-allocation/overspending states. The Item breakdown includes only Items with activity in the period and compares period net cash flow using horizontal bars extending from zero. The timeline offers a display-mode switch between cumulative balance and income/expense flows; its last mode is remembered separately per Plan.
- Report detail: tapping a report card or chart opens a dedicated detail screen containing an expanded chart, equivalent text summary, numerical breakdown, and contributing transactions. Transaction rows use local-day sections; tapping one opens its Item detail with that transaction visible.

Every chart must expose an equivalent localized text summary and accessible breakdown. Positive income/net cash flow uses the existing income semantic color, negative expense/net cash flow uses the expense semantic color, and meaning must never depend on color alone. Empty datasets show a specific no-activity state rather than zero-valued decorative charts.

## Data and service boundaries

Define repository protocols for Budget, Budget Plan, Budget Item, and Transaction operations. SwiftUI views must not perform persistence logic directly. Define service protocols for receipt scanning, recurrence processing, reports, peer transfer, and transfer merging so each can be tested independently.

## Acceptance criteria

- The app works without internet access after installation.
- The hierarchy and totals remain correct after create, edit, reorder, rollover, delete, and import operations.
- Receipt OCR is treated as a suggestion and is fully reviewable.
- Partial-receipt selection creates a transaction using the selected subtotal.
- Recurrence processing is deterministic and duplicate-safe.
- Transfer review prevents unapproved overwrites and duplicate records.
- Core screens support loading, empty, content, and recoverable error states.
- Global transaction search and filters return the same deterministic results as fixed query fixtures and preserve applied state across tab changes.
- Home, Budget, Plan, and report-detail figures agree with fixed transaction fixtures at local-day period boundaries, including future-income and negative-value cases.
- Every report chart has an equivalent localized text summary and accessible numerical breakdown.
- Core Budget, Plan, Item, and transaction surfaces adapt without clipping or lost navigation state on supported iPhone landscape and iPad sizes.
- Light mode, dark mode, Dynamic Type, VoiceOver, Reduce Motion, and 44-point minimum tap targets are supported.

## Explicitly out of scope

- User accounts or sign-in
- Cloud synchronization
- Multiple currencies or exchange rates
- Categories and category reports
- Notifications or background reminders
- Disabled placeholders for later-version features
