//
//  CanISchema.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

enum CanISchema {
    static var schema: Schema {
        Schema([
            AppSettings.self,
            Budget.self,
            BudgetPlan.self,
            BudgetItem.self,
            Transaction.self,
            RecurringTransactionTemplate.self,
            ReceiptCapture.self,
            ReceiptLineItem.self
        ])
    }

    static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let modelSchema = schema
        let configuration: ModelConfiguration
        if let storeURL, !inMemory {
            configuration = ModelConfiguration(schema: modelSchema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: modelSchema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: modelSchema, configurations: [configuration])
    }

    static func recoverPersistentStore(storeURL: URL? = nil) throws -> (container: ModelContainer, backupDirectory: URL) {
        let targetURL = storeURL ?? defaultStoreURL()
        let backupDirectory = try backupPersistentStoreFiles(for: targetURL)
        do {
            return (try makeContainer(storeURL: targetURL), backupDirectory)
        } catch {
            throw StoreRecoveryError.resetFailed(backupDirectory: backupDirectory, underlying: error)
        }
    }

    static func defaultStoreURL() -> URL {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url
    }

    private static func backupPersistentStoreFiles(for storeURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let fileName = storeURL.lastPathComponent
        let candidates = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent == fileName || $0.lastPathComponent.hasPrefix("\(fileName)-") }

        let backupRoot = directory.appendingPathComponent("CanI Store Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupDirectory = backupRoot.appendingPathComponent("\(stamp)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        for url in candidates {
            try fileManager.moveItem(at: url, to: backupDirectory.appendingPathComponent(url.lastPathComponent))
        }
        return backupDirectory
    }
}

enum StoreRecoveryError: LocalizedError {
    case resetFailed(backupDirectory: URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .resetFailed(let backupDirectory, let underlying):
            "A backup was created at \(backupDirectory.path), but a new database could not be opened: \(underlying.localizedDescription)"
        }
    }
}
