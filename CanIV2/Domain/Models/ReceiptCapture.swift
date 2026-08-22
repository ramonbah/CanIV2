//
//  ReceiptCapture.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class ReceiptCapture: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // Optional image data (camera or photo library)
    @Attribute(.externalStorage) var imageData: Data?

    // Parsed or user-edited merchant name
    var merchant: String?

    // Parsed or user-edited date
    var date: Date?

    // Parsed or user-edited total
    var total: Decimal?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Required parent. Transaction.receipt owns the inverse and cascade rule.
    var transaction: Transaction!

    @Relationship(deleteRule: .cascade, inverse: \ReceiptLineItem.receiptCapture)
    var lineItems: [ReceiptLineItem] = []

    // Complete initializer with safe defaults
    init(
        id: UUID = UUID(),
        imageData: Data? = nil,
        merchant: String? = nil,
        date: Date? = nil,
        total: Decimal? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        transaction: Transaction,
        lineItems: [ReceiptLineItem] = []
    ) {
        self.id = id
        self.imageData = imageData
        self.merchant = merchant
        self.date = date
        self.total = total
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.transaction = transaction
        self.lineItems = lineItems
    }

    func validate() throws {
        // Receipt fields are OCR suggestions and may remain empty until review.
    }
}
