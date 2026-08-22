# CanI V2 - Phase 3 Observation Refinement 2

## Status and objective

Phase 3 Observation Refinement 1 is the certified baseline with 134 enabled tests passing. This bounded observation refinement improves current-balance visibility during Item and Transaction entry, simplifies Item rows by classification, and adds a derived Mark as Spent workflow.

Preserve all Phase 3 and Observation Refinement 1 behavior not explicitly superseded here. Do not change the SwiftData schema, and do not implement Phase 4 or later work.

## Scope

Include only:

- live allocation preview in Budget Item create and edit forms
- live Item and Plan projections in Transaction create and edit forms
- simplified Item-row presentation by Available, Spent, Overspent, and Income-only state
- Mark as Spent action that creates an expense transaction for the exact current remaining amount
- centralized immutable DTOs and calculation/use-case functions for these behaviors
- focused deterministic domain and UI tests for this refinement

## Live allocation preview

Budget Item forms show a compact allocation summary based on current operational values as of today, independent of the selected reporting period.

Plan available funds are:

`Plan starting amount + all currently effective Plan income`

Projected unallocated is:

`Plan available funds - qualifying allocation from all other Items - qualifying draft allocation`

Draft allocation is:

`draft unit amount x draft multiplier`

All calculations use Decimal. Income-only Items do not count as allocated. Empty Items, mixed Items, and expense Items count as allocated. Editing removes the persisted Item's current qualifying allocation before applying the draft values and never double-counts the edited Item.

Invalid or incomplete input shows no calculated amount. Nonnegative states use explicit “unallocated” text. Negative states use explicit “overallocated” text. Color is supplementary only.

## Live Transaction projections

Transaction forms show both projected balances:

`Item after transaction = Item planned amount + effective Item income - Item expenses`

`Plan after transaction = Plan starting amount + effective Plan income - Plan expenses`

Editing first removes the persisted Transaction's original effect, then applies the draft effect. Destination, kind, amount, date, and Create New Item state changes recalculate immediately. Future-dated income is identified as scheduled and excluded from current balances.

For Create New Item, the accepted shared Item-name/Transaction-note behavior remains. The Item unit amount equals the Transaction amount and multiplier is one. Expense creation normally projects the new Item to exactly zero remaining. Income-only new Items retain their unit amount and remain excluded from allocated totals.

## Item-row presentation

Available Items retain planned, spent, remaining, progress, and percentage.

Income-only Items show effective income and scheduled income separately, and hide progress, percentage, spent amount, and remaining amount.

Spent Items show total spent and hide progress, percentage, planned amount, and remaining amount.

Overspent Items show total spent and explicit overspent amount, and hide progress and percentage.

Classification remains derived from transactions and current funds. Rows update after relevant Item, Transaction, and local-day changes.

## Mark as Spent

Mark as Spent is available from Item-row swipe actions and Item detail actions only when the Item is not income-only and current remaining amount is greater than zero.

It confirms the exact generated expense amount dated today. On confirmation it atomically creates one Expense transaction with:

- amount equal to exact current remaining
- date equal to today in the current local Calendar
- note equal to the Item name
- destination equal to that Item

It does not store spent state. Spent state remains derived from Transactions. Rapid duplicate taps are guarded. Failure leaves no partial mutation and shows a recoverable error.

## Centralized calculations

Views render immutable snapshots and invoke coordinator/use-case actions only. They must not duplicate formulas for allocation preview, transaction projections, effective versus scheduled income, Mark as Spent eligibility, or simplified row presentation.

## Verification

Preserve all 134 certified tests. Add focused deterministic tests for allocation preview, transaction projections, row presentation, Mark as Spent, and the new UI interactions.

The 120-second tool wrapper limit is binding. Use deterministic counted batches and never count an unresolved timeout as passed.

Runtime verification remains scoped to the selected iPhone 17 simulator in portrait around 402 x 874 and landscape around 874 x 402. Broader device verification remains deferred.
