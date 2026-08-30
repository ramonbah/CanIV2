import Foundation
import SwiftData
import Testing
@testable import CanIV2

@Suite("Phase 4 rollover recurrence and migration")
struct Phase4Tests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var formatter: CurrencyFormatter {
        CurrencyFormatter(currencyCode: "MYR", locale: Locale(identifier: "en_US"))
    }

    @MainActor
    @Test("Rollover copies selected Items in source order without Transactions and records source UUID")
    func rolloverSelectedItems() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let fixture = try rolloverFixture(context: context)

        let created = try RolloverUseCase(context: context).rollItems(
            from: fixture.sourcePlan,
            itemIDs: [fixture.firstSource.id, fixture.secondSource.id],
            into: fixture.destinationPlan,
            now: fixture.now
        )

        #expect(created.map(\.name) == ["First", "Second"])
        #expect(created.map(\.sourceItemID) == [fixture.firstSource.id, fixture.secondSource.id])
        #expect(created.allSatisfy { $0.transactions.isEmpty })
        #expect(created.map(\.sortOrder) == [1, 2])
        #expect(fixture.firstSource.transactions.count == 1)
    }

    @MainActor
    @Test("Rollover rejects duplicate source and name conflicts before inserting")
    func rolloverValidationIsAtomic() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let fixture = try rolloverFixture(context: context)

        let conflicting = BudgetItem(name: "First", unitAmount: 1, multiplier: 1, sortOrder: 1, budgetPlan: fixture.destinationPlan)
        fixture.destinationPlan.budgetItems.append(conflicting)
        context.insert(conflicting)
        try ModelMutationService.saveValidated(context)

        #expect(throws: Phase4ValidationError.rolloverNameConflict("First")) {
            _ = try RolloverUseCase(context: context).rollItems(
                from: fixture.sourcePlan,
                itemIDs: [fixture.firstSource.id],
                into: fixture.destinationPlan,
                now: fixture.now
            )
        }
        #expect(fixture.destinationPlan.budgetItems.count == 2)
    }

    @MainActor
    @Test("Recurring schedules cover daily weekly monthly yearly intervals and date boundaries")
    func recurrenceScheduleBoundaries() throws {
        let jan31 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))!
        let monthly = RecurrenceSchedule(frequency: .monthly, interval: 1, startDate: jan31, endDate: nil)
        #expect(calendar.component(.day, from: monthly.next(after: jan31, calendar: calendar)) == 28)

        let leap = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 9))!
        let yearly = RecurrenceSchedule(frequency: .yearly, interval: 1, startDate: leap, endDate: nil)
        let nextLeap = yearly.next(after: leap, calendar: calendar)
        #expect(calendar.component(.month, from: nextLeap) == 2)
        #expect(calendar.component(.day, from: nextLeap) == 28)

        let daily = RecurrenceSchedule(frequency: .daily, interval: 2, startDate: jan31, endDate: nil)
        #expect(daily.next(after: jan31, calendar: calendar) == calendar.date(byAdding: .day, value: 2, to: jan31))

        let weekly = RecurrenceSchedule(frequency: .weekly, interval: 3, startDate: jan31, endDate: nil)
        #expect(weekly.next(after: jan31, calendar: calendar) == calendar.date(byAdding: .weekOfYear, value: 3, to: jan31))
    }

    @MainActor
    @Test("Recurring generation catches up missed occurrences exactly once and advances atomically")
    func recurrenceGenerationIsIdempotent() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        let budget = Budget(name: "Budget", createdAt: now, updatedAt: now)
        let plan = BudgetPlan(name: "Plan", startingAmount: 0, createdAt: now, updatedAt: now, budget: budget)
        let item = BudgetItem(name: "Rent", unitAmount: 0, multiplier: 1, createdAt: now, updatedAt: now, budgetPlan: plan)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9))!
        let template = RecurringTransactionTemplate(name: "Rent", amount: 10, kind: .expense, frequency: .daily, interval: 3, startDate: start, nextOccurrence: start, isEnabled: true, createdAt: now, updatedAt: now, budget: budget, destinationBudgetItem: item)
        budget.budgetPlans = [plan]
        budget.recurringTemplates = [template]
        plan.budgetItems = [item]
        item.destinationRecurringTemplates = [template]
        context.insert(budget)
        try ModelMutationService.saveValidated(context)

        let coordinator = RecurrenceGenerationCoordinator(context: context)
        let first = try coordinator.processDueTemplates(in: [budget], clock: FixedClock(now: now, calendar: calendar), limit: 100)
        let second = try coordinator.processDueTemplates(in: [budget], clock: FixedClock(now: now, calendar: calendar), limit: 100)

        #expect(first == 4)
        #expect(second == 0)
        #expect(item.transactions.count == 4)
        #expect(Set(item.transactions.compactMap(\.sourceTemplateID)) == [template.id])
        #expect(calendar.startOfDay(for: template.nextOccurrence) == calendar.date(from: DateComponents(year: 2026, month: 8, day: 13)))
    }

    @MainActor
    @Test("Recurring occurrence uniqueness survives same-day destination changes and on-disk retry")
    func recurrenceOccurrenceUniquenessIsDestinationIndependent() throws {
        let storeURL = try temporaryStoreURL()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        let occurrenceDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!
        let templateID: UUID

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let budget = Budget(name: "Budget", createdAt: now, updatedAt: now)
            let plan = BudgetPlan(name: "Plan", startingAmount: 0, createdAt: now, updatedAt: now, budget: budget)
            let itemA = BudgetItem(name: "Item A", unitAmount: 0, multiplier: 1, sortOrder: 0, createdAt: now, updatedAt: now, budgetPlan: plan)
            let itemB = BudgetItem(name: "Item B", unitAmount: 0, multiplier: 1, sortOrder: 1, createdAt: now, updatedAt: now, budgetPlan: plan)
            let template = RecurringTransactionTemplate(name: "Daily", amount: 11, kind: .expense, frequency: .daily, interval: 1, startDate: occurrenceDay, nextOccurrence: occurrenceDay, isEnabled: true, createdAt: now, updatedAt: now, budget: budget, destinationBudgetItem: itemA)
            templateID = template.id
            budget.budgetPlans = [plan]
            budget.recurringTemplates = [template]
            plan.budgetItems = [itemA, itemB]
            itemA.destinationRecurringTemplates = [template]
            context.insert(budget)
            try ModelMutationService.saveValidated(context)

            let first = try RecurrenceGenerationCoordinator(context: context).processDueTemplates(in: [budget], clock: FixedClock(now: now, calendar: calendar), limit: 10)
            #expect(first == 1)
            #expect(countOccurrences(for: templateID, on: occurrenceDay, in: budget) == 1)

            try RecurringTemplateUseCase(context: context).update(template, name: "Daily", amount: 11, kind: .expense, frequency: .daily, interval: 1, startDate: occurrenceDay, endDate: nil, destination: itemB, clock: FixedClock(now: now, calendar: calendar))
            let second = try RecurrenceGenerationCoordinator(context: context).processDueTemplates(in: [budget], clock: FixedClock(now: now, calendar: calendar), limit: 10)
            #expect(second == 0)
            #expect(countOccurrences(for: templateID, on: occurrenceDay, in: budget) == 1)
            #expect(calendar.startOfDay(for: template.nextOccurrence) == calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))
            template.nextOccurrence = occurrenceDay
            try ModelMutationService.saveValidated(context)
        }

        do {
            let reopened = try CanISchema.makeContainer(storeURL: storeURL)
            let context = reopened.mainContext
            let budget = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
            let template = try #require(try context.fetch(FetchDescriptor<RecurringTransactionTemplate>()).first)
            let repeated = try RecurrenceGenerationCoordinator(context: context).processDueTemplates(in: [budget], clock: FixedClock(now: now, calendar: calendar), limit: 10)
            #expect(repeated == 0)
            #expect(countOccurrences(for: templateID, on: occurrenceDay, in: budget) == 1)
            #expect(calendar.startOfDay(for: template.nextOccurrence) == calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))
        }
    }

    @MainActor
    @Test("Pause resume missing destination and repair preserve templates")
    func recurrencePauseResumeAndRepair() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let fixture = TestFixtures.hierarchy()
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        try RecurringTemplateUseCase(context: context).setEnabled(false, for: fixture.template, clock: FixedClock(now: now, calendar: calendar))
        #expect(fixture.template.isEnabled == false)
        let pausedCount = try RecurrenceGenerationCoordinator(context: context).processDueTemplates(in: [fixture.budget], clock: FixedClock(now: now, calendar: calendar))
        #expect(pausedCount == 0)

        context.delete(fixture.item)
        try context.save()
        let templates = try context.fetch(FetchDescriptor<RecurringTransactionTemplate>())
        #expect(templates.first?.destinationBudgetItem == nil)

        let newPlan = BudgetPlan(name: "Repair Plan", budget: fixture.budget)
        let newItem = BudgetItem(name: "Repair Item", budgetPlan: newPlan)
        fixture.budget.budgetPlans.append(newPlan)
        newPlan.budgetItems = [newItem]
        context.insert(newPlan)
        context.insert(newItem)
        try ModelMutationService.saveValidated(context)
        let repaired = try #require(templates.first)
        try RecurringTemplateUseCase(context: context).repairDestination(newItem, for: repaired, clock: FixedClock(now: now, calendar: calendar))
        try RecurringTemplateUseCase(context: context).setEnabled(true, for: repaired, clock: FixedClock(now: now, calendar: calendar))
        #expect(repaired.destinationBudgetItem?.id == newItem.id)
        #expect(repaired.isEnabled)
        #expect(calendar.startOfDay(for: repaired.nextOccurrence) >= calendar.startOfDay(for: now))
    }

    @MainActor
    @Test("Recurring report separates projections from actual Transactions and statuses")
    func recurringReport() throws {
        let fixture = TestFixtures.hierarchy()
        let paused = RecurringTransactionTemplate(name: "Paused", amount: 5, kind: .income, frequency: .weekly, interval: 2, startDate: fixture.template.startDate, nextOccurrence: fixture.template.startDate, isEnabled: false, budget: fixture.budget, destinationBudgetItem: nil)
        fixture.budget.recurringTemplates.append(paused)

        let snapshot = RecurringReportService(calendar: calendar, asOf: fixture.template.startDate, formatter: formatter).snapshot(for: fixture.budget)
        #expect(snapshot.rows.count == 2)
        #expect(snapshot.rows.contains { $0.name == "Recurring" && $0.status == .active })
        #expect(snapshot.rows.contains { $0.name == "Paused" && $0.status == .needsDestination })
    }

    @MainActor
    @Test("Zero-display presentation rules preserve offsetting activity")
    func zeroDisplayPresentationRules() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", startingAmount: 100, budget: budget)
        let item = BudgetItem(name: "Item", unitAmount: 50, multiplier: 1, budgetPlan: plan)
        budget.budgetPlans = [plan]
        plan.budgetItems = [item]
        let inactiveTotals = Phase2Calculations.planTotals(for: plan, asOf: now, calendar: calendar)
        let inactivePlanVisibility = Phase4PresentationRules.planVisibility(for: plan, totals: inactiveTotals)
        #expect(inactivePlanVisibility.showsPlanned)
        #expect(!inactivePlanVisibility.showsSpent)
        #expect(!inactivePlanVisibility.showsBalance)
        #expect(!inactivePlanVisibility.showsProgress)
        #expect(!Phase4PresentationRules.itemVisibility(for: item, totals: Phase2Calculations.itemTotals(for: item, asOf: now, calendar: calendar)).showsRemaining)

        item.transactions = [Transaction(name: "Income", amount: 10, kind: .income, date: now, createdAt: now, budgetItem: item)]
        let incomeOnlyVisibility = Phase4PresentationRules.planVisibility(for: plan, totals: Phase2Calculations.planTotals(for: plan, asOf: now, calendar: calendar))
        #expect(incomeOnlyVisibility.showsPlanned)
        #expect(!incomeOnlyVisibility.showsSpent)
        #expect(incomeOnlyVisibility.showsBalance)
        #expect(!incomeOnlyVisibility.showsProgress)

        item.transactions = [
            Transaction(name: "Income", amount: 10, kind: .income, date: now, createdAt: now, budgetItem: item),
            Transaction(name: "Expense", amount: 10, kind: .expense, date: now, createdAt: now, budgetItem: item)
        ]
        let activeTotals = Phase2Calculations.planTotals(for: plan, asOf: now, calendar: calendar)
        let offsettingVisibility = Phase4PresentationRules.planVisibility(for: plan, totals: activeTotals)
        #expect(offsettingVisibility.showsPlanned)
        #expect(offsettingVisibility.showsSpent)
        #expect(offsettingVisibility.showsBalance)
        #expect(offsettingVisibility.showsProgress)
        #expect(Phase4PresentationRules.itemVisibility(for: item, totals: Phase2Calculations.itemTotals(for: item, asOf: now, calendar: calendar)).showsRemaining)

        item.transactions = [Transaction(name: "Income", amount: 10, kind: .income, date: now, createdAt: now, budgetItem: item)]
        item.unitAmount = 0
        let zeroPlannedIncomeOnly = Phase4PresentationRules.planVisibility(for: plan, totals: Phase2Calculations.planTotals(for: plan, asOf: now, calendar: calendar))
        #expect(!zeroPlannedIncomeOnly.showsPlanned)
        #expect(!zeroPlannedIncomeOnly.showsSpent)
        #expect(!zeroPlannedIncomeOnly.showsProgress)

        item.transactions.append(Transaction(name: "Expense", amount: 1, kind: .expense, date: now, createdAt: now, budgetItem: item))
        let spendingVisibility = Phase4PresentationRules.planVisibility(for: plan, totals: Phase2Calculations.planTotals(for: plan, asOf: now, calendar: calendar))
        #expect(spendingVisibility.showsSpent)
        #expect(spendingVisibility.showsProgress)

        let bucket = MoneyBucket(id: "offset", label: "Today", start: now, income: 10, expense: 10, balance: 0)
        #expect(Phase4PresentationRules.reportHasMeaningfulData(buckets: [bucket], rows: [], transactions: []))
        #expect(!Phase4PresentationRules.reportHasMeaningfulData(buckets: [MoneyBucket(id: "zero", label: "Today", start: now, income: 0, expense: 0, balance: 0)], rows: [], transactions: []))
    }

    @MainActor
    @Test("On-disk Phase 3 store reopens through Phase 4 schema preserving all models and relationships")
    func onDiskPhase3StoreReopens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Phase3.store")
        let countsBefore: [Int]
        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let fixture = TestFixtures.hierarchy()
            context.insert(AppSettings(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, currencyCode: "MYR", createdAt: TestFixtures.date, updatedAt: TestFixtures.date))
            context.insert(fixture.budget)
            try ModelMutationService.saveValidated(context)
            countsBefore = try modelCounts(in: context)
        }

        let sidecars = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent).sorted()
        #expect(!sidecars.isEmpty)

        do {
            let migrated = try CanISchema.makeContainer(storeURL: storeURL)
            let context = migrated.mainContext
            #expect(try modelCounts(in: context) == countsBefore)
            let budgets = try context.fetch(FetchDescriptor<Budget>())
            let budget = try #require(budgets.first)
            #expect(budget.budgetPlans.count == 1)
            #expect(budget.recurringTemplates.count == 1)
            let item = try #require(budget.budgetPlans.first?.budgetItems.first)
            #expect(item.transactions.count == 1)
            #expect(item.destinationRecurringTemplates.count == 1)
            #expect(item.transactions.first?.receipt?.lineItems.count == 1)
        }

        do {
            let reopened = try CanISchema.makeContainer(storeURL: storeURL)
            #expect(try modelCounts(in: reopened.mainContext) == countsBefore)
        }
    }

    @MainActor
    @Test("Fresh Phase 4 installation and empty Phase 3 store open without recovery")
    func freshAndEmptyStoresOpen() throws {
        let freshURL = try temporaryStoreURL()
        let fresh = try CanISchema.makeContainer(storeURL: freshURL)
        #expect(try modelCounts(in: fresh.mainContext) == [0, 0, 0, 0, 0, 0, 0, 0])

        let emptyURL = try temporaryStoreURL()
        do {
            _ = try CanISchema.makeContainer(storeURL: emptyURL)
        }
        let reopened = try CanISchema.makeContainer(storeURL: emptyURL)
        #expect(try modelCounts(in: reopened.mainContext) == [0, 0, 0, 0, 0, 0, 0, 0])
    }

    @MainActor
    @Test("Migrated store preserves cascade and nullify rules after representative deletes and reopen")
    func migratedStoreDeleteRulesSurviveReopen() throws {
        let storeURL = try temporaryStoreURL()
        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            container.mainContext.insert(TestFixtures.hierarchy().budget)
            try ModelMutationService.saveValidated(container.mainContext)
        }

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let budget = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
            let plan = try #require(budget.budgetPlans.first)
            let item = try #require(plan.budgetItems.first)
            context.delete(item)
            try context.save()
        }

        do {
            let reopened = try CanISchema.makeContainer(storeURL: storeURL)
            let context = reopened.mainContext
            #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<BudgetPlan>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<BudgetItem>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
            let template = try #require(try context.fetch(FetchDescriptor<RecurringTransactionTemplate>()).first)
            #expect(template.destinationBudgetItem == nil)
        }
    }

    @MainActor
    @Test("Phase 4 incompatible store open leaves original files untouched")
    func incompatibleStoreOpenPreservesFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CanI.sqlite")
        let walURL = directory.appendingPathComponent("CanI.sqlite-wal")
        let shmURL = directory.appendingPathComponent("CanI.sqlite-shm")
        let storeData = Data("not a compatible swiftdata store".utf8)
        let walData = Data("phase4 wal".utf8)
        let shmData = Data("phase4 shm".utf8)
        try storeData.write(to: storeURL)
        try walData.write(to: walURL)
        try shmData.write(to: shmURL)

        #expect(throws: Error.self) {
            _ = try CanISchema.makeContainer(storeURL: storeURL)
        }
        #expect(try Data(contentsOf: storeURL) == storeData)
        #expect(try Data(contentsOf: walURL) == walData)
        #expect(try Data(contentsOf: shmURL) == shmData)
    }

    @MainActor
    private func rolloverFixture(context: ModelContext) throws -> (budget: Budget, sourcePlan: BudgetPlan, destinationPlan: BudgetPlan, firstSource: BudgetItem, secondSource: BudgetItem, now: Date) {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let budget = Budget(name: "Budget", createdAt: now, updatedAt: now)
        let sourcePlan = BudgetPlan(name: "July", startingAmount: 0, descriptiveDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)), sortOrder: 0, createdAt: now.addingTimeInterval(-10), updatedAt: now, budget: budget)
        let destinationPlan = BudgetPlan(name: "August", startingAmount: 0, descriptiveDate: calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)), sortOrder: 1, createdAt: now, updatedAt: now, budget: budget)
        let firstSource = BudgetItem(name: "First", unitAmount: 10, multiplier: 2, sortOrder: 0, budgetPlan: sourcePlan)
        let secondSource = BudgetItem(name: "Second", unitAmount: 20, multiplier: 1, sortOrder: 1, budgetPlan: sourcePlan)
        let transaction = Transaction(name: "Expense", amount: 5, kind: .expense, date: now, budgetItem: firstSource)
        let existing = BudgetItem(name: "Existing", unitAmount: 1, multiplier: 1, sortOrder: 0, budgetPlan: destinationPlan)
        budget.budgetPlans = [sourcePlan, destinationPlan]
        sourcePlan.budgetItems = [firstSource, secondSource]
        destinationPlan.budgetItems = [existing]
        firstSource.transactions = [transaction]
        context.insert(budget)
        try ModelMutationService.saveValidated(context)
        return (budget, sourcePlan, destinationPlan, firstSource, secondSource, now)
    }

    @MainActor
    private func modelCounts(in context: ModelContext) throws -> [Int] {
        try [
            context.fetchCount(FetchDescriptor<AppSettings>()),
            context.fetchCount(FetchDescriptor<Budget>()),
            context.fetchCount(FetchDescriptor<BudgetPlan>()),
            context.fetchCount(FetchDescriptor<BudgetItem>()),
            context.fetchCount(FetchDescriptor<Transaction>()),
            context.fetchCount(FetchDescriptor<RecurringTransactionTemplate>()),
            context.fetchCount(FetchDescriptor<ReceiptCapture>()),
            context.fetchCount(FetchDescriptor<ReceiptLineItem>())
        ]
    }

    private func countOccurrences(for templateID: UUID, on occurrenceDate: Date, in budget: Budget) -> Int {
        budget.budgetPlans
            .flatMap(\.budgetItems)
            .flatMap(\.transactions)
            .filter { $0.sourceTemplateID == templateID && calendar.isDate($0.date, inSameDayAs: occurrenceDate) }
            .count
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("CanI.sqlite")
    }
}
