# CanI V2 Phase 3 Implementation Brief

## Status and precedence

This brief is the binding scope for the single-pass Phase 3 delivery: Search, Filters, and Reports. It starts from the accepted Phase 2 plus Refinement 1 implementation with 88 enabled tests.

Use this precedence:

1. `AGENTS.md` for repository-wide engineering rules.
2. This brief for Phase 3 behavior and explicit deferrals.
3. `PRODUCT_SPEC.md` for product/domain behavior.
4. `UI_SPEC.md` for interface and navigation behavior.
5. `REFINEMENT_1_IMPLEMENTATION_BRIEF.md` and `PHASE_2_IMPLEMENTATION_BRIEF.md` for the verified baseline.
6. `IMPLEMENTATION_PLAN.md` for phase order.

Phase 3 is one complete implementation pass, not separate 3A/3B releases. Observation of the accepted build continues independently; do not incorporate unapproved observation notes opportunistically.

## Hard boundaries

- Do not change the SwiftData schema or expose the generated internal Transaction name.
- Do not implement receipt merchant/OCR search, receipt-attached filtering, receipt UI, or scanning. Those belong to Phase 5.
- Do not implement recurring reports, recurrence processing, or rollover. Those belong to Phase 4.
- Do not add categories, accounts, cloud sync, multiple currencies, notifications, authentication, or disabled placeholders.
- Preserve all Phase 2 and Refinement 1 behavior and keep all existing 88 tests enabled.
- Current runtime verification is limited by user decision to iPhone 17 portrait and landscape. Keep production code adaptive and list broader verification as deferred, never as completed.

## Architecture

### Transaction querying

Create query types outside SwiftUI, with value semantics and deterministic equality:

- submitted normalized search text;
- selected Budget, Plan, and Item UUID sets;
- selected transaction kinds;
- date criterion: none/all time, preset, or inclusive custom local-day range;
- optional inclusive minimum/maximum positive amount magnitude.

Separate draft filter state from applied query state. Search text becomes applied only when submitted. Apply atomically validates and commits the filter draft. Removing a chip creates and applies a new query immediately. Clear All resets submitted text, applied filters, and filter draft.

Use a focused `TransactionQueryService`/use case. Search case- and diacritic-insensitively over notes, Item name, and Plan name. Whitespace-only search is empty. Do not search Budget name, formatted amount/date, kind label, currency symbol, or internal Transaction name.

Filter semantics:

- selected values within a category use OR;
- different categories combine with AND;
- empty selection means no restriction for that category;
- transaction amount filters use stored positive magnitude and inclusive Decimal boundaries;
- date filters use the transaction's date and injected local Calendar; endpoints include their complete local days;
- future income may appear if its transaction date is inside the query range, but retains scheduled presentation and remains excluded from current financial totals until effective.

Return result snapshots carrying the UUID path needed to navigate to Budget, Plan, Item, and Transaction without retaining mutable SwiftData models in query state. Sort/group through the existing local-day transaction ordering rules.

### Reports

Define a `ReportService` protocol and immutable snapshot DTOs for:

- reporting interval and bucket identity;
- Home net-flow trend, recent transactions, and active Plans;
- Budget Plan net-flow comparison, expense trend, and income/expense totals and buckets;
- Plan allocation, spent/remaining, Item net-flow comparison, cumulative-balance timeline, and flow timeline;
- report-detail text summary, breakdown rows, and contributing transaction identities.

All aggregation accepts an injected `asOf`, Calendar, Locale where formatting is needed, and the selected report period. Calculations and snapshots use Decimal. Reuse central calculation/domain rules rather than duplicating formulas in views. Chart-facing adapters may convert final snapshot values to plottable numeric types, but chart values never feed displayed money or later calculations.

Use one observable Phase 3 state/coordinator above the report surfaces for the session-wide reporting period and temporary Home See All route. Reset the period to Last 30 Days when the app composition is created. Persist only the approved scoped preferences:

- Budget trend interval keyed by Budget UUID and report-period identity;
- Plan timeline mode keyed by Plan UUID.

Do not persist the shared reporting period. Preserve Transactions submitted/applied query while navigating between tabs during the running app. A temporary Home See All query is navigation context, not a replacement for saved Transactions state.

## Reporting-period rules

All ranges end at injected `asOf`:

- Last 7 Days: local start of today minus six calendar days through `asOf`.
- Last 30 Days: local start of today minus 29 calendar days through `asOf`.
- Last 90 Days: local start of today minus 89 calendar days through `asOf`.
- Current Month: local start of the first day of the current month through `asOf`.
- All Time: earliest relevant record through `asOf`; an empty dataset yields no buckets.

Period-flow figures include income and expense transactions dated within the interval. Balance-at-end figures include Plan starting funds when the Plan exists by the endpoint, all income effective by the endpoint, and all expenses dated by the endpoint. Never count future income after the endpoint.

Bucket boundaries use the injected local Calendar:

- Day buckets use local calendar days.
- Week buckets use the Calendar's week rules and localized labels.
- Month buckets use local calendar months.
- Empty interior buckets appear as zero only when required for a continuous time axis; a wholly empty dataset uses an empty state instead of a decorative zero chart.

Automatic Budget trend interval: Day for Last 7 Days, Last 30 Days, and Current Month; Week for Last 90 Days; Month for All Time. A saved manual override is read for the same Budget and reporting period before using the automatic value.

## Transactions UI

- Replace the placeholder with grouped results, search submission, and an inline expandable filter panel.
- Search exists only in this tab and runs on Return/Search.
- Multi-select hierarchy filters show only valid descendants and clear incompatible draft child selections when a parent changes.
- Presets: Last 7, Last 30, Last 90, Current Month, All Time, Custom Range.
- Custom start/end and amount min/max validate inline and in a concise Apply summary. Invalid drafts do not replace the applied query.
- Apply collapses the panel and displays removable active-filter chips. Keep a clear distinction between submitted search and filter chips.
- Clear All resets everything. Back navigation from a result restores query, grouping, and reasonable scroll position.
- Tapping a result navigates to Item detail and requests scroll/highlight for its Transaction UUID. The highlight is non-destructive, accessible, and does not change transaction data.
- Provide no-data, no-matches, invalid-filter, and recoverable-query error states.

## Home reports

- Lead with a net-cash-flow trend across all Budgets for the selected period, with the localized net amount in the header.
- Period net cash flow is effective period income minus period expenses.
- Show up to the three newest contributing transactions before See All.
- Show at most three active Plans. Active means at least one transaction in the selected period. Order by latest transaction date, then latest createdAt, then stable UUID.
- See All opens a temporary period-filtered Transactions result and preserves the Transactions tab's submitted search/filter state.
- Transaction and Plan rows navigate to their existing destinations. The report opens Home report detail.

## Budget reports

- Include only Plans with at least one transaction in the selected period.
- Compare Plan period net cash flow with horizontal diverging bars around zero.
- Show period expense trend at the active Day/Week/Month interval.
- Show income and expense totals plus time buckets with income above zero and expenses below zero.
- Use deterministic stable ordering for equal comparison values.
- Provide report detail for comparison, spending trend, and income/expense reports.
- Omit recurring overview entirely in Phase 3.

## Plan reports

- Allocation snapshot: available funds at period end equals starting amount plus income effective by the endpoint. Allocated equals the sum of every Item planned amount. Unallocated equals available funds minus allocated. Negative values show explicit over-allocation; proportional visual fill is capped without hiding the exact negative amount.
- Spent/remaining snapshot: spent equals every expense dated through the endpoint. Remaining cash balance equals starting amount plus effective income through the endpoint minus spent. Negative remaining shows explicit overspending; visual fill is capped while text stays exact.
- Item comparison includes only Items with at least one transaction in the period and compares period net cash flow with horizontal diverging bars.
- Timeline Balance mode shows cumulative cash balance over the selected interval. Flow mode shows period income above zero and expense below zero using the applicable buckets. The per-Plan saved mode selects the initial view.
- Provide a report-detail destination for every Plan report card.

## Report detail, navigation, and accessibility

Every report detail includes:

1. report title and exact localized period;
2. expanded chart;
3. concise equivalent text summary;
4. ordered localized breakdown rows;
5. contributing transactions grouped by local day.

Tapping a contributing transaction opens its Item detail and identifies that Transaction. Returning restores the report detail and selected chart mode/interval.

Every chart must:

- have a useful accessibility label and summary;
- expose values and category/time labels without requiring chart gestures;
- have a complete text equivalent adjacent or reachable in the same screen;
- use semantic income/expense colors while also using position, sign, labels, and spoken meaning;
- remain legible in light/dark mode, portrait/landscape, and representative content lengths;
- avoid clipped currency labels and unstable axes when all values are zero, negative, or mixed.

## Required deterministic tests

### Query service and state

- notes, Item-name, and Plan-name matching; case/diacritic folding and whitespace normalization;
- explicit proof that generated Transaction name and Budget name are not searched;
- OR within multi-select categories and AND across categories;
- descendant option restriction and incompatible-selection clearing;
- income/expense kind filters;
- inclusive Decimal amount minimum/maximum and invalid min-greater-than-max;
- every preset plus inclusive custom date boundaries across local midnight, month, week, DST, calendar, and time-zone changes;
- staged filters do not affect results before Apply; invalid Apply preserves prior applied query;
- chip removal, Clear All, submitted-search timing, empty query, no matches, and tab-state preservation;
- grouping/order, future-income presentation, result UUID route, and scroll/highlight intent.

### Report service

- exact Last 7/30/90, Current Month, and All Time boundaries;
- period income, expenses, and net flow versus balance-at-end semantics;
- scheduled future income before/at/after the endpoint;
- Home three-transaction and three-active-Plan limits and tie-breakers;
- Plan activity inclusion for Home/Budget and Item activity inclusion for Plan breakdown;
- automatic and saved Budget interval selection;
- Day/Week/Month buckets including missing interior buckets;
- Budget comparison, expense trend, and signed income/expense buckets;
- Plan allocation/over-allocation, spent/remaining/overspending, Item net flow, cumulative balance, and flow timeline;
- zero, all-positive, all-negative, mixed-sign, empty, and exact-Decimal datasets;
- text summaries agree with snapshot values and currency formatting.

### UI and navigation

- Transactions search does not run before submission;
- filter expansion, staging, dependent selections, Apply collapse, chips, individual removal, and Clear All;
- no-data versus no-match and validation recovery;
- result-to-Item navigation and return-state preservation;
- shared report period propagation and launch reset;
- Home recent/active limits and temporary See All query isolation;
- report-card-to-detail navigation, text alternatives, contributing transaction navigation, and return state;
- Budget interval preference per Budget and period;
- Plan timeline preference per Plan;
- portrait and landscape reachability, chart labels, 44-point actions, VoiceOver content, and no obvious clipping on iPhone 17.

## Verification and exit condition

1. Build every target with no new warnings caused by Phase 3.
2. Keep all existing 88 tests enabled and passing.
3. Run every new Phase 3 domain, coordinator/state, and UI test.
4. Verify the complete Phase 3 flow on iPhone 17 at approximately 402 × 874 portrait and 874 × 402 landscape.
5. Audit every requirement in this brief and report exact test totals.
6. Report iPad, iPhone SE, narrow-width fallback, Split View, and broader Dynamic Type verification as intentionally deferred by user decision.

Phase 3 is complete only when search/filter behavior and report snapshots agree with deterministic fixtures, every report chart has an equivalent text summary, all enabled tests pass, and the scoped iPhone 17 runtime verification succeeds.
