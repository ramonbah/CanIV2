//
//  Enums.swift
//  CanIV2
//
//  Centralized domain enums for consistency across models.
//

import Foundation

/// Kind of a transaction (income or expense)
public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case income
    case expense
}

/// Recurrence frequency for a recurring transaction
public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}
