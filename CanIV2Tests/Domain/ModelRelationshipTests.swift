import SwiftData
import Testing
@testable import CanIV2

@Suite("SwiftData relationship deletion rules")
struct ModelRelationshipTests {
    @MainActor
    @Test("Deleting a Budget cascades through owned records")
    func budgetCascade() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let fixture = TestFixtures.hierarchy()
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        context.delete(fixture.budget)
        try context.save()

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<Budget>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<BudgetPlan>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<BudgetItem>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<RecurringTransactionTemplate>()) == 0)
    }

    @MainActor
    @Test("Deleting a Plan cascades through items, transactions, and receipts")
    func planCascade() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let fixture = TestFixtures.hierarchy()
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        context.delete(fixture.plan)
        try context.save()

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<Budget>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<BudgetPlan>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<BudgetItem>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 0)
    }

    @MainActor
    @Test("Deleting an Item cascades transactions and nullifies its recurring destination")
    func itemCascadeAndTemplateNullify() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let fixture = TestFixtures.hierarchy()
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        context.delete(fixture.item)
        try context.save()

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<BudgetItem>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)
        let templates = try fresh.fetch(FetchDescriptor<RecurringTransactionTemplate>())
        #expect(templates.count == 1)
        #expect(templates.first?.destinationBudgetItem == nil)
    }

    @MainActor
    @Test("Deleting a Transaction cascades its receipt and lines")
    func transactionCascade() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let fixture = TestFixtures.hierarchy()
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        context.delete(fixture.transaction)
        try context.save()

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<BudgetItem>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 0)
    }

    @MainActor
    @Test("Deleting a Receipt cascades its lines but preserves the Transaction")
    func receiptCascade() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let fixture = TestFixtures.hierarchy()
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        context.delete(fixture.receipt)
        try context.save()

        let fresh = ModelContext(container)
        let transactions = try fresh.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1)
        #expect(transactions.first?.receipt == nil)
        #expect(try fresh.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 0)
    }

    @MainActor
    @Test("Deleting a recurring template preserves its destination item")
    func templateDoesNotDeleteDestination() throws {
        let container = try TestFixtures.container()
        let context = ModelContext(container)
        let fixture = TestFixtures.hierarchy()
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        context.delete(fixture.template)
        try context.save()

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<RecurringTransactionTemplate>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<BudgetItem>()) == 1)
    }
}
