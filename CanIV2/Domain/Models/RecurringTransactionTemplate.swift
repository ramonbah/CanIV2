//
//  RecurringTransactionTemplate.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class RecurringTransactionTemplate: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // Name (required, non-empty after trim)
    var name: String

    var amount: Decimal

    var kind: TransactionKind

    var frequency: RecurrenceFrequency

    // Interval (>= 1)
    var interval: Int

    // Start and optional end date
    var startDate: Date
    var endDate: Date?

    // Next scheduled occurrence
    var nextOccurrence: Date

    // Enabled/paused
    var isEnabled: Bool

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Required parent. Budget.recurringTemplates owns the inverse and cascade rule.
    var budget: Budget!

    // Optional destination. BudgetItem.destinationRecurringTemplates owns the inverse and nullify rule.
    var destinationBudgetItem: BudgetItem?

    // Complete initializer with safe defaults
    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal,
        kind: TransactionKind,
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date? = nil,
        nextOccurrence: Date,
        isEnabled: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        budget: Budget,
        destinationBudgetItem: BudgetItem? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.kind = kind
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.nextOccurrence = nextOccurrence
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.budget = budget
        self.destinationBudgetItem = destinationBudgetItem
    }

    // Application-level validation
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard amount > 0 else {
            throw DomainValidationError.nonPositiveRecurringAmount
        }
        guard interval >= 1 else {
            throw DomainValidationError.invalidRecurrenceInterval
        }
        if let end = endDate {
            guard end >= startDate else {
                throw DomainValidationError.invalidRecurrenceDateRange
            }
        }
    }
}
