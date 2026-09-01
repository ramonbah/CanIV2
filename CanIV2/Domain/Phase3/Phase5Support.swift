//
//  Phase5Support.swift
//  CanIV2
//
//  Created by Codex on 8/31/26.
//

import CoreGraphics
import Foundation
import PDFKit
import SwiftData
import UIKit
import Vision

enum Phase5ValidationError: LocalizedError, Equatable {
    case noImage
    case imageNormalizationFailed
    case scanningCancelled
    case scanningFailed
    case missingReceiptTotal
    case noSelectedReceiptLines
    case invalidReceiptLineAmount(String)
    case invalidReceiptChargeAmount(String)
    case invalidReceiptChargePercentage(String)
    case invalidReceiptChargeDivisor(String)
    case unsupportedReceiptFile
    case receiptFileUnreadable
    case invalidReceiptPDFPage
    case receiptAlreadyExists

    var errorDescription: String? {
        switch self {
        case .noImage:
            "Choose or capture a receipt image first."
        case .imageNormalizationFailed:
            "The receipt image could not be prepared for scanning."
        case .scanningCancelled:
            "Receipt scanning was cancelled."
        case .scanningFailed:
            "The receipt could not be scanned. Try again or enter the details manually."
        case .missingReceiptTotal:
            "Enter a valid receipt total before continuing."
        case .noSelectedReceiptLines:
            "Select at least one receipt line with a valid amount."
        case .invalidReceiptLineAmount(let name):
            "Enter a valid amount for \(name)."
        case .invalidReceiptChargeAmount(let name):
            "Enter a valid charge amount for \(name)."
        case .invalidReceiptChargePercentage(let name):
            "Enter a percentage greater than 0 and no more than 100 for \(name)."
        case .invalidReceiptChargeDivisor(let name):
            "Enter a positive whole-number divisor for \(name)."
        case .unsupportedReceiptFile:
            "Choose a supported receipt image or PDF."
        case .receiptFileUnreadable:
            "The selected receipt file could not be read."
        case .invalidReceiptPDFPage:
            "Choose a valid PDF receipt page."
        case .receiptAlreadyExists:
            "This Transaction already has a receipt."
        }
    }
}

enum ReceiptCaptureSource: String, CaseIterable, Identifiable {
    case camera
    case photoLibrary
    case files

    var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .camera: "Camera"
        case .photoLibrary: "Photo Library"
        case .files: "Files"
        }
    }
}

enum ReceiptReviewMode: String, CaseIterable, Identifiable {
    case wholeReceipt
    case selectedItems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wholeReceipt: "Whole Receipt"
        case .selectedItems: "Selected Items"
        }
    }
}

enum ReceiptChargeKind: String, CaseIterable, Identifiable, Sendable {
    case tax
    case serviceCharge
    case surcharge
    case deliveryFee
    case packagingFee
    case tip
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tax: "Tax"
        case .serviceCharge: "Service Charge"
        case .surcharge: "Surcharge"
        case .deliveryFee: "Delivery Fee"
        case .packagingFee: "Packaging Fee"
        case .tip: "Tip"
        case .other: "Other Charge"
        }
    }
}

enum ReceiptChargeSource: String, Sendable {
    case ocr
    case manual
}

enum ReceiptChargeAllocationMethod: String, CaseIterable, Identifiable, Sendable {
    case exclude
    case includeAll
    case percentage
    case divideEqually

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exclude: "Exclude"
        case .includeAll: "Include All"
        case .percentage: "Percentage"
        case .divideEqually: "Divide Equally"
        }
    }
}

struct ReceiptImagePolicy: Equatable {
    var maximumDimension: CGFloat = 1_600
    var jpegCompressionQuality: CGFloat = 0.78

    static let production = ReceiptImagePolicy()
    static let ocr = ReceiptImagePolicy(maximumDimension: 3_000, jpegCompressionQuality: 0.92)
    static let thumbnail = ReceiptImagePolicy(maximumDimension: 480, jpegCompressionQuality: 0.72)
}

struct ReceiptImageProcessor {
    var policy: ReceiptImagePolicy = .production

    func normalizedJPEGData(from image: UIImage, rotation: ReceiptImageRotation = .none, crop: CGRect? = nil) throws -> Data {
        let oriented = image.normalizedOrientation()
        let cropped = crop.flatMap { oriented.cropped(toUnitRect: $0) } ?? oriented
        let rotated = cropped.rotated(rotation)
        let scaled = rotated.scaledToFit(maximumDimension: policy.maximumDimension)
        guard let data = scaled.jpegData(compressionQuality: policy.jpegCompressionQuality) else {
            throw Phase5ValidationError.imageNormalizationFailed
        }
        return data
    }
}

struct ReceiptPDFImport: Equatable {
    var data: Data
    var pageCount: Int

    var pageIndexes: [Int] {
        Array(0..<pageCount)
    }
}

struct ReceiptFileImportProcessor {
    var temporaryDirectory: URL = FileManager.default.temporaryDirectory
    var maximumPDFRenderDimension: CGFloat = 2_000

    func copyIntoTemporaryStorage(from url: URL) throws -> URL {
        let ext = url.pathExtension.isEmpty ? "receipt" : url.pathExtension
        let destination = temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            throw Phase5ValidationError.receiptFileUnreadable
        }
    }

    func image(from data: Data) throws -> UIImage {
        guard let image = UIImage(data: data) else {
            throw Phase5ValidationError.unsupportedReceiptFile
        }
        return image
    }

    func pdfImport(from data: Data) throws -> ReceiptPDFImport {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw Phase5ValidationError.receiptFileUnreadable
        }
        guard document.page(at: 0) != nil else {
            throw Phase5ValidationError.receiptFileUnreadable
        }
        return ReceiptPDFImport(data: data, pageCount: document.pageCount)
    }

    func renderedImage(from importInfo: ReceiptPDFImport, pageIndex: Int) throws -> UIImage {
        guard pageIndex >= 0,
              pageIndex < importInfo.pageCount,
              let document = PDFDocument(data: importInfo.data),
              let page = document.page(at: pageIndex) else {
            throw Phase5ValidationError.invalidReceiptPDFPage
        }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            throw Phase5ValidationError.invalidReceiptPDFPage
        }
        let scale = min(maximumPDFRenderDimension / bounds.width, maximumPDFRenderDimension / bounds.height)
        let size = CGSize(width: floor(bounds.width * scale), height: floor(bounds.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }
}

enum ReceiptImageRotation: Equatable {
    case none
    case clockwise
    case counterClockwise
}

struct RecognizedReceiptLine: Identifiable, Hashable, Sendable {
    let id: UUID
    var text: String

    nonisolated init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct RecognizedReceiptObservation: Identifiable, Hashable, Sendable {
    let id: UUID
    var text: String
    var normalizedBoundingBox: CGRect
    var confidence: Float
    var alternative: String?
    var pageIndex: Int
    var readingOrder: Int

    nonisolated init(
        id: UUID = UUID(),
        text: String,
        normalizedBoundingBox: CGRect,
        confidence: Float = 1,
        alternative: String? = nil,
        pageIndex: Int = 0,
        readingOrder: Int = 0
    ) {
        self.id = id
        self.text = text
        self.normalizedBoundingBox = normalizedBoundingBox
        self.confidence = confidence
        self.alternative = alternative
        self.pageIndex = pageIndex
        self.readingOrder = readingOrder
    }
}

struct ReceiptLineSuggestion: Identifiable, Hashable, Sendable {
    let id: UUID
    var rawText: String
    var name: String
    var amount: Decimal?
    var isSelected: Bool

    nonisolated init(id: UUID = UUID(), rawText: String, name: String, amount: Decimal?, isSelected: Bool = true) {
        self.id = id
        self.rawText = rawText
        self.name = name
        self.amount = amount
        self.isSelected = isSelected
    }
}

struct ReceiptChargeSuggestion: Identifiable, Hashable, Sendable {
    let id: UUID
    var rawText: String
    var name: String
    var originalAmount: Decimal?
    var kind: ReceiptChargeKind
    var source: ReceiptChargeSource
    var allocationMethod: ReceiptChargeAllocationMethod
    var percentageText: String
    var divisorText: String

    nonisolated init(
        id: UUID = UUID(),
        rawText: String,
        name: String,
        originalAmount: Decimal?,
        kind: ReceiptChargeKind,
        source: ReceiptChargeSource = .ocr,
        allocationMethod: ReceiptChargeAllocationMethod = .exclude,
        percentageText: String = "100",
        divisorText: String = "1"
    ) {
        self.id = id
        self.rawText = rawText
        self.name = name
        self.originalAmount = originalAmount
        self.kind = kind
        self.source = source
        self.allocationMethod = allocationMethod
        self.percentageText = percentageText
        self.divisorText = divisorText
    }

    func appliedAmount(formatter: CurrencyFormatter) throws -> Decimal {
        if allocationMethod == .exclude {
            return 0
        }
        guard let originalAmount, originalAmount > 0 else {
            throw Phase5ValidationError.invalidReceiptChargeAmount(name)
        }
        let unrounded: Decimal
        switch allocationMethod {
        case .exclude:
            unrounded = 0
        case .includeAll:
            unrounded = originalAmount
        case .percentage:
            guard let percentage = formatter.parse(percentageText), percentage > 0, percentage <= 100 else {
                throw Phase5ValidationError.invalidReceiptChargePercentage(name)
            }
            unrounded = originalAmount * percentage / 100
        case .divideEqually:
            guard let divisor = Decimal(string: divisorText, locale: Locale(identifier: "en_US_POSIX")),
                  divisor > 0,
                  divisor == Decimal(Int(truncating: divisor as NSDecimalNumber)) else {
                throw Phase5ValidationError.invalidReceiptChargeDivisor(name)
            }
            unrounded = originalAmount / divisor
        }
        return formatter.roundedForDisplay(unrounded)
    }
}

struct ReceiptScanResult: Equatable, Sendable {
    var imageData: Data
    var recognizedLines: [RecognizedReceiptLine]
    var recognizedObservations: [RecognizedReceiptObservation] = []
    var merchantCandidate: String?
    var dateCandidates: [Date]
    var hasAmbiguousDate: Bool
    var totalCandidates: [Decimal]
    var lineItemCandidates: [ReceiptLineSuggestion]
    var chargeCandidates: [ReceiptChargeSuggestion] = []
    var warnings: [String]

    var rawText: String {
        recognizedLines.map(\.text).joined(separator: "\n")
    }

    var status: ReceiptRecognitionStatus {
        guard !recognizedLines.isEmpty else { return .noTextRecognized }
        let hasReceiptField = !dateCandidates.isEmpty || !totalCandidates.isEmpty || !lineItemCandidates.isEmpty || !chargeCandidates.isEmpty
        guard hasReceiptField else { return .textWithoutReceiptFields }
        if merchantCandidate != nil, !dateCandidates.isEmpty, !totalCandidates.isEmpty, !lineItemCandidates.isEmpty {
            return .recognized
        }
        return .partial
    }
}

enum ReceiptRecognitionStatus: String, Sendable {
    case noTextRecognized
    case textWithoutReceiptFields
    case partial
    case recognized

    nonisolated var title: String {
        switch self {
        case .noTextRecognized: "No text recognized"
        case .textWithoutReceiptFields: "Text recognized, but receipt fields could not be determined"
        case .partial: "Partial receipt recognized"
        case .recognized: "Receipt recognized"
        }
    }
}

protocol ReceiptScanningService: Sendable {
    func scan(imageData: Data) async throws -> ReceiptScanResult
}

struct ReceiptParser: Sendable {
    let calendar: Calendar
    let locale: Locale

    nonisolated func parse(observations: [RecognizedReceiptObservation], imageData: Data = Data()) -> ReceiptScanResult {
        let groupedLines = groupedVisualLines(from: observations)
        var result = parse(lines: groupedLines, imageData: imageData)
        result.recognizedObservations = sortedObservations(observations)
        return result
    }

    nonisolated func parse(lines: [String], imageData: Data = Data()) -> ReceiptScanResult {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let merchant = cleaned.first { !containsMoney($0) && dateCandidates(in: $0).isEmpty }
        let dates = cleaned.flatMap(dateCandidates)
        let totals = totalCandidates(in: cleaned)
        let charges = cleaned.compactMap(chargeCandidate)
        let lineItems = cleaned.compactMap(lineItemCandidate)
        var warnings: [String] = []
        if cleaned.isEmpty { warnings.append(ReceiptRecognitionStatus.noTextRecognized.title) }
        if totals.isEmpty { warnings.append("No receipt total was detected.") }
        if dates.count > 1 { warnings.append("Multiple possible receipt dates were detected.") }
        if lineItems.isEmpty { warnings.append("No line items were detected.") }
        return ReceiptScanResult(
            imageData: imageData,
            recognizedLines: cleaned.map { RecognizedReceiptLine(text: $0) },
            recognizedObservations: [],
            merchantCandidate: merchant,
            dateCandidates: dates.map { calendar.startOfDay(for: $0) },
            hasAmbiguousDate: dates.count > 1,
            totalCandidates: totals,
            lineItemCandidates: lineItems,
            chargeCandidates: charges,
            warnings: warnings
        )
    }

    nonisolated func groupedVisualLines(from observations: [RecognizedReceiptObservation]) -> [String] {
        let sorted = sortedObservations(observations)
        var rows: [[RecognizedReceiptObservation]] = []
        for observation in sorted {
            guard !observation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return first.pageIndex == observation.pageIndex
                    && abs(first.normalizedBoundingBox.midY - observation.normalizedBoundingBox.midY) <= rowTolerance(for: first, observation)
            }) {
                rows[index].append(observation)
            } else {
                rows.append([observation])
            }
        }

        var lines: [String] = []
        var pendingDescription: String?
        for row in rows {
            let rowSorted = row.sorted { lhs, rhs in
                lhs.normalizedBoundingBox.minX == rhs.normalizedBoundingBox.minX
                    ? lhs.readingOrder < rhs.readingOrder
                    : lhs.normalizedBoundingBox.minX < rhs.normalizedBoundingBox.minX
            }
            let texts = rowSorted.map(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !texts.isEmpty else { continue }
            let moneyObservations = rowSorted.filter { !moneyCandidates(in: $0.text).isEmpty }
            let rightMoney = moneyObservations.sorted {
                $0.normalizedBoundingBox.maxX == $1.normalizedBoundingBox.maxX
                    ? $0.normalizedBoundingBox.minX > $1.normalizedBoundingBox.minX
                    : $0.normalizedBoundingBox.maxX > $1.normalizedBoundingBox.maxX
            }.first
            let nonMoneyText = rowSorted
                .filter { moneyCandidates(in: $0.text).isEmpty }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let rightMoney, rightMoney.normalizedBoundingBox.midX >= 0.55, moneyCandidates(in: rightMoney.text).last != nil {
                let description = [pendingDescription, nonMoneyText]
                    .compactMap { value in
                        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return trimmed.isEmpty ? nil : trimmed
                    }
                    .joined(separator: " ")
                pendingDescription = nil
                if description.isEmpty {
                    lines.append(rightMoney.text)
                } else {
                    lines.append("\(description) \(rightMoney.text)")
                }
                continue
            }

            if moneyObservations.count == rowSorted.count,
               let rightMoney,
               moneyCandidates(in: rightMoney.text).last != nil {
                if let existingDescription = pendingDescription {
                    lines.append("\(existingDescription) \(rightMoney.text)")
                    pendingDescription = nil
                } else {
                    lines.append(rightMoney.text)
                }
                continue
            }

            let rowText = texts.joined(separator: " ")
            if moneyCandidates(in: rowText).isEmpty, !dateCandidates(in: rowText).isEmpty {
                if let existingDescription = pendingDescription {
                    lines.append(existingDescription)
                    pendingDescription = nil
                }
                lines.append(rowText)
                continue
            }
            if moneyCandidates(in: rowText).isEmpty,
               !isLikelyHeaderOrFooter(rowText) {
                if dateCandidates(in: rowText).isEmpty,
                   let existingDescription = pendingDescription,
                   !isLikelyHeaderOrFooter(existingDescription),
                   dateCandidates(in: existingDescription).isEmpty {
                    pendingDescription = "\(existingDescription) \(rowText)"
                } else if pendingDescription == nil {
                    pendingDescription = rowText
                } else {
                    lines.append(pendingDescription ?? "")
                    pendingDescription = rowText
                }
            } else {
                if let existingDescription = pendingDescription {
                    lines.append(existingDescription)
                    self.pendingDescriptionClear(&pendingDescription)
                }
                lines.append(rowText)
            }
        }
        if let pendingDescription {
            lines.append(pendingDescription)
        }
        return lines
    }

    nonisolated func sortedObservations(_ observations: [RecognizedReceiptObservation]) -> [RecognizedReceiptObservation] {
        observations.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            let yDelta = abs(lhs.normalizedBoundingBox.midY - rhs.normalizedBoundingBox.midY)
            if yDelta > max(lhs.normalizedBoundingBox.height, rhs.normalizedBoundingBox.height, 0.015) {
                return lhs.normalizedBoundingBox.midY > rhs.normalizedBoundingBox.midY
            }
            if abs(lhs.normalizedBoundingBox.minX - rhs.normalizedBoundingBox.minX) > 0.01 {
                return lhs.normalizedBoundingBox.minX < rhs.normalizedBoundingBox.minX
            }
            return lhs.readingOrder < rhs.readingOrder
        }.enumerated().map { index, observation in
            var copy = observation
            copy.readingOrder = index
            return copy
        }
    }

    private nonisolated func rowTolerance(for lhs: RecognizedReceiptObservation, _ rhs: RecognizedReceiptObservation) -> CGFloat {
        max(lhs.normalizedBoundingBox.height, rhs.normalizedBoundingBox.height, 0.018) * 0.70
    }

    private nonisolated func isLikelyHeaderOrFooter(_ line: String) -> Bool {
        let upper = line.uppercased()
        return ["TEL", "PHONE", "ADDRESS", "SSM", "GST NO", "SST", "APPROVAL", "AUTH", "CARD", "THANK", "FOLLOW", "DOWNLOAD"].contains {
            upper.contains($0)
        }
    }

    private nonisolated func pendingDescriptionClear(_ value: inout String?) {
        value = nil
    }

    private nonisolated func totalCandidates(in lines: [String]) -> [Decimal] {
        let preferred = ["GRAND TOTAL", "AMOUNT DUE", "NET TOTAL", "TOTAL"]
        var labeled: [(priority: Int, value: Decimal)] = []
        for line in lines {
            let upper = line.uppercased()
            guard !isExcludedTotalLine(upper) else { continue }
            guard let amount = moneyCandidates(in: line).last else { continue }
            if let priority = preferred.firstIndex(where: { upper.contains($0) }) {
                labeled.append((priority, amount))
            }
        }
        if !labeled.isEmpty {
            return labeled.sorted { $0.priority == $1.priority ? $0.value > $1.value : $0.priority < $1.priority }.map(\.value)
        }
        return lines
            .filter { !isExcludedTotalLine($0.uppercased()) && chargeKind(in: $0) == nil }
            .flatMap(moneyCandidates)
            .filter(isReasonableReceiptAmount)
            .sorted(by: >)
    }

    private nonisolated func isExcludedTotalLine(_ upper: String) -> Bool {
        ["SUBTOTAL", "SUB TOTAL", "CASH", "TENDER", "CHANGE", "DISCOUNT", "REBATE", "VOUCHER", "TAX", "SERVICE CHARGE", "SVC", "CARD", "APPROVAL", "AUTH", "PHONE", "TEL"].contains {
            upper.contains($0)
        }
    }

    private nonisolated func lineItemCandidate(from line: String) -> ReceiptLineSuggestion? {
        guard let amount = moneyCandidates(in: line).last, isReasonableReceiptAmount(amount) else { return nil }
        let upper = line.uppercased()
        guard !isExcludedTotalLine(upper), !upper.contains("TOTAL"), chargeKind(in: line) == nil else { return nil }
        let name = line.replacingOccurrences(of: moneyPattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -\t"))
        guard !name.isEmpty else { return nil }
        return ReceiptLineSuggestion(rawText: line, name: name, amount: amount)
    }

    private nonisolated func chargeCandidate(from line: String) -> ReceiptChargeSuggestion? {
        guard let kind = chargeKind(in: line),
              let amount = moneyCandidates(in: line).last,
              isReasonableReceiptAmount(amount) else { return nil }
        let name = line.replacingOccurrences(of: moneyPattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -\t"))
        return ReceiptChargeSuggestion(rawText: line, name: name.isEmpty ? fallbackTitle(for: kind) : name, originalAmount: amount, kind: kind)
    }

    private nonisolated func chargeKind(in line: String) -> ReceiptChargeKind? {
        let checks: [(String, ReceiptChargeKind)] = [
            (#"\bservice\s+charge\b"#, .serviceCharge),
            (#"\bsurcharge\b"#, .surcharge),
            (#"\bdelivery\s+(fee|charge)\b"#, .deliveryFee),
            (#"\bpackaging\s+(fee|charge)\b"#, .packagingFee),
            (#"\b(gratuity|tip)\b"#, .tip),
            (#"\btax\b"#, .tax),
            (#"\bsst\b"#, .tax),
            (#"\bgst\b"#, .tax)
        ]
        return checks.first { pattern, _ in !matches(pattern: pattern, in: line).isEmpty }?.1
    }

    private nonisolated func fallbackTitle(for kind: ReceiptChargeKind) -> String {
        switch kind {
        case .tax: "Tax"
        case .serviceCharge: "Service Charge"
        case .surcharge: "Surcharge"
        case .deliveryFee: "Delivery Fee"
        case .packagingFee: "Packaging Fee"
        case .tip: "Tip"
        case .other: "Other Charge"
        }
    }

    private nonisolated func moneyCandidates(in line: String) -> [Decimal] {
        matches(pattern: moneyPattern, in: line).compactMap { token in
            let sanitized = token
                .replacingOccurrences(of: "RM", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decimal = Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return decimal
        }
    }

    private nonisolated func dateCandidates(in line: String) -> [Date] {
        var values: [Date] = []
        let formats = ["dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd"]
        for token in matches(pattern: #"\b(\d{2}[/-]\d{2}[/-]\d{4}|\d{4}-\d{2}-\d{2})\b"#, in: line) {
            for format in formats {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = format
                if let date = formatter.date(from: token) {
                    values.append(date)
                    break
                }
            }
        }
        return values
    }

    private nonisolated func containsMoney(_ line: String) -> Bool {
        !moneyCandidates(in: line).isEmpty
    }

    private nonisolated func isReasonableReceiptAmount(_ amount: Decimal) -> Bool {
        amount > -100_000_000 && amount < 100_000_000
    }

    private nonisolated func matches(pattern: String, in line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let range = Range(match.range, in: line) else { return nil }
            return String(line[range])
        }
    }

    private nonisolated var moneyPattern: String {
        #"(?<!\d)(?:RM\s*)?-?\d{1,3}(?:,\d{3})*(?:\.\d{2})|(?<!\d)(?:RM\s*)?-?\d+\.\d{2}"#
    }
}

actor VisionReceiptScanningService: ReceiptScanningService {
    private let calendar: Calendar
    private let locale: Locale

    init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    func scan(imageData: Data) async throws -> ReceiptScanResult {
        try Task.checkCancellation()
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw Phase5ValidationError.imageNormalizationFailed
        }
        let observations = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let preferred = ["en-MY", "en-US"].filter { supported.contains($0) }
            if !preferred.isEmpty {
                request.recognitionLanguages = preferred
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch is CancellationError {
                throw Phase5ValidationError.scanningCancelled
            } catch {
                throw Phase5ValidationError.scanningFailed
            }
            try Task.checkCancellation()
            return (request.results ?? []).enumerated().compactMap { index, observation -> RecognizedReceiptObservation? in
                let candidates = observation.topCandidates(2)
                guard let top = candidates.first else { return nil }
                let alternative = candidates.dropFirst().first?.string
                return RecognizedReceiptObservation(
                    text: top.string,
                    normalizedBoundingBox: observation.boundingBox,
                    confidence: top.confidence,
                    alternative: alternative,
                    pageIndex: 0,
                    readingOrder: index
                )
            }
        }.value
        let parser = ReceiptParser(calendar: calendar, locale: locale)
        return parser.parse(observations: observations, imageData: imageData)
    }
}

#if DEBUG
struct FakeReceiptScanningService: ReceiptScanningService {
    var result: ReceiptScanResult
    var delayNanoseconds: UInt64 = 0
    var error: Error?

    func scan(imageData: Data) async throws -> ReceiptScanResult {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        try Task.checkCancellation()
        if let error { throw error }
        var copy = result
        copy.imageData = imageData
        return copy
    }

    static func uiTesting(calendar: Calendar = .autoupdatingCurrent) -> FakeReceiptScanningService {
        let parser = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US"))
        let result = parser.parse(lines: [
            "Kedai Makan Contoh",
            "30/08/2026",
            "Nasi Lemak RM 8.50",
            "Teh Ais 3.20",
            "Service Charge RM 0.60",
            "GRAND TOTAL RM 12.30"
        ], imageData: Data("synthetic receipt image".utf8))
        return FakeReceiptScanningService(result: result)
    }
}
#endif

struct ReceiptReviewDraft: Equatable {
    var imageData: Data
    var merchant: String
    var date: Date?
    var totalText: String
    var lineItems: [ReceiptLineSuggestion]
    var charges: [ReceiptChargeSuggestion]
    var additionalTipText: String = ""
    var percentageTipText: String = ""
    var recognitionStatus: ReceiptRecognitionStatus
    var rawText: String
    var warnings: [String]
    var mode: ReceiptReviewMode = .wholeReceipt

    init(scanResult: ReceiptScanResult, formatter: CurrencyFormatter) {
        imageData = scanResult.imageData
        merchant = scanResult.merchantCandidate ?? ""
        date = scanResult.dateCandidates.first
        totalText = scanResult.totalCandidates.first.map { LocalizedNumericEditingPolicy(locale: formatter.locale).editableString(for: $0) } ?? ""
        lineItems = scanResult.lineItemCandidates
        charges = scanResult.chargeCandidates
        rawText = scanResult.rawText
        recognitionStatus = scanResult.status
        warnings = scanResult.warnings
    }

    func transactionAmount(formatter: CurrencyFormatter) throws -> Decimal {
        switch mode {
        case .wholeReceipt:
            guard let amount = formatter.parse(totalText), amount > 0, formatter.hasValidMinorUnits(totalText) else {
                throw Phase5ValidationError.missingReceiptTotal
            }
            return amount + (try additionalTipAmount(formatter: formatter, base: amount))
        case .selectedItems:
            let subtotal = try selectedProductSubtotal()
            let charges = try includedCharges(formatter: formatter).reduce(Decimal(0), +)
            let total = subtotal + charges + (try additionalTipAmount(formatter: formatter, base: subtotal))
            guard total > 0 else { throw Phase5ValidationError.noSelectedReceiptLines }
            return total
        }
    }

    func selectedSubtotal() -> Decimal {
        lineItems.filter(\.isSelected).reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
    }

    func selectedProductSubtotal() throws -> Decimal {
        let selected = lineItems.filter(\.isSelected)
        guard !selected.isEmpty else { throw Phase5ValidationError.noSelectedReceiptLines }
        var total = Decimal(0)
        for line in selected {
            guard let amount = line.amount, amount > 0 else {
                throw Phase5ValidationError.invalidReceiptLineAmount(line.name)
            }
            total += amount
        }
        return total
    }

    func includedCharges(formatter: CurrencyFormatter) throws -> [Decimal] {
        try charges.map { try $0.appliedAmount(formatter: formatter) }.filter { $0 > 0 }
    }

    func additionalTipAmount(formatter: CurrencyFormatter, base: Decimal? = nil) throws -> Decimal {
        var total = Decimal(0)
        if !additionalTipText.isEmpty {
            guard let fixed = formatter.parse(additionalTipText), fixed > 0, formatter.hasValidMinorUnits(additionalTipText) else {
                throw Phase5ValidationError.invalidReceiptChargeAmount("Additional Tip")
            }
            total += fixed
        }
        if !percentageTipText.isEmpty {
            let tipBase = try base ?? (mode == .selectedItems ? selectedProductSubtotal() : formatter.parse(totalText) ?? 0)
            guard tipBase > 0,
                  let percentage = formatter.parse(percentageTipText),
                  percentage > 0,
                  percentage <= 100 else {
                throw Phase5ValidationError.invalidReceiptChargePercentage("Additional Tip")
            }
            total += formatter.roundedForDisplay(tipBase * percentage / 100)
        }
        return total
    }

    func receiptLineDrafts() -> [ReceiptLineDraft] {
        lineItems.map { line in
            ReceiptLineDraft(rawText: line.rawText, name: line.name.isEmpty ? nil : line.name, amount: line.amount, isSelected: line.isSelected)
        }
    }

    func receiptLineDrafts(formatter: CurrencyFormatter) throws -> [ReceiptLineDraft] {
        var drafts = lineItems.map { line in
            ReceiptLineDraft(rawText: line.rawText, name: line.name.isEmpty ? nil : line.name, amount: line.amount, isSelected: line.isSelected)
        }
        switch mode {
        case .wholeReceipt:
            for charge in charges {
                guard let originalAmount = charge.originalAmount, originalAmount > 0 else { continue }
                let name = charge.name.isEmpty ? charge.kind.title : charge.name
                drafts.append(ReceiptLineDraft(rawText: charge.rawText, name: name, amount: originalAmount, isSelected: true))
            }
        case .selectedItems:
            for charge in charges {
                guard let originalAmount = charge.originalAmount, originalAmount > 0 else { continue }
                let name = charge.name.isEmpty ? charge.kind.title : charge.name
                let applied = try charge.appliedAmount(formatter: formatter)
                drafts.append(ReceiptLineDraft(
                    rawText: charge.rawText,
                    name: name,
                    amount: applied > 0 ? applied : originalAmount,
                    isSelected: applied > 0
                ))
            }
        }
        let tip = try additionalTipAmount(formatter: formatter)
        if tip > 0 {
            drafts.append(ReceiptLineDraft(rawText: "Manual additional tip", name: "Additional Tip", amount: tip, isSelected: true))
        }
        return drafts
    }
}

struct ReceiptLineDraft: Equatable {
    var rawText: String
    var name: String?
    var amount: Decimal?
    var isSelected: Bool
}

struct ReceiptAttachmentDraft: Equatable {
    var imageData: Data
    var merchant: String?
    var date: Date?
    var total: Decimal?
    var lines: [ReceiptLineDraft]
}

struct PendingReceiptReviewRequest: Equatable {
    var record: SharedReceiptManifestRecord
    var imageData: Data
}

struct SavedReceiptLineDraft: Identifiable, Equatable {
    var id: UUID
    var rawText: String
    var name: String
    var amountText: String
    var isSelected: Bool

    init(id: UUID = UUID(), rawText: String, name: String, amountText: String, isSelected: Bool) {
        self.id = id
        self.rawText = rawText
        self.name = name
        self.amountText = amountText
        self.isSelected = isSelected
    }
}

struct SavedReceiptEditDraft: Equatable {
    var merchant: String
    var date: Date?
    var totalText: String
    var lines: [SavedReceiptLineDraft]

    init(receipt: ReceiptCapture, formatter: CurrencyFormatter) {
        merchant = receipt.merchant ?? ""
        date = receipt.date
        totalText = receipt.total.map { LocalizedNumericEditingPolicy(locale: formatter.locale).editableString(for: $0) } ?? ""
        lines = receipt.lineItems.map { line in
            SavedReceiptLineDraft(
                id: line.id,
                rawText: line.rawText,
                name: line.name ?? line.rawText,
                amountText: line.amount.map { LocalizedNumericEditingPolicy(locale: formatter.locale).editableString(for: $0) } ?? "",
                isSelected: line.isSelected
            )
        }
    }

    func attachmentDraft(existingImageData: Data?, formatter: CurrencyFormatter) throws -> ReceiptAttachmentDraft {
        let parsedTotal = totalText.isEmpty ? nil : formatter.parse(totalText)
        let lineDrafts = try lines.map { line -> ReceiptLineDraft in
            let trimmedName = NameNormalizer.trimmed(line.name)
            let parsedAmount = line.amountText.isEmpty ? nil : formatter.parse(line.amountText)
            if !line.amountText.isEmpty, parsedAmount == nil {
                throw Phase5ValidationError.invalidReceiptLineAmount(trimmedName.isEmpty ? "Receipt Line" : trimmedName)
            }
            return ReceiptLineDraft(
                rawText: line.rawText.isEmpty ? (trimmedName.isEmpty ? "Manual line" : trimmedName) : line.rawText,
                name: trimmedName.isEmpty ? nil : trimmedName,
                amount: parsedAmount,
                isSelected: line.isSelected
            )
        }
        let merchant = NameNormalizer.trimmed(merchant)
        return ReceiptAttachmentDraft(
            imageData: existingImageData ?? Data(),
            merchant: merchant.isEmpty ? nil : merchant,
            date: date,
            total: parsedTotal,
            lines: lineDrafts
        )
    }

    func includedAmount(formatter: CurrencyFormatter) throws -> Decimal {
        try lines.filter(\.isSelected).reduce(Decimal(0)) { partial, line in
            guard let amount = formatter.parse(line.amountText), amount >= 0 else {
                throw Phase5ValidationError.invalidReceiptLineAmount(line.name)
            }
            return partial + amount
        }
    }

    func includedProductSubtotal(formatter: CurrencyFormatter) throws -> Decimal {
        try lines.filter { $0.isSelected && !SavedReceiptPresentation.isChargeOrTip(name: $0.name, rawText: $0.rawText) }.reduce(Decimal(0)) { partial, line in
            guard let amount = formatter.parse(line.amountText), amount >= 0 else {
                throw Phase5ValidationError.invalidReceiptLineAmount(line.name)
            }
            return partial + amount
        }
    }

    func includedChargeTipSubtotal(formatter: CurrencyFormatter) throws -> Decimal {
        try lines.filter { $0.isSelected && SavedReceiptPresentation.isChargeOrTip(name: $0.name, rawText: $0.rawText) }.reduce(Decimal(0)) { partial, line in
            guard let amount = formatter.parse(line.amountText), amount >= 0 else {
                throw Phase5ValidationError.invalidReceiptLineAmount(line.name)
            }
            return partial + amount
        }
    }
}

struct SavedReceiptPresentation {
    var includedItems: [ReceiptLineItem]
    var excludedItems: [ReceiptLineItem]
    var chargesAndTips: [ReceiptLineItem]

    var includedSubtotal: Decimal {
        includedItems.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
    }

    var includedChargesAndTipsSubtotal: Decimal {
        chargesAndTips.filter(\.isSelected).reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
    }

    var includedLineTotal: Decimal {
        includedSubtotal + includedChargesAndTipsSubtotal
    }

    @MainActor
    init(lines: [ReceiptLineItem]) {
        chargesAndTips = lines.filter(Self.isChargeOrTip)
        let products = lines.filter { !Self.isChargeOrTip($0) }
        includedItems = products.filter(\.isSelected)
        excludedItems = products.filter { !$0.isSelected }
    }

    static func isChargeOrTip(_ line: ReceiptLineItem) -> Bool {
        isChargeOrTip(name: line.name ?? "", rawText: line.rawText)
    }

    nonisolated static func isChargeOrTip(name: String, rawText: String) -> Bool {
        let text = "\(name) \(rawText)"
        let patterns = [
            #"\bservice\s+charge\b"#,
            #"\bsurcharge\b"#,
            #"\bdelivery\s+(fee|charge)\b"#,
            #"\bpackaging\s+(fee|charge)\b"#,
            #"\b(gratuity|tip)\b"#,
            #"\badditional\s+tip\b"#,
            #"\btax\b"#,
            #"\bsst\b"#,
            #"\bgst\b"#,
            #"\bother\s+charge\b"#
        ]
        return patterns.contains {
            text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

extension ReceiptAttachmentDraft {
    init(review: ReceiptReviewDraft, formatter: CurrencyFormatter) throws {
        imageData = review.imageData
        let merchant = NameNormalizer.trimmed(review.merchant)
        self.merchant = merchant.isEmpty ? nil : merchant
        date = review.date
        total = formatter.parse(review.totalText)
        lines = try review.receiptLineDrafts(formatter: formatter)
    }
}

@MainActor
struct ReceiptUseCase {
    let context: ModelContext

    func attach(_ draft: ReceiptAttachmentDraft, to transaction: Transaction, now: Date) throws {
        guard transaction.receipt == nil else { throw Phase5ValidationError.receiptAlreadyExists }
        let receipt = ReceiptCapture(
            imageData: draft.imageData,
            merchant: draft.merchant,
            date: draft.date,
            total: draft.total,
            createdAt: now,
            updatedAt: now,
            transaction: transaction
        )
        let lines = draft.lines.map {
            ReceiptLineItem(
                rawText: $0.rawText,
                name: $0.name,
                amount: $0.amount,
                isSelected: $0.isSelected,
                createdAt: now,
                updatedAt: now,
                receiptCapture: receipt
            )
        }
        receipt.lineItems = lines
        transaction.receipt = receipt
        context.insert(receipt)
        lines.forEach(context.insert)
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            transaction.receipt = nil
            lines.forEach(context.delete)
            context.delete(receipt)
            context.rollback()
            throw error
        }
    }

    func replaceReceipt(on transaction: Transaction, with draft: ReceiptAttachmentDraft, now: Date) throws {
        let original = transaction.receipt
        let originalLines = original?.lineItems ?? []
        if let original {
            original.lineItems.forEach(context.delete)
            context.delete(original)
            transaction.receipt = nil
        }
        do {
            try attach(draft, to: transaction, now: now)
        } catch {
            if let original {
                transaction.receipt = original
                original.lineItems = originalLines
                context.insert(original)
                originalLines.forEach(context.insert)
            }
            context.rollback()
            throw error
        }
    }

    func updateReceiptDetails(on transaction: Transaction, with draft: ReceiptAttachmentDraft, transactionAmount: Decimal?, now: Date) throws {
        guard let receipt = transaction.receipt else { return }
        let originalMerchant = receipt.merchant
        let originalDate = receipt.date
        let originalTotal = receipt.total
        let originalUpdatedAt = receipt.updatedAt
        let originalTransactionAmount = transaction.amount
        let originalTransactionUpdatedAt = transaction.updatedAt
        let originalLines = receipt.lineItems.map {
            (
                line: $0,
                rawText: $0.rawText,
                name: $0.name,
                amount: $0.amount,
                isSelected: $0.isSelected,
                updatedAt: $0.updatedAt
            )
        }

        receipt.merchant = draft.merchant
        receipt.date = draft.date
        receipt.total = draft.total
        receipt.updatedAt = now
        for existing in receipt.lineItems {
            context.delete(existing)
        }
        let newLines = draft.lines.map {
            ReceiptLineItem(
                rawText: $0.rawText,
                name: $0.name,
                amount: $0.amount,
                isSelected: $0.isSelected,
                createdAt: now,
                updatedAt: now,
                receiptCapture: receipt
            )
        }
        receipt.lineItems = newLines
        newLines.forEach(context.insert)
        if let transactionAmount {
            transaction.amount = transactionAmount
            transaction.updatedAt = now
        }

        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            receipt.merchant = originalMerchant
            receipt.date = originalDate
            receipt.total = originalTotal
            receipt.updatedAt = originalUpdatedAt
            newLines.forEach(context.delete)
            for snapshot in originalLines {
                snapshot.line.rawText = snapshot.rawText
                snapshot.line.name = snapshot.name
                snapshot.line.amount = snapshot.amount
                snapshot.line.isSelected = snapshot.isSelected
                snapshot.line.updatedAt = snapshot.updatedAt
                context.insert(snapshot.line)
            }
            receipt.lineItems = originalLines.map(\.line)
            transaction.amount = originalTransactionAmount
            transaction.updatedAt = originalTransactionUpdatedAt
            context.rollback()
            throw error
        }
    }

    func removeReceipt(from transaction: Transaction, now: Date) throws {
        guard let receipt = transaction.receipt else { return }
        let originalLines = receipt.lineItems
        transaction.receipt = nil
        receipt.lineItems.forEach(context.delete)
        context.delete(receipt)
        transaction.updatedAt = now
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            transaction.receipt = receipt
            receipt.lineItems = originalLines
            context.insert(receipt)
            originalLines.forEach(context.insert)
            context.rollback()
            throw error
        }
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size, format: .receiptScaleOne).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func cropped(toUnitRect rect: CGRect) -> UIImage? {
        let bounded = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard bounded.width > 0, bounded.height > 0, let cgImage else { return nil }
        let pixelRect = CGRect(
            x: bounded.minX * CGFloat(cgImage.width),
            y: bounded.minY * CGFloat(cgImage.height),
            width: bounded.width * CGFloat(cgImage.width),
            height: bounded.height * CGFloat(cgImage.height)
        ).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    func rotated(_ rotation: ReceiptImageRotation) -> UIImage {
        guard rotation != .none else { return self }
        let newSize = CGSize(width: size.height, height: size.width)
        return UIGraphicsImageRenderer(size: newSize, format: .receiptScaleOne).image { context in
            switch rotation {
            case .clockwise:
                context.cgContext.translateBy(x: newSize.width, y: 0)
                context.cgContext.rotate(by: .pi / 2)
            case .counterClockwise:
                context.cgContext.translateBy(x: 0, y: newSize.height)
                context.cgContext.rotate(by: -.pi / 2)
            case .none:
                break
            }
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func scaledToFit(maximumDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maximumDimension, maximumDimension > 0 else { return self }
        let scaleFactor = maximumDimension / longest
        let target = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        return UIGraphicsImageRenderer(size: target, format: .receiptScaleOne).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private extension UIGraphicsImageRendererFormat {
    static var receiptScaleOne: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return format
    }
}
