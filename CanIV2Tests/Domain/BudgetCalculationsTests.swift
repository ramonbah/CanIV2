import Testing
@testable import CanIV2
import Foundation

@Suite("Budget calculations")
struct BudgetCalculationsTests {
    @MainActor
    @Test("Budget totals aggregate equivalent plan totals")
    func totals() {
        let budget = Budget(name: "Budget")
        let first = BudgetPlan(name: "First", startingAmount: 500, budget: budget)
        let second = BudgetPlan(name: "Second", startingAmount: 300, budget: budget)
        let firstItem = BudgetItem(name: "First item", unitAmount: 200, multiplier: 1, budgetPlan: first)
        let secondItem = BudgetItem(name: "Second item", unitAmount: 100, multiplier: 2, budgetPlan: second)
        firstItem.transactions = [
            Transaction(name: "Expense", amount: 50, kind: .expense, date: TestFixtures.date, budgetItem: firstItem)
        ]
        secondItem.transactions = [
            Transaction(name: "Income", amount: 25, kind: .income, date: TestFixtures.date, budgetItem: secondItem),
            Transaction(name: "Expense", amount: 75, kind: .expense, date: TestFixtures.date, budgetItem: secondItem)
        ]
        first.budgetItems = [firstItem]
        second.budgetItems = [secondItem]
        budget.budgetPlans = [first, second]

        #expect(BudgetCalculations.plannedTotal(for: budget) == 400)
        #expect(BudgetCalculations.incomeTotal(for: budget) == 25)
        #expect(BudgetCalculations.expenseTotal(for: budget) == 125)
        #expect(BudgetCalculations.totalFundsReceived(for: budget) == 825)
        #expect(BudgetCalculations.unallocatedAmount(for: budget) == 425)
        #expect(BudgetCalculations.currentCashBalance(for: budget) == 700)
    }
}
