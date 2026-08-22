//
//  BudgetItem.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class BudgetItem: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // Item name (required, non-empty after trim)
    var name: String

    // Unit amount (>= 0)
    var unitAmount: Decimal

    // Multiplier (> 0, supports decimal)
    var multiplier: Decimal

    // Sort order (>= 0)
    var sortOrder: Int

    // Rollover provenance (optional)
    var sourceItemID: UUID?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Required parent. The inverse and cascade rule are declared on BudgetPlan.budgetItems.
    var budgetPlan: BudgetPlan!

    @Relationship(deleteRule: .cascade, inverse: \Transaction.budgetItem)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTransactionTemplate.destinationBudgetItem)
    var destinationRecurringTemplates: [RecurringTransactionTemplate] = []

    // Complete initializer with safe defaults
    init(
        id: UUID = UUID(),
        name: String,
        unitAmount: Decimal = 0,
        multiplier: Decimal = 1,
        sortOrder: Int = 0,
        sourceItemID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        budgetPlan: BudgetPlan,
        transactions: [Transaction] = [],
        destinationRecurringTemplates: [RecurringTransactionTemplate] = []
    ) {
        self.id = id
        self.name = name
        self.unitAmount = unitAmount
        self.multiplier = multiplier
        self.sortOrder = sortOrder
        self.sourceItemID = sourceItemID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.budgetPlan = budgetPlan
        self.transactions = transactions
        self.destinationRecurringTemplates = destinationRecurringTemplates
    }

    // Application-level validation
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard unitAmount >= 0 else {
            throw DomainValidationError.negativeUnitAmount
        }
        guard multiplier > 0 else {
            throw DomainValidationError.nonPositiveMultiplier
        }
        guard sortOrder >= 0 else {
            throw DomainValidationError.negativeSortOrder
        }
    }
}
