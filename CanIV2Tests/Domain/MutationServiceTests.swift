import SwiftData
import Testing
@testable import CanIV2
import Foundation

@Suite("Mutation foundations")
struct MutationServiceTests {
    @MainActor
    @Test("Receipt attachment rejects a receipt owned by another transaction")
    func receiptOwnership() throws {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Item", budgetPlan: plan)
        let first = Transaction(name: "First", amount: 1, kind: .expense, date: TestFixtures.date, budgetItem: item)
        let second = Transaction(name: "Second", amount: 1, kind: .expense, date: TestFixtures.date, budgetItem: item)
        let receipt = ReceiptCapture(transaction: first)

        #expect(throws: DomainValidationError.receiptBelongsToAnotherTransaction) {
            try ModelMutationService.attach(receipt, to: second, at: TestFixtures.date)
        }
    }

    @MainActor
    @Test("Receipt attachment maintains both sides and timestamps")
    func attachReceipt() throws {
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Item", budgetPlan: plan)
        let transaction = Transaction(name: "Expense", amount: 1, kind: .expense, date: TestFixtures.date, budgetItem: item)
        let receipt = ReceiptCapture(transaction: transaction)
        let updateDate = TestFixtures.date.addingTimeInterval(100)

        try ModelMutationService.attach(receipt, to: transaction, at: updateDate)

        #expect(transaction.receipt?.id == receipt.id)
        #expect(receipt.transaction.id == transaction.id)
        #expect(transaction.updatedAt == updateDate)
        #expect(receipt.updatedAt == updateDate)
    }
}
