import Foundation
import SwiftData
import Testing
@testable import CanIV2

@Suite("Phase 2 completion coverage")
struct Phase2CompletionTests {
    @Test("Plan and item sort preferences are scoped by stable parent UUID")
    func scopedPreferences() {
        let store = MemoryPhase2PreferenceStore()
        let firstBudget = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondBudget = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let firstPlan = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let secondPlan = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

        store.setPlanSortMode(.name, for: firstBudget)
        store.setPlanSortDirection(.ascending, for: firstBudget)
        store.setItemSortDirection(.lowestRemainingFirst, for: firstPlan)

        #expect(store.planSortMode(for: firstBudget) == .name)
        #expect(store.planSortDirection(for: firstBudget) == .ascending)
        #expect(store.planSortMode(for: secondBudget) == .dateAdded)
        #expect(store.planSortDirection(for: secondBudget) == .descending)
        #expect(store.itemSortDirection(for: firstPlan) == .lowestRemainingFirst)
        #expect(store.itemSortDirection(for: secondPlan) == .highestRemainingFirst)
    }

    @MainActor
    @Test("Coordinator sort state updates immediately and persists after recreation")
    func coordinatorSortStatePersistsAndUpdatesImmediately() throws {
        let container = try TestFixtures.container()
        let store = MemoryPhase2PreferenceStore()
        let budget = Budget(name: "Budget")
        let alpha = BudgetPlan(name: "Alpha", sortOrder: 1, budget: budget)
        let beta = BudgetPlan(name: "Beta", sortOrder: 0, budget: budget)
        budget.budgetPlans = [alpha, beta]
        container.mainContext.insert(budget)
        try ModelMutationService.saveValidated(container.mainContext)

        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)), preferences: store)
        #expect(coordinator.sortedPlans(for: budget).map(\.name) == ["Beta", "Alpha"])

        coordinator.setPlanSortMode(.name, for: budget)
        coordinator.setPlanSortDirection(.ascending, for: budget)
        #expect(coordinator.sortedPlans(for: budget).map(\.name) == ["Alpha", "Beta"])

        let recreated = BudgetingCoordinator(context: container.mainContext, clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)), preferences: store)
        #expect(recreated.planSortMode(for: budget) == .name)
        #expect(recreated.planSortDirection(for: budget) == .ascending)
        #expect(recreated.sortedPlans(for: budget).map(\.name) == ["Alpha", "Beta"])
    }

    @MainActor
    @Test("Manual sort restore replace repeated prompts persistence and scoped Budgets")
    func manualSortRestoreReplaceRepeatedPromptsPersistenceAndScoping() throws {
        let container = try TestFixtures.container()
        let store = MemoryPhase2PreferenceStore()
        let clock = FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian))

        let firstBudget = Budget(name: "First Budget", createdAt: TestFixtures.date, updatedAt: TestFixtures.date)
        let first = BudgetPlan(name: "Beta", sortOrder: 0, createdAt: TestFixtures.date.addingTimeInterval(1), updatedAt: TestFixtures.date, budget: firstBudget)
        let second = BudgetPlan(name: "Alpha", sortOrder: 1, createdAt: TestFixtures.date.addingTimeInterval(2), updatedAt: TestFixtures.date, budget: firstBudget)
        firstBudget.budgetPlans = [first, second]

        let secondBudget = Budget(name: "Second Budget", createdAt: TestFixtures.date, updatedAt: TestFixtures.date)
        let otherFirst = BudgetPlan(name: "Delta", sortOrder: 0, createdAt: TestFixtures.date, updatedAt: TestFixtures.date, budget: secondBudget)
        let otherSecond = BudgetPlan(name: "Charlie", sortOrder: 1, createdAt: TestFixtures.date.addingTimeInterval(1), updatedAt: TestFixtures.date, budget: secondBudget)
        secondBudget.budgetPlans = [otherFirst, otherSecond]

        container.mainContext.insert(firstBudget)
        container.mainContext.insert(secondBudget)
        try ModelMutationService.saveValidated(container.mainContext)

        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: clock, preferences: store)
        #expect(coordinator.sortedPlans(for: firstBudget).map(\.name) == ["Alpha", "Beta"])

        coordinator.setPlanSortMode(.name, for: firstBudget)
        coordinator.setPlanSortDirection(.ascending, for: firstBudget)
        #expect(coordinator.sortedPlans(for: firstBudget).map(\.name) == ["Alpha", "Beta"])
        #expect(coordinator.requestPlanSortMode(.manual, for: firstBudget))

        coordinator.restoreManualPlanOrder(for: firstBudget)
        #expect(coordinator.sortedPlans(for: firstBudget).map(\.name) == ["Beta", "Alpha"])

        coordinator.setPlanSortMode(.name, for: firstBudget)
        coordinator.setPlanSortDirection(.ascending, for: firstBudget)
        #expect(coordinator.requestPlanSortMode(.manual, for: firstBudget))
        try coordinator.replaceManualPlanOrder(with: coordinator.sortedPlans(for: firstBudget), for: firstBudget)
        #expect(firstBudget.budgetPlans.sorted { $0.sortOrder < $1.sortOrder }.map(\.name) == ["Alpha", "Beta"])
        #expect(coordinator.sortedPlans(for: firstBudget).map(\.name) == ["Alpha", "Beta"])

        coordinator.setPlanSortMode(.lastUpdated, for: firstBudget)
        #expect(coordinator.requestPlanSortMode(.manual, for: firstBudget))

        coordinator.setPlanSortMode(.name, for: secondBudget)
        coordinator.setPlanSortDirection(.ascending, for: secondBudget)
        #expect(coordinator.requestPlanSortMode(.manual, for: secondBudget))
        coordinator.restoreManualPlanOrder(for: secondBudget)
        #expect(coordinator.sortedPlans(for: secondBudget).map(\.name) == ["Delta", "Charlie"])
        #expect(coordinator.sortedPlans(for: firstBudget).map(\.name) == ["Alpha", "Beta"])

        let recreated = BudgetingCoordinator(context: container.mainContext, clock: clock, preferences: store)
        #expect(recreated.planSortMode(for: firstBudget) == .lastUpdated)
        #expect(recreated.requestPlanSortMode(.manual, for: firstBudget))
        recreated.restoreManualPlanOrder(for: firstBudget)
        #expect(recreated.sortedPlans(for: firstBudget).map(\.name) == ["Alpha", "Beta"])
    }

    @MainActor
    @Test("Local day scheduler restarts and refreshes active scheduled income state")
    func localDaySchedulerRestartsAndRefreshesScheduledIncome() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let before = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))
        let boundary = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0)))
        let clock = MutableTestClock(now: before, calendar: calendar)
        let scheduler = ManualLocalDayRefreshScheduler()
        let container = try TestFixtures.container()
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", startingAmount: 0, budget: budget)
        let scheduledItem = BudgetItem(name: "Scheduled", unitAmount: 0, multiplier: 1, sortOrder: 0, budgetPlan: plan)
        let emptyItem = BudgetItem(name: "Empty", unitAmount: 1, multiplier: 1, sortOrder: 1, budgetPlan: plan)
        let income = Transaction(name: "Income", amount: 10, kind: .income, date: boundary, notes: "Payday", budgetItem: scheduledItem)
        scheduledItem.transactions = [income]
        plan.budgetItems = [scheduledItem, emptyItem]
        budget.budgetPlans = [plan]
        container.mainContext.insert(budget)
        try ModelMutationService.saveValidated(container.mainContext)

        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: clock, preferences: MemoryPhase2PreferenceStore(), localDayScheduler: scheduler)
        coordinator.setItemSortDirection(.highestRemainingFirst, for: plan)
        coordinator.startLocalDayRefreshLoop()
        #expect(scheduler.scheduleCount == 1)
        #expect(coordinator.isScheduledIncome(income))
        #expect(coordinator.itemTotals(for: scheduledItem).scheduledIncome == 10)
        #expect(coordinator.planTotals(for: plan).totalFundsReceived == 0)
        #expect(coordinator.budgetTotals(for: budget).totalFundsReceived == 0)
        #expect(coordinator.progress(spent: 5, funds: coordinator.itemTotals(for: scheduledItem).available).isWarning)
        #expect(coordinator.sortedItems(for: plan).map(\.name) == ["Empty", "Scheduled"])

        coordinator.refreshForCalendarOrTimeChange()
        #expect(scheduler.cancelCount == 1)
        #expect(scheduler.scheduleCount == 2)

        clock.now = boundary
        scheduler.fire()
        #expect(!coordinator.isScheduledIncome(income))
        #expect(coordinator.itemTotals(for: scheduledItem).effectiveIncome == 10)
        #expect(coordinator.itemTotals(for: scheduledItem).scheduledIncome == 0)
        #expect(coordinator.planTotals(for: plan).totalFundsReceived == 10)
        #expect(coordinator.budgetTotals(for: budget).totalFundsReceived == 10)
        #expect(!coordinator.progress(spent: 5, funds: coordinator.itemTotals(for: scheduledItem).available).isWarning)
        #expect(coordinator.sortedItems(for: plan).map(\.name) == ["Scheduled", "Empty"])
        #expect(scheduler.scheduleCount == 3)

        coordinator.stopLocalDayRefreshLoop()
        #expect(scheduler.cancelCount == 3)
    }

    @MainActor
    @Test("Every plan sort mode and direction is deterministic")
    func planSorting() {
        let budget = Budget(name: "Budget")
        let oldest = Date(timeIntervalSince1970: 100)
        let middle = Date(timeIntervalSince1970: 200)
        let newest = Date(timeIntervalSince1970: 300)
        let beta = BudgetPlan(name: "Beta", sortOrder: 2, createdAt: oldest, updatedAt: newest, budget: budget)
        let alpha = BudgetPlan(name: "Alpha", sortOrder: 1, createdAt: newest, updatedAt: middle, budget: budget)
        let gamma = BudgetPlan(name: "Gamma", sortOrder: 0, createdAt: middle, updatedAt: oldest, budget: budget)
        let plans = [beta, alpha, gamma]
        let sorter = SortUseCase()

        #expect(sorter.plans(plans, mode: .dateAdded, direction: .ascending).map(\.name) == ["Beta", "Gamma", "Alpha"])
        #expect(sorter.plans(plans, mode: .dateAdded, direction: .descending).map(\.name) == ["Alpha", "Gamma", "Beta"])
        #expect(sorter.plans(plans, mode: .lastUpdated, direction: .ascending).map(\.name) == ["Gamma", "Alpha", "Beta"])
        #expect(sorter.plans(plans, mode: .lastUpdated, direction: .descending).map(\.name) == ["Beta", "Alpha", "Gamma"])
        #expect(sorter.plans(plans, mode: .name, direction: .ascending).map(\.name) == ["Alpha", "Beta", "Gamma"])
        #expect(sorter.plans(plans, mode: .name, direction: .descending).map(\.name) == ["Gamma", "Beta", "Alpha"])
        #expect(sorter.plans(plans, mode: .manual, direction: .descending).map(\.name) == ["Gamma", "Alpha", "Beta"])
    }

    @MainActor
    @Test("Item remaining sort supports both directions with stable ties")
    func itemSorting() {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let low = BudgetItem(name: "Low", unitAmount: 5, multiplier: 1, sortOrder: 0, budgetPlan: plan)
        let high = BudgetItem(name: "High", unitAmount: 10, multiplier: 1, sortOrder: 1, budgetPlan: plan)
        let tie = BudgetItem(name: "Tie", unitAmount: 5, multiplier: 1, sortOrder: 2, budgetPlan: plan)
        let items = [tie, high, low]
        let sorter = SortUseCase()

        let calendar = Calendar(identifier: .gregorian)
        #expect(sorter.items(items, direction: .highestRemainingFirst, asOf: TestFixtures.date, calendar: calendar).map(\.name) == ["High", "Low", "Tie"])
        #expect(sorter.items(items, direction: .lowestRemainingFirst, asOf: TestFixtures.date, calendar: calendar).map(\.name) == ["Low", "Tie", "High"])
    }

    @MainActor
    @Test("Failed Plan creation restores parent relationship and timestamp")
    func failedPlanCreateRollsBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let repo = FailingPlanRepository()

        #expect(throws: TestFailure.expected) {
            _ = try PlanUseCase(repository: repo).create(name: "Plan", startingAmount: 0, in: budget, now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(budget.budgetPlans.isEmpty)
        #expect(budget.updatedAt == TestFixtures.date)
        #expect(repo.insertedCount == 1)
        #expect(repo.deletedCount == 1)
    }

    @MainActor
    @Test("Failed Budget creation and rename restore memory state")
    func failedBudgetCreateAndRenameRollBackMemory() throws {
        let repo = FailingBudgetRepository()

        #expect(throws: TestFailure.expected) {
            _ = try BudgetUseCase(repository: repo).create(name: "Budget", now: TestFixtures.date)
        }
        #expect(repo.insertedCount == 1)
        #expect(repo.deletedCount == 1)

        let budget = Budget(name: "Original", updatedAt: TestFixtures.date)
        let renameRepo = FailingBudgetRepository(existingBudgets: [budget])
        #expect(throws: TestFailure.expected) {
            try BudgetUseCase(repository: renameRepo).rename(budget, name: "Changed", now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(budget.name == "Original")
        #expect(budget.updatedAt == TestFixtures.date)
    }

    @MainActor
    @Test("Failed Settings save preserves currency")
    func failedSettingsSaveRollsBackMemory() throws {
        let settings = AppSettings(currencyCode: "MYR", updatedAt: TestFixtures.date)
        let repo = FailingBudgetRepository()

        #expect(throws: TestFailure.expected) {
            try SettingsUseCase(repository: repo).setCurrencyCode("JPY", on: settings, at: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(settings.currencyCode == "MYR")
        #expect(settings.updatedAt == TestFixtures.date)
    }

    @MainActor
    @Test("Failed Item creation restores parent relationships and timestamps")
    func failedItemCreateRollsBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let plan = BudgetPlan(name: "Plan", updatedAt: TestFixtures.date, budget: budget)
        let repo = FailingItemRepository()

        #expect(throws: TestFailure.expected) {
            _ = try ItemUseCase(repository: repo).create(name: "Item", unitAmount: 0, multiplier: 1, in: plan, now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(plan.budgetItems.isEmpty)
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)
        #expect(repo.insertedCount == 1)
        #expect(repo.deletedCount == 1)
    }

    @MainActor
    @Test("Failed Plan and Item updates restore edited values and parent timestamps")
    func failedPlanAndItemUpdatesRollBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let plan = BudgetPlan(name: "Plan", startingAmount: 10, updatedAt: TestFixtures.date, budget: budget)
        let item = BudgetItem(name: "Item", unitAmount: 5, multiplier: 2, updatedAt: TestFixtures.date, budgetPlan: plan)

        #expect(throws: TestFailure.expected) {
            try PlanUseCase(repository: FailingPlanRepository()).update(plan, name: "Changed", startingAmount: 20, now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(plan.name == "Plan")
        #expect(plan.startingAmount == 10)
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)

        #expect(throws: TestFailure.expected) {
            try ItemUseCase(repository: FailingItemRepository()).update(item, name: "Changed", unitAmount: 8, multiplier: 3, now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(item.name == "Item")
        #expect(item.unitAmount == 5)
        #expect(item.multiplier == 2)
        #expect(item.updatedAt == TestFixtures.date)
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)
    }

    @MainActor
    @Test("Failed reorder restores all sort orders and timestamps")
    func failedReorderRollsBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let first = BudgetPlan(name: "First", sortOrder: 0, updatedAt: TestFixtures.date, budget: budget)
        let second = BudgetPlan(name: "Second", sortOrder: 1, updatedAt: TestFixtures.date, budget: budget)
        let repo = FailingPlanRepository()

        #expect(throws: TestFailure.expected) {
            try PlanUseCase(repository: repo).reorder([second, first], now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(first.sortOrder == 0)
        #expect(second.sortOrder == 1)
        #expect(first.updatedAt == TestFixtures.date)
        #expect(second.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)
    }

    @MainActor
    @Test("Failed transaction move restores source, destination, and transaction timestamps")
    func failedTransactionMoveRollsBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let plan = BudgetPlan(name: "Plan", updatedAt: TestFixtures.date, budget: budget)
        let source = BudgetItem(name: "Source", updatedAt: TestFixtures.date, budgetPlan: plan)
        let destination = BudgetItem(name: "Destination", updatedAt: TestFixtures.date, budgetPlan: plan)
        let transaction = Transaction(name: "Income", amount: 5, kind: .income, date: TestFixtures.date, updatedAt: TestFixtures.date, budgetItem: source)
        let repo = FailingTransactionRepository()
        let later = TestFixtures.date.addingTimeInterval(100)

        #expect(throws: TestFailure.expected) {
            try TransactionUseCase(repository: repo).update(transaction, kind: .expense, amount: 6, date: TestFixtures.date, notes: "changed", destinationItem: destination, clock: FixedClock(now: later, calendar: Calendar(identifier: .gregorian)))
        }
        #expect(transaction.budgetItem.id == source.id)
        #expect(transaction.kind == .income)
        #expect(transaction.amount == 5)
        #expect(transaction.notes == nil)
        #expect(transaction.updatedAt == TestFixtures.date)
        #expect(source.updatedAt == TestFixtures.date)
        #expect(destination.updatedAt == TestFixtures.date)
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)
    }

    @MainActor
    @Test("Failed Transaction creation and same-item update restore memory state")
    func failedTransactionCreateAndUpdateRollBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let plan = BudgetPlan(name: "Plan", updatedAt: TestFixtures.date, budget: budget)
        let item = BudgetItem(name: "Item", updatedAt: TestFixtures.date, budgetPlan: plan)
        let later = TestFixtures.date.addingTimeInterval(100)
        let clock = FixedClock(now: later, calendar: Calendar(identifier: .gregorian))

        #expect(throws: TestFailure.expected) {
            _ = try TransactionUseCase(repository: FailingTransactionRepository()).create(kind: .expense, amount: 5, date: TestFixtures.date, notes: "Lunch", item: item, clock: clock)
        }
        #expect(item.transactions.isEmpty)
        #expect(item.updatedAt == TestFixtures.date)
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)

        let transaction = Transaction(name: "Expense", amount: 5, kind: .expense, date: TestFixtures.date, notes: "Original", updatedAt: TestFixtures.date, budgetItem: item)
        item.transactions = [transaction]
        #expect(throws: TestFailure.expected) {
            try TransactionUseCase(repository: FailingTransactionRepository()).update(transaction, kind: .income, amount: 9, date: TestFixtures.date, notes: "Changed", destinationItem: item, clock: clock)
        }
        #expect(transaction.kind == .expense)
        #expect(transaction.amount == 5)
        #expect(transaction.notes == "Original")
        #expect(transaction.updatedAt == TestFixtures.date)
        #expect(item.updatedAt == TestFixtures.date)
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)
    }

    @MainActor
    @Test("Failed Budget Plan and Item deletions restore relationships")
    func failedHierarchyDeletesRollBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let plan = BudgetPlan(name: "Plan", updatedAt: TestFixtures.date, budget: budget)
        let item = BudgetItem(name: "Item", updatedAt: TestFixtures.date, budgetPlan: plan)
        budget.budgetPlans = [plan]
        plan.budgetItems = [item]

        #expect(throws: TestFailure.expected) {
            try BudgetUseCase(repository: FailingBudgetRepository(existingBudgets: [budget])).delete(budget)
        }

        #expect(throws: TestFailure.expected) {
            try PlanUseCase(repository: FailingPlanRepository()).delete(plan, now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(budget.budgetPlans.map(\.id).contains(plan.id))
        #expect(budget.updatedAt == TestFixtures.date)

        #expect(throws: TestFailure.expected) {
            try ItemUseCase(repository: FailingItemRepository()).delete(item, now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(plan.budgetItems.map(\.id).contains(item.id))
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)
    }

    @MainActor
    @Test("Failed Transaction deletion restores relationship and parent timestamps")
    func failedTransactionDeleteRollsBackMemory() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let plan = BudgetPlan(name: "Plan", updatedAt: TestFixtures.date, budget: budget)
        let item = BudgetItem(name: "Item", updatedAt: TestFixtures.date, budgetPlan: plan)
        let transaction = Transaction(name: "Expense", amount: 5, kind: .expense, date: TestFixtures.date, updatedAt: TestFixtures.date, budgetItem: item)
        item.transactions = [transaction]
        let repo = FailingTransactionRepository()

        #expect(throws: TestFailure.expected) {
            try TransactionUseCase(repository: repo).delete(transaction, now: TestFixtures.date.addingTimeInterval(100))
        }
        #expect(item.transactions.map(\.id) == [transaction.id])
        #expect(item.updatedAt == TestFixtures.date)
        #expect(plan.updatedAt == TestFixtures.date)
        #expect(budget.updatedAt == TestFixtures.date)
        #expect(repo.deletedCount == 1)
        #expect(repo.insertedCount == 1)
    }

    @MainActor
    @Test("SwiftData Item deletion removes child and cascades transactions without clearing required parent")
    func swiftDataItemDeleteDoesNotClearRequiredParentRelationship() throws {
        let container = try TestFixtures.container()
        let fixture = TestFixtures.hierarchy()
        container.mainContext.insert(fixture.budget)
        try ModelMutationService.saveValidated(container.mainContext)

        try ItemUseCase(repository: SwiftDataBudgetItemRepository(context: container.mainContext)).delete(
            fixture.item,
            now: TestFixtures.date.addingTimeInterval(100)
        )

        let budgets = try container.mainContext.fetch(FetchDescriptor<Budget>())
        let plans = budgets.flatMap(\.budgetPlans)
        let items = plans.flatMap(\.budgetItems)
        let transactions = items.flatMap(\.transactions)
        #expect(items.isEmpty)
        #expect(transactions.isEmpty)
        #expect(plans.map(\.id) == [fixture.plan.id])
        #expect(plans.first?.updatedAt == TestFixtures.date.addingTimeInterval(100))
        #expect(budgets.first?.updatedAt == TestFixtures.date.addingTimeInterval(100))
    }

    @MainActor
    @Test("Plan report availability is safe after Plan is detached during deletion")
    func detachedPlanReportAvailabilityDoesNotCrash() throws {
        let budget = Budget(name: "Budget", updatedAt: TestFixtures.date)
        let plan = BudgetPlan(name: "Plan", startingAmount: 100, updatedAt: TestFixtures.date, budget: budget)
        let item = BudgetItem(name: "Item", updatedAt: TestFixtures.date, budgetPlan: plan)
        budget.budgetPlans = [plan]
        plan.budgetItems = [item]
        budget.budgetPlans.removeAll { $0.id == plan.id }

        let service = DefaultReportService(
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            asOf: TestFixtures.date
        )

        #expect(!service.hasMeaningfulPlanReports(plan: plan, formatter: CurrencyFormatter(currencyCode: "MYR")))
    }

    @MainActor
    @Test("Unreadable persistent store is not automatically replaced")
    func unreadablePersistentStoreIsNotAutomaticallyReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CanI.sqlite")
        let originalData = Data("not a swiftdata store".utf8)
        try originalData.write(to: storeURL)

        #expect(throws: Error.self) {
            _ = try CanISchema.makeContainer(storeURL: storeURL)
        }
        #expect(try Data(contentsOf: storeURL) == originalData)
    }

    @MainActor
    @Test("Explicit persistent store recovery backs up sidecars before opening empty store")
    func explicitPersistentStoreRecoveryBacksUpSidecars() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CanI.sqlite")
        let walURL = directory.appendingPathComponent("CanI.sqlite-wal")
        let shmURL = directory.appendingPathComponent("CanI.sqlite-shm")
        try Data("bad store".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: walURL)
        try Data("shm".utf8).write(to: shmURL)

        let recovery = try CanISchema.recoverPersistentStore(storeURL: storeURL)
        _ = recovery.container

        #expect(FileManager.default.fileExists(atPath: recovery.backupDirectory.appendingPathComponent("CanI.sqlite").path))
        #expect(FileManager.default.fileExists(atPath: recovery.backupDirectory.appendingPathComponent("CanI.sqlite-wal").path))
        #expect(FileManager.default.fileExists(atPath: recovery.backupDirectory.appendingPathComponent("CanI.sqlite-shm").path))
        let reopened = try CanISchema.makeContainer(storeURL: storeURL)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<Budget>()).isEmpty)
    }

    @Test("Rounding disclosure reports exact total with extra precision")
    func roundingDisclosureExactTotal() throws {
        let formatter = CurrencyFormatter(currencyCode: "MYR")
        let total = Decimal(string: "0.01")!
        let disclosure = try #require(formatter.displayMismatch(components: [Decimal(string: "0.005")!, Decimal(string: "0.005")!], total: total))

        #expect(disclosure.exactTotalDescription.contains("0.010"))
        #expect(disclosure.explanation.contains("rounded"))
    }

    @Test("Rounding disclosure uses minimal extra precision")
    func roundingDisclosureMinimalPrecision() throws {
        let formatter = CurrencyFormatter(currencyCode: "MYR")
        let disclosure = try #require(formatter.displayMismatch(components: [Decimal(string: "0.0049")!, Decimal(string: "0.0049")!], total: Decimal(string: "0.0098")!))

        #expect(disclosure.exactTotalDescription.contains("0.0098"))
        #expect(!disclosure.exactTotalDescription.contains("0.00980"))
    }

    @MainActor
    @Test("Transaction and progress accessibility labels are readable")
    func accessibilityLabels() throws {
        let container = try TestFixtures.container()
        let coordinator = BudgetingCoordinator(
            context: container.mainContext,
            clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)),
            preferences: MemoryPhase2PreferenceStore()
        )
        _ = coordinator.saveCurrency("MYR")
        let budget = try coordinator.createBudget(name: "Budget")
        let plan = try coordinator.createPlan(name: "Plan", amountText: "100", in: budget)
        let item = try coordinator.createItem(name: "Item", unitAmountText: "50", multiplierText: "1", in: plan)
        let expense = try coordinator.createTransaction(kind: .expense, amountText: "12", date: TestFixtures.date, notes: "Lunch", item: item)
        let income = try coordinator.createTransaction(kind: .income, amountText: "20", date: TestFixtures.date, notes: "", item: item)

        #expect(coordinator.transactionAccessibilityLabel(for: expense).contains("Expense"))
        #expect(coordinator.transactionAccessibilityLabel(for: expense).contains("MYR"))
        #expect(coordinator.transactionAccessibilityLabel(for: expense).contains("Lunch"))
        #expect(coordinator.transactionAccessibilityLabel(for: income).contains("Income"))
        #expect(!coordinator.transactionAccessibilityLabel(for: income).contains(",,"))

        let normal = coordinator.progress(spent: 50, funds: 100)
        let overspent = coordinator.progress(spent: 150, funds: 100)
        let unfunded = coordinator.progress(spent: 10, funds: 0)
        #expect(normal.label.contains("of"))
        #expect(overspent.label.contains("Overspent by"))
        #expect(unfunded.label.contains("Not funded"))
    }

    @MainActor
    @Test("Next local day boundary uses injected calendar and time zone")
    func nextLocalDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let beforeMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 23, minute: 59)))
        let next = try #require(BudgetingCoordinator.nextLocalDayBoundary(after: beforeMidnight, calendar: calendar))

        #expect(calendar.component(.day, from: next) == 11)
        #expect(calendar.component(.hour, from: next) == 0)
        #expect(calendar.component(.minute, from: next) == 0)
    }

    @MainActor
    @Test("Plan and Item names are normalized unique within their parents")
    func planAndItemNameUniqueness() throws {
        let container = try TestFixtures.container()
        let budgetRepository = SwiftDataBudgetRepository(context: container.mainContext)
        let budget = try BudgetUseCase(repository: budgetRepository).create(name: "Budget", now: TestFixtures.date)
        let planRepository = SwiftDataBudgetPlanRepository(context: container.mainContext)
        let plan = try PlanUseCase(repository: planRepository).create(name: "  August  ", startingAmount: 0, in: budget, now: TestFixtures.date)

        #expect(throws: Phase2ValidationError.duplicateName) {
            _ = try PlanUseCase(repository: planRepository).create(name: "august", startingAmount: 0, in: budget, now: TestFixtures.date)
        }

        let itemRepository = SwiftDataBudgetItemRepository(context: container.mainContext)
        _ = try ItemUseCase(repository: itemRepository).create(name: "  Meals  ", unitAmount: 0, multiplier: 1, in: plan, now: TestFixtures.date)
        #expect(throws: Phase2ValidationError.duplicateName) {
            _ = try ItemUseCase(repository: itemRepository).create(name: "meals", unitAmount: 0, multiplier: 1, in: plan, now: TestFixtures.date)
        }
    }

    @MainActor
    @Test("Scheduled income affects Item Plan and Budget progress before on and after date")
    func scheduledIncomeProgressBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let before = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))
        let effectiveDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0)))
        let after = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 12)))
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", startingAmount: 0, budget: budget)
        let item = BudgetItem(name: "Item", unitAmount: 0, multiplier: 1, budgetPlan: plan)
        item.transactions = [
            Transaction(name: "Income", amount: 100, kind: .income, date: effectiveDay, budgetItem: item),
            Transaction(name: "Expense", amount: 50, kind: .expense, date: before, budgetItem: item)
        ]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]
        let formatter = CurrencyFormatter(currencyCode: "MYR")

        let itemBefore = Phase2Calculations.itemTotals(for: item, asOf: before, calendar: calendar)
        let planBefore = Phase2Calculations.planTotals(for: plan, asOf: before, calendar: calendar)
        let budgetBefore = Phase2Calculations.budgetTotals(for: budget, asOf: before, calendar: calendar)
        #expect(itemBefore.scheduledIncome == 100)
        #expect(planBefore.totalFundsReceived == 0)
        #expect(budgetBefore.totalFundsReceived == 0)
        #expect(Phase2Calculations.progress(spent: itemBefore.expenses, funds: itemBefore.available, formatter: formatter).isWarning)

        for date in [effectiveDay, after] {
            let itemTotals = Phase2Calculations.itemTotals(for: item, asOf: date, calendar: calendar)
            let planTotals = Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar)
            let budgetTotals = Phase2Calculations.budgetTotals(for: budget, asOf: date, calendar: calendar)
            #expect(itemTotals.effectiveIncome == 100)
            #expect(itemTotals.scheduledIncome == 0)
            #expect(planTotals.totalFundsReceived == 100)
            #expect(budgetTotals.totalFundsReceived == 100)
            #expect(!Phase2Calculations.progress(spent: itemTotals.expenses, funds: itemTotals.available, formatter: formatter).isWarning)
        }
    }

    @Test("Device currency suggestion uses supported region currency")
    func deviceCurrencySuggestion() {
        let locale = Locale(identifier: "en_MY")
        #expect(CurrencyCatalog.suggestedCurrencyCode(locale: locale) == "MYR")
    }
}

private enum TestFailure: Error, Equatable {
    case expected
}

@MainActor
private final class FailingBudgetRepository: BudgetRepository {
    var insertedCount = 0
    var deletedCount = 0
    var existingBudgets: [Budget]

    init(existingBudgets: [Budget] = []) {
        self.existingBudgets = existingBudgets
    }

    func budgets() throws -> [Budget] { existingBudgets }
    func settings(defaultCurrencyCode: String) throws -> AppSettings { AppSettings(currencyCode: defaultCurrencyCode) }
    func budgetCount() throws -> Int { existingBudgets.count }
    func insert(_ budget: Budget) { insertedCount += 1 }
    func delete(_ budget: Budget) throws { deletedCount += 1 }
    func save() throws { throw TestFailure.expected }
}

@MainActor
private final class FailingPlanRepository: BudgetPlanRepository {
    var insertedCount = 0
    var deletedCount = 0
    func insert(_ plan: BudgetPlan) { insertedCount += 1 }
    func delete(_ plan: BudgetPlan) throws { deletedCount += 1 }
    func save() throws { throw TestFailure.expected }
}

@MainActor
private final class FailingItemRepository: BudgetItemRepository {
    var insertedCount = 0
    var deletedCount = 0
    func insert(_ item: BudgetItem) { insertedCount += 1 }
    func delete(_ item: BudgetItem) throws { deletedCount += 1 }
    func save() throws { throw TestFailure.expected }
}

@MainActor
private final class FailingTransactionRepository: TransactionRepository {
    var insertedCount = 0
    var deletedCount = 0
    func insert(_ transaction: Transaction) { insertedCount += 1 }
    func delete(_ transaction: Transaction) throws { deletedCount += 1 }
    func save() throws { throw TestFailure.expected }
}

private final class MutableTestClock: AppClock {
    var now: Date
    var calendar: Calendar

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }
}

@MainActor
private final class ManualLocalDayRefreshScheduler: LocalDayRefreshScheduler {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduleCount = 0
    private(set) var cancelCount = 0

    func schedule(at boundary: Date, clock: AppClock, action: @escaping @MainActor () -> Void) -> LocalDayRefreshCancellable {
        scheduleCount += 1
        self.action = action
        return ManualLocalDayRefreshCancellation { [weak self] in
            self?.cancelCount += 1
        }
    }

    func fire() {
        action?()
    }
}

private final class ManualLocalDayRefreshCancellation: LocalDayRefreshCancellable {
    private let onCancel: @MainActor () -> Void

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    @MainActor
    func cancel() {
        onCancel()
    }
}
