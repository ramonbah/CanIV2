//
//  BudgetPlan.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class BudgetPlan: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // Plan name (required, non-empty after trim)
    var name: String

    // Starting amount, default 0
    var startingAmount: Decimal

    // Optional single descriptive date for sorting/display
    var descriptiveDate: Date?

    // Optional notes
    var notes: String?

    // Sort order, default 0, must be >= 0
    var sortOrder: Int

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Required parent. The inverse and cascade rule are declared on Budget.budgetPlans.
    var budget: Budget!

    @Relationship(deleteRule: .cascade, inverse: \BudgetItem.budgetPlan)
    var budgetItems: [BudgetItem] = []

    // Complete initializer with safe defaults
    init(
        id: UUID = UUID(),
        name: String,
        startingAmount: Decimal = 0,
        descriptiveDate: Date? = nil,
        notes: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        budget: Budget,
        budgetItems: [BudgetItem] = []
    ) {
        self.id = id
        self.name = name
        self.startingAmount = startingAmount
        self.descriptiveDate = descriptiveDate
        self.notes = notes
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.budget = budget
        self.budgetItems = budgetItems
    }

    // Application-level validation
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard sortOrder >= 0 else {
            throw DomainValidationError.negativeSortOrder
        }
    }
}
