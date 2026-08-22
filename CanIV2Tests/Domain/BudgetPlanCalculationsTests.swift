import Testing
@testable import CanIV2
import Foundation

@Suite("Budget Plan calculations")
struct BudgetPlanCalculationsTests {
    @MainActor
    @Test("Allocation and cash balance remain distinct")
    func totals() {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", startingAmount: 500, budget: budget)
        let food = BudgetItem(name: "Food", unitAmount: 100, multiplier: 2, budgetPlan: plan)
        let travel = BudgetItem(name: "Travel", unitAmount: 150, multiplier: 1, budgetPlan: plan)
        food.transactions = [
            Transaction(name: "Food expense", amount: 80, kind: .expense, date: TestFixtures.date, budgetItem: food),
            Transaction(name: "Top-up", amount: 50, kind: .income, date: TestFixtures.date, budgetItem: food)
        ]
        travel.transactions = [
            Transaction(name: "Travel expense", amount: 25, kind: .expense, date: TestFixtures.date, budgetItem: travel)
        ]
        plan.budgetItems = [food, travel]

        #expect(BudgetPlanCalculations.plannedTotal(for: plan) == 350)
        #expect(BudgetPlanCalculations.incomeTotal(for: plan) == 50)
        #expect(BudgetPlanCalculations.expenseTotal(for: plan) == 105)
        #expect(BudgetPlanCalculations.totalFundsReceived(for: plan) == 550)
        #expect(BudgetPlanCalculations.unallocatedAmount(for: plan) == 200)
        #expect(BudgetPlanCalculations.currentCashBalance(for: plan) == 445)
    }

    @MainActor
    @Test("Negative totals expose over-allocation and overspending")
    func negativeTotals() {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", startingAmount: 100, budget: budget)
        let item = BudgetItem(name: "Item", unitAmount: 150, multiplier: 1, budgetPlan: plan)
        item.transactions = [
            Transaction(name: "Expense", amount: 125, kind: .expense, date: TestFixtures.date, budgetItem: item)
        ]
        plan.budgetItems = [item]

        #expect(BudgetPlanCalculations.unallocatedAmount(for: plan) == -50)
        #expect(BudgetPlanCalculations.currentCashBalance(for: plan) == -25)
    }
}
