# CanI V2 - Phase 3 Observation Refinement 3

## Status and objective

Phase 3 Observation Refinement 2 is the current source baseline. This bounded refinement certifies the SwiftData optional relationship backing-storage correction needed for safe deletion and adds Time Effort settings, calculations, calculator access, and on-demand effort lookup for monetary values.

Preserve all Phase 3, Observation Refinement 1, and Observation Refinement 2 behavior not explicitly superseded here. Do not implement Phase 4 or later work.

## Persistence and deletion safety

SwiftData child-to-parent relationship backing storage remains optional for BudgetPlan to Budget, BudgetItem to BudgetPlan, Transaction to BudgetItem, ReceiptCapture to Transaction, ReceiptLineItem to ReceiptCapture, and RecurringTransactionTemplate to Budget. Production code treats these relationships as required outside SwiftData deletion and migration windows by guarding parent access at mutation and report boundaries.

Normal app launch must not silently back up, replace, or empty an unreadable store. Store-open failure is a blocking recoverable state with Retry and a statement that user data has not been deleted.

Delete operations must tolerate detached models, avoid invalid required-relationship access, navigate to surviving parents, and leave no orphaned descendants after committed delete. Failed saves must not leave a partially deleted graph.

## Time Effort

Settings adds Time Effort configuration:

- Monthly Salary is a positive Decimal monetary value stored in Keychain without floating-point conversion. It is hidden by default, reveal is session-only, and backgrounding hides it again.
- Monthly Working Hours is a positive Decimal preference with default 160.
- Hours per Workday is a positive Decimal preference with default 8 and must not exceed the configured work-week hours.
- Currency changes relabel salary consistently with all other app values and do not convert it.

Effort calculation uses Decimal:

`effortHours = amount / monthlySalary * monthlyWorkingHours`

The configured effort hierarchy is 12 work months per year, monthly working hours per month, monthly working hours divided by 4 per week, configured hours per workday per day, then hour, minute, second, and millisecond. Durations round to the nearest millisecond and carry overflow through all units.

Display formatting shows the largest nonzero unit and the next two nonzero smaller units, skipping zero units and showing at most three localized components. A zero duration displays "0 milliseconds."

The Effort Calculator accepts a positive amount, updates a valid result live, shows the configured assumptions, works while salary display is hidden, and provides a route to configure salary when missing.

On-demand effort lookup is exposed by reusable money presentation. Press and hold a monetary amount, or use the equivalent accessibility action, to open a compact sheet showing the selected amount, formatted effort, configured assumptions, and a route to the full calculator. The sheet never reveals salary.

## Verification

Add deterministic persistence, deletion, settings/privacy, calculation, calculator UI, and representative quick-lookup tests. The 120-second runner wrapper remains binding; use counted batches and do not count timed-out attempts as passes.
