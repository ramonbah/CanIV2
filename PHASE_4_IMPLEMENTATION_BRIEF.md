# CanI V2 - Phase 4 Implementation Brief

## Status and objective

Phase 3 Observation Refinement 3 is the accepted baseline. Phase 4 implements Rollover and Recurrence while preserving Phase 3 persistence startup safety, reports, search, Time Effort, manual hierarchy behavior, and existing data.

## Persistence baseline and migration

Phase 4 uses the shipped Phase 3 SwiftData schema without changing any `@Model` stored property, relationship, inverse, delete rule, uniqueness attribute, or deployment target. The dormant Phase 3 fields already cover this phase:

- `BudgetItem.sourceItemID` records rollover provenance.
- `Budget.recurringTemplates` cascades recurring templates with their Budget.
- `RecurringTransactionTemplate` stores recurrence configuration, enabled/paused state, optional destination, and `nextOccurrence`.
- `BudgetItem.destinationRecurringTemplates` nullifies template destinations when an Item is deleted.
- `Transaction.sourceTemplateID` records generated-transaction provenance.

Because no production schema changes are made, Phase 3 stores are recognized by the same unversioned SwiftData schema and opened through the existing non-destructive startup path. A real on-disk regression must still create a Phase 3-shaped store, close it, reopen it through the Phase 4 application schema, and assert every record and relationship survives. If a future phase changes any model schema, it must introduce explicit `VersionedSchema` and `SchemaMigrationPlan` coverage before shipping.

## Rollover behavior

From a destination Plan, the user selects Items from an earlier Plan in the same Budget. Rollover copies Item name, unit amount, multiplier, and selected relative order only. It never copies Transactions. The new Item stores the source Item UUID in `sourceItemID`.

Rollover validates the whole selection before inserting anything. It rejects a source Plan outside the destination Budget, a source Plan that is not earlier than the destination Plan, empty selections, duplicate source Items in the request, Items already rolled from the same source into the destination Plan, and destination Item name conflicts after trimming and case folding.

Created Items are appended after existing destination Items while preserving selected source order. If validation or save fails, no selected Item is persisted and parent timestamps are restored.

## Recurrence behavior

Templates support daily, weekly, monthly, and yearly frequencies with positive whole-number intervals, start date, optional inclusive end date, amount, kind, Budget, destination Item, next occurrence, and enabled state. Pause sets `isEnabled` false and prevents generation. Resume sets `isEnabled` true and advances `nextOccurrence` to the first occurrence on or after the current local day, preserving the original monthly or yearly anchor.

Missed active occurrences are caught up while the app is active, capped by the caller-provided processing limit. The engine never creates future expense transactions. Income may be generated for future scheduled dates only when the occurrence is due by the local processing day. End dates are inclusive by local calendar day.

Generation is serialized by a coordinator actor. Each processing pass creates all due transactions for an eligible template and advances `nextOccurrence` in the same save operation. Before creating an occurrence, the engine checks all Transactions in the template's Budget for the same `sourceTemplateID` and occurrence local day. The check is destination-independent, so changing or repairing the template destination, moving a generated Transaction, or retrying processing after relaunch cannot create a second Transaction for the same template day.

If a destination Item is deleted, SwiftData nullifies `destinationBudgetItem`. The template remains visible as Needs Destination and is skipped until repaired. Repairing a destination resumes from the first occurrence on or after the repair day; missed occurrences while unresolved are not fabricated.

## Recurring Budget report

Budget Reports include a Recurring Templates report. It lists template name, amount, kind, frequency, interval, status, next occurrence, and destination Item when available. Status values are Active, Paused, Ended, and Needs Destination. The report separates projected template information from generated Transactions and never counts projections as actual income or spending.

## Zero-value presentation refinement

Phase 4 suppresses redundant zero-value metrics without changing financial calculations, stored values, or report inputs. A metric is hidden only when its own `Decimal` value is zero or when it duplicates another visible value because no relevant activity exists. Zero remains visible when it communicates validation, warnings, comparisons, form values, accounting inconsistency, or meaningful state.

Plan summaries and Plan detail evaluate each metric independently. Planned is visible only when Planned is nonzero. Spent is visible only when Spent is nonzero. Progress bars and percentage text are visible only when represented spending progress is nonzero; an unrelated income Transaction never makes a `0%` progress indicator visible. Balance may remain activity-sensitive so offsetting activity is still explainable. Equal funds and balance alone is not treated as no activity. Item rows and Item detail hide zero Income, zero Spent, zero Planned where applicable, redundant Remaining that only repeats Planned with no transaction activity, and zero-progress bars/text. Offsetting nonzero income and expense remain visible because contributing activity exists.

Reports evaluate the currently selected period and scope. If no contributing records exist and every chart value is zero, the chart, empty axes, legends, and zero-only rows are replaced with the concise empty state "No data to show for this filter yet." Nonzero income and expense that net to zero remain meaningful and still render.

## Verification

Phase 4 must preserve all enabled Phase 3 tests and add deterministic domain, on-disk persistence, recurrence, rollover, report, and focused UI tests. Normal startup must still never replace an incompatible store automatically; Retry remains non-mutating, and explicit reset-with-backup remains the only destructive recovery path.
