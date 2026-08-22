import Foundation

enum DomainValidationError: Error, Equatable {
    case emptyName
    case negativeUnitAmount
    case nonPositiveMultiplier
    case negativeSortOrder
    case nonPositiveTransactionAmount
    case nonPositiveRecurringAmount
    case invalidRecurrenceInterval
    case invalidRecurrenceDateRange
    case emptyReceiptLineText
    case invalidCurrencyCode
    case unsupportedCurrencyCode(String)
    case multipleSettingsRecords
    case receiptAlreadyAttached
    case receiptBelongsToAnotherTransaction
    case inconsistentReceiptRelationship
}

protocol TimestampedModel: AnyObject {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}

extension TimestampedModel {
    func touch(at date: Date = .now) {
        updatedAt = date
    }
}

enum CurrencyCode {
    static let supported: Set<String> = Set(
        Locale.commonISOCurrencyCodes.map { $0.uppercased() }
    )
}
