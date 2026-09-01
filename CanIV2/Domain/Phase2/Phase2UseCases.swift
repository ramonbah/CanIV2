//
//  Phase2UseCases.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@MainActor
struct SettingsUseCase {
    let repository: BudgetRepository

    func setCurrencyCode(_ currencyCode: String, on settings: AppSettings, at date: Date) throws {
        let original = (settings.currencyCode, settings.updatedAt)
        do {
            try ModelMutationService.setCurrencyCode(currencyCode, on: settings, at: date)
            try repository.save()
        } catch {
            settings.currencyCode = original.0
            settings.updatedAt = original.1
            throw error
        }
    }
}

@MainActor
struct BudgetUseCase {
    let repository: BudgetRepository

    func create(name: String, now: Date) throws -> Budget {
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: try repository.budgets().map(\.name))
        let budget = Budget(name: trimmed, createdAt: now, updatedAt: now)
        repository.insert(budget)
        do {
            try repository.save()
            return budget
        } catch {
            try repository.delete(budget)
            throw error
        }
    }

    func rename(_ budget: Budget, name: String, now: Date) throws {
        let original = (budget.name, budget.updatedAt)
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: try repository.budgets().filter { $0.id != budget.id }.map(\.name))
        budget.name = trimmed
        budget.updatedAt = now
        do {
            try repository.save()
        } catch {
            budget.name = original.0
            budget.updatedAt = original.1
            throw error
        }
    }

    func delete(_ budget: Budget) throws {
        try repository.delete(budget)
        do {
            try repository.save()
        } catch {
            repository.insert(budget)
            throw error
        }
    }
}

@MainActor
struct PlanUseCase {
    let repository: BudgetPlanRepository

    func create(name: String, startingAmount: Decimal, in budget: Budget, now: Date) throws -> BudgetPlan {
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: budget.budgetPlans.map(\.name))
        guard startingAmount >= 0 else { throw Phase2ValidationError.negativeAmount }
        let nextOrder = ((budget.budgetPlans.map(\.sortOrder).max() ?? -1) + 1)
        let originalBudgetUpdatedAt = budget.updatedAt
        let plan = BudgetPlan(name: trimmed, startingAmount: startingAmount, sortOrder: nextOrder, createdAt: now, updatedAt: now, budget: budget)
        budget.budgetPlans.append(plan)
        budget.updatedAt = now
        repository.insert(plan)
        do {
            try repository.save()
            return plan
        } catch {
            budget.budgetPlans.removeAll { $0.id == plan.id }
            budget.updatedAt = originalBudgetUpdatedAt
            try repository.delete(plan)
            throw error
        }
    }

    func update(_ plan: BudgetPlan, name: String, startingAmount: Decimal, now: Date) throws {
        let original = (plan.name, plan.startingAmount, plan.updatedAt, plan.budget.updatedAt)
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: plan.budget.budgetPlans.filter { $0.id != plan.id }.map(\.name))
        guard startingAmount >= 0 else { throw Phase2ValidationError.negativeAmount }
        plan.name = trimmed
        plan.startingAmount = startingAmount
        plan.updatedAt = now
        plan.budget.updatedAt = now
        do {
            try repository.save()
        } catch {
            plan.name = original.0
            plan.startingAmount = original.1
            plan.updatedAt = original.2
            plan.budget.updatedAt = original.3
            throw error
        }
    }

    func reorder(_ plans: [BudgetPlan], now: Date) throws {
        let original = plans.map { ($0, $0.sortOrder, $0.updatedAt) }
        let budget = plans.first?.budget
        let originalBudgetUpdatedAt = budget?.updatedAt
        for (index, plan) in plans.enumerated() {
            plan.sortOrder = index
            plan.updatedAt = now
        }
        budget?.updatedAt = now
        do {
            try repository.save()
        } catch {
            for item in original {
                item.0.sortOrder = item.1
                item.0.updatedAt = item.2
            }
            if let originalBudgetUpdatedAt { budget?.updatedAt = originalBudgetUpdatedAt }
            throw error
        }
    }

    func delete(_ plan: BudgetPlan, now: Date) throws {
        guard let budget = plan.budget else { throw Phase2ValidationError.missingParentRelationship }
        let originalBudgetUpdatedAt = budget.updatedAt
        budget.budgetPlans.removeAll { $0.id == plan.id }
        budget.updatedAt = now
        do {
            try repository.delete(plan)
            try repository.save()
        } catch {
            if !budget.budgetPlans.contains(where: { $0.id == plan.id }) {
                budget.budgetPlans.append(plan)
            }
            budget.updatedAt = originalBudgetUpdatedAt
            repository.insert(plan)
            throw error
        }
    }
}

@MainActor
struct ItemUseCase {
    let repository: BudgetItemRepository

    func create(name: String, unitAmount: Decimal, multiplier: Decimal, in plan: BudgetPlan, now: Date) throws -> BudgetItem {
        guard let budget = plan.budget else { throw Phase2ValidationError.missingParentRelationship }
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: plan.budgetItems.map(\.name))
        try ValidationUseCase.validateItemAmounts(unitAmount: unitAmount, multiplier: multiplier)
        let nextOrder = ((plan.budgetItems.map(\.sortOrder).max() ?? -1) + 1)
        let originalPlanUpdatedAt = plan.updatedAt
        let originalBudgetUpdatedAt = budget.updatedAt
        let item = BudgetItem(name: trimmed, unitAmount: unitAmount, multiplier: multiplier, sortOrder: nextOrder, createdAt: now, updatedAt: now, budgetPlan: plan)
        plan.budgetItems.append(item)
        plan.updatedAt = now
        budget.updatedAt = now
        repository.insert(item)
        do {
            try repository.save()
            return item
        } catch {
            plan.budgetItems.removeAll { $0.id == item.id }
            plan.updatedAt = originalPlanUpdatedAt
            budget.updatedAt = originalBudgetUpdatedAt
            try repository.delete(item)
            throw error
        }
    }

    func update(_ item: BudgetItem, name: String, unitAmount: Decimal, multiplier: Decimal, now: Date) throws {
        guard let plan = item.budgetPlan, let budget = plan.budget else { throw Phase2ValidationError.missingParentRelationship }
        let original = (item.name, item.unitAmount, item.multiplier, item.updatedAt, plan.updatedAt, budget.updatedAt)
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: plan.budgetItems.filter { $0.id != item.id }.map(\.name))
        try ValidationUseCase.validateItemAmounts(unitAmount: unitAmount, multiplier: multiplier)
        item.name = trimmed
        item.unitAmount = unitAmount
        item.multiplier = multiplier
        item.updatedAt = now
        plan.updatedAt = now
        budget.updatedAt = now
        do {
            try repository.save()
        } catch {
            item.name = original.0
            item.unitAmount = original.1
            item.multiplier = original.2
            item.updatedAt = original.3
            plan.updatedAt = original.4
            budget.updatedAt = original.5
            throw error
        }
    }

    func delete(_ item: BudgetItem, now: Date) throws {
        guard let plan = item.budgetPlan, let budget = plan.budget else { throw Phase2ValidationError.missingParentRelationship }
        let originalPlanUpdatedAt = plan.updatedAt
        let originalBudgetUpdatedAt = budget.updatedAt
        plan.updatedAt = now
        budget.updatedAt = now
        do {
            try repository.delete(item)
            try repository.save()
        } catch {
            plan.updatedAt = originalPlanUpdatedAt
            budget.updatedAt = originalBudgetUpdatedAt
            repository.insert(item)
            throw error
        }
    }
}

@MainActor
struct TransactionUseCase {
    let repository: TransactionRepository

    func create(kind: TransactionKind, amount: Decimal, date: Date, notes: String, item: BudgetItem, receiptDraft: ReceiptAttachmentDraft? = nil, clock: AppClock) throws -> Transaction {
        guard let plan = item.budgetPlan, let budget = plan.budget else { throw Phase2ValidationError.missingParentRelationship }
        try ValidationUseCase.validateTransaction(kind: kind, amount: amount, date: date, calendar: clock.calendar, asOf: clock.now)
        let trimmedNotes = NameNormalizer.trimmed(notes)
        let originalItemUpdatedAt = item.updatedAt
        let originalPlanUpdatedAt = plan.updatedAt
        let originalBudgetUpdatedAt = budget.updatedAt
        let originalTransactions = item.transactions
        let transaction = Transaction(
            name: generatedName(for: kind),
            amount: amount,
            kind: kind,
            date: date,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            createdAt: clock.now,
            updatedAt: clock.now,
            budgetItem: item
        )
        let receipt = receiptDraft.map {
            ReceiptCapture(
                imageData: $0.imageData,
                merchant: $0.merchant,
                date: $0.date,
                total: $0.total,
                createdAt: clock.now,
                updatedAt: clock.now,
                transaction: transaction
            )
        }
        let receiptLines = receiptDraft?.lines.map { draft in
            ReceiptLineItem(
                rawText: draft.rawText,
                name: draft.name,
                amount: draft.amount,
                isSelected: draft.isSelected,
                createdAt: clock.now,
                updatedAt: clock.now,
                receiptCapture: receipt!
            )
        } ?? []
        receipt?.lineItems = receiptLines
        transaction.receipt = receipt
        item.transactions.append(transaction)
        item.updatedAt = clock.now
        plan.updatedAt = clock.now
        budget.updatedAt = clock.now
        repository.insert(transaction)
        if let receipt {
            (repository as? SwiftDataTransactionRepository)?.context.insert(receipt)
            receiptLines.forEach { (repository as? SwiftDataTransactionRepository)?.context.insert($0) }
        }
        do {
            try repository.save()
            return transaction
        } catch {
            item.transactions = originalTransactions
            item.updatedAt = originalItemUpdatedAt
            plan.updatedAt = originalPlanUpdatedAt
            budget.updatedAt = originalBudgetUpdatedAt
            receiptLines.forEach { (repository as? SwiftDataTransactionRepository)?.context.delete($0) }
            if let receipt {
                (repository as? SwiftDataTransactionRepository)?.context.delete(receipt)
            }
            try repository.delete(transaction)
            throw error
        }
    }

    func update(_ transaction: Transaction, kind: TransactionKind, amount: Decimal, date: Date, notes: String, destinationItem: BudgetItem, clock: AppClock) throws {
        guard
            let sourceItem = transaction.budgetItem,
            let sourcePlan = sourceItem.budgetPlan,
            let sourceBudget = sourcePlan.budget,
            let destinationPlan = destinationItem.budgetPlan,
            let destinationBudget = destinationPlan.budget
        else { throw Phase2ValidationError.missingParentRelationship }
        guard destinationPlan.id == sourcePlan.id else { throw Phase2ValidationError.noDestinationItem }
        try ValidationUseCase.validateTransaction(kind: kind, amount: amount, date: date, calendar: clock.calendar, asOf: clock.now)
        let original = (
            kind: transaction.kind,
            amount: transaction.amount,
            date: transaction.date,
            notes: transaction.notes,
            name: transaction.name,
            item: transaction.budgetItem,
            updatedAt: transaction.updatedAt,
            sourceUpdatedAt: sourceItem.updatedAt,
            destinationUpdatedAt: destinationItem.updatedAt,
            planUpdatedAt: sourcePlan.updatedAt,
            budgetUpdatedAt: sourceBudget.updatedAt
        )
        transaction.kind = kind
        transaction.amount = amount
        transaction.date = date
        let trimmedNotes = NameNormalizer.trimmed(notes)
        transaction.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        transaction.name = generatedName(for: kind)
        transaction.budgetItem = destinationItem
        transaction.updatedAt = clock.now
        sourceItem.updatedAt = clock.now
        destinationItem.updatedAt = clock.now
        destinationPlan.updatedAt = clock.now
        destinationBudget.updatedAt = clock.now
        do {
            try repository.save()
        } catch {
            transaction.kind = original.kind
            transaction.amount = original.amount
            transaction.date = original.date
            transaction.notes = original.notes
            transaction.name = original.name
            transaction.budgetItem = original.item
            transaction.updatedAt = original.updatedAt
            sourceItem.updatedAt = original.sourceUpdatedAt
            destinationItem.updatedAt = original.destinationUpdatedAt
            sourcePlan.updatedAt = original.planUpdatedAt
            sourceBudget.updatedAt = original.budgetUpdatedAt
            throw error
        }
    }

    func delete(_ transaction: Transaction, now: Date) throws {
        guard let item = transaction.budgetItem, let plan = item.budgetPlan, let budget = plan.budget else { throw Phase2ValidationError.missingParentRelationship }
        let originalItemUpdatedAt = item.updatedAt
        let originalPlanUpdatedAt = plan.updatedAt
        let originalBudgetUpdatedAt = budget.updatedAt
        item.updatedAt = now
        plan.updatedAt = now
        budget.updatedAt = now
        do {
            try repository.delete(transaction)
            try repository.save()
        } catch {
            item.updatedAt = originalItemUpdatedAt
            plan.updatedAt = originalPlanUpdatedAt
            budget.updatedAt = originalBudgetUpdatedAt
            repository.insert(transaction)
            throw error
        }
    }

    func generatedName(for kind: TransactionKind) -> String {
        switch kind {
        case .income: "Income"
        case .expense: "Expense"
        }
    }
}

enum ValidationUseCase {
    static func validateName(_ trimmedName: String, siblings: [String]) throws {
        guard !trimmedName.isEmpty else { throw Phase2ValidationError.emptyName }
        guard !NameNormalizer.isDuplicate(trimmedName, among: siblings) else { throw Phase2ValidationError.duplicateName }
    }

    static func validateItemAmounts(unitAmount: Decimal, multiplier: Decimal) throws {
        guard unitAmount >= 0 else { throw Phase2ValidationError.negativeAmount }
        guard multiplier > 0, multiplier == Decimal(Int(truncating: multiplier as NSDecimalNumber)) else {
            throw Phase2ValidationError.invalidMultiplier
        }
    }

    static func validateTransaction(kind: TransactionKind, amount: Decimal, date: Date, calendar: Calendar, asOf: Date) throws {
        guard amount > 0 else { throw Phase2ValidationError.nonPositiveAmount }
        if kind == .expense, calendar.startOfDay(for: date) > calendar.startOfDay(for: asOf) {
            throw Phase2ValidationError.futureExpenseDate
        }
    }
}

struct DeletionImpactUseCase {
    func impact(for budget: Budget) -> DeletionImpact {
        let plans = budget.budgetPlans
        let items = plans.flatMap(\.budgetItems)
        return DeletionImpact(planCount: plans.count, itemCount: items.count, transactionCount: items.flatMap(\.transactions).count)
    }

    func impact(for plan: BudgetPlan) -> DeletionImpact {
        let items = plan.budgetItems
        return DeletionImpact(itemCount: items.count, transactionCount: items.flatMap(\.transactions).count)
    }

    func impact(for item: BudgetItem) -> DeletionImpact {
        DeletionImpact(transactionCount: item.transactions.count)
    }
}

struct SortUseCase {
    func plans(_ plans: [BudgetPlan], mode: PlanSortMode, direction: SortDirection) -> [BudgetPlan] {
        switch mode {
        case .manual:
            plans.sorted(by: manualPlanOrder)
        case .dateAdded:
            plans.sorted { compare($0.createdAt, $1.createdAt, direction: direction) ?? manualPlanOrder($0, $1) }
        case .lastUpdated:
            plans.sorted { compare($0.updatedAt, $1.updatedAt, direction: direction) ?? manualPlanOrder($0, $1) }
        case .name:
            plans.sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                if comparison == .orderedSame {
                    return manualPlanOrder($0, $1)
                }
                return direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
        }
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T, direction: SortDirection) -> Bool? {
        if lhs == rhs { return nil }
        return direction == .ascending ? lhs < rhs : lhs > rhs
    }

    private func manualPlanOrder(_ lhs: BudgetPlan, _ rhs: BudgetPlan) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func items(_ items: [BudgetItem], direction: ItemSortDirection, asOf date: Date, calendar: Calendar) -> [BudgetItem] {
        items.sorted { lhs, rhs in
            let lhsRemaining = Phase2Calculations.itemTotals(for: lhs, asOf: date, calendar: calendar).remaining
            let rhsRemaining = Phase2Calculations.itemTotals(for: rhs, asOf: date, calendar: calendar).remaining
            if lhsRemaining == rhsRemaining { return lhs.sortOrder < rhs.sortOrder }
            return direction == .highestRemainingFirst ? lhsRemaining > rhsRemaining : lhsRemaining < rhsRemaining
        }
    }

    func transactions(_ transactions: [Transaction]) -> [Transaction] {
        transactions.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

@MainActor
enum Phase2UseCases {
    static func deletionImpact(for budget: Budget) -> DeletionImpact { DeletionImpactUseCase().impact(for: budget) }
    static func deletionImpact(for plan: BudgetPlan) -> DeletionImpact { DeletionImpactUseCase().impact(for: plan) }
    static func deletionImpact(for item: BudgetItem) -> DeletionImpact { DeletionImpactUseCase().impact(for: item) }
    static func createBudget(name: String, repository: BudgetRepository, now: Date = Date()) throws -> Budget { try BudgetUseCase(repository: repository).create(name: name, now: now) }
    static func renameBudget(_ budget: Budget, name: String, repository: BudgetRepository, now: Date = Date()) throws { try BudgetUseCase(repository: repository).rename(budget, name: name, now: now) }
    static func deleteBudget(_ budget: Budget, repository: BudgetRepository) throws { try BudgetUseCase(repository: repository).delete(budget) }
    static func createPlan(name: String, startingAmount: Decimal, in budget: Budget, repository: BudgetPlanRepository, now: Date = Date()) throws -> BudgetPlan { try PlanUseCase(repository: repository).create(name: name, startingAmount: startingAmount, in: budget, now: now) }
    static func updatePlan(_ plan: BudgetPlan, name: String, startingAmount: Decimal, repository: BudgetPlanRepository, now: Date = Date()) throws { try PlanUseCase(repository: repository).update(plan, name: name, startingAmount: startingAmount, now: now) }
    static func reorderPlans(_ plans: [BudgetPlan], repository: BudgetPlanRepository, now: Date = Date()) throws { try PlanUseCase(repository: repository).reorder(plans, now: now) }
    static func deletePlan(_ plan: BudgetPlan, repository: BudgetPlanRepository, now: Date = Date()) throws { try PlanUseCase(repository: repository).delete(plan, now: now) }
    static func createItem(name: String, unitAmount: Decimal, multiplier: Decimal, in plan: BudgetPlan, repository: BudgetItemRepository, now: Date = Date()) throws -> BudgetItem { try ItemUseCase(repository: repository).create(name: name, unitAmount: unitAmount, multiplier: multiplier, in: plan, now: now) }
    static func updateItem(_ item: BudgetItem, name: String, unitAmount: Decimal, multiplier: Decimal, repository: BudgetItemRepository, now: Date = Date()) throws { try ItemUseCase(repository: repository).update(item, name: name, unitAmount: unitAmount, multiplier: multiplier, now: now) }
    static func deleteItem(_ item: BudgetItem, repository: BudgetItemRepository, now: Date = Date()) throws { try ItemUseCase(repository: repository).delete(item, now: now) }
    static func createTransaction(kind: TransactionKind, amount: Decimal, date: Date, notes: String, item: BudgetItem, repository: TransactionRepository, clock: AppClock) throws -> Transaction { try TransactionUseCase(repository: repository).create(kind: kind, amount: amount, date: date, notes: notes, item: item, clock: clock) }
    static func updateTransaction(_ transaction: Transaction, kind: TransactionKind, amount: Decimal, date: Date, notes: String, destinationItem: BudgetItem, repository: TransactionRepository, clock: AppClock) throws { try TransactionUseCase(repository: repository).update(transaction, kind: kind, amount: amount, date: date, notes: notes, destinationItem: destinationItem, clock: clock) }
    static func deleteTransaction(_ transaction: Transaction, repository: TransactionRepository, now: Date = Date()) throws { try TransactionUseCase(repository: repository).delete(transaction, now: now) }
    static func generatedTransactionName(for kind: TransactionKind) -> String { TransactionUseCase(repository: NoopTransactionRepository()).generatedName(for: kind) }
    static func validateName(_ trimmedName: String, siblings: [String]) throws { try ValidationUseCase.validateName(trimmedName, siblings: siblings) }
    static func validateItemAmounts(unitAmount: Decimal, multiplier: Decimal) throws { try ValidationUseCase.validateItemAmounts(unitAmount: unitAmount, multiplier: multiplier) }
    static func validateTransaction(kind: TransactionKind, amount: Decimal, date: Date, calendar: Calendar, asOf: Date) throws { try ValidationUseCase.validateTransaction(kind: kind, amount: amount, date: date, calendar: calendar, asOf: asOf) }
}

@MainActor
private struct NoopTransactionRepository: TransactionRepository {
    func insert(_ transaction: Transaction) { }
    func delete(_ transaction: Transaction) throws { }
    func save() throws { }
}
