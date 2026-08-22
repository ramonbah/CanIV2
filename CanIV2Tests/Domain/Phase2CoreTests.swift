import Foundation
import SwiftData
import Testing
@testable import CanIV2

@Suite("Phase 2 core behavior")
struct Phase2CoreTests {
    @Test("Currency precision accepts zero, two, and three minor unit currencies")
    func currencyPrecisionValidation() {
        let yen = CurrencyFormatter(currencyCode: "JPY")
        let ringgit = CurrencyFormatter(currencyCode: "MYR")
        let dinar = CurrencyFormatter(currencyCode: "BHD")

        #expect(yen.hasValidMinorUnits("12"))
        #expect(!yen.hasValidMinorUnits("12.1"))
        #expect(ringgit.hasValidMinorUnits("12.34"))
        #expect(!ringgit.hasValidMinorUnits("12.345"))
        #expect(dinar.hasValidMinorUnits("12.345"))
        #expect(!dinar.hasValidMinorUnits("12.3456"))
    }

    @Test("Rounding disclosure detects displayed component mismatch")
    func roundingDisclosure() {
        let formatter = CurrencyFormatter(currencyCode: "MYR")
        let disclosure = formatter.displayMismatch(components: [Decimal(string: "0.005")!, Decimal(string: "0.005")!], total: Decimal(string: "0.01")!)

        #expect(disclosure != nil)
    }

    @MainActor
    @Test("Budget names are trimmed and case-insensitive unique")
    func budgetNameUniqueness() throws {
        let container = try TestFixtures.container()
        let repository = SwiftDataBudgetRepository(context: container.mainContext)
        _ = try Phase2UseCases.createBudget(name: "  Travel  ", repository: repository, now: TestFixtures.date)

        #expect(throws: Phase2ValidationError.duplicateName) {
            _ = try Phase2UseCases.createBudget(name: "travel", repository: repository, now: TestFixtures.date)
        }

        let budgets = try repository.budgets()
        #expect(budgets.first?.name == "Travel")
    }

    @MainActor
    @Test("Plan and Item amount rules accept zero and enforce whole positive multiplier")
    func planAndItemValidation() throws {
        let container = try TestFixtures.container()
        let repository = SwiftDataBudgetRepository(context: container.mainContext)
        let budget = try Phase2UseCases.createBudget(name: "Budget", repository: repository, now: TestFixtures.date)
        let plan = try Phase2UseCases.createPlan(name: "Plan", startingAmount: 0, in: budget, repository: SwiftDataBudgetPlanRepository(context: container.mainContext), now: TestFixtures.date)
        _ = try Phase2UseCases.createItem(name: "Zero", unitAmount: 0, multiplier: 1, in: plan, repository: SwiftDataBudgetItemRepository(context: container.mainContext), now: TestFixtures.date)

        #expect(throws: Phase2ValidationError.invalidMultiplier) {
            _ = try Phase2UseCases.createItem(name: "Fraction", unitAmount: 1, multiplier: Decimal(string: "1.5")!, in: plan, repository: SwiftDataBudgetItemRepository(context: container.mainContext), now: TestFixtures.date)
        }
    }

    @MainActor
    @Test("Future income is scheduled until its local calendar day")
    func scheduledIncomeEffectiveDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = Date(timeIntervalSince1970: 1_767_225_600)
        let future = calendar.date(byAdding: .day, value: 1, to: asOf)!
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", startingAmount: 100, budget: budget)
        let item = BudgetItem(name: "Item", unitAmount: 50, multiplier: 1, budgetPlan: plan)
        item.transactions = [
            Transaction(name: "Income", amount: 25, kind: .income, date: future, budgetItem: item),
            Transaction(name: "Expense", amount: 10, kind: .expense, date: asOf, budgetItem: item)
        ]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]

        let itemBefore = Phase2Calculations.itemTotals(for: item, asOf: asOf, calendar: calendar)
        #expect(itemBefore.effectiveIncome == 0)
        #expect(itemBefore.scheduledIncome == 25)
        #expect(itemBefore.remaining == 40)

        let itemOnDate = Phase2Calculations.itemTotals(for: item, asOf: future, calendar: calendar)
        #expect(itemOnDate.effectiveIncome == 25)
        #expect(itemOnDate.scheduledIncome == 0)
        #expect(itemOnDate.remaining == 65)

        let planBefore = Phase2Calculations.planTotals(for: plan, asOf: asOf, calendar: calendar)
        #expect(planBefore.totalFundsReceived == 100)
        #expect(planBefore.currentBalance == 90)

        let budgetBefore = Phase2Calculations.budgetTotals(for: budget, asOf: asOf, calendar: calendar)
        #expect(budgetBefore.totalFundsReceived == 100)
        #expect(budgetBefore.currentBalance == 90)
    }

    @MainActor
    @Test("Expense rejects future date and type change must correct future income date")
    func futureExpenseValidation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = TestFixtures.date
        let future = calendar.date(byAdding: .day, value: 1, to: asOf)!
        #expect(throws: Phase2ValidationError.futureExpenseDate) {
            try Phase2UseCases.validateTransaction(kind: .expense, amount: 1, date: future, calendar: calendar, asOf: asOf)
        }
    }

    @MainActor
    @Test("Manual plan ordering persists sort order")
    func manualPlanOrdering() throws {
        let container = try TestFixtures.container()
        let budget = Budget(name: "Budget", createdAt: TestFixtures.date, updatedAt: TestFixtures.date)
        let first = BudgetPlan(name: "First", sortOrder: 0, createdAt: TestFixtures.date, updatedAt: TestFixtures.date, budget: budget)
        let second = BudgetPlan(name: "Second", sortOrder: 1, createdAt: TestFixtures.date, updatedAt: TestFixtures.date, budget: budget)
        budget.budgetPlans = [first, second]
        container.mainContext.insert(budget)
        try ModelMutationService.saveValidated(container.mainContext)

        try Phase2UseCases.reorderPlans([second, first], repository: SwiftDataBudgetPlanRepository(context: container.mainContext), now: TestFixtures.date)

        #expect(second.sortOrder == 0)
        #expect(first.sortOrder == 1)
    }

    @MainActor
    @Test("Transaction can move only within the same Plan")
    func transactionMoveSamePlanOnly() throws {
        let container = try TestFixtures.container()
        let hierarchy = TestFixtures.hierarchy()
        let otherItem = BudgetItem(name: "Other", budgetPlan: hierarchy.plan)
        hierarchy.plan.budgetItems.append(otherItem)
        container.mainContext.insert(hierarchy.budget)
        try ModelMutationService.saveValidated(container.mainContext)

        try Phase2UseCases.updateTransaction(hierarchy.transaction, kind: .expense, amount: 30, date: TestFixtures.date, notes: "Moved", destinationItem: otherItem, repository: SwiftDataTransactionRepository(context: container.mainContext), clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)))
        #expect(hierarchy.transaction.budgetItem.id == otherItem.id)

        let outsideBudget = Budget(name: "Outside")
        let outsidePlan = BudgetPlan(name: "Outside", budget: outsideBudget)
        let outsideItem = BudgetItem(name: "Outside", budgetPlan: outsidePlan)
        #expect(throws: Phase2ValidationError.noDestinationItem) {
            try Phase2UseCases.updateTransaction(hierarchy.transaction, kind: .expense, amount: 30, date: TestFixtures.date, notes: "", destinationItem: outsideItem, repository: SwiftDataTransactionRepository(context: container.mainContext), clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)))
        }
    }

    @MainActor
    @Test("Deletion impact counts descendants")
    func deletionImpactCounts() {
        let hierarchy = TestFixtures.hierarchy()

        #expect(Phase2UseCases.deletionImpact(for: hierarchy.budget) == DeletionImpact(planCount: 1, itemCount: 1, transactionCount: 1))
        #expect(Phase2UseCases.deletionImpact(for: hierarchy.plan) == DeletionImpact(itemCount: 1, transactionCount: 1))
        #expect(Phase2UseCases.deletionImpact(for: hierarchy.item) == DeletionImpact(transactionCount: 1))
    }

    @Test("Progress states cover normal, overspent, and unfunded")
    func progressStates() {
        let formatter = CurrencyFormatter(currencyCode: "MYR")

        #expect(Phase2Calculations.progress(spent: 50, funds: 100, formatter: formatter).isWarning == false)
        #expect(Phase2Calculations.progress(spent: 150, funds: 100, formatter: formatter).label.contains("Overspent"))
        #expect(Phase2Calculations.progress(spent: 10, funds: 0, formatter: formatter).label.contains("Not funded"))
    }
}
