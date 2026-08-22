import SwiftData
import Testing
@testable import CanIV2

@Suite("Preview sample data")
struct SampleDataTests {
    @MainActor
    @Test("Sample data forms a valid representative hierarchy")
    func sampleHierarchy() throws {
        let container = try SampleData.makePreviewContainer()
        let context = ModelContext(container)

        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BudgetPlan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BudgetItem>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<ReceiptCapture>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<RecurringTransactionTemplate>()) == 1)
    }
}
