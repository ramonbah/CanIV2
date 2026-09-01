//
//  RepositoriesAndUseCases.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@MainActor
protocol BudgetRepository {
    func budgets() throws -> [Budget]
    func settings(defaultCurrencyCode: String) throws -> AppSettings
    func budgetCount() throws -> Int
    func insert(_ budget: Budget)
    func delete(_ budget: Budget) throws
    func save() throws
}

@MainActor
protocol BudgetPlanRepository {
    func insert(_ plan: BudgetPlan)
    func delete(_ plan: BudgetPlan) throws
    func save() throws
}

@MainActor
protocol BudgetItemRepository {
    func insert(_ item: BudgetItem)
    func delete(_ item: BudgetItem) throws
    func save() throws
}

@MainActor
protocol TransactionRepository {
    func insert(_ transaction: Transaction)
    func delete(_ transaction: Transaction) throws
    func save() throws
}

@MainActor
struct SwiftDataBudgetRepository: BudgetRepository {
    let context: ModelContext

    func budgets() throws -> [Budget] {
        try context.fetch(FetchDescriptor<Budget>()).sorted { $0.createdAt > $1.createdAt }
    }

    func existingSettings() throws -> AppSettings? {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        guard settings.count <= 1 else {
            throw DomainValidationError.multipleSettingsRecords
        }
        if let existing = settings.first {
            try existing.validate()
            return existing
        }
        return nil
    }

    func settings(defaultCurrencyCode: String) throws -> AppSettings {
        try ModelMutationService.fetchOrCreateSettings(in: context, defaultCurrencyCode: defaultCurrencyCode)
    }

    func budgetCount() throws -> Int {
        try context.fetch(FetchDescriptor<Budget>()).count
    }

    func insert(_ budget: Budget) {
        context.insert(budget)
    }

    func delete(_ budget: Budget) throws {
        for plan in Array(budget.budgetPlans) {
            try context.deletePlanTree(plan)
        }
        context.delete(budget)
        try ModelMutationService.saveValidated(context)
    }

    func save() throws {
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
struct SwiftDataBudgetPlanRepository: BudgetPlanRepository {
    let context: ModelContext

    func insert(_ plan: BudgetPlan) {
        context.insert(plan)
    }

    func delete(_ plan: BudgetPlan) throws {
        try context.deletePlanTree(plan)
        context.delete(plan)
        try ModelMutationService.saveValidated(context)
    }

    func save() throws {
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
struct SwiftDataBudgetItemRepository: BudgetItemRepository {
    let context: ModelContext

    func insert(_ item: BudgetItem) {
        context.insert(item)
    }

    func delete(_ item: BudgetItem) throws {
        try context.deleteItemTree(item)
        context.delete(item)
        try ModelMutationService.saveValidated(context)
    }

    func save() throws {
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
struct SwiftDataTransactionRepository: TransactionRepository {
    let context: ModelContext

    func insert(_ transaction: Transaction) {
        context.insert(transaction)
    }

    func delete(_ transaction: Transaction) throws {
        try context.deleteTransactionTree(transaction)
        context.delete(transaction)
        try ModelMutationService.saveValidated(context)
    }

    func save() throws {
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

@MainActor
private extension ModelContext {
    func deletePlanTree(_ plan: BudgetPlan) throws {
        for item in Array(plan.budgetItems) {
            try deleteItemTree(item)
        }
    }

    func deleteItemTree(_ item: BudgetItem) throws {
        for transaction in Array(item.transactions) {
            try deleteTransactionTree(transaction)
            delete(transaction)
            try ModelMutationService.saveValidated(self)
        }
    }

    func deleteTransactionTree(_ transaction: Transaction) throws {
        guard let receipt = transaction.receipt else { return }
        for lineItem in Array(receipt.lineItems) {
            delete(lineItem)
        }
        delete(receipt)
    }
}
