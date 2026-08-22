//
//  ReceiptLineItem.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class ReceiptLineItem: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // Raw OCR text for this line
    var rawText: String

    // Optional user-edited name
    var name: String?

    // Optional parsed/edited amount
    var amount: Decimal?

    // Is this line selected for transaction
    var isSelected: Bool

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Required parent. The inverse and cascade rule are declared on ReceiptCapture.lineItems.
    var receiptCapture: ReceiptCapture!

    // Complete initializer with safe defaults
    init(
        id: UUID = UUID(),
        rawText: String,
        name: String? = nil,
        amount: Decimal? = nil,
        isSelected: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        receiptCapture: ReceiptCapture
    ) {
        self.id = id
        self.rawText = rawText
        self.name = name
        self.amount = amount
        self.isSelected = isSelected
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.receiptCapture = receiptCapture
    }

    // Application-level validation
    func validate() throws {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyReceiptLineText
        }
    }
}
