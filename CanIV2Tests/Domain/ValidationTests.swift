import Testing
@testable import CanIV2
import Foundation

@Suite("Domain validation")
struct ValidationTests {
    @MainActor
    @Test("Names are non-empty after trimming")
    func emptyName() {
        let budget = Budget(name: "  \n")
        #expect(throws: DomainValidationError.emptyName) {
            try budget.validate()
        }
    }

    @MainActor
    @Test("Budget Item amounts, multiplier, and sort order are constrained")
    func itemRules() {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)

        let negativeAmount = BudgetItem(name: "Item", unitAmount: -1, budgetPlan: plan)
        #expect(throws: DomainValidationError.negativeUnitAmount) {
            try negativeAmount.validate()
        }

        let zeroMultiplier = BudgetItem(name: "Item", multiplier: 0, budgetPlan: plan)
        #expect(throws: DomainValidationError.nonPositiveMultiplier) {
            try zeroMultiplier.validate()
        }

        let negativeOrder = BudgetItem(name: "Item", sortOrder: -1, budgetPlan: plan)
        #expect(throws: DomainValidationError.negativeSortOrder) {
            try negativeOrder.validate()
        }
    }

    @MainActor
    @Test("Transaction and recurrence amounts must be positive")
    func positiveAmounts() {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Item", budgetPlan: plan)
        let transaction = Transaction(name: "Expense", amount: 0, kind: .expense, date: TestFixtures.date, budgetItem: item)
        #expect(throws: DomainValidationError.nonPositiveTransactionAmount) {
            try transaction.validate()
        }

        let recurring = RecurringTransactionTemplate(
            name: "Recurring",
            amount: 0,
            kind: .expense,
            frequency: .monthly,
            interval: 1,
            startDate: TestFixtures.date,
            nextOccurrence: TestFixtures.date,
            isEnabled: true,
            budget: budget,
            destinationBudgetItem: item
        )
        #expect(throws: DomainValidationError.nonPositiveRecurringAmount) {
            try recurring.validate()
        }
    }

    @MainActor
    @Test("Recurrence end date cannot precede start date")
    func recurrenceDateRange() {
        let budget = Budget(name: "Budget")
        let recurring = RecurringTransactionTemplate(
            name: "Recurring",
            amount: 10,
            kind: .expense,
            frequency: .monthly,
            interval: 1,
            startDate: TestFixtures.date,
            endDate: TestFixtures.date.addingTimeInterval(-1),
            nextOccurrence: TestFixtures.date,
            isEnabled: true,
            budget: budget
        )
        #expect(throws: DomainValidationError.invalidRecurrenceDateRange) {
            try recurring.validate()
        }
    }
}
