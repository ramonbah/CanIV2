import Foundation
import SwiftData
import Testing
import UIKit
@testable import CanIV2

@Suite("Phase 5 receipt capture and OCR")
struct Phase5Tests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var formatter: CurrencyFormatter {
        CurrencyFormatter(currencyCode: "MYR", locale: Locale(identifier: "en_US"))
    }

    @Test("Parser extracts merchant dates totals lines and warnings with Decimal values")
    func parserExtractsReceiptSuggestions() {
        let result = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US")).parse(lines: [
            "Kedai Contoh Sdn Bhd",
            "30/08/2026",
            "Nasi Lemak RM 8.50",
            "Teh Ais 3.20",
            "SUBTOTAL RM 11.70",
            "Service Charge RM 0.60",
            "GRAND TOTAL RM 12.30",
            "Cash RM 20.00",
            "Change RM 7.70",
            "Tel 03-12345678"
        ])

        #expect(result.merchantCandidate == "Kedai Contoh Sdn Bhd")
        #expect(result.dateCandidates.count == 1)
        #expect(result.totalCandidates.first == Decimal(string: "12.30"))
        #expect(result.lineItemCandidates.map(\.name) == ["Nasi Lemak", "Teh Ais"])
        #expect(result.lineItemCandidates.map(\.amount) == [Decimal(string: "8.50"), Decimal(string: "3.20")])
        #expect(result.chargeCandidates.map(\.kind) == [.serviceCharge])
        #expect(result.chargeCandidates.first?.originalAmount == Decimal(string: "0.60"))
    }

    @Test("Parser keeps missing and ambiguous receipt data reviewable")
    func parserHandlesNoisyAmbiguousAndInvalidData() {
        let result = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US")).parse(lines: [
            "Pasar Contoh",
            "01/02/2026",
            "2026-02-01",
            "Approval 123456",
            "Tax RM 1.00",
            "Cash RM 30.00",
            "Change RM 2.00",
            "Huge RM 123456789.00"
        ])

        #expect(result.hasAmbiguousDate)
        #expect(result.totalCandidates.isEmpty)
        #expect(result.lineItemCandidates.isEmpty)
        #expect(result.warnings.contains("No receipt total was detected."))
        #expect(result.warnings.contains("Multiple possible receipt dates were detected."))
    }

    @Test("Parser handles fictional long receipt layout with products charges discounts and payment exclusions")
    func parserHandlesLongReceiptLayout() {
        let result = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US")).parse(lines: [
            "Fictional Receipt House",
            "22/08/2026",
            "Item Qty Price",
            "Sparkling Citrus Drink x1 RM 12.80",
            "Garden Rice Bowl x2 24.40",
            "SUBTOTAL RM 37.20",
            "Service Charge RM 3.72",
            "SST(6%) RM 2.45",
            "Discount -5.00",
            "GRAND TOTAL RM 38.37",
            "Cash RM 50.00",
            "Change RM 11.63",
            "Approval 123456"
        ])

        #expect(result.status == .recognized)
        #expect(result.merchantCandidate == "Fictional Receipt House")
        #expect(result.dateCandidates.count == 1)
        #expect(result.totalCandidates.first == Decimal(string: "38.37"))
        #expect(result.lineItemCandidates.map(\.name) == ["Sparkling Citrus Drink x1", "Garden Rice Bowl x2"])
        #expect(result.chargeCandidates.map(\.kind) == [.serviceCharge, .tax])
        #expect(!result.lineItemCandidates.contains { $0.rawText.localizedCaseInsensitiveContains("Cash") })
        #expect(!result.lineItemCandidates.contains { $0.rawText.localizedCaseInsensitiveContains("Approval") })
    }

    @Test("Layout parser groups two-column receipt observations")
    func layoutParserGroupsTwoColumnObservations() {
        let parser = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US"))
        let result = parser.parse(observations: [
            observation("Fictional Counter", x: 0.10, y: 0.92, width: 0.45),
            observation("22/08/2026", x: 0.10, y: 0.86, width: 0.28),
            observation("Blue Rice Bowl", x: 0.10, y: 0.70, width: 0.42),
            observation("18.90", x: 0.76, y: 0.70, width: 0.14),
            observation("Lime Tea", x: 0.10, y: 0.64, width: 0.28),
            observation("4.20", x: 0.79, y: 0.64, width: 0.11),
            observation("SUBTOTAL", x: 0.54, y: 0.48, width: 0.20),
            observation("23.10", x: 0.77, y: 0.48, width: 0.13),
            observation("Service Charge", x: 0.44, y: 0.42, width: 0.30),
            observation("2.31", x: 0.80, y: 0.42, width: 0.10),
            observation("Tax", x: 0.60, y: 0.36, width: 0.12),
            observation("1.53", x: 0.80, y: 0.36, width: 0.10),
            observation("GRAND TOTAL", x: 0.46, y: 0.30, width: 0.28),
            observation("26.94", x: 0.77, y: 0.30, width: 0.13),
            observation("Cash", x: 0.58, y: 0.22, width: 0.16),
            observation("30.00", x: 0.77, y: 0.22, width: 0.13),
            observation("Change", x: 0.56, y: 0.18, width: 0.18),
            observation("3.06", x: 0.80, y: 0.18, width: 0.10)
        ])

        #expect(result.status == .recognized)
        #expect(result.merchantCandidate == "Fictional Counter")
        #expect(result.lineItemCandidates.map(\.name) == ["Blue Rice Bowl", "Lime Tea"])
        #expect(result.lineItemCandidates.map(\.amount) == [Decimal(string: "18.90"), Decimal(string: "4.20")])
        #expect(result.chargeCandidates.map(\.kind) == [.serviceCharge, .tax])
        #expect(result.totalCandidates.first == Decimal(string: "26.94"))
        #expect(!result.lineItemCandidates.contains { $0.rawText.localizedCaseInsensitiveContains("Cash") })
        #expect(result.recognizedObservations.count == 18)
    }

    @Test("Layout parser joins wrapped descriptions and rightmost line totals")
    func layoutParserJoinsWrappedDescriptionsAndChoosesLineTotal() {
        let parser = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US"))
        let result = parser.parse(observations: [
            observation("Fictional Market", x: 0.10, y: 0.94, width: 0.40),
            observation("22/08/2026", x: 0.10, y: 0.88, width: 0.28),
            observation("Very Long Wrapped", x: 0.10, y: 0.72, width: 0.38),
            observation("Product Name", x: 0.10, y: 0.67, width: 0.30),
            observation("2", x: 0.54, y: 0.67, width: 0.05),
            observation("5.50", x: 0.65, y: 0.67, width: 0.10),
            observation("11.00", x: 0.80, y: 0.67, width: 0.12),
            observation("Delivery Fee", x: 0.48, y: 0.46, width: 0.24),
            observation("3.00", x: 0.80, y: 0.46, width: 0.10),
            observation("NET TOTAL", x: 0.50, y: 0.38, width: 0.22),
            observation("14.00", x: 0.78, y: 0.38, width: 0.12),
            observation("Card Approval", x: 0.44, y: 0.24, width: 0.28),
            observation("123456", x: 0.78, y: 0.24, width: 0.14)
        ])

        #expect(result.lineItemCandidates.map(\.name) == ["Very Long Wrapped Product Name 2"])
        #expect(result.lineItemCandidates.first?.amount == Decimal(string: "11.00"))
        #expect(result.chargeCandidates.map(\.kind) == [.deliveryFee])
        #expect(result.totalCandidates.first == Decimal(string: "14.00"))
    }

    @Test("Observation ordering is page top-to-bottom and left-to-right")
    func observationOrderingIsDeterministic() {
        let parser = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US"))
        let grouped = parser.groupedVisualLines(from: [
            observation("3.00", x: 0.80, y: 0.60, width: 0.10, order: 0),
            observation("First Product", x: 0.10, y: 0.60, width: 0.34, order: 1),
            observation("Second Product", x: 0.10, y: 0.52, width: 0.36, order: 2),
            observation("4.00", x: 0.80, y: 0.52, width: 0.10, order: 3)
        ])

        #expect(grouped == ["First Product 3.00", "Second Product 4.00"])
    }

    @Test("Recognition status distinguishes no text partial and unstructured text")
    func receiptRecognitionStatusStates() {
        let parser = ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US"))
        #expect(parser.parse(lines: []).status == .noTextRecognized)
        #expect(parser.parse(lines: ["Thank you for visiting our store"]).status == .textWithoutReceiptFields)
        #expect(parser.parse(lines: ["Fictional Shop", "TOTAL RM 4.00"]).status == .partial)
    }

    @Test("Review calculations support whole receipt and selected item subtotal")
    func reviewCalculations() throws {
        let scan = ReceiptScanResult(
            imageData: Data([1, 2, 3]),
            recognizedLines: [RecognizedReceiptLine(id: fixedUUID(1), text: "TOTAL RM 12.30")],
            merchantCandidate: "Cafe Contoh",
            dateCandidates: [calendar.date(from: DateComponents(year: 2026, month: 8, day: 30))!],
            hasAmbiguousDate: false,
            totalCandidates: [Decimal(string: "12.30")!],
            lineItemCandidates: [
                ReceiptLineSuggestion(id: fixedUUID(2), rawText: "Food RM 8.50", name: "Food", amount: Decimal(string: "8.50")!, isSelected: true),
                ReceiptLineSuggestion(id: fixedUUID(3), rawText: "Tea RM 3.20", name: "Tea", amount: Decimal(string: "3.20")!, isSelected: false),
                ReceiptLineSuggestion(id: fixedUUID(4), rawText: "Discount -1.00", name: "Discount", amount: Decimal(string: "-1.00")!, isSelected: false)
            ],
            warnings: []
        )
        var review = ReceiptReviewDraft(scanResult: scan, formatter: formatter)

        #expect(try review.transactionAmount(formatter: formatter) == Decimal(string: "12.30"))
        review.mode = .selectedItems
        #expect(try review.transactionAmount(formatter: formatter) == Decimal(string: "8.50"))
        review.lineItems[1].isSelected = true
        #expect(review.selectedSubtotal() == Decimal(string: "11.70"))
        review.lineItems = review.lineItems.map {
            ReceiptLineSuggestion(id: $0.id, rawText: $0.rawText, name: $0.name, amount: $0.amount, isSelected: false)
        }
        #expect(throws: Phase5ValidationError.noSelectedReceiptLines) {
            _ = try review.transactionAmount(formatter: formatter)
        }
    }

    @Test("Charge allocation supports include exclude percentage divide and rounding")
    func chargeAllocationCalculations() throws {
        var review = chargeReview()
        review.mode = .selectedItems
        review.charges[0].allocationMethod = .includeAll
        review.charges[1].allocationMethod = .exclude
        review.charges[2].allocationMethod = .percentage
        review.charges[2].percentageText = "50"
        review.charges[3].allocationMethod = .divideEqually
        review.charges[3].divisorText = "3"

        #expect(try review.includedCharges(formatter: formatter) == [Decimal(string: "1.20"), Decimal(string: "0.50"), Decimal(string: "0.33")])
        #expect(try review.transactionAmount(formatter: formatter) == Decimal(string: "13.73"))
    }

    @Test("Charge validation rejects invalid percentage divisor and nonpositive amounts")
    func chargeAllocationValidation() throws {
        var review = chargeReview()
        review.mode = .selectedItems
        review.charges[0].allocationMethod = .percentage
        review.charges[0].percentageText = "0"
        #expect(throws: Phase5ValidationError.invalidReceiptChargePercentage("Tax")) {
            _ = try review.transactionAmount(formatter: formatter)
        }

        review = chargeReview()
        review.mode = .selectedItems
        review.charges[0].allocationMethod = .divideEqually
        review.charges[0].divisorText = "1.5"
        #expect(throws: Phase5ValidationError.invalidReceiptChargeDivisor("Tax")) {
            _ = try review.transactionAmount(formatter: formatter)
        }

        review = chargeReview()
        review.mode = .selectedItems
        review.charges[0].originalAmount = 0
        review.charges[0].allocationMethod = .includeAll
        #expect(throws: Phase5ValidationError.invalidReceiptChargeAmount("Tax")) {
            _ = try review.transactionAmount(formatter: formatter)
        }
    }

    @Test("Tips and whole receipt avoid charge double counting")
    func tipsAndWholeReceiptChargeSemantics() throws {
        var review = chargeReview()
        review.mode = .wholeReceipt
        review.charges[0].allocationMethod = .includeAll
        review.additionalTipText = "2.00"
        review.percentageTipText = "10"
        #expect(try review.transactionAmount(formatter: formatter) == Decimal(string: "15.53"))

        review = chargeReview()
        review.mode = .selectedItems
        review.charges[0].kind = .tip
        review.charges[0].name = "Gratuity"
        review.charges[0].allocationMethod = .includeAll
        review.additionalTipText = "1.00"
        review.percentageTipText = "10"
        #expect(try review.transactionAmount(formatter: formatter) == Decimal(string: "15.07"))
    }

    @Test("Applied charge and tip lines persist as reviewed receipt lines")
    func appliedChargeLinesPersistAsReviewedLines() throws {
        var review = chargeReview()
        review.mode = .selectedItems
        review.lineItems[1].isSelected = false
        review.charges[0].allocationMethod = .includeAll
        review.charges[1].allocationMethod = .exclude
        review.charges[2].allocationMethod = .percentage
        review.charges[2].percentageText = "50"
        review.additionalTipText = "1.00"

        let draft = try ReceiptAttachmentDraft(review: review, formatter: formatter)
        #expect(try review.transactionAmount(formatter: formatter) == Decimal(string: "11.20"))
        #expect(draft.lines.contains { $0.rawText == "Tea RM 3.20" && $0.isSelected == false })
        #expect(draft.lines.contains { $0.rawText == "Tax RM 1.20" && $0.name == "Tax" && $0.amount == Decimal(string: "1.20") })
        #expect(draft.lines.contains { $0.rawText == "Service Charge RM 0.60" && $0.name == "Service Charge" && $0.amount == Decimal(string: "0.60") && $0.isSelected == false })
        #expect(draft.lines.contains { $0.rawText == "Surcharge RM 1.00" && $0.name == "Surcharge" && $0.amount == Decimal(string: "0.50") })
        #expect(draft.lines.contains { $0.rawText == "Manual additional tip" && $0.name == "Additional Tip" && $0.amount == Decimal(string: "1.00") })
    }

    @Test("Whole receipt persists detected charges without double counting")
    func wholeReceiptPersistsChargesWithoutDoubleCounting() throws {
        var review = chargeReview()
        review.mode = .wholeReceipt
        review.charges[0].allocationMethod = .exclude
        review.charges[1].allocationMethod = .exclude
        review.additionalTipText = "1.00"

        let draft = try ReceiptAttachmentDraft(review: review, formatter: formatter)

        #expect(try review.transactionAmount(formatter: formatter) == Decimal(string: "13.30"))
        #expect(draft.lines.contains { $0.rawText == "Tax RM 1.20" && $0.amount == Decimal(string: "1.20") && $0.isSelected })
        #expect(draft.lines.contains { $0.rawText == "Service Charge RM 0.60" && $0.amount == Decimal(string: "0.60") && $0.isSelected })
        #expect(draft.lines.contains { $0.rawText == "Manual additional tip" && $0.amount == Decimal(string: "1.00") && $0.isSelected })
    }

    @MainActor
    @Test("Saved receipt presentation distinguishes included excluded and charges")
    func savedReceiptPresentationDistinguishesIncludedExcludedAndCharges() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let fixture = TestFixtures.hierarchy()
        fixture.transaction.receipt = nil
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        var review = chargeReview()
        review.mode = .selectedItems
        review.lineItems[1].isSelected = false
        review.charges[0].allocationMethod = .includeAll
        review.charges[1].allocationMethod = .exclude
        try ReceiptUseCase(context: context).attach(ReceiptAttachmentDraft(review: review, formatter: formatter), to: fixture.transaction, now: TestFixtures.date)

        let receipt = try #require(fixture.transaction.receipt)
        let presentation = SavedReceiptPresentation(lines: receipt.lineItems)
        #expect(presentation.includedItems.map { $0.name ?? "" } == ["Food"])
        #expect(presentation.excludedItems.map { $0.name ?? "" } == ["Tea"])
        #expect(presentation.chargesAndTips.count == 4)
        #expect(presentation.includedSubtotal == Decimal(string: "8.50"))
        #expect(presentation.includedChargesAndTipsSubtotal == Decimal(string: "1.20"))
        #expect(presentation.includedLineTotal == Decimal(string: "9.70"))
    }

    @MainActor
    @Test("Saved receipt presentation totals separate products charges tips and exclusions")
    func savedReceiptPresentationTotalsSeparateProductsChargesTipsAndExclusions() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let fixture = TestFixtures.hierarchy()
        fixture.transaction.receipt = nil
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        let draft = ReceiptAttachmentDraft(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            merchant: "Fictional Electronics",
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)),
            total: Decimal(string: "36.20"),
            lines: [
                ReceiptLineDraft(rawText: "Phone Charger RM 30.00", name: "Phone Charger", amount: Decimal(string: "30.00"), isSelected: true),
                ReceiptLineDraft(rawText: "Tea RM 3.00", name: "Tea", amount: Decimal(string: "3.00"), isSelected: true),
                ReceiptLineDraft(rawText: "Snack RM 5.00", name: "Snack", amount: Decimal(string: "5.00"), isSelected: false),
                ReceiptLineDraft(rawText: "Tax RM 1.20", name: "Tax", amount: Decimal(string: "1.20"), isSelected: true),
                ReceiptLineDraft(rawText: "Additional Tip RM 2.00", name: "Additional Tip", amount: Decimal(string: "2.00"), isSelected: true),
                ReceiptLineDraft(rawText: "Service Charge RM 0.60", name: "Service Charge", amount: Decimal(string: "0.60"), isSelected: false),
                ReceiptLineDraft(rawText: "Manual charge", name: "Other Charge", amount: Decimal(string: "1.50"), isSelected: true),
                ReceiptLineDraft(rawText: "Other Charge Manual charge", name: nil, amount: Decimal(string: "0.50"), isSelected: true),
                ReceiptLineDraft(rawText: "Charge Cable RM 7.00", name: "Charge Cable", amount: Decimal(string: "7.00"), isSelected: true)
            ]
        )
        try ReceiptUseCase(context: context).attach(draft, to: fixture.transaction, now: TestFixtures.date)

        let presentation = SavedReceiptPresentation(lines: try #require(fixture.transaction.receipt).lineItems)
        #expect(presentation.includedItems.map { $0.name ?? "" }.sorted() == ["Charge Cable", "Phone Charger", "Tea"])
        #expect(presentation.excludedItems.map { $0.name ?? "" } == ["Snack"])
        #expect(presentation.chargesAndTips.map { $0.name ?? $0.rawText }.sorted() == ["Additional Tip", "Other Charge", "Other Charge Manual charge", "Service Charge", "Tax"])
        #expect(presentation.includedSubtotal == Decimal(string: "40.00"))
        #expect(presentation.includedChargesAndTipsSubtotal == Decimal(string: "5.20"))
        #expect(presentation.includedLineTotal == Decimal(string: "45.20"))
    }

    @MainActor
    @Test("Saved receipt edits persist and optionally update transaction amount")
    func savedReceiptEditsPersistAndUpdateTransactionAmount() throws {
        let storeURL = try temporaryStoreURL()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 14))!
        let transactionID: UUID

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let fixture = TestFixtures.hierarchy()
            fixture.transaction.receipt = nil
            context.insert(fixture.budget)
            try ModelMutationService.saveValidated(context)
            transactionID = fixture.transaction.id
            try ReceiptUseCase(context: context).attach(attachmentDraft(merchant: "Original Cafe", total: 12), to: fixture.transaction, now: now)
        }

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let transaction = try #require(try context.fetch(FetchDescriptor<Transaction>()).first { $0.id == transactionID })
            let receipt = try #require(transaction.receipt)
            var draft = SavedReceiptEditDraft(receipt: receipt, formatter: formatter)
            draft.merchant = "Edited Cafe"
            let foodIndex = try #require(draft.lines.firstIndex { $0.name == "Food" })
            draft.lines[foodIndex].name = "Edited Food"
            draft.lines[foodIndex].amountText = "10.00"
            let attachment = try draft.attachmentDraft(existingImageData: receipt.imageData, formatter: formatter)
            #expect(try draft.includedAmount(formatter: formatter) == Decimal(string: "13.20"))
            try ReceiptUseCase(context: context).updateReceiptDetails(on: transaction, with: attachment, transactionAmount: Decimal(string: "9.99"), now: now)
            #expect(transaction.amount == Decimal(string: "9.99"))
        }

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let transaction = try #require(try context.fetch(FetchDescriptor<Transaction>()).first { $0.id == transactionID })
            #expect(transaction.receipt?.merchant == "Edited Cafe")
            #expect(transaction.receipt?.lineItems.contains { $0.name == "Edited Food" && $0.amount == Decimal(string: "10.00") } == true)
            var draft = SavedReceiptEditDraft(receipt: try #require(transaction.receipt), formatter: formatter)
            let editedIndex = try #require(draft.lines.firstIndex { $0.name == "Edited Food" })
            draft.lines[editedIndex].amountText = "20.00"
            let attachment = try draft.attachmentDraft(existingImageData: transaction.receipt?.imageData, formatter: formatter)
            try ReceiptUseCase(context: context).updateReceiptDetails(on: transaction, with: attachment, transactionAmount: nil, now: now)
            #expect(transaction.amount == Decimal(string: "9.99"))
        }
    }

    @MainActor
    @Test("Failed saved receipt edit rolls back receipt and transaction")
    func failedSavedReceiptEditRollsBack() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let fixture = TestFixtures.hierarchy()
        fixture.transaction.receipt = nil
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)
        try ReceiptUseCase(context: context).attach(attachmentDraft(merchant: "Rollback Cafe", total: 12), to: fixture.transaction, now: TestFixtures.date)
        let receipt = try #require(fixture.transaction.receipt)
        let originalAmount = fixture.transaction.amount
        let invalid = ReceiptAttachmentDraft(
            imageData: receipt.imageData ?? Data(),
            merchant: "Broken",
            date: nil,
            total: 2,
            lines: [ReceiptLineDraft(rawText: "", name: "Broken", amount: 2, isSelected: true)]
        )

        #expect(throws: Error.self) {
            try ReceiptUseCase(context: context).updateReceiptDetails(on: fixture.transaction, with: invalid, transactionAmount: 2, now: TestFixtures.date)
        }
        #expect(fixture.transaction.amount == originalAmount)
        #expect(fixture.transaction.receipt?.merchant == "Rollback Cafe")
        #expect(fixture.transaction.receipt?.lineItems.count == 2)
    }

    @MainActor
    @Test("Receipt attachment persists reopens replaces removes and cascades")
    func receiptPersistenceLifecycle() throws {
        let storeURL = try temporaryStoreURL()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))!
        let transactionID: UUID

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let fixture = TestFixtures.hierarchy()
            fixture.transaction.receipt = nil
            context.insert(fixture.budget)
            try ModelMutationService.saveValidated(context)
            transactionID = fixture.transaction.id

            let draft = attachmentDraft(merchant: "Cafe Contoh", total: Decimal(string: "12.30")!)
            try ReceiptUseCase(context: context).attach(draft, to: fixture.transaction, now: now)
            #expect(fixture.transaction.receipt?.lineItems.count == 2)
        }

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let transaction = try #require(try context.fetch(FetchDescriptor<Transaction>()).first { $0.id == transactionID })
            #expect(transaction.receipt?.merchant == "Cafe Contoh")
            #expect(transaction.receipt?.lineItems.count == 2)
            try ReceiptUseCase(context: context).replaceReceipt(on: transaction, with: attachmentDraft(merchant: "New Cafe", total: 9), now: now)
            #expect(try context.fetchCount(FetchDescriptor<ReceiptCapture>()) == 1)
            #expect(transaction.receipt?.merchant == "New Cafe")
            try ReceiptUseCase(context: context).removeReceipt(from: transaction, now: now)
            #expect(transaction.receipt == nil)
            #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)

            try ReceiptUseCase(context: context).attach(attachmentDraft(merchant: "Cascade Cafe", total: 7), to: transaction, now: now)
            context.delete(transaction)
            try ModelMutationService.saveValidated(context)
            #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 0)
        }
    }

    @MainActor
    @Test("Transaction deletion removes attached receipt graph in one mutation")
    func transactionDeletionRemovesAttachedReceiptGraph() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let fixture = TestFixtures.hierarchy()
        fixture.transaction.receipt = nil
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)
        try ReceiptUseCase(context: context).attach(attachmentDraft(merchant: "Delete Cafe", total: 7), to: fixture.transaction, now: TestFixtures.date)

        try TransactionUseCase(repository: SwiftDataTransactionRepository(context: context)).delete(fixture.transaction, now: TestFixtures.date)

        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 0)
    }

    @MainActor
    @Test("Failed receipt attachment rolls back without partial graph")
    func failedReceiptAttachmentRollsBack() throws {
        let container = try TestFixtures.container()
        let context = container.mainContext
        let fixture = TestFixtures.hierarchy()
        fixture.transaction.receipt = nil
        context.insert(fixture.budget)
        try ModelMutationService.saveValidated(context)

        let invalid = ReceiptAttachmentDraft(
            imageData: Data([1]),
            merchant: "Invalid",
            date: nil,
            total: 1,
            lines: [ReceiptLineDraft(rawText: "", name: "Blank", amount: 1, isSelected: true)]
        )

        #expect(throws: Error.self) {
            try ReceiptUseCase(context: context).attach(invalid, to: fixture.transaction, now: TestFixtures.date)
        }
        #expect(fixture.transaction.receipt == nil)
        #expect(try context.fetchCount(FetchDescriptor<ReceiptCapture>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 0)
    }

    @MainActor
    @Test("Phase 4 store opens under Phase 5 and preserves recurring rollover and receiptless transactions")
    func phase4StorePreservationAndReceiptAttach() throws {
        let storeURL = try temporaryStoreURL()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 10))!
        let budgetID: UUID
        let transactionID: UUID
        let templateID: UUID
        let sourceID = fixedUUID(40)

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let budget = Budget(id: fixedUUID(1), name: "Phase 4 Budget", createdAt: now, updatedAt: now)
            let plan = BudgetPlan(id: fixedUUID(2), name: "Phase 4 Plan", startingAmount: 100, sortOrder: 0, createdAt: now, updatedAt: now, budget: budget)
            let item = BudgetItem(id: fixedUUID(3), name: "Phase 4 Item", unitAmount: 10, multiplier: 2, sortOrder: 0, sourceItemID: sourceID, createdAt: now, updatedAt: now, budgetPlan: plan)
            let transaction = Transaction(id: fixedUUID(4), name: "Expense", amount: 5, kind: .expense, date: now, notes: "No receipt yet", createdAt: now, updatedAt: now, budgetItem: item)
            let template = RecurringTransactionTemplate(id: fixedUUID(5), name: "Recurring", amount: 6, kind: .expense, frequency: .monthly, interval: 1, startDate: now, nextOccurrence: now, isEnabled: true, createdAt: now, updatedAt: now, budget: budget, destinationBudgetItem: item)
            budgetID = budget.id
            transactionID = transaction.id
            templateID = template.id
            budget.budgetPlans = [plan]
            budget.recurringTemplates = [template]
            plan.budgetItems = [item]
            item.transactions = [transaction]
            item.destinationRecurringTemplates = [template]
            context.insert(budget)
            try ModelMutationService.saveValidated(context)
        }

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            let budget = try #require(try context.fetch(FetchDescriptor<Budget>()).first)
            let transaction = try #require(try context.fetch(FetchDescriptor<Transaction>()).first)
            let template = try #require(try context.fetch(FetchDescriptor<RecurringTransactionTemplate>()).first)
            #expect(budget.id == budgetID)
            #expect(transaction.id == transactionID)
            #expect(transaction.receipt == nil)
            #expect(template.id == templateID)
            #expect(template.destinationBudgetItem?.sourceItemID == sourceID)
            try ReceiptUseCase(context: context).attach(attachmentDraft(merchant: "Upgrade Cafe", total: 12), to: transaction, now: now)
        }

        do {
            let container = try CanISchema.makeContainer(storeURL: storeURL)
            let context = container.mainContext
            #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<BudgetPlan>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<BudgetItem>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<RecurringTransactionTemplate>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<ReceiptCapture>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<ReceiptLineItem>()) == 2)
        }
    }

    @MainActor
    @Test("Receipt search and attachment filters match merchant line names and raw text")
    func receiptSearchAndFilters() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let budget = Budget(name: "Budget", createdAt: now, updatedAt: now)
        let plan = BudgetPlan(name: "Plan", startingAmount: 0, createdAt: now, updatedAt: now, budget: budget)
        let item = BudgetItem(name: "Meals", createdAt: now, updatedAt: now, budgetPlan: plan)
        let withReceipt = Transaction(name: "Expense", amount: 12, kind: .expense, date: now, notes: nil, createdAt: now, updatedAt: now, budgetItem: item)
        let withoutReceipt = Transaction(name: "Expense", amount: 4, kind: .expense, date: now, notes: "Taxi", createdAt: now, updatedAt: now, budgetItem: item)
        let receipt = ReceiptCapture(imageData: Data([1]), merchant: "Kedai Contoh", date: now, total: 12, createdAt: now, updatedAt: now, transaction: withReceipt)
        let line = ReceiptLineItem(rawText: "Nasi Lemak RM 8.50", name: "Nasi Lemak", amount: Decimal(string: "8.50")!, isSelected: true, createdAt: now, updatedAt: now, receiptCapture: receipt)
        budget.budgetPlans = [plan]
        plan.budgetItems = [item]
        item.transactions = [withReceipt, withoutReceipt]
        withReceipt.receipt = receipt
        receipt.lineItems = [line]

        let service = TransactionQueryService(calendar: calendar, locale: Locale(identifier: "en_US"), asOf: now)
        #expect(try service.results(for: [budget], query: service.query(from: .empty, submittedSearchText: "kedai", formatter: formatter)).map(\.id) == [withReceipt.id])
        #expect(try service.results(for: [budget], query: service.query(from: .empty, submittedSearchText: "lemak", formatter: formatter)).map(\.id) == [withReceipt.id])

        var draft = TransactionFilterDraft.empty
        draft.receiptCriterion = .hasReceipt
        #expect(try service.results(for: [budget], query: service.query(from: draft, submittedSearchText: "", formatter: formatter)).map(\.id) == [withReceipt.id])
        draft.receiptCriterion = .noReceipt
        #expect(try service.results(for: [budget], query: service.query(from: draft, submittedSearchText: "", formatter: formatter)).map(\.id) == [withoutReceipt.id])
    }

    @MainActor
    @Test("Incompatible store remains untouched and no empty replacement appears")
    func incompatibleStorePreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CanI.sqlite")
        let walURL = directory.appendingPathComponent("CanI.sqlite-wal")
        let shmURL = directory.appendingPathComponent("CanI.sqlite-shm")
        let storeData = Data("not phase 5 compatible".utf8)
        let walData = Data("wal".utf8)
        let shmData = Data("shm".utf8)
        try storeData.write(to: storeURL)
        try walData.write(to: walURL)
        try shmData.write(to: shmURL)

        #expect(throws: Error.self) {
            _ = try CanISchema.makeContainer(storeURL: storeURL)
        }
        #expect(try Data(contentsOf: storeURL) == storeData)
        #expect(try Data(contentsOf: walURL) == walData)
        #expect(try Data(contentsOf: shmURL) == shmData)
    }

    @Test("Image normalization caps dimensions and produces JPEG data")
    func imageNormalizationPolicy() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 1_200)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_200))
            UIColor.black.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 300, height: 100))
        }
        let data = try ReceiptImageProcessor(policy: ReceiptImagePolicy(maximumDimension: 600, jpegCompressionQuality: 0.7)).normalizedJPEGData(from: image, rotation: .clockwise, crop: CGRect(x: 0, y: 0, width: 1, height: 1))
        let normalized = try #require(UIImage(data: data))
        #expect(max(normalized.size.width, normalized.size.height) <= 600)
    }

    @Test("OCR representation preserves more receipt resolution than stored image")
    func ocrRepresentationUsesLargerBoundedImage() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4_000, height: 1_200)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4_000, height: 1_200))
            UIColor.black.setFill()
            context.fill(CGRect(x: 100, y: 100, width: 300, height: 100))
        }

        let storedData = try ReceiptImageProcessor(policy: .production).normalizedJPEGData(from: image)
        let ocrData = try ReceiptImageProcessor(policy: .ocr).normalizedJPEGData(from: image)
        let stored = try #require(UIImage(data: storedData))
        let ocr = try #require(UIImage(data: ocrData))
        #expect(max(stored.size.width, stored.size.height) <= 1_600)
        #expect(max(ocr.size.width, ocr.size.height) <= 3_000)
        #expect(max(ocr.size.width, ocr.size.height) > max(stored.size.width, stored.size.height))
    }

    @Test("Document camera OCR policy preserves higher resolution for long narrow receipts")
    func documentCameraOCRPolicyPreservesLongNarrowReceipts() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 6_000)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 6_000))
            for row in 0..<60 {
                let y = 80 + row * 90
                "Synthetic Item \(row)".draw(in: CGRect(x: 80, y: y, width: 480, height: 42), withAttributes: [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.black])
                "9.90".draw(in: CGRect(x: 680, y: y, width: 120, height: 42), withAttributes: [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.black])
            }
        }

        let stored = try #require(UIImage(data: try ReceiptImageProcessor().normalizedJPEGData(from: image)))
        let ocr = try #require(UIImage(data: try ReceiptImageProcessor(policy: .ocr).normalizedJPEGData(from: image)))

        #expect(ocr.size.height == 3_000)
        #expect(ocr.size.width > stored.size.width)
    }

    @Test("Files import processor loads images renders selected PDF pages and rejects invalid pages")
    func fileImportProcessorLoadsImagesAndPDFs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let processor = ReceiptFileImportProcessor(temporaryDirectory: directory, maximumPDFRenderDimension: 900)
        let imageData = try #require(syntheticReceiptImage().pngData())
        let sourceURL = directory.appendingPathComponent("source.png")
        try imageData.write(to: sourceURL)

        let copiedURL = try processor.copyIntoTemporaryStorage(from: sourceURL)
        #expect(copiedURL != sourceURL)
        #expect(FileManager.default.fileExists(atPath: copiedURL.path))
        #expect(try processor.image(from: try Data(contentsOf: copiedURL)).size.width > 0)

        let pdf = try processor.pdfImport(from: syntheticReceiptPDFData(pageCount: 2))
        #expect(pdf.pageCount == 2)
        let rendered = try processor.renderedImage(from: pdf, pageIndex: 1)
        #expect(max(rendered.size.width, rendered.size.height) <= 900)
        #expect(throws: Phase5ValidationError.invalidReceiptPDFPage) {
            _ = try processor.renderedImage(from: pdf, pageIndex: 2)
        }
        #expect(throws: Phase5ValidationError.receiptFileUnreadable) {
            _ = try processor.pdfImport(from: Data("not a pdf".utf8))
        }
    }

    @Test("Fake scanner propagates cancellation and errors")
    func fakeScannerCancellationAndErrors() async throws {
        let cancellable = FakeReceiptScanningService(
            result: ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US")).parse(lines: ["TOTAL RM 1.00"]),
            delayNanoseconds: 1_000_000_000
        )
        let task = Task {
            try await cancellable.scan(imageData: Data([1]))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        let failing = FakeReceiptScanningService(
            result: ReceiptParser(calendar: calendar, locale: Locale(identifier: "en_US")).parse(lines: []),
            error: Phase5ValidationError.scanningFailed
        )
        await #expect(throws: Phase5ValidationError.scanningFailed) {
            _ = try await failing.scan(imageData: Data([1]))
        }
    }

    @Test("Shared receipt inbox writes atomic metadata stores data rejects unsupported content and cleans temporary files")
    func sharedReceiptInboxService() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = SharedReceiptInboxService(inboxURL: directory, maximumBytes: 32)
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
        let id = fixedUUID(80)

        let record = try await service.savePendingReceipt(data: Data([1, 2, 3]), originalExtension: "png", contentType: "public.png", now: now, id: id)
        #expect(record.version == 1)
        #expect(record.id == id)
        #expect(record.filename == "\(id.uuidString).png")
        #expect(try await service.pendingReceipts() == [record])
        #expect(try await service.data(for: record) == Data([1, 2, 3]))

        try Data([9]).write(to: directory.appendingPathComponent("abandoned.tmp"))
        try await service.cleanupIncompleteTemporaryFiles()
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("abandoned.tmp").path))

        await #expect(throws: SharedReceiptInboxError.unsupportedType) {
            _ = try await service.savePendingReceipt(data: Data([1]), originalExtension: "txt", contentType: "text/plain")
        }
        await #expect(throws: SharedReceiptInboxError.oversized) {
            _ = try await service.savePendingReceipt(data: Data(repeating: 1, count: 33), originalExtension: "png", contentType: "public.png")
        }

        try await service.delete(record)
        #expect(try await service.pendingReceipts().isEmpty)
    }

    @Test("Quick add routes encode no financial values and suppress duplicate handling")
    func quickAddRoutes() throws {
        let destinationID = fixedUUID(81)
        let expense = QuickAddRoute(action: .addExpense, destinationID: destinationID)
        let scan = QuickAddRoute(action: .scanReceipt)

        #expect(expense.url.absoluteString.contains("action=addExpense"))
        #expect(!expense.url.absoluteString.localizedCaseInsensitiveContains("amount"))
        #expect(!expense.url.absoluteString.localizedCaseInsensitiveContains("salary"))
        #expect(QuickAddRoute(url: expense.url) == expense)
        #expect(QuickAddRoute(url: scan.url) == scan)
        #expect(QuickAddRoute(url: URL(string: "cani://quick-add?action=scanReceipt&destination=not-a-uuid")!) == nil)

        var router = QuickAddRouteRouter()
        #expect(router.command(for: expense) == .addExpense(destinationID: destinationID))
        #expect(router.command(for: expense) == nil)
        #expect(router.command(for: scan) == .scanReceipt(destinationID: nil))
    }

    @Test("Widget destination snapshot writes renamed Items and omits deleted destinations without SwiftData access")
    func widgetDestinationSnapshotStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = WidgetDestinationSnapshotStore(snapshotURL: directory.appendingPathComponent("destinations.json"))
        let itemID = fixedUUID(82)
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 13))!
        try store.write(WidgetDestinationSnapshot(updatedAt: now, items: [
            WidgetDestinationSnapshot.Item(id: itemID, name: "Meals", planName: "August")
        ]))
        #expect(try store.read()?.items.map(\.name) == ["Meals"])

        try store.write(WidgetDestinationSnapshot(updatedAt: now.addingTimeInterval(60), items: [
            WidgetDestinationSnapshot.Item(id: itemID, name: "Food", planName: "August")
        ]))
        #expect(try store.read()?.items.map(\.name) == ["Food"])

        try store.write(WidgetDestinationSnapshot(updatedAt: now.addingTimeInterval(120), items: []))
        #expect(try store.read()?.items.isEmpty == true)
    }

    private func attachmentDraft(merchant: String, total: Decimal) -> ReceiptAttachmentDraft {
        ReceiptAttachmentDraft(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            merchant: merchant,
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)),
            total: total,
            lines: [
                ReceiptLineDraft(rawText: "Food RM 8.50", name: "Food", amount: Decimal(string: "8.50"), isSelected: true),
                ReceiptLineDraft(rawText: "Tea RM 3.20", name: "Tea", amount: Decimal(string: "3.20"), isSelected: true)
            ]
        )
    }

    private func chargeReview() -> ReceiptReviewDraft {
        var review = ReceiptReviewDraft(
            scanResult: ReceiptScanResult(
                imageData: Data([1]),
                recognizedLines: [],
                merchantCandidate: "Charge Cafe",
                dateCandidates: [],
                hasAmbiguousDate: false,
                totalCandidates: [Decimal(string: "12.30")!],
                lineItemCandidates: [
                    ReceiptLineSuggestion(rawText: "Food RM 8.50", name: "Food", amount: Decimal(string: "8.50")!, isSelected: true),
                    ReceiptLineSuggestion(rawText: "Tea RM 3.20", name: "Tea", amount: Decimal(string: "3.20")!, isSelected: true)
                ],
                chargeCandidates: [
                    ReceiptChargeSuggestion(rawText: "Tax RM 1.20", name: "Tax", originalAmount: Decimal(string: "1.20")!, kind: .tax),
                    ReceiptChargeSuggestion(rawText: "Service Charge RM 0.60", name: "Service Charge", originalAmount: Decimal(string: "0.60")!, kind: .serviceCharge),
                    ReceiptChargeSuggestion(rawText: "Surcharge RM 1.00", name: "Surcharge", originalAmount: Decimal(string: "1.00")!, kind: .surcharge),
                    ReceiptChargeSuggestion(rawText: "Delivery Fee RM 1.00", name: "Delivery Fee", originalAmount: Decimal(string: "1.00")!, kind: .deliveryFee)
                ],
                warnings: []
            ),
            formatter: formatter
        )
        review.percentageTipText = ""
        review.additionalTipText = ""
        return review
    }

    private func syntheticReceiptImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 480)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
            "Kedai Fail\nTOTAL RM 9.90".draw(
                in: CGRect(x: 24, y: 24, width: 272, height: 420),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black]
            )
        }
    }

    private func syntheticReceiptPDFData(pageCount: Int) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for page in 1...pageCount {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
                "PDF Receipt Page \(page)\nTOTAL RM 9.90".draw(
                    in: CGRect(x: 48, y: 48, width: 516, height: 696),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black]
                )
            }
        }
    }

    private func observation(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat = 0.035,
        order: Int = 0
    ) -> RecognizedReceiptObservation {
        RecognizedReceiptObservation(
            text: text,
            normalizedBoundingBox: CGRect(x: x, y: y, width: width, height: height),
            confidence: 0.95,
            alternative: nil,
            pageIndex: 0,
            readingOrder: order
        )
    }

    private func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("CanI.sqlite")
    }

    private func fixedUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (value, value, value, value, value, value, value, value, value, value, value, value, value, value, value, value))
    }
}
