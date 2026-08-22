import Foundation
import SwiftData
import Testing
@testable import CanIV2

@Suite("Decimal persistence")
struct DecimalPersistenceTests {
    @MainActor
    @Test("All monetary fields survive a save and fresh-context fetch exactly")
    func decimalRoundTrip() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        let value = try #require(Decimal(string: "999999999.99", locale: locale))
        let multiplier = try #require(Decimal(string: "2.5", locale: locale))
        let container = try TestFixtures.container()
        let context = ModelContext(container)

        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", startingAmount: value, budget: budget)
        let item = BudgetItem(name: "Item", unitAmount: value, multiplier: multiplier, budgetPlan: plan)
        let transaction = Transaction(name: "Transaction", amount: value, kind: .expense, date: TestFixtures.date, budgetItem: item)
        let receipt = ReceiptCapture(total: value, transaction: transaction)
        let line = ReceiptLineItem(rawText: "ITEM", amount: value, receiptCapture: receipt)
        let template = RecurringTransactionTemplate(
            name: "Recurring",
            amount: value,
            kind: .expense,
            frequency: .monthly,
            interval: 1,
            startDate: TestFixtures.date,
            nextOccurrence: TestFixtures.date,
            isEnabled: true,
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
        context.insert(budget)
        try ModelMutationService.saveValidated(context)

        let fresh = ModelContext(container)
        let plans = try fresh.fetch(FetchDescriptor<BudgetPlan>())
        let items = try fresh.fetch(FetchDescriptor<BudgetItem>())
        let transactions = try fresh.fetch(FetchDescriptor<Transaction>())
        let templates = try fresh.fetch(FetchDescriptor<RecurringTransactionTemplate>())
        let receipts = try fresh.fetch(FetchDescriptor<ReceiptCapture>())
        let lines = try fresh.fetch(FetchDescriptor<ReceiptLineItem>())
        let fetchedPlan = try #require(plans.first)
        let fetchedItem = try #require(items.first)
        let fetchedTransaction = try #require(transactions.first)
        let fetchedTemplate = try #require(templates.first)
        let fetchedReceipt = try #require(receipts.first)
        let fetchedLine = try #require(lines.first)

        #expect(fetchedPlan.startingAmount == value)
        #expect(fetchedItem.unitAmount == value)
        #expect(fetchedItem.multiplier == multiplier)
        #expect(fetchedTransaction.amount == value)
        #expect(fetchedTemplate.amount == value)
        #expect(fetchedReceipt.total == value)
        #expect(fetchedLine.amount == value)
    }
}
