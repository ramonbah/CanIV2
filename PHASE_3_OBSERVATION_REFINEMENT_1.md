# CanI V2 - Phase 3 Observation Refinement 1

## Status and objective

Phase 3 Search, Filters, and Reports is the certified baseline with 124 enabled tests passing. This bounded observation refinement adjusts the Phase 3 user experience and corrects report semantics discovered during observation.

This refinement is active over the certified Phase 3 baseline. Preserve all Phase 3 behavior not explicitly superseded here, preserve Refinement 1 and Phase 2 accepted behavior, do not change the SwiftData schema, and do not implement Phase 4 or later work.

## Scope

Include only:

- dedicated Budget and Plan report screens reached from compact Reports rows
- corrected Plan Remaining, Unallocated, and income-only allocation semantics
- compact proportional report-card spacing
- hierarchical Transaction Budget, Plan, and Item draft filters
- UUID-safe row and report-card navigation audit fixes
- atomic Item-and-Transaction creation from the Transaction form
- dynamic Plan Item classification tabs
- centralized user-visible date presentation
- focused deterministic domain and UI tests for this refinement

## Reports in hierarchy screens

Budget detail and Plan detail show one Reports row or button instead of long inline report content. The row is hidden when no report has meaningful data even under All Time, as determined by report/domain snapshots rather than view-local calculations.

The dedicated Budget Reports screen owns the shared reporting-period picker, Budget interval picker, and Budget report cards. The dedicated Plan Reports screen owns the shared reporting-period picker, Plan timeline mode picker, and Plan report cards.

Every report card opens only its matching report-detail destination. Allocation opens Allocation, Spent and Remaining opens Spent and Remaining, Item Net Flow opens Item Net Flow, Timeline opens Timeline, and every Budget report follows the same exact-routing rule. Returning restores the Reports screen, selected reporting period, Budget interval, and Plan timeline mode.

## Correct report calculations

Plan Remaining is:

`starting amount + every income effective by the selected period endpoint - every expense through the selected period endpoint`

Plan Unallocated is:

`starting amount + every income effective by the selected period endpoint - qualifying allocated Item planned amounts`

Remaining and Unallocated are independent. Expenses reduce Remaining. Planned allocations reduce Unallocated. Expenses do not reduce Unallocated. Planned allocation does not reduce Remaining.

An Item is income-only when it has at least one transaction and every transaction is income. Income-only Item planned/unit amounts are excluded from allocated totals. Income still increases available funds and Remaining when effective. Items with expenses, including mixed income-and-expense Items, participate in allocation normally. Items with no transactions and a planned amount continue to count as allocated.

All calculations use Decimal. Conversion to Double remains limited to chart rendering.

## Proportional report-card spacing

Allocation and Spent and Remaining report cards use compact proportional bars without a large inherited chart minimum height. Expanded report-detail charts may remain larger.

## Hierarchical Transaction filters

Draft filters initially show Budget choices only. Plans appear only after at least one Budget is selected and are grouped under their selected Budget. Items appear only after at least one Plan is selected and are grouped under their selected Plan.

Multiple Budgets, Plans, and Items remain selectable. Identical Plan or Item names under different parents remain visually distinguishable. Clearing or deselecting a Budget immediately removes incompatible draft Plan and Item selections. Clearing or deselecting a Plan immediately removes incompatible draft Item selections.

Results remain unchanged until Apply. Invalid Apply preserves the prior applied query and the invalid draft for correction. Apply collapses the panel and shows chips. Chip labels include parent context where needed to distinguish duplicates.

## Row navigation

Every tappable Budget, Plan, Item, Transaction, report card, and report transaction row routes by stable UUID identity to exactly the intended entity or report. Transaction search and report rows open the exact Item and highlighted Transaction. Duplicate names under different parents must not affect routing.

## Create a new Item while adding a Transaction

Transaction creation destination selection offers Existing Item and Create New Item. Create New Item asks for one required name. The trimmed name becomes both the new Budget Item name and the Transaction note. The Item unit amount equals the Transaction amount and multiplier defaults to 1.

The new Item and Transaction save atomically. If validation or persistence fails, neither is saved. Existing Item-name uniqueness rules within the Plan apply.

For income transactions, the new Item retains the income amount as unit amount, is classified as Income when it contains only income, excludes its planned/unit amount from allocation totals, and its effective income increases Plan funds and Remaining. For expense transactions, the new Item is classified by the dynamic Item classification rules.

## Dynamic Plan Item tabs

Plan Items are classified as:

- Income: has at least one transaction and every transaction is income
- Spent: not income-only, and expenses are at least 100% of available Item funds
- Available: every remaining Item, including empty Items, partially spent Items, and mixed income-and-expense Items below 100% spent

Classification uses centralized Item progress/funds calculations. Views must not duplicate financial arithmetic.

Only populated classifications are shown. If one classification is populated, no tab control is shown. If two or three are populated, show exactly those tabs. Empty tabs are never shown. If mutation removes the selected tab, choose the first available tab in this order: Available, Spent, Income. Existing Item sorting is preserved within each classification.

## Date presentation

Centralize user-visible date formatting. Dates in the current local calendar year omit the year. Dates outside the current local calendar year include the year. Use the injected or current local Calendar, Locale, and reference date. Apply consistently to transaction rows, grouping headers, report ranges, and detail surfaces. Stored dates and filter calculations are unchanged.

## Verification

Preserve all certified tests and add focused deterministic tests for report calculations, report UI routing, hierarchical filters, UUID row navigation, atomic Item-and-Transaction creation, Item classification tabs, and date presentation.

The 120-second tool wrapper limit is binding. Run tests in deterministic counted batches, split any individual long test by behavior if needed, and never count an unresolved timeout as passed.

Runtime verification remains scoped to the selected iPhone 17 simulator in portrait around 402 x 874 and landscape around 874 x 402. Broader device verification remains deferred.
