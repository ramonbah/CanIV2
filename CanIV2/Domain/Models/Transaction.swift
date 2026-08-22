//
//  Transaction.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class Transaction: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // Transaction name (required, non-empty after trim)
    var name: String

    // Amount, must be > 0
    var amount: Decimal

    // Expense or income
    var kind: TransactionKind

    // Transaction date
    var date: Date

    // Optional notes
    var notes: String?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Provenance if from recurring template
    var sourceTemplateID: UUID?

    // Required parent. The inverse and cascade rule are declared on BudgetItem.transactions.
    var budgetItem: BudgetItem!

    // Relationship: Optional receipt (cascade on delete)
    @Relationship(deleteRule: .cascade, inverse: \ReceiptCapture.transaction)
    var receipt: ReceiptCapture?

    // Complete initializer with safe defaults
    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal,
        kind: TransactionKind,
        date: Date,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceTemplateID: UUID? = nil,
        budgetItem: BudgetItem,
        receipt: ReceiptCapture? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.kind = kind
        self.date = date
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceTemplateID = sourceTemplateID
        self.budgetItem = budgetItem
        self.receipt = receipt
    }

    // Application-level validation
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyName
        }
        guard amount > 0 else {
            throw DomainValidationError.nonPositiveTransactionAmount
        }
    }
}
