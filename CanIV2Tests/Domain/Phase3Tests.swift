import Foundation
import SwiftData
import Testing
@testable import CanIV2

@Suite("Phase 3 search filters and reports")
struct Phase3Tests {
    @MainActor
    @Test("Search submits only on command and matches notes Item and Plan but not Budget or internal name")
    func searchSubmissionAndFields() throws {
        let fixture = phase3Fixture()
        let service = TransactionQueryService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let empty = TransactionQuery.empty
        #expect(service.results(for: [fixture.travel], query: empty).count == 5)

        let foodQuery = try service.query(from: .empty, submittedSearchText: "CAFÉ", formatter: fixture.formatter)
        #expect(service.results(for: [fixture.travel], query: foodQuery).map(\.id) == [fixture.cafe.id])

        let itemQuery = try service.query(from: .empty, submittedSearchText: "meals", formatter: fixture.formatter)
        #expect(Set(service.results(for: [fixture.travel], query: itemQuery).map(\.id)) == Set([fixture.cafe.id, fixture.futureIncome.id]))

        let planQuery = try service.query(from: .empty, submittedSearchText: "august", formatter: fixture.formatter)
        #expect(service.results(for: [fixture.travel], query: planQuery).count == 5)

        let budgetQuery = try service.query(from: .empty, submittedSearchText: "travel", formatter: fixture.formatter)
        #expect(service.results(for: [fixture.travel], query: budgetQuery).isEmpty)

        let internalNameQuery = try service.query(from: .empty, submittedSearchText: "expense", formatter: fixture.formatter)
        #expect(service.results(for: [fixture.travel], query: internalNameQuery).isEmpty)
    }

    @MainActor
    @Test("Filters use OR within categories AND across categories with Decimal amount and date boundaries")
    func filterSemantics() throws {
        let fixture = phase3Fixture()
        let service = TransactionQueryService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        var draft = TransactionFilterDraft.empty
        draft.itemIDs = [fixture.meals.id, fixture.lodging.id]
        draft.kinds = [.expense]
        draft.dateCriterion = .preset(.last7Days)
        draft.minimumAmountText = "20"
        draft.maximumAmountText = "100"
        let query = try service.query(from: draft, submittedSearchText: "", formatter: fixture.formatter)
        #expect(service.results(for: [fixture.travel], query: query).map(\.id) == [fixture.cafe.id, fixture.hotel.id])

        draft.minimumAmountText = "100.01"
        draft.maximumAmountText = "20"
        #expect(throws: TransactionQueryValidationError.amountRange) {
            _ = try service.query(from: draft, submittedSearchText: "", formatter: fixture.formatter)
        }
    }

    @MainActor
    @Test("Coordinator stages filters until Apply and invalid Apply preserves prior query")
    func coordinatorState() throws {
        let fixture = phase3Fixture()
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())

        coordinator.transactionSearchDraft = "Cafe"
        #expect(coordinator.transactionResults.count == 5)
        coordinator.submitTransactionSearch()
        #expect(coordinator.transactionResults.map(\.id) == [fixture.cafe.id])

        coordinator.transactionFilterDraft.minimumAmountText = "100"
        #expect(coordinator.transactionResults.map(\.id) == [fixture.cafe.id])
        coordinator.applyTransactionFilters()
        #expect(coordinator.transactionResults.isEmpty)

        coordinator.transactionFilterDraft.maximumAmountText = "10"
        coordinator.applyTransactionFilters()
        #expect(coordinator.transactionQueryErrorMessage != nil)
        #expect(coordinator.transactionQuery.minimumAmount == 100)
        #expect(coordinator.transactionQuery.maximumAmount == nil)

        coordinator.clearTransactionQuery()
        #expect(coordinator.transactionResults.count == 5)

        coordinator.transactionSearchDraft = "Hotel"
        coordinator.submitTransactionSearch()
        #expect(coordinator.transactionResults.map(\.id) == [fixture.hotel.id])
        coordinator.beginHomeSeeAllTransactions()
        #expect(coordinator.transactionQuery.dateCriterion == .preset(.last30Days))
        coordinator.restoreTransactionsStateAfterHomeSeeAll()
        #expect(coordinator.transactionQuery.submittedSearchText == "hotel")
        #expect(coordinator.transactionResults.map(\.id) == [fixture.hotel.id])
    }

    @MainActor
    @Test("Parent filter changes clear incompatible descendants")
    func descendantClearing() {
        let fixture = phase3Fixture()
        let otherBudget = Budget(name: "Other")
        let otherPlan = BudgetPlan(name: "Other Plan", budget: otherBudget)
        let otherItem = BudgetItem(name: "Other Item", budgetPlan: otherPlan)
        otherPlan.budgetItems = [otherItem]
        otherBudget.budgetPlans = [otherPlan]
        let service = TransactionQueryService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        var draft = TransactionFilterDraft(budgetIDs: [fixture.travel.id], planIDs: [otherPlan.id], itemIDs: [otherItem.id])

        draft = service.draftByClearingIncompatibleDescendants(draft, budgets: [fixture.travel, otherBudget])
        #expect(draft.planIDs.isEmpty)
        #expect(draft.itemIDs.isEmpty)
    }

    @MainActor
    @Test("Report snapshots use Decimal semantics, future income endpoint rules, limits, and scoped preferences")
    func reportSnapshotsAndPreferences() throws {
        let fixture = phase3Fixture()
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let home = service.homeSnapshot(budgets: [fixture.travel], period: .last7Days, formatter: fixture.formatter)
        #expect(home.netFlow == -120)
        #expect(home.recentTransactions.count == 3)
        #expect(home.activePlans.count == 1)
        #expect(home.buckets.contains { $0.income == 0 && $0.expense == 0 })

        let budget = service.budgetSnapshot(budget: fixture.travel, period: .last30Days, interval: .day, formatter: fixture.formatter)
        #expect(budget.incomeTotal == 300)
        #expect(budget.expenseTotal == 420)
        #expect(budget.planComparisons.first?.value == -120)

        let plan = service.planSnapshot(plan: fixture.august, period: .last30Days, timelineMode: .balance, formatter: fixture.formatter)
        #expect(plan.availableFunds == 800)
        #expect(plan.allocated == 600)
        #expect(plan.unallocated == 200)
        #expect(plan.spent == 420)
        #expect(plan.remaining == 380)
        #expect(plan.itemComparisons.count == 2)

        let preferences = MemoryPhase2PreferenceStore()
        preferences.setBudgetReportInterval(.week, for: fixture.travel.id, periodID: ReportingPeriod.last30Days.id)
        preferences.setPlanTimelineMode(.flow, for: fixture.august.id)
        #expect(preferences.budgetReportInterval(for: fixture.travel.id, periodID: ReportingPeriod.last30Days.id) == .week)
        #expect(preferences.budgetReportInterval(for: fixture.travel.id, periodID: ReportingPeriod.last7Days.id) == nil)
        #expect(preferences.planTimelineMode(for: fixture.august.id) == .flow)
    }

    @MainActor
    @Test("Every transaction date preset and custom local-day range uses inclusive boundaries")
    func datePresetsAndCustomBoundaries() throws {
        let fixture = phase3Fixture()
        let service = TransactionQueryService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let expectations: [(ReportingPeriod, Set<UUID>)] = [
            (.last7Days, Set([fixture.cafe.id, fixture.hotel.id, fixture.salary.id, fixture.taxi.id])),
            (.last30Days, Set([fixture.cafe.id, fixture.hotel.id, fixture.salary.id, fixture.taxi.id])),
            (.last90Days, Set([fixture.cafe.id, fixture.hotel.id, fixture.salary.id, fixture.taxi.id])),
            (.currentMonth, Set([fixture.cafe.id, fixture.hotel.id, fixture.salary.id, fixture.taxi.id])),
            (.allTime, Set([fixture.cafe.id, fixture.hotel.id, fixture.salary.id, fixture.taxi.id, fixture.futureIncome.id]))
        ]
        for (period, ids) in expectations {
            let query = try service.query(from: TransactionFilterDraft(dateCriterion: .preset(period)), submittedSearchText: "", formatter: fixture.formatter)
            #expect(Set(service.results(for: [fixture.travel], query: query).map(\.id)) == ids, "Unexpected ids for \(period)")
        }

        let start = fixture.calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let end = fixture.calendar.date(from: DateComponents(year: 2026, month: 8, day: 21))!
        let custom = try service.query(from: TransactionFilterDraft(dateCriterion: .custom(start: start, end: end)), submittedSearchText: "", formatter: fixture.formatter)
        #expect(Set(service.results(for: [fixture.travel], query: custom).map(\.id)) == Set([fixture.cafe.id, fixture.hotel.id]))

        #expect(throws: TransactionQueryValidationError.invalidCustomDateRange) {
            _ = try service.query(from: TransactionFilterDraft(dateCriterion: .custom(start: end, end: start)), submittedSearchText: "", formatter: fixture.formatter)
        }
    }

    @MainActor
    @Test("Date boundaries respect injected time zone and DST calendar days")
    func dateBoundariesUseInjectedCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let budget = Budget(name: "DST Budget", createdAt: asOf, updatedAt: asOf)
        let plan = BudgetPlan(name: "DST Plan", startingAmount: 0, createdAt: asOf, updatedAt: asOf, budget: budget)
        let item = BudgetItem(name: "DST Item", createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let included = Transaction(name: "Expense", amount: 1, kind: .expense, date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 0, minute: 1))!, createdAt: asOf, budgetItem: item)
        let excluded = Transaction(name: "Expense", amount: 1, kind: .expense, date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 23, minute: 59))!, createdAt: asOf.addingTimeInterval(-1), budgetItem: item)
        item.transactions = [included, excluded]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]

        let service = TransactionQueryService(calendar: calendar, locale: Locale(identifier: "en_US"), asOf: asOf)
        let query = try service.query(from: TransactionFilterDraft(dateCriterion: .preset(.last7Days)), submittedSearchText: "", formatter: CurrencyFormatter(currencyCode: "MYR", locale: Locale(identifier: "en_US")))
        #expect(service.results(for: [budget], query: query).map(\.id) == [included.id])
    }

    @MainActor
    @Test("Plan balance timeline enters period with pre-period balance and excludes future income until effective")
    func planBalanceOpeningAndFutureIncome() throws {
        let fixture = phase3Fixture()
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let plan = service.planSnapshot(plan: fixture.august, period: .last7Days, timelineMode: .balance, formatter: fixture.formatter)
        #expect(plan.timelineBuckets.first?.balance == 500)
        #expect(plan.timelineBuckets.last?.balance == 380)
        #expect(!plan.timelineBuckets.contains { $0.balance >= 1_000 })
    }

    @MainActor
    @Test("Report snapshots cover empty positive negative mixed and exact Decimal datasets")
    func reportDatasetShapes() throws {
        let fixture = phase3Fixture()
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let emptyBudget = Budget(name: "Empty")
        #expect(service.homeSnapshot(budgets: [emptyBudget], period: .allTime, formatter: fixture.formatter).buckets.isEmpty)

        let positiveOnly = service.budgetSnapshot(budget: budgetWithSingleTransaction(kind: .income, amount: Decimal(string: "0.10")!, asOf: fixture.asOf, calendar: fixture.calendar), period: .last7Days, interval: .day, formatter: fixture.formatter)
        #expect(positiveOnly.incomeTotal == Decimal(string: "0.10"))
        #expect(positiveOnly.expenseTotal == 0)

        let negativeOnly = service.budgetSnapshot(budget: budgetWithSingleTransaction(kind: .expense, amount: Decimal(string: "0.20")!, asOf: fixture.asOf, calendar: fixture.calendar), period: .last7Days, interval: .day, formatter: fixture.formatter)
        #expect(negativeOnly.incomeTotal == 0)
        #expect(negativeOnly.expenseTotal == Decimal(string: "0.20"))

        let mixed = service.homeSnapshot(budgets: [fixture.travel], period: .last30Days, formatter: fixture.formatter)
        #expect(mixed.netFlow == Decimal(-120))
        #expect(mixed.summary.contains(fixture.formatter.string(for: mixed.netFlow)))
    }

    @MainActor
    @Test("Chip removal applies immediately and Clear All resets search query and draft state")
    func chipRemovalAndClearAll() throws {
        let fixture = phase3Fixture()
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())

        coordinator.transactionSearchDraft = "Hotel"
        coordinator.submitTransactionSearch()
        coordinator.transactionFilterDraft.kinds = [.expense]
        coordinator.transactionFilterDraft.minimumAmountText = "50"
        coordinator.applyTransactionFilters()
        #expect(coordinator.transactionResults.map(\.id) == [fixture.hotel.id])

        coordinator.removeTransactionFilterChip(.kind(.expense))
        #expect(coordinator.transactionQuery.kinds.isEmpty)
        #expect(coordinator.transactionFilterDraft.kinds.isEmpty)
        #expect(coordinator.transactionQuery.submittedSearchText == "hotel")
        #expect(coordinator.transactionQuery.minimumAmount == 50)
        #expect(coordinator.transactionResults.map(\.id) == [fixture.hotel.id])

        coordinator.clearTransactionQuery()
        #expect(coordinator.transactionSearchDraft.isEmpty)
        #expect(coordinator.transactionQuery == .empty)
        #expect(coordinator.transactionFilterDraft == .empty)
        #expect(coordinator.transactionResults.count == 5)
    }

    @MainActor
    @Test("Temporary Home See All restores prior submitted search applied query and draft filters")
    func homeSeeAllRestoresTransactionsState() throws {
        let fixture = phase3Fixture()
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())

        coordinator.transactionSearchDraft = "Hotel"
        coordinator.submitTransactionSearch()
        coordinator.transactionFilterDraft.kinds = [.expense]
        coordinator.transactionFilterDraft.minimumAmountText = "25"
        coordinator.applyTransactionFilters()
        coordinator.transactionFilterDraft.maximumAmountText = "150"
        let savedQuery = coordinator.transactionQuery
        let savedDraft = coordinator.transactionFilterDraft

        coordinator.reportingPeriod = .last7Days
        coordinator.beginHomeSeeAllTransactions()
        #expect(coordinator.transactionSearchDraft.isEmpty)
        #expect(coordinator.transactionQuery.submittedSearchText.isEmpty)
        #expect(coordinator.transactionQuery.dateCriterion == .preset(.last7Days))

        coordinator.restoreTransactionsStateAfterHomeSeeAll()
        #expect(coordinator.transactionSearchDraft == "hotel")
        #expect(coordinator.transactionQuery == savedQuery)
        #expect(coordinator.transactionFilterDraft == savedDraft)
        #expect(coordinator.transactionResults.map(\.id) == [fixture.hotel.id])
    }

    @MainActor
    @Test("Result route carries Budget Plan Item and Transaction UUIDs and future income remains identifiable")
    func resultRouteAndScheduledIncome() throws {
        let fixture = phase3Fixture()
        let service = TransactionQueryService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let results = service.results(for: [fixture.travel], query: .empty)

        let hotel = try #require(results.first { $0.id == fixture.hotel.id })
        #expect(hotel.route.budgetID == fixture.travel.id)
        #expect(hotel.route.planID == fixture.august.id)
        #expect(hotel.route.itemID == fixture.lodging.id)
        #expect(hotel.route.transactionID == fixture.hotel.id)

        let future = try #require(results.first { $0.id == fixture.futureIncome.id })
        #expect(future.kind == .income)
        #expect(future.isScheduledIncome)
    }

    @MainActor
    @Test("Transaction result grouping and ordering use local day transaction date createdAt and UUID")
    func resultGroupingAndOrderingTieBreakers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))!
        let budget = Budget(name: "Ordering", createdAt: asOf, updatedAt: asOf)
        let plan = BudgetPlan(name: "Plan", createdAt: asOf, updatedAt: asOf, budget: budget)
        let item = BudgetItem(name: "Item", createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 10))!
        let olderDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 10))!
        let newest = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-300000000003")!, name: "Expense", amount: 1, kind: .expense, date: date, createdAt: asOf.addingTimeInterval(2), budgetItem: item)
        let lowerUUID = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-300000000001")!, name: "Expense", amount: 1, kind: .expense, date: date, createdAt: asOf, budgetItem: item)
        let higherUUID = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-300000000002")!, name: "Expense", amount: 1, kind: .expense, date: date, createdAt: asOf, budgetItem: item)
        let olderDay = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-300000000004")!, name: "Expense", amount: 1, kind: .expense, date: olderDate, createdAt: asOf.addingTimeInterval(99), budgetItem: item)
        item.transactions = [higherUUID, olderDay, lowerUUID, newest]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]

        let service = TransactionQueryService(calendar: calendar, locale: Locale(identifier: "en_US"), asOf: asOf)
        let results = service.results(for: [budget], query: .empty)
        #expect(results.map(\.id) == [newest.id, lowerUUID.id, higherUUID.id, olderDay.id])
        let sections = service.sections(for: results)
        #expect(sections.count == 2)
        #expect(sections.first?.transactions.map(\.id) == [newest.id, lowerUUID.id, higherUUID.id])
    }

    @MainActor
    @Test("Report preferences and automatic Budget intervals are scoped by period Budget and Plan UUID")
    func reportPreferenceScopingAndAutomaticIntervals() throws {
        let fixture = phase3Fixture()
        let otherBudget = Budget(id: UUID(uuidString: "00000000-0000-0000-0000-400000000001")!, name: "Other")
        let otherPlan = BudgetPlan(id: UUID(uuidString: "00000000-0000-0000-0000-400000000002")!, name: "Other Plan", budget: otherBudget)
        otherBudget.budgetPlans = [otherPlan]
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        container.mainContext.insert(otherBudget)
        try ModelMutationService.saveValidated(container.mainContext)
        let preferences = MemoryPhase2PreferenceStore()
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: preferences)

        let automatic: [(ReportingPeriod, ReportBucketInterval)] = [
            (.last7Days, .day),
            (.last30Days, .day),
            (.last90Days, .week),
            (.currentMonth, .day),
            (.allTime, .month)
        ]
        for (period, interval) in automatic {
            coordinator.reportingPeriod = period
            #expect(coordinator.automaticBudgetReportInterval() == interval)
        }

        coordinator.reportingPeriod = .last30Days
        coordinator.setBudgetReportInterval(.week, for: fixture.travel)
        coordinator.setPlanTimelineMode(.flow, for: fixture.august)
        #expect(coordinator.budgetReportInterval(for: fixture.travel) == .week)
        #expect(coordinator.budgetReportInterval(for: otherBudget) == .day)
        coordinator.reportingPeriod = .last7Days
        #expect(coordinator.budgetReportInterval(for: fixture.travel) == .day)
        #expect(coordinator.planTimelineMode(for: fixture.august) == .flow)
        #expect(coordinator.planTimelineMode(for: otherPlan) == .balance)
    }

    @MainActor
    @Test("Report buckets include day week and month intervals with missing interior buckets")
    func reportBucketsIncludeMissingInteriorBuckets() {
        let fixture = phase3Fixture()
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let day = service.budgetSnapshot(budget: fixture.travel, period: .last7Days, interval: .day, formatter: fixture.formatter)
        #expect(day.flowBuckets.count == 7)
        #expect(day.flowBuckets.contains { $0.income == 0 && $0.expense == 0 })

        let week = service.budgetSnapshot(budget: fixture.travel, period: .last90Days, interval: .week, formatter: fixture.formatter)
        #expect(week.flowBuckets.count > 7)
        #expect(week.flowBuckets.contains { $0.income == 0 && $0.expense == 0 })

        let monthly = monthlyGapFixture(calendar: fixture.calendar)
        let month = service.budgetSnapshot(budget: monthly, period: .allTime, interval: .month, formatter: fixture.formatter)
        #expect(month.flowBuckets.map(\.income) == [10, 0, 20])
    }

    @MainActor
    @Test("Report inclusion requires period activity for Budget Plans and Plan Items")
    func reportInclusionRequiresPeriodActivity() {
        let fixture = phase3Fixture()
        let inactivePlan = BudgetPlan(id: UUID(uuidString: "00000000-0000-0000-0000-500000000001")!, name: "Inactive", createdAt: fixture.asOf, updatedAt: fixture.asOf, budget: fixture.travel)
        let inactiveItem = BudgetItem(id: UUID(uuidString: "00000000-0000-0000-0000-500000000002")!, name: "Inactive Item", createdAt: fixture.asOf, updatedAt: fixture.asOf, budgetPlan: fixture.august)
        fixture.travel.budgetPlans.append(inactivePlan)
        fixture.august.budgetItems.append(inactiveItem)

        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let budget = service.budgetSnapshot(budget: fixture.travel, period: .last30Days, interval: .day, formatter: fixture.formatter)
        #expect(budget.planComparisons.map(\.title) == ["August"])
        let plan = service.planSnapshot(plan: fixture.august, period: .last30Days, timelineMode: .flow, formatter: fixture.formatter)
        #expect(Set(plan.itemComparisons.map(\.title)) == Set(["Lodging", "Meals"]))
        #expect(!plan.itemComparisons.map(\.title).contains("Inactive Item"))
    }

    @MainActor
    @Test("Plan allocation and spent remaining snapshots cover normal overallocated and overspent cases")
    func planAllocationAndSpentRemainingShapes() {
        let fixture = phase3Fixture()
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let normal = service.planSnapshot(plan: fixture.august, period: .last30Days, timelineMode: .balance, formatter: fixture.formatter)
        #expect(normal.allocationSnapshot.secondary == 200)
        #expect(normal.spentRemainingSnapshot.secondary == 380)

        let overallocated = planFixture(starting: 100, unitAmount: 200, expense: 50, asOf: fixture.asOf)
        let overallocatedSnapshot = service.planSnapshot(plan: overallocated, period: .last30Days, timelineMode: .balance, formatter: fixture.formatter)
        #expect(overallocatedSnapshot.unallocated == -100)
        #expect(overallocatedSnapshot.allocationSnapshot.secondary == -100)

        let overspent = planFixture(starting: 100, unitAmount: 50, expense: 125, asOf: fixture.asOf)
        let overspentSnapshot = service.planSnapshot(plan: overspent, period: .last30Days, timelineMode: .balance, formatter: fixture.formatter)
        #expect(overspentSnapshot.remaining == -25)
        #expect(overspentSnapshot.spentRemainingSnapshot.secondary == -25)
    }

    @MainActor
    @Test("Home limits active Plans to three and orders by date createdAt and UUID tie breakers")
    func homeActivePlanLimitsAndTieBreakers() {
        let fixture = phase3Fixture()
        let budget = Budget(name: "Activity", createdAt: fixture.asOf, updatedAt: fixture.asOf)
        let plans = [
            activePlan(name: "Fourth", idSuffix: "4", transactionDay: 17, createdOffset: 4, budget: budget, calendar: fixture.calendar, asOf: fixture.asOf),
            activePlan(name: "Latest Date", idSuffix: "3", transactionDay: 21, createdOffset: 1, budget: budget, calendar: fixture.calendar, asOf: fixture.asOf),
            activePlan(name: "Created Tie Winner", idSuffix: "2", transactionDay: 20, createdOffset: 2, budget: budget, calendar: fixture.calendar, asOf: fixture.asOf),
            activePlan(name: "UUID Tie Winner", idSuffix: "1", transactionDay: 20, createdOffset: 2, budget: budget, calendar: fixture.calendar, asOf: fixture.asOf)
        ]
        budget.budgetPlans = plans
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let home = service.homeSnapshot(budgets: [budget], period: .last7Days, formatter: fixture.formatter)

        #expect(home.activePlans.count == 3)
        #expect(home.activePlans.map(\.name) == ["Latest Date", "UUID Tie Winner", "Created Tie Winner"])
    }

    @MainActor
    @Test("Report text summaries include monetary values that agree with snapshots")
    func reportTextSummariesAgreeWithSnapshots() {
        let fixture = phase3Fixture()
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let home = service.homeSnapshot(budgets: [fixture.travel], period: .last30Days, formatter: fixture.formatter)
        #expect(home.summary.contains(fixture.formatter.string(for: home.netFlow)))
        let budget = service.budgetSnapshot(budget: fixture.travel, period: .last30Days, interval: .day, formatter: fixture.formatter)
        #expect(budget.summary.contains(fixture.formatter.string(for: budget.incomeTotal)))
        #expect(budget.summary.contains(fixture.formatter.string(for: budget.expenseTotal)))
        let plan = service.planSnapshot(plan: fixture.august, period: .last30Days, timelineMode: .balance, formatter: fixture.formatter)
        #expect(plan.summary.contains(fixture.formatter.string(for: plan.availableFunds)))
        #expect(plan.summary.contains(fixture.formatter.string(for: plan.allocated)))
        #expect(plan.summary.contains(fixture.formatter.string(for: plan.remaining)))
    }

    @MainActor
    @Test("Plan remaining and unallocated use independent endpoint formulas with income-only exclusion")
    func observationRefinementPlanRemainingAndUnallocatedFormulas() {
        let fixture = phase3Fixture()
        let plan = planWithIncomeOnlyAndMixedItems(calendar: fixture.calendar, asOf: fixture.asOf)
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let snapshot = service.planSnapshot(plan: plan, period: .last30Days, timelineMode: .balance, formatter: fixture.formatter)

        #expect(snapshot.availableFunds == 330)
        #expect(snapshot.allocated == 175)
        #expect(snapshot.unallocated == 155)
        #expect(snapshot.spent == 55)
        #expect(snapshot.remaining == 275)
        #expect(snapshot.summary.contains(fixture.formatter.string(for: snapshot.remaining)))
    }

    @MainActor
    @Test("Future income affects Plan reports only after the selected endpoint")
    func observationRefinementFutureIncomeEndpoint() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let before = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 12))!
        let budget = Budget(name: "Endpoint", createdAt: before, updatedAt: before)
        let plan = BudgetPlan(name: "Endpoint Plan", startingAmount: 100, createdAt: before, updatedAt: before, budget: budget)
        let item = BudgetItem(name: "Income", unitAmount: 50, multiplier: 1, createdAt: before, updatedAt: before, budgetPlan: plan)
        let future = Transaction(name: "Income", amount: 80, kind: .income, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 9))!, createdAt: before, budgetItem: item)
        item.transactions = [future]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]
        let formatter = CurrencyFormatter(currencyCode: "MYR", locale: Locale(identifier: "en_US"))

        let beforeSnapshot = DefaultReportService(calendar: calendar, locale: Locale(identifier: "en_US"), asOf: before)
            .planSnapshot(plan: plan, period: .last30Days, timelineMode: .balance, formatter: formatter)
        let afterSnapshot = DefaultReportService(calendar: calendar, locale: Locale(identifier: "en_US"), asOf: after)
            .planSnapshot(plan: plan, period: .last30Days, timelineMode: .balance, formatter: formatter)

        #expect(beforeSnapshot.availableFunds == 100)
        #expect(beforeSnapshot.remaining == 100)
        #expect(afterSnapshot.availableFunds == 180)
        #expect(afterSnapshot.remaining == 180)
    }

    @MainActor
    @Test("Meaningful report availability is derived from all-time snapshots")
    func observationRefinementMeaningfulReportAvailability() {
        let fixture = phase3Fixture()
        let service = DefaultReportService(calendar: fixture.calendar, locale: Locale(identifier: "en_US"), asOf: fixture.asOf)
        let emptyBudget = Budget(name: "Empty", createdAt: fixture.asOf, updatedAt: fixture.asOf)
        let emptyPlan = BudgetPlan(name: "Empty Plan", startingAmount: 0, createdAt: fixture.asOf, updatedAt: fixture.asOf, budget: emptyBudget)
        emptyBudget.budgetPlans = [emptyPlan]

        #expect(!service.hasMeaningfulBudgetReports(budget: emptyBudget, formatter: fixture.formatter))
        #expect(!service.hasMeaningfulPlanReports(plan: emptyPlan, formatter: fixture.formatter))
        #expect(service.hasMeaningfulBudgetReports(budget: fixture.travel, formatter: fixture.formatter))
        #expect(service.hasMeaningfulPlanReports(plan: fixture.august, formatter: fixture.formatter))
    }

    @MainActor
    @Test("Hierarchical draft filters expose descendants only after parents and clear incompatible selections")
    func observationRefinementHierarchicalDraftFilters() throws {
        let fixture = phase3Fixture()
        let otherBudget = Budget(name: "Other", createdAt: fixture.asOf, updatedAt: fixture.asOf)
        let otherPlan = BudgetPlan(name: "August", createdAt: fixture.asOf, updatedAt: fixture.asOf, budget: otherBudget)
        let otherItem = BudgetItem(name: "Meals", createdAt: fixture.asOf, updatedAt: fixture.asOf, budgetPlan: otherPlan)
        otherPlan.budgetItems = [otherItem]
        otherBudget.budgetPlans = [otherPlan]
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        container.mainContext.insert(otherBudget)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())

        #expect(coordinator.transactionDraftPlansByBudget().isEmpty)
        coordinator.setTransactionDraftBudgetSelected(fixture.travel.id, selected: true)
        #expect(coordinator.transactionDraftPlansByBudget().map(\.budget.id) == [fixture.travel.id])
        coordinator.setTransactionDraftPlanSelected(fixture.august.id, selected: true)
        #expect(coordinator.transactionDraftItemsByPlan().map(\.plan.id) == [fixture.august.id])
        #expect(coordinator.contextLabel(forItemID: fixture.meals.id).contains("Travel / August / Meals"))

        coordinator.setTransactionDraftBudgetSelected(fixture.travel.id, selected: false)
        #expect(coordinator.transactionFilterDraft.planIDs.isEmpty)
        #expect(coordinator.transactionFilterDraft.itemIDs.isEmpty)
    }

    @MainActor
    @Test("Atomic new Item and Transaction creation succeeds for income and expense and rejects duplicates")
    func observationRefinementAtomicItemAndTransactionCreation() throws {
        let fixture = phase3Fixture()
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())
        let plan = try #require(coordinator.plan(with: fixture.august.id))

        let expense = try coordinator.createItemAndTransaction(kind: .expense, amountText: "12.34", date: fixture.asOf, itemName: "  Museum  ", in: plan)
        #expect(expense.item.name == "Museum")
        #expect(expense.item.unitAmount == Decimal(string: "12.34"))
        #expect(expense.item.multiplier == 1)
        #expect(expense.transaction.notes == "Museum")
        #expect(coordinator.itemClassification(for: expense.item) == .spent)

        let income = try coordinator.createItemAndTransaction(kind: .income, amountText: "50", date: fixture.asOf, itemName: "Bonus", in: plan)
        #expect(income.item.unitAmount == 50)
        #expect(income.transaction.kind == .income)
        #expect(coordinator.itemClassification(for: income.item) == .income)

        #expect(throws: Phase2ValidationError.duplicateName) {
            _ = try coordinator.createItemAndTransaction(kind: .expense, amountText: "1", date: fixture.asOf, itemName: "Museum", in: plan)
        }
        #expect(throws: Phase2ValidationError.nonPositiveAmount) {
            _ = try coordinator.createItemAndTransaction(kind: .expense, amountText: "0", date: fixture.asOf, itemName: "Invalid", in: plan)
        }
    }

    @MainActor
    @Test("Atomic new Item and Transaction creation rolls back when persistence validation fails")
    func observationRefinementAtomicRollbackOnPersistenceFailure() throws {
        let fixture = phase3Fixture()
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())
        let plan = try #require(coordinator.plan(with: fixture.august.id))
        let itemCount = plan.budgetItems.count
        let transactionCount = plan.budgetItems.flatMap(\.transactions).count
        container.mainContext.insert(AppSettings(currencyCode: "MYR", createdAt: fixture.asOf, updatedAt: fixture.asOf))
        container.mainContext.insert(AppSettings(currencyCode: "USD", createdAt: fixture.asOf, updatedAt: fixture.asOf))

        #expect(throws: DomainValidationError.multipleSettingsRecords) {
            _ = try coordinator.createItemAndTransaction(kind: .expense, amountText: "10", date: fixture.asOf, itemName: "Rollback", in: plan)
        }
        #expect(plan.budgetItems.count == itemCount)
        #expect(plan.budgetItems.flatMap(\.transactions).count == transactionCount)
    }

    @MainActor
    @Test("Item classification covers empty available spent overspent income-only mixed and visible tabs")
    func observationRefinementItemClassificationAndTabs() throws {
        let fixture = phase3Fixture()
        let plan = planForItemClassification(calendar: fixture.calendar, asOf: fixture.asOf)
        let container = try TestFixtures.container()
        container.mainContext.insert(plan.budget)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())
        let savedPlan = try #require(coordinator.plan(with: plan.id))

        let classified = Dictionary(uniqueKeysWithValues: savedPlan.budgetItems.map { ($0.name, coordinator.itemClassification(for: $0)) })
        #expect(classified["Empty"] == .available)
        #expect(classified["Partial"] == .available)
        #expect(classified["Exact"] == .spent)
        #expect(classified["Overspent"] == .spent)
        #expect(classified["Income"] == .income)
        #expect(classified["Mixed"] == .available)
        #expect(coordinator.visibleItemClassifications(for: savedPlan) == [.available, .spent, .income])
        #expect(coordinator.sortedItems(for: savedPlan, classification: .income).map(\.name) == ["Income"])
    }

    @MainActor
    @Test("Centralized date presentation omits current year includes other years and respects local year and locale")
    func observationRefinementDatePresentation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 1))!
        let formatter = UserVisibleDateFormatter(calendar: calendar, locale: Locale(identifier: "en_GB"), referenceDate: reference)

        #expect(formatter.string(for: calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23))!) == "31 Dec")
        #expect(formatter.string(for: calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23))!) == "31 Dec 2025")
        let french = UserVisibleDateFormatter(calendar: calendar, locale: Locale(identifier: "fr_FR"), referenceDate: reference)
        #expect(french.string(for: calendar.date(from: DateComponents(year: 2026, month: 8, day: 9))!).contains("août"))
    }

    @MainActor
    @Test("Observation Refinement 2 allocation preview handles new edit overallocated invalid income-only mixed and exact Decimal")
    func observationRefinement2AllocationPreview() throws {
        let fixture = phase3Fixture()
        let preview = Phase2Calculations.allocationPreview(for: fixture.august, editing: nil, draftUnitAmount: Decimal(string: "100.25")!, draftMultiplier: 2, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(preview.planAvailableFunds == 800)
        #expect(preview.otherAllocated == 600)
        #expect(preview.draftAllocation == Decimal(string: "200.50")!)
        #expect(preview.projectedUnallocated == Decimal(string: "-0.50")!)

        let editPreview = Phase2Calculations.allocationPreview(for: fixture.august, editing: fixture.meals, draftUnitAmount: 100, draftMultiplier: 1, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(editPreview.otherAllocated == 400)
        #expect(editPreview.projectedUnallocated == 300)

        let incomePlan = planWithIncomeOnlyAndMixedItems(calendar: fixture.calendar, asOf: fixture.asOf)
        let incomeOnly = incomePlan.budgetItems.first { $0.name == "Income Only" }!
        let incomeEdit = Phase2Calculations.allocationPreview(for: incomePlan, editing: incomeOnly, draftUnitAmount: 999, draftMultiplier: 1, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(incomeEdit.draftAllocation == 0)
        #expect(incomeEdit.otherAllocated == 175)

        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())
        #expect(coordinator.itemAllocationPreview(for: fixture.august, editing: nil, unitAmountText: "", multiplierText: "1") == nil)
        #expect(coordinator.itemAllocationPreview(for: fixture.august, editing: nil, unitAmountText: "10", multiplierText: "1.5") == nil)
    }

    @MainActor
    @Test("Observation Refinement 2 transaction projections handle expense income edit destination kind scheduled and new Item cases")
    func observationRefinement2TransactionProjections() {
        let fixture = phase3Fixture()
        let expense = Phase2Calculations.transactionProjection(in: fixture.august, destination: fixture.meals, editing: nil, draftKind: .expense, draftAmount: 30, draftDate: fixture.asOf, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(expense.itemAfter == 150)
        #expect(expense.planAfter == 350)

        let income = Phase2Calculations.transactionProjection(in: fixture.august, destination: fixture.meals, editing: nil, draftKind: .income, draftAmount: 25, draftDate: fixture.asOf, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(income.itemAfter == 205)
        #expect(income.planAfter == 405)

        let scheduledDate = fixture.calendar.date(byAdding: .day, value: 2, to: fixture.asOf)!
        let scheduled = Phase2Calculations.transactionProjection(in: fixture.august, destination: fixture.meals, editing: nil, draftKind: .income, draftAmount: 25, draftDate: scheduledDate, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(scheduled.itemAfter == 180)
        #expect(scheduled.planAfter == 380)
        #expect(scheduled.scheduledIncomeAmount == 25)

        let edit = Phase2Calculations.transactionProjection(in: fixture.august, destination: fixture.lodging, editing: fixture.cafe, draftKind: .expense, draftAmount: 30, draftDate: fixture.asOf, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(edit.itemAfter == 270)
        #expect(edit.planAfter == 370)

        let kindChange = Phase2Calculations.transactionProjection(in: fixture.august, destination: fixture.meals, editing: fixture.cafe, draftKind: .income, draftAmount: 20, draftDate: fixture.asOf, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(kindChange.itemAfter == 220)
        #expect(kindChange.planAfter == 420)

        let newExpense = Phase2Calculations.newItemTransactionProjection(in: fixture.august, draftKind: .expense, draftAmount: Decimal(string: "12.34")!, draftDate: fixture.asOf, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(newExpense.itemAfter == 0)
        #expect(newExpense.planAfter == Decimal(string: "367.66")!)

        let newIncome = Phase2Calculations.newItemTransactionProjection(in: fixture.august, draftKind: .income, draftAmount: Decimal(string: "12.34")!, draftDate: scheduledDate, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(newIncome.itemAfter == Decimal(string: "12.34")!)
        #expect(newIncome.planAfter == 380)
        #expect(newIncome.scheduledIncomeAmount == Decimal(string: "12.34")!)
    }

    @MainActor
    @Test("Observation Refinement 2 row presentation distinguishes available spent overspent income scheduled and local-day activation")
    func observationRefinement2RowPresentation() {
        let fixture = phase3Fixture()
        let plan = planForItemClassification(calendar: fixture.calendar, asOf: fixture.asOf)
        let empty = plan.budgetItems.first { $0.name == "Empty" }!
        let exact = plan.budgetItems.first { $0.name == "Exact" }!
        let overspent = plan.budgetItems.first { $0.name == "Overspent" }!
        let income = plan.budgetItems.first { $0.name == "Income" }!
        let mixed = plan.budgetItems.first { $0.name == "Mixed" }!

        #expect(Phase2Calculations.itemRowPresentation(for: empty, asOf: fixture.asOf, calendar: fixture.calendar).style == .available)
        #expect(Phase2Calculations.itemRowPresentation(for: exact, asOf: fixture.asOf, calendar: fixture.calendar).style == .spent)
        let overspentPresentation = Phase2Calculations.itemRowPresentation(for: overspent, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(overspentPresentation.style == .overspent)
        #expect(overspentPresentation.overspent == 1)
        #expect(Phase2Calculations.itemRowPresentation(for: income, asOf: fixture.asOf, calendar: fixture.calendar).style == .income)
        #expect(Phase2Calculations.itemRowPresentation(for: mixed, asOf: fixture.asOf, calendar: fixture.calendar).style == .available)

        let scheduledDate = fixture.calendar.date(byAdding: .day, value: 1, to: fixture.asOf)!
        let scheduledIncome = Transaction(name: "Income", amount: 10, kind: .income, date: scheduledDate, createdAt: fixture.asOf, budgetItem: income)
        income.transactions.append(scheduledIncome)
        let before = Phase2Calculations.itemRowPresentation(for: income, asOf: fixture.asOf, calendar: fixture.calendar)
        #expect(before.effectiveIncome == 20)
        #expect(before.scheduledIncome == 10)
        let after = Phase2Calculations.itemRowPresentation(for: income, asOf: scheduledDate, calendar: fixture.calendar)
        #expect(after.effectiveIncome == 30)
        #expect(after.scheduledIncome == 0)
    }

    @MainActor
    @Test("Observation Refinement 2 Mark as Spent creates exact expense and prevents partial duplicate mutation")
    func observationRefinement2MarkAsSpent() throws {
        let fixture = phase3Fixture()
        let container = try TestFixtures.container()
        container.mainContext.insert(fixture.travel)
        try ModelMutationService.saveValidated(container.mainContext)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: fixture.asOf, calendar: fixture.calendar), preferences: MemoryPhase2PreferenceStore())

        let meals = try #require(coordinator.item(with: fixture.meals.id))
        let preview = coordinator.markAsSpentPreview(for: meals)
        #expect(preview.isEligible)
        #expect(preview.amount == 180)
        let transaction = try coordinator.markItemAsSpent(meals)
        #expect(transaction.kind == .expense)
        #expect(transaction.amount == 180)
        #expect(transaction.notes == "Meals")
        #expect(fixture.calendar.isDate(transaction.date, inSameDayAs: fixture.asOf))
        #expect(coordinator.itemClassification(for: meals) == .spent)
        #expect(!coordinator.markAsSpentPreview(for: meals).isEligible)

        let count = meals.transactions.count
        #expect(throws: Phase2ValidationError.self) {
            _ = try coordinator.markItemAsSpent(meals)
        }
        #expect(meals.transactions.count == count)
    }

    @Test("Time Effort calculates Decimal work duration and formats largest nonzero units")
    func timeEffortCalculationAndFormatting() throws {
        let calculator = TimeEffortCalculator()
        let config = TimeEffortConfiguration(monthlySalary: 4_000, monthlyWorkingHours: 160, hoursPerWorkday: 8)

        let month = try calculator.snapshot(amount: 4_000, configuration: config)
        #expect(month.formattedDuration == "1 month")

        let half = try calculator.snapshot(amount: 2_000, configuration: config)
        #expect(half.formattedDuration == "2 weeks")

        let detailed = calculator.format(TimeEffortDuration(years: 0, months: 0, weeks: 3, days: 2, hours: 0, minutes: 3, seconds: 0, milliseconds: 0))
        #expect(detailed == "3 weeks 2 days 3 minutes")

        let skippedZeros = calculator.format(TimeEffortDuration(years: 0, months: 1, weeks: 0, days: 0, hours: 0, minutes: 3, seconds: 5, milliseconds: 0))
        #expect(skippedZeros == "1 month 3 minutes 5 seconds")

        let exact = try calculator.snapshot(amount: Decimal(string: "0.001")!, configuration: TimeEffortConfiguration(monthlySalary: 3, monthlyWorkingHours: 1, hoursPerWorkday: Decimal(string: "0.25")!))
        #expect(exact.duration.seconds == 1)
        #expect(exact.duration.milliseconds == 200)
    }

    @Test("Time Effort rejects unrepresentably large durations and localizes labels")
    func timeEffortOverflowAndLocalization() throws {
        let calculator = TimeEffortCalculator(locale: Locale(identifier: "ms_MY"))
        #expect(calculator.format(TimeEffortDuration(years: 1, months: 2, weeks: 0, days: 3, hours: 0, minutes: 0, seconds: 0, milliseconds: 0)) == "1 tahun 2 bulan 3 hari")

        #expect(throws: TimeEffortError.amountTooLarge) {
            _ = try calculator.snapshot(
                amount: Decimal(Int.max),
                configuration: TimeEffortConfiguration(monthlySalary: Decimal(string: "0.000001")!, monthlyWorkingHours: Decimal(Int.max), hoursPerWorkday: 1)
            )
        }
    }

    @Test("Time Effort unit boundaries carry into configured units")
    func timeEffortUnitBoundaryCarry() throws {
        let calculator = TimeEffortCalculator()
        let config = TimeEffortConfiguration(monthlySalary: 160, monthlyWorkingHours: 160, hoursPerWorkday: 8)

        let belowMinute = try calculator.snapshot(amount: Decimal(string: "0.0166665")!, configuration: config)
        #expect(belowMinute.duration.minutes == 0)
        #expect(belowMinute.duration.seconds == 59)

        let exactMinute = try calculator.snapshot(amount: Decimal(string: "0.0166666666666666667")!, configuration: config)
        #expect(exactMinute.duration.minutes == 1)
        #expect(exactMinute.duration.seconds == 0)

        let oneDay = try calculator.snapshot(amount: 8, configuration: config)
        #expect(oneDay.formattedDuration == "1 day")

        let oneWeek = try calculator.snapshot(amount: 40, configuration: config)
        #expect(oneWeek.formattedDuration == "1 week")

        let oneYear = try calculator.snapshot(amount: 1_920, configuration: config)
        #expect(oneYear.formattedDuration == "1 year")
    }

    @Test("Time Effort validates missing salary amount and work schedule")
    func timeEffortValidation() throws {
        let calculator = TimeEffortCalculator()
        #expect(throws: TimeEffortError.missingSalary) {
            _ = try calculator.snapshot(amount: 10, configuration: .defaults)
        }
        #expect(throws: TimeEffortError.invalidAmount) {
            _ = try calculator.snapshot(amount: 0, configuration: TimeEffortConfiguration(monthlySalary: 1_000, monthlyWorkingHours: 160, hoursPerWorkday: 8))
        }
        #expect(throws: TimeEffortError.invalidWorkdayHours) {
            _ = try calculator.snapshot(amount: 10, configuration: TimeEffortConfiguration(monthlySalary: 1_000, monthlyWorkingHours: 20, hoursPerWorkday: 6))
        }
    }

    @MainActor
    @Test("Coordinator stores Time Effort schedule and salary through injected secure storage")
    func timeEffortCoordinatorStorage() throws {
        let container = try TestFixtures.container()
        let salaryStore = MemorySalaryStore()
        let coordinator = BudgetingCoordinator(
            context: container.mainContext,
            clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)),
            preferences: MemoryPhase2PreferenceStore(),
            localDayScheduler: TaskLocalDayRefreshScheduler(),
            salaryStore: salaryStore
        )

        #expect(coordinator.monthlySalary == nil)
        #expect(coordinator.saveMonthlySalary(Decimal(string: "1234.56")!))
        #expect(coordinator.monthlySalary == Decimal(string: "1234.56")!)
        try coordinator.saveTimeEffortSchedule(monthlyWorkingHours: 150, hoursPerWorkday: Decimal(string: "7.5")!)
        let snapshot = try coordinator.effortSnapshot(for: Decimal(string: "123.456")!)
        #expect(snapshot.monthlyWorkingHours == 150)
        #expect(snapshot.hoursPerWorkday == Decimal(string: "7.5")!)
        #expect(!snapshot.formattedDuration.isEmpty)
        coordinator.isSalaryVisible = true
        coordinator.hideSalary()
        #expect(!coordinator.isSalaryVisible)
        #expect(coordinator.clearMonthlySalary())
        #expect(coordinator.monthlySalary == nil)
    }

    @MainActor
    @Test("Coordinator preserves last salary on secure-store failures")
    func timeEffortSalaryFailurePreservesPreviousValue() throws {
        let container = try TestFixtures.container()
        let salaryStore = MemorySalaryStore()
        let coordinator = BudgetingCoordinator(
            context: container.mainContext,
            clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)),
            preferences: MemoryPhase2PreferenceStore(),
            localDayScheduler: TaskLocalDayRefreshScheduler(),
            salaryStore: salaryStore
        )

        #expect(coordinator.saveMonthlySalary(500))
        salaryStore.failure = TimeEffortError.keychainFailure(errSecAuthFailed)
        #expect(!coordinator.saveMonthlySalary(600))
        #expect(coordinator.monthlySalary == 500)
        #expect(!coordinator.clearMonthlySalary())
        #expect(coordinator.monthlySalary == 500)
    }

    @MainActor
    private func budgetWithSingleTransaction(kind: TransactionKind, amount: Decimal, asOf: Date, calendar: Calendar) -> Budget {
        let budget = Budget(name: "Shape", createdAt: asOf, updatedAt: asOf)
        let plan = BudgetPlan(name: "Shape Plan", createdAt: asOf, updatedAt: asOf, budget: budget)
        let item = BudgetItem(name: "Shape Item", createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let transaction = Transaction(name: kind == .income ? "Income" : "Expense", amount: amount, kind: kind, date: asOf, createdAt: asOf, budgetItem: item)
        item.transactions = [transaction]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]
        return budget
    }

    @MainActor
    private func monthlyGapFixture(calendar: Calendar) -> Budget {
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))!
        let budget = Budget(name: "Monthly", createdAt: asOf, updatedAt: asOf)
        let plan = BudgetPlan(name: "Monthly Plan", createdAt: asOf, updatedAt: asOf, budget: budget)
        let item = BudgetItem(name: "Monthly Item", createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let june = Transaction(name: "Income", amount: 10, kind: .income, date: calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 9))!, createdAt: asOf, budgetItem: item)
        let august = Transaction(name: "Income", amount: 20, kind: .income, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9))!, createdAt: asOf, budgetItem: item)
        item.transactions = [june, august]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]
        return budget
    }

    @MainActor
    private func planFixture(starting: Decimal, unitAmount: Decimal, expense: Decimal, asOf: Date) -> BudgetPlan {
        let budget = Budget(name: "Plan Shape", createdAt: asOf, updatedAt: asOf)
        let plan = BudgetPlan(name: "Plan Shape", startingAmount: starting, createdAt: asOf, updatedAt: asOf, budget: budget)
        let item = BudgetItem(name: "Item Shape", unitAmount: unitAmount, multiplier: 1, createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let transaction = Transaction(name: "Expense", amount: expense, kind: .expense, date: asOf, createdAt: asOf, budgetItem: item)
        item.transactions = [transaction]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]
        return plan
    }

    @MainActor
    private func activePlan(name: String, idSuffix: String, transactionDay: Int, createdOffset: TimeInterval, budget: Budget, calendar: Calendar, asOf: Date) -> BudgetPlan {
        let plan = BudgetPlan(id: UUID(uuidString: "00000000-0000-0000-0000-60000000000\(idSuffix)")!, name: name, createdAt: asOf, updatedAt: asOf, budget: budget)
        let item = BudgetItem(name: "\(name) Item", createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let transaction = Transaction(name: "Expense", amount: 1, kind: .expense, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: transactionDay, hour: 9))!, createdAt: asOf.addingTimeInterval(createdOffset), budgetItem: item)
        item.transactions = [transaction]
        plan.budgetItems = [item]
        return plan
    }

    @MainActor
    private func planWithIncomeOnlyAndMixedItems(calendar: Calendar, asOf: Date) -> BudgetPlan {
        let budget = Budget(name: "Allocation Rules", createdAt: asOf, updatedAt: asOf)
        let plan = BudgetPlan(name: "Allocation Rules", startingAmount: 200, createdAt: asOf, updatedAt: asOf, budget: budget)
        let incomeOnly = BudgetItem(name: "Income Only", unitAmount: 75, multiplier: 1, createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let income = Transaction(name: "Income", amount: 100, kind: .income, date: asOf, createdAt: asOf, budgetItem: incomeOnly)
        incomeOnly.transactions = [income]
        let expenseOnly = BudgetItem(name: "Expense Only", unitAmount: 50, multiplier: 2, createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let expense = Transaction(name: "Expense", amount: 40, kind: .expense, date: asOf, createdAt: asOf, budgetItem: expenseOnly)
        expenseOnly.transactions = [expense]
        let mixed = BudgetItem(name: "Mixed", unitAmount: 75, multiplier: 1, createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
        let mixedIncome = Transaction(name: "Income", amount: 30, kind: .income, date: asOf, createdAt: asOf, budgetItem: mixed)
        let mixedExpense = Transaction(name: "Expense", amount: 15, kind: .expense, date: asOf, createdAt: asOf, budgetItem: mixed)
        mixed.transactions = [mixedIncome, mixedExpense]
        plan.budgetItems = [incomeOnly, expenseOnly, mixed]
        budget.budgetPlans = [plan]
        return plan
    }

    @MainActor
    private func planForItemClassification(calendar: Calendar, asOf: Date) -> BudgetPlan {
        let budget = Budget(name: "Tabs", createdAt: asOf, updatedAt: asOf)
        let plan = BudgetPlan(id: UUID(uuidString: "00000000-0000-0000-0000-700000000001")!, name: "Tabs", startingAmount: 0, createdAt: asOf, updatedAt: asOf, budget: budget)
        func item(_ name: String, unit: Decimal, order: Int, transactions: [Transaction] = []) -> BudgetItem {
            let item = BudgetItem(name: name, unitAmount: unit, multiplier: 1, sortOrder: order, createdAt: asOf, updatedAt: asOf, budgetPlan: plan)
            item.transactions = transactions
            transactions.forEach { $0.budgetItem = item }
            return item
        }
        let partialExpense = Transaction(name: "Expense", amount: 5, kind: .expense, date: asOf, createdAt: asOf, budgetItem: BudgetItem(name: "Temp", budgetPlan: plan))
        let exactExpense = Transaction(name: "Expense", amount: 10, kind: .expense, date: asOf, createdAt: asOf, budgetItem: BudgetItem(name: "Temp", budgetPlan: plan))
        let overspentExpense = Transaction(name: "Expense", amount: 11, kind: .expense, date: asOf, createdAt: asOf, budgetItem: BudgetItem(name: "Temp", budgetPlan: plan))
        let incomeTransaction = Transaction(name: "Income", amount: 20, kind: .income, date: asOf, createdAt: asOf, budgetItem: BudgetItem(name: "Temp", budgetPlan: plan))
        let mixedIncome = Transaction(name: "Income", amount: 5, kind: .income, date: asOf, createdAt: asOf, budgetItem: BudgetItem(name: "Temp", budgetPlan: plan))
        let mixedExpense = Transaction(name: "Expense", amount: 5, kind: .expense, date: asOf, createdAt: asOf, budgetItem: BudgetItem(name: "Temp", budgetPlan: plan))
        plan.budgetItems = [
            item("Empty", unit: 10, order: 0),
            item("Partial", unit: 10, order: 1, transactions: [partialExpense]),
            item("Exact", unit: 10, order: 2, transactions: [exactExpense]),
            item("Overspent", unit: 10, order: 3, transactions: [overspentExpense]),
            item("Income", unit: 20, order: 4, transactions: [incomeTransaction]),
            item("Mixed", unit: 10, order: 5, transactions: [mixedIncome, mixedExpense])
        ]
        budget.budgetPlans = [plan]
        return plan
    }

    @MainActor
    private func phase3Fixture() -> (
        calendar: Calendar,
        asOf: Date,
        formatter: CurrencyFormatter,
        travel: Budget,
        august: BudgetPlan,
        meals: BudgetItem,
        lodging: BudgetItem,
        cafe: Transaction,
        hotel: Transaction,
        salary: Transaction,
        taxi: Transaction,
        futureIncome: Transaction
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))!
        let travel = Budget(id: UUID(uuidString: "00000000-0000-0000-0000-100000000001")!, name: "Travel", createdAt: asOf, updatedAt: asOf)
        let created = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9))!
        let august = BudgetPlan(id: UUID(uuidString: "00000000-0000-0000-0000-100000000002")!, name: "August", startingAmount: 500, createdAt: created, updatedAt: asOf, budget: travel)
        let meals = BudgetItem(id: UUID(uuidString: "00000000-0000-0000-0000-100000000003")!, name: "Meals", unitAmount: 100, multiplier: 2, createdAt: created, updatedAt: asOf, budgetPlan: august)
        let lodging = BudgetItem(id: UUID(uuidString: "00000000-0000-0000-0000-100000000004")!, name: "Lodging", unitAmount: 400, multiplier: 1, createdAt: created, updatedAt: asOf, budgetPlan: august)
        let cafe = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-100000000005")!, name: "Expense", amount: 20, kind: .expense, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 9))!, notes: "Café breakfast", createdAt: asOf.addingTimeInterval(5), budgetItem: meals)
        let hotel = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-100000000006")!, name: "Expense", amount: 100, kind: .expense, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!, notes: "Hotel", createdAt: asOf.addingTimeInterval(4), budgetItem: lodging)
        let salary = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-100000000007")!, name: "Income", amount: 300, kind: .income, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 9))!, notes: "Salary", createdAt: asOf.addingTimeInterval(3), budgetItem: lodging)
        let taxi = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-100000000008")!, name: "Expense", amount: 300, kind: .expense, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 9))!, notes: "Taxi", createdAt: asOf.addingTimeInterval(2), budgetItem: lodging)
        let futureIncome = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-100000000009")!, name: "Income", amount: 900, kind: .income, date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 9))!, notes: "Future grant", createdAt: asOf.addingTimeInterval(1), budgetItem: meals)
        meals.transactions = [cafe, futureIncome]
        lodging.transactions = [hotel, salary, taxi]
        august.budgetItems = [meals, lodging]
        travel.budgetPlans = [august]
        return (calendar, asOf, CurrencyFormatter(currencyCode: "MYR", locale: Locale(identifier: "en_US")), travel, august, meals, lodging, cafe, hotel, salary, taxi, futureIncome)
    }
}

private final class MemorySalaryStore: SalarySecureStore {
    var salary: Decimal?
    var failure: Error?

    func readSalary() throws -> Decimal? {
        if let failure { throw failure }
        return salary
    }

    func saveSalary(_ salary: Decimal) throws {
        if let failure { throw failure }
        self.salary = salary
    }

    func clearSalary() throws {
        if let failure { throw failure }
        salary = nil
    }
}
