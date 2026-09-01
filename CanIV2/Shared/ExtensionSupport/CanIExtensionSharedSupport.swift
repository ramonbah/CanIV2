//
//  CanIExtensionSharedSupport.swift
//  CanIV2
//
//  Created by Codex on 8/31/26.
//

import Foundation
import UniformTypeIdentifiers

let canIAppGroupIdentifier = "group.profile.com.ios.canIV2.CanIV2"

enum SharedReceiptInboxError: LocalizedError, Equatable {
    case appGroupUnavailable
    case unsupportedType
    case oversized
    case unreadable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: "CanI shared storage is unavailable."
        case .unsupportedType: "This receipt file type is not supported."
        case .oversized: "This receipt file is too large to import."
        case .unreadable: "This pending receipt could not be read."
        }
    }
}

struct SharedReceiptManifestRecord: Codable, Equatable, Identifiable, Sendable {
    var version: Int
    var id: UUID
    var filename: String
    var originalExtension: String
    var contentType: String
    var byteCount: Int
    var createdAt: Date
}

struct SharedReceiptInboxLocator: Sendable {
    var appGroupIdentifier: String = canIAppGroupIdentifier

    func inboxURL() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedReceiptInboxError.appGroupUnavailable
        }
        return container.appendingPathComponent("PendingReceipts", isDirectory: true)
    }
}

actor SharedReceiptInboxService {
    private let inboxURL: URL
    private let maximumBytes: Int
    private let supportedContentTypes: Set<String>
    private let fileManager: FileManager

    init(
        inboxURL: URL,
        maximumBytes: Int = 15_000_000,
        supportedContentTypes: Set<String> = Set(SharedReceiptContentType.supported.map(\.identifier)),
        fileManager: FileManager = .default
    ) {
        self.inboxURL = inboxURL
        self.maximumBytes = maximumBytes
        self.supportedContentTypes = supportedContentTypes
        self.fileManager = fileManager
    }

    func savePendingReceipt(
        data: Data,
        originalExtension: String,
        contentType: String,
        now: Date = Date(),
        id: UUID = UUID()
    ) throws -> SharedReceiptManifestRecord {
        guard supportedContentTypes.contains(contentType) else {
            throw SharedReceiptInboxError.unsupportedType
        }
        guard data.count > 0 else {
            throw SharedReceiptInboxError.unreadable
        }
        guard data.count <= maximumBytes else {
            throw SharedReceiptInboxError.oversized
        }
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let normalizedExtension = originalExtension.isEmpty ? SharedReceiptContentType.fileExtension(for: contentType) : originalExtension
        let receiptFilename = "\(id.uuidString).\(normalizedExtension)"
        let metadataFilename = "\(id.uuidString).json"
        let receiptURL = inboxURL.appendingPathComponent(receiptFilename)
        let metadataURL = inboxURL.appendingPathComponent(metadataFilename)
        let temporaryReceiptURL = inboxURL.appendingPathComponent("\(receiptFilename).tmp")
        let temporaryMetadataURL = inboxURL.appendingPathComponent("\(metadataFilename).tmp")
        let record = SharedReceiptManifestRecord(
            version: 1,
            id: id,
            filename: receiptFilename,
            originalExtension: normalizedExtension,
            contentType: contentType,
            byteCount: data.count,
            createdAt: now
        )

        try data.write(to: temporaryReceiptURL, options: [.atomic])
        try JSONEncoder.receiptInbox.encode(record).write(to: temporaryMetadataURL, options: [.atomic])
        try? fileManager.removeItem(at: receiptURL)
        try? fileManager.removeItem(at: metadataURL)
        try fileManager.moveItem(at: temporaryReceiptURL, to: receiptURL)
        try fileManager.moveItem(at: temporaryMetadataURL, to: metadataURL)
        try? (receiptURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        try? (metadataURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        return record
    }

    func pendingReceipts() throws -> [SharedReceiptManifestRecord] {
        guard fileManager.fileExists(atPath: inboxURL.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)
        return try urls
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".tmp") }
            .map { try JSONDecoder.receiptInbox.decode(SharedReceiptManifestRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func data(for record: SharedReceiptManifestRecord) throws -> Data {
        let url = inboxURL.appendingPathComponent(record.filename)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SharedReceiptInboxError.unreadable
        }
        return try Data(contentsOf: url)
    }

    func delete(_ record: SharedReceiptManifestRecord) throws {
        try? fileManager.removeItem(at: inboxURL.appendingPathComponent(record.filename))
        try? fileManager.removeItem(at: inboxURL.appendingPathComponent("\(record.id.uuidString).json"))
    }

    func cleanupIncompleteTemporaryFiles() throws {
        guard fileManager.fileExists(atPath: inboxURL.path) else { return }
        let urls = try fileManager.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)
        for url in urls where url.lastPathComponent.hasSuffix(".tmp") {
            try? fileManager.removeItem(at: url)
        }
    }
}

enum SharedReceiptContentType {
    static let supported: [UTType] = [.jpeg, .png, .heic, .heif, .pdf]

    static func supportedType(for typeIdentifier: String?) -> UTType? {
        guard let typeIdentifier, let type = UTType(typeIdentifier) else { return nil }
        return supported.first { type.conforms(to: $0) }
    }

    static func contentTypeIdentifier(for typeIdentifier: String?) -> String? {
        supportedType(for: typeIdentifier)?.identifier
    }

    static func contentTypeIdentifier(forFilenameExtension filenameExtension: String) -> String? {
        guard let type = UTType(filenameExtension: filenameExtension) else { return nil }
        return supported.first { type.conforms(to: $0) }?.identifier
    }

    static func fileExtension(for contentType: String) -> String {
        switch contentType {
        case UTType.jpeg.identifier: "jpg"
        case UTType.png.identifier: "png"
        case UTType.heic.identifier: "heic"
        case UTType.heif.identifier: "heif"
        case UTType.pdf.identifier: "pdf"
        default: "receipt"
        }
    }
}

enum QuickAddAction: String, Codable, Equatable, Sendable {
    case addExpense
    case scanReceipt
}

struct QuickAddRoute: Equatable, Sendable {
    var action: QuickAddAction
    var destinationID: UUID?

    var url: URL {
        var components = URLComponents()
        components.scheme = "cani"
        components.host = "quick-add"
        var items = [URLQueryItem(name: "action", value: action.rawValue)]
        if let destinationID {
            items.append(URLQueryItem(name: "destination", value: destinationID.uuidString))
        }
        components.queryItems = items
        return components.url!
    }

    init(action: QuickAddAction, destinationID: UUID? = nil) {
        self.action = action
        self.destinationID = destinationID
    }

    init?(url: URL) {
        guard url.scheme == "cani", url.host == "quick-add" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        guard let actionValue = query["action"], let action = QuickAddAction(rawValue: actionValue) else { return nil }
        if let destinationValue = query["destination"] {
            guard let destinationID = UUID(uuidString: destinationValue) else { return nil }
            self.destinationID = destinationID
        } else {
            destinationID = nil
        }
        self.action = action
    }
}

enum QuickAddNavigationCommand: Equatable, Sendable {
    case addExpense(destinationID: UUID?)
    case scanReceipt(destinationID: UUID?)
}

struct QuickAddRouteRouter: Sendable {
    private(set) var lastHandledRoute: QuickAddRoute?

    mutating func command(for route: QuickAddRoute) -> QuickAddNavigationCommand? {
        guard route != lastHandledRoute else { return nil }
        lastHandledRoute = route
        switch route.action {
        case .addExpense:
            return .addExpense(destinationID: route.destinationID)
        case .scanReceipt:
            return .scanReceipt(destinationID: route.destinationID)
        }
    }
}

struct WidgetDestinationSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var name: String
        var planName: String
    }

    var updatedAt: Date
    var items: [Item]
}

struct WidgetDestinationSnapshotStore: Sendable {
    var snapshotURL: URL

    func write(_ snapshot: WidgetDestinationSnapshot) throws {
        try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = snapshotURL.deletingLastPathComponent().appendingPathComponent("\(snapshotURL.lastPathComponent).tmp")
        try JSONEncoder.receiptInbox.encode(snapshot).write(to: temporaryURL, options: [.atomic])
        try? FileManager.default.removeItem(at: snapshotURL)
        try FileManager.default.moveItem(at: temporaryURL, to: snapshotURL)
        try? (snapshotURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }

    func read() throws -> WidgetDestinationSnapshot? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        return try JSONDecoder.receiptInbox.decode(WidgetDestinationSnapshot.self, from: Data(contentsOf: snapshotURL))
    }

    static func appGroupStore(appGroupIdentifier: String = canIAppGroupIdentifier) throws -> WidgetDestinationSnapshotStore {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw SharedReceiptInboxError.appGroupUnavailable
        }
        return WidgetDestinationSnapshotStore(snapshotURL: container.appendingPathComponent("WidgetDestinations.json"))
    }
}

private extension JSONEncoder {
    static var receiptInbox: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var receiptInbox: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
