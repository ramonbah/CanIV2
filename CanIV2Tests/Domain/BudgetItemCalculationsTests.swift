import Testing
@testable import CanIV2
import Foundation

@Suite("Budget Item calculations")
struct BudgetItemCalculationsTests {
    @MainActor
    @Test("Planned, income, expense, and remaining totals use Decimal")
    func totals() {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Food", unitAmount: 50, multiplier: 2.5, budgetPlan: plan)
        item.transactions = [
            Transaction(name: "Groceries", amount: 40, kind: .expense, date: TestFixtures.date, budgetItem: item),
            Transaction(name: "Refund", amount: 10, kind: .income, date: TestFixtures.date, budgetItem: item)
        ]

        #expect(BudgetItemCalculations.plannedAmount(for: item) == 125)
        #expect(BudgetItemCalculations.expenseTotal(for: item) == 40)
        #expect(BudgetItemCalculations.incomeTotal(for: item) == 10)
        #expect(BudgetItemCalculations.netRemaining(for: item) == 95)
    }
}
