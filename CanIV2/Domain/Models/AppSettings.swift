//
//  AppSettings.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@Model
final class AppSettings: TimestampedModel {
    // Stable unique identifier
    @Attribute(.unique)
    var id: UUID

    // ISO 4217 currency code (e.g., "MYR")
    var currencyCode: String

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // Full initializer with safe defaults
    init(
        id: UUID = UUID(),
        currencyCode: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func validate() throws {
        let trimmed = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 3, trimmed.uppercased() == trimmed else {
            throw DomainValidationError.invalidCurrencyCode
        }
        guard CurrencyCode.supported.contains(trimmed) else {
            throw DomainValidationError.unsupportedCurrencyCode(trimmed)
        }
    }
}
