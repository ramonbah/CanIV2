//
//  Budget.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class Budget: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // Budget name (required, non-empty after trim)
    var name: String

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Relationship: All plans for this budget, cascade on delete
    @Relationship(deleteRule: .cascade, inverse: \BudgetPlan.budget)
    var budgetPlans: [BudgetPlan] = []

    // Relationship: All recurring templates for this budget, cascade on delete
    @Relationship(deleteRule: .cascade, inverse: \RecurringTransactionTemplate.budget)
    var recurringTemplates: [RecurringTransactionTemplate] = []

    // Complete initializer with safe defaults
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        budgetPlans: [BudgetPlan] = [],
        recurringTemplates: [RecurringTransactionTemplate] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.budgetPlans = budgetPlans
        self.recurringTemplates = recurringTemplates
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
    }
}
