import Foundation
import SwiftData
@testable import CanIV2

@MainActor
enum TestFixtures {
    static let date = Date(timeIntervalSince1970: 1_767_225_600)

    static func container() throws -> ModelContainer {
        try CanISchema.makeContainer(inMemory: true)
    }

    static func hierarchy() -> (
        budget: Budget,
        plan: BudgetPlan,
        item: BudgetItem,
        transaction: Transaction,
        receipt: ReceiptCapture,
        line: ReceiptLineItem,
        template: RecurringTransactionTemplate
    ) {
        let budget = Budget(name: "Budget", createdAt: date, updatedAt: date)
        let plan = BudgetPlan(
            name: "Plan",
            startingAmount: 1_000,
            createdAt: date,
            updatedAt: date,
            budget: budget
        )
        let item = BudgetItem(
            name: "Item",
            unitAmount: 100,
            multiplier: 2,
            createdAt: date,
            updatedAt: date,
            budgetPlan: plan
        )
        let transaction = Transaction(
            name: "Expense",
            amount: 25,
            kind: .expense,
            date: date,
            createdAt: date,
            updatedAt: date,
            budgetItem: item
        )
        let receipt = ReceiptCapture(
            merchant: "Merchant",
            date: date,
            total: 25,
            createdAt: date,
            updatedAt: date,
            transaction: transaction
        )
        let line = ReceiptLineItem(
            rawText: "ITEM 25.00",
            name: "Item",
            amount: 25,
            isSelected: true,
            createdAt: date,
            updatedAt: date,
            receiptCapture: receipt
        )
        let template = RecurringTransactionTemplate(
            name: "Recurring",
            amount: 10,
            kind: .expense,
            frequency: .monthly,
            interval: 1,
            startDate: date,
            nextOccurrence: date,
            isEnabled: true,
            createdAt: date,
            updatedAt: date,
            budget: budget,
            destinationBudgetItem: item
        )

        budget.budgetPlans = [plan]
        budget.recurringTemplates = [template]
        plan.budgetItems = [item]
        item.transactions = [transaction]
        item.destinationRecurringTemplates = [template]
        transaction.receipt = receipt
        receipt.lineItems = [line]

        return (budget, plan, item, transaction, receipt, line, template)
    }
}
