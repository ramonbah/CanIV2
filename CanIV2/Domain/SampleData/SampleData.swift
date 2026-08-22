//
//  SampleData.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@MainActor
enum SampleData {
    static let fixedDate = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC

    static func makePreviewContainer() throws -> ModelContainer {
        let container = try CanISchema.makeContainer(inMemory: true)
        try insert(into: container.mainContext)
        return container
    }

    static func insert(into context: ModelContext) throws {
        let settings = AppSettings(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currencyCode: "MYR",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let budget = Budget(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            name: "Monthly Living",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let plan = BudgetPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            name: "January 2026",
            startingAmount: 3_000,
            descriptiveDate: fixedDate,
            sortOrder: 0,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            budget: budget
        )
        let groceries = BudgetItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            name: "Weekend groceries",
            unitAmount: 120,
            multiplier: 4,
            sortOrder: 0,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            budgetPlan: plan
        )
        let transport = BudgetItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            name: "Work transport",
            unitAmount: 18,
            multiplier: 22,
            sortOrder: 1,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            budgetPlan: plan
        )

        let groceryExpense = Transaction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            name: "Jaya Grocer",
            amount: 96.50,
            kind: .expense,
            date: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            budgetItem: groceries
        )
        let topUp = Transaction(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
            name: "Plan top-up",
            amount: 250,
            kind: .income,
            date: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            budgetItem: groceries
        )
        let receipt = ReceiptCapture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000050")!,
            merchant: "Jaya Grocer",
            date: fixedDate,
            total: 96.50,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            transaction: groceryExpense
        )
        let vegetables = ReceiptLineItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000060")!,
            rawText: "VEGETABLES 36.50",
            name: "Vegetables",
            amount: 36.50,
            isSelected: true,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            receiptCapture: receipt
        )
        let pantry = ReceiptLineItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!,
            rawText: "PANTRY 60.00",
            name: "Pantry items",
            amount: 60,
            isSelected: true,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            receiptCapture: receipt
        )
        let recurring = RecurringTransactionTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000070")!,
            name: "Weekly groceries",
            amount: 120,
            kind: .expense,
            frequency: .weekly,
            interval: 1,
            startDate: fixedDate,
            nextOccurrence: fixedDate,
            isEnabled: true,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            budget: budget,
            destinationBudgetItem: groceries
        )

        budget.budgetPlans = [plan]
        budget.recurringTemplates = [recurring]
        plan.budgetItems = [groceries, transport]
        groceries.transactions = [groceryExpense, topUp]
        groceryExpense.receipt = receipt
        receipt.lineItems = [vegetables, pantry]
        groceries.destinationRecurringTemplates = [recurring]

        context.insert(settings)
        context.insert(budget)
        try ModelMutationService.saveValidated(context)
    }
}
