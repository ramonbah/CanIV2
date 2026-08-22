//
//  ModelMutationService.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

@MainActor
enum ModelMutationService {
    static func fetchOrCreateSettings(
        in context: ModelContext,
        defaultCurrencyCode: String = "MYR",
        now: Date = .now
    ) throws -> AppSettings {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        guard settings.count <= 1 else {
            throw DomainValidationError.multipleSettingsRecords
        }
        if let existing = settings.first {
            try existing.validate()
            return existing
        }

        let created = AppSettings(
            currencyCode: defaultCurrencyCode,
            createdAt: now,
            updatedAt: now
        )
        try created.validate()
        context.insert(created)
        return created
    }

    static func setCurrencyCode(
        _ currencyCode: String,
        on settings: AppSettings,
        at date: Date = .now
    ) throws {
        let previousCode = settings.currencyCode
        settings.currencyCode = currencyCode
        do {
            try settings.validate()
            settings.touch(at: date)
        } catch {
            settings.currencyCode = previousCode
            throw error
        }
    }

    static func attach(
        _ receipt: ReceiptCapture,
        to transaction: Transaction,
        at date: Date = .now
    ) throws {
        if let existing = transaction.receipt, existing.id != receipt.id {
            throw DomainValidationError.receiptAlreadyAttached
        }
        guard receipt.transaction.id == transaction.id else {
            throw DomainValidationError.receiptBelongsToAnotherTransaction
        }

        transaction.receipt = receipt
        transaction.touch(at: date)
        receipt.touch(at: date)
    }

    static func saveValidated(_ context: ModelContext) throws {
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        guard settings.count <= 1 else {
            throw DomainValidationError.multipleSettingsRecords
        }
        try settings.forEach { try $0.validate() }

        try context.fetch(FetchDescriptor<Budget>()).forEach { try $0.validate() }
        try context.fetch(FetchDescriptor<BudgetPlan>()).forEach { try $0.validate() }
        try context.fetch(FetchDescriptor<BudgetItem>()).forEach { try $0.validate() }
        try context.fetch(FetchDescriptor<Transaction>()).forEach { try $0.validate() }
        try context.fetch(FetchDescriptor<RecurringTransactionTemplate>()).forEach { try $0.validate() }
        try context.fetch(FetchDescriptor<ReceiptLineItem>()).forEach { try $0.validate() }

        let receipts = try context.fetch(FetchDescriptor<ReceiptCapture>())
        try receipts.forEach { try $0.validate() }
        var transactionIDs = Set<UUID>()
        for receipt in receipts {
            guard transactionIDs.insert(receipt.transaction.id).inserted else {
                throw DomainValidationError.receiptAlreadyAttached
            }
            guard receipt.transaction.receipt?.id == receipt.id else {
                throw DomainValidationError.inconsistentReceiptRelationship
            }
        }

        try context.save()
    }
}
