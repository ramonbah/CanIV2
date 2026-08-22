//
//  Phase2Support.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import SwiftData

protocol AppClock {
    var now: Date { get }
    var calendar: Calendar { get }
}

protocol LocalDayRefreshCancellable {
    @MainActor
    func cancel()
}

protocol LocalDayRefreshScheduler {
    @MainActor
    func schedule(at boundary: Date, clock: AppClock, action: @escaping @MainActor () -> Void) -> LocalDayRefreshCancellable
}

struct TaskLocalDayRefreshScheduler: LocalDayRefreshScheduler {
    @MainActor
    func schedule(at boundary: Date, clock: AppClock, action: @escaping @MainActor () -> Void) -> LocalDayRefreshCancellable {
        let interval = max(0, boundary.timeIntervalSince(clock.now))
        let task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
            if !Task.isCancelled {
                action()
            }
        }
        return TaskLocalDayRefreshCancellation(task: task)
    }
}

private struct TaskLocalDayRefreshCancellation: LocalDayRefreshCancellable {
    let task: Task<Void, Never>

    @MainActor
    func cancel() {
        task.cancel()
    }
}

struct SystemClock: AppClock {
    var now: Date { Date() }
    var calendar: Calendar { .autoupdatingCurrent }
}

struct FixedClock: AppClock {
    let now: Date
    var calendar: Calendar
}

enum NameNormalizer {
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func key(_ value: String) -> String {
        trimmed(value).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func isDuplicate(_ value: String, among names: [String]) -> Bool {
        let target = key(value)
        return names.contains { key($0) == target }
    }
}

enum CurrencyCatalog {
    struct Currency: Identifiable, Hashable {
        var id: String { code }
        let code: String
        let name: String
        let minorUnits: Int
    }

    static let currencies: [Currency] = Locale.commonISOCurrencyCodes
        .map { code in
            Currency(
                code: code.uppercased(),
                name: Locale.current.localizedString(forCurrencyCode: code) ?? code.uppercased(),
                minorUnits: minorUnits(for: code)
            )
        }
        .sorted { lhs, rhs in lhs.code < rhs.code }

    static func currency(for code: String) -> Currency {
        currencies.first { $0.code == code.uppercased() } ?? Currency(code: code.uppercased(), name: code.uppercased(), minorUnits: 2)
    }

    static func suggestedCurrencyCode(locale: Locale = .autoupdatingCurrent) -> String {
        if let override = ProcessInfo.processInfo.environment["UI_TESTING_CURRENCY_CODE"]?.uppercased(), CurrencyCode.supported.contains(override) {
            return override
        }
        if let code = locale.currency?.identifier.uppercased(), CurrencyCode.supported.contains(code) {
            return code
        }
        return "USD"
    }

    static func minorUnits(for code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.uppercased()
        return formatter.maximumFractionDigits
    }
}

struct CurrencyFormatter {
    let currencyCode: String
    var locale: Locale = .autoupdatingCurrent

    var minorUnits: Int {
        CurrencyCatalog.currency(for: currencyCode).minorUnits
    }

    func string(for amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        formatter.minimumFractionDigits = minorUnits
        formatter.maximumFractionDigits = minorUnits
        formatter.generatesDecimalNumbers = true
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currencyCode) \(amount)"
    }

    func parse(_ text: String) -> Decimal? {
        LocalizedNumericEditingPolicy(locale: locale).completeDecimal(from: text)
    }

    func hasValidMinorUnits(_ text: String) -> Bool {
        LocalizedNumericEditingPolicy(locale: locale).hasValidFractionDigits(text, maximum: minorUnits)
    }

    func roundedForDisplay(_ amount: Decimal) -> Decimal {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, minorUnits, .bankers)
        return result
    }

    func displayMismatch(components: [Decimal], total: Decimal) -> RoundingDisclosure? {
        let displayedComponentTotal = components.reduce(Decimal(0)) { $0 + roundedForDisplay($1) }
        let displayedTotal = roundedForDisplay(total)
        guard displayedComponentTotal != displayedTotal else { return nil }
        return RoundingDisclosure(
            displayedComponentsTotal: displayedComponentTotal,
            displayedTotal: displayedTotal,
            exactTotal: total,
            currencyCode: currencyCode,
            standardMinorUnits: minorUnits
        )
    }
}

enum NumericEditKind {
    case decimal
    case wholeNumber
}

struct NumericEditValidation: Equatable {
    let isAcceptedEdit: Bool
    let isCompleteNumber: Bool
    let decimal: Decimal?
    let error: String?
}

struct LocalizedNumericEditingPolicy {
    var locale: Locale
    var kind: NumericEditKind = .decimal

    private var decimalSeparator: String {
        locale.decimalSeparator ?? "."
    }

    private var groupingSeparator: String {
        locale.groupingSeparator ?? ","
    }

    func validateEdit(_ proposedText: String) -> NumericEditValidation {
        guard proposedText == proposedText.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return rejected()
        }
        let text = proposedText
        guard !text.isEmpty else {
            return NumericEditValidation(isAcceptedEdit: true, isCompleteNumber: false, decimal: nil, error: nil)
        }
        guard !containsInvalidCharacter(text) else {
            return rejected()
        }
        guard kind == .decimal || !text.contains(decimalSeparator) else {
            return rejected()
        }
        guard text.components(separatedBy: decimalSeparator).count <= 2 else {
            return rejected()
        }

        let hasTrailingDecimal = kind == .decimal && text.hasSuffix(decimalSeparator)
        let parts = text.components(separatedBy: decimalSeparator)
        let integerPart = parts[0]
        let fractionPart = parts.count == 2 ? parts[1] : nil

        guard isValidIntegerPart(integerPart), fractionPart?.allSatisfy(\.isWholeNumber) ?? true else {
            return rejected()
        }
        if hasTrailingDecimal {
            return NumericEditValidation(isAcceptedEdit: true, isCompleteNumber: false, decimal: completeDecimal(from: String(text.dropLast(decimalSeparator.count))), error: nil)
        }
        guard let decimal = completeDecimal(from: text) else {
            return rejected()
        }
        if kind == .wholeNumber, decimal != Decimal(Int(truncating: decimal as NSDecimalNumber)) {
            return rejected()
        }
        return NumericEditValidation(isAcceptedEdit: true, isCompleteNumber: true, decimal: decimal, error: nil)
    }

    func completeDecimal(from text: String) -> Decimal? {
        guard text == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let validationText = text
        let validation = validateEditWithoutParsing(validationText)
        guard validation, !validationText.isEmpty, !validationText.hasSuffix(decimalSeparator) else { return nil }
        let normalized = validationText
            .replacingOccurrences(of: groupingSeparator, with: "")
            .replacingOccurrences(of: decimalSeparator, with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    func hasValidFractionDigits(_ text: String, maximum: Int) -> Bool {
        guard text == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let trimmed = text
        guard validateEditWithoutParsing(trimmed), !trimmed.isEmpty, !trimmed.hasSuffix(decimalSeparator) else { return false }
        let parts = trimmed.components(separatedBy: decimalSeparator)
        guard parts.count <= 2 else { return false }
        return parts.count == 1 || parts[1].count <= maximum
    }

    func editableString(for decimal: Decimal) -> String {
        let number = decimal as NSDecimalNumber
        var plain = number.stringValue
        if decimalSeparator != "." {
            plain = plain.replacingOccurrences(of: ".", with: decimalSeparator)
        }
        return plain
    }

    private func validateEditWithoutParsing(_ text: String) -> Bool {
        guard !text.isEmpty, !containsInvalidCharacter(text) else { return false }
        guard kind == .decimal || !text.contains(decimalSeparator) else { return false }
        let parts = text.components(separatedBy: decimalSeparator)
        guard parts.count <= 2 else { return false }
        guard isValidIntegerPart(parts[0]) else { return false }
        return parts.count == 1 || parts[1].allSatisfy(\.isWholeNumber)
    }

    private func containsInvalidCharacter(_ text: String) -> Bool {
        let allowedScalars = CharacterSet.decimalDigits
            .union(CharacterSet(charactersIn: decimalSeparator))
            .union(CharacterSet(charactersIn: groupingSeparator))
        return text.unicodeScalars.contains { !allowedScalars.contains($0) }
    }

    private func isValidIntegerPart(_ integerPart: String) -> Bool {
        guard !integerPart.isEmpty else { return false }
        if integerPart.contains(groupingSeparator) {
            let groups = integerPart.components(separatedBy: groupingSeparator)
            guard let first = groups.first, (1...3).contains(first.count), first.allSatisfy(\.isWholeNumber) else {
                return false
            }
            return groups.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isWholeNumber) }
        }
        return integerPart.allSatisfy(\.isWholeNumber)
    }

    private func rejected() -> NumericEditValidation {
        NumericEditValidation(
            isAcceptedEdit: false,
            isCompleteNumber: false,
            decimal: nil,
            error: "Use numbers only, with valid separators for your locale."
        )
    }
}

struct TransactionDaySection: Identifiable {
    let day: Date
    let header: String
    let transactions: [Transaction]

    var id: Date { day }
}

struct TransactionDayGrouper {
    var calendar: Calendar
    var locale: Locale
    var now: Date

    func sections(for transactions: [Transaction]) -> [TransactionDaySection] {
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            let entries = (grouped[day] ?? []).sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            return TransactionDaySection(day: day, header: header(for: day), transactions: entries)
        }
    }

    func header(for day: Date) -> String {
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = locale
        weekdayFormatter.calendar = calendar
        weekdayFormatter.timeZone = calendar.timeZone
        weekdayFormatter.dateFormat = "EEEE"
        let weekday = weekdayFormatter.string(from: day)
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today · \(weekday)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday · \(weekday)"
        }
        let date = UserVisibleDateFormatter(calendar: calendar, locale: locale, referenceDate: now).string(for: day)
        return "\(weekday), \(date)"
    }
}

struct UserVisibleDateFormatter {
    var calendar: Calendar
    var locale: Locale
    var referenceDate: Date

    func string(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = isCurrentLocalYear(date) ? "d MMM" : "d MMM y"
        return formatter.string(from: date)
    }

    func rangeDescription(title: String, start: Date?, end: Date) -> String {
        guard let start else {
            return "\(title), through \(string(for: end))"
        }
        return "\(title), \(string(for: start)) to \(string(for: end))"
    }

    private func isCurrentLocalYear(_ date: Date) -> Bool {
        calendar.component(.year, from: date) == calendar.component(.year, from: referenceDate)
    }
}

struct BudgetNavigationSelection: Equatable {
    var budgetID: UUID?
    var planID: UUID?
    var itemID: UUID?
    var report: BudgetReportNavigationSelection?

    mutating func selectBudget(_ id: UUID?) {
        budgetID = id
        planID = nil
        itemID = nil
        report = nil
    }

    mutating func selectPlan(_ id: UUID?) {
        planID = id
        itemID = nil
        report = nil
    }

    mutating func selectItem(_ id: UUID?) {
        itemID = id
        report = nil
    }
}

enum BudgetReportNavigationSelection: Equatable {
    case budget(UUID)
    case plan(UUID)
}

struct RoundingDisclosure: Equatable {
    let displayedComponentsTotal: Decimal
    let displayedTotal: Decimal
    let exactTotal: Decimal
    let currencyCode: String
    let standardMinorUnits: Int

    var explanation: String {
        "Stored amounts include more precision than this currency displays, so rounded line values may not add up exactly to the rounded total."
    }

    var exactTotalDescription: String {
        "\(currencyCode) \(decimalString(exactTotal, fractionDigits: neededFractionDigits))"
    }

    private var neededFractionDigits: Int {
        let standard = rounded(exactTotal, fractionDigits: standardMinorUnits)
        for digits in (standardMinorUnits + 1)...8 {
            if rounded(exactTotal, fractionDigits: digits) != standard {
                return digits
            }
        }
        return min(standardMinorUnits + 1, 8)
    }

    private func rounded(_ value: Decimal, fractionDigits: Int) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, fractionDigits, .bankers)
        return result
    }

    private func decimalString(_ value: Decimal, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.generatesDecimalNumbers = true
        return formatter.string(from: value as NSDecimalNumber) ?? NSDecimalNumber(decimal: value).stringValue
    }
}

struct ItemTotals: Equatable {
    let planned: Decimal
    let effectiveIncome: Decimal
    let scheduledIncome: Decimal
    let expenses: Decimal

    var available: Decimal { planned + effectiveIncome }
    var remaining: Decimal { available - expenses }
}

struct ItemAllocationPreview: Equatable {
    let planAvailableFunds: Decimal
    let otherAllocated: Decimal
    let draftAllocation: Decimal
    let projectedUnallocated: Decimal

    var isOverallocated: Bool { projectedUnallocated < 0 }
}

struct TransactionProjection: Equatable {
    let itemAfter: Decimal
    let planAfter: Decimal
    let scheduledIncomeAmount: Decimal

    var hasScheduledIncome: Bool { scheduledIncomeAmount > 0 }
}

struct ItemRowPresentation: Equatable {
    enum Style: Equatable {
        case available
        case spent
        case overspent
        case income
    }

    let style: Style
    let planned: Decimal
    let effectiveIncome: Decimal
    let scheduledIncome: Decimal
    let spent: Decimal
    let remaining: Decimal
    let overspent: Decimal

    var canMarkAsSpent: Bool {
        style == .available && remaining > 0
    }
}

struct MarkAsSpentPreview: Equatable {
    let isEligible: Bool
    let amount: Decimal
}

enum BudgetItemClassification: String, CaseIterable, Identifiable {
    case available
    case spent
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: "Available"
        case .spent: "Spent"
        case .income: "Income"
        }
    }
}

struct PlanTotals: Equatable {
    let planned: Decimal
    let effectiveIncome: Decimal
    let scheduledIncome: Decimal
    let expenses: Decimal
    let startingAmount: Decimal

    var totalFundsReceived: Decimal { startingAmount + effectiveIncome }
    var unallocated: Decimal { totalFundsReceived - planned }
    var currentBalance: Decimal { totalFundsReceived - expenses }
}

struct BudgetTotals: Equatable {
    let planned: Decimal
    let effectiveIncome: Decimal
    let scheduledIncome: Decimal
    let expenses: Decimal
    let totalFundsReceived: Decimal
    let currentBalance: Decimal
}

struct ProgressState: Equatable {
    let fraction: Decimal
    let label: String
    let isWarning: Bool

    var cappedFraction: Double {
        let decimal = min(max(fraction, 0), 1)
        return NSDecimalNumber(decimal: decimal).doubleValue
    }
}

enum Phase2Calculations {
    static func isEffective(_ transaction: Transaction, asOf date: Date, calendar: Calendar) -> Bool {
        transaction.kind == .expense || !calendar.startOfDay(for: transaction.date).compare(calendar.startOfDay(for: date)).isAfter
    }

    static func itemTotals(for item: BudgetItem, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> ItemTotals {
        let planned = item.unitAmount * item.multiplier
        let effectiveIncome = item.transactions
            .filter { $0.kind == .income && isEffective($0, asOf: date, calendar: calendar) }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let scheduledIncome = item.transactions
            .filter { $0.kind == .income && !isEffective($0, asOf: date, calendar: calendar) }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let expenses = item.transactions
            .filter { $0.kind == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return ItemTotals(planned: planned, effectiveIncome: effectiveIncome, scheduledIncome: scheduledIncome, expenses: expenses)
    }

    static func isIncomeOnly(_ item: BudgetItem) -> Bool {
        !item.transactions.isEmpty && item.transactions.allSatisfy { $0.kind == .income }
    }

    static func allocatedPlannedAmount(for item: BudgetItem) -> Decimal {
        isIncomeOnly(item) ? 0 : item.unitAmount * item.multiplier
    }

    static func allocationPreview(
        for plan: BudgetPlan,
        editing editedItem: BudgetItem?,
        draftUnitAmount: Decimal,
        draftMultiplier: Decimal,
        asOf date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> ItemAllocationPreview {
        let totals = planTotals(for: plan, asOf: date, calendar: calendar)
        let editedID = editedItem?.id
        let otherAllocated = plan.budgetItems.reduce(Decimal(0)) { result, item in
            guard item.id != editedID else { return result }
            return result + allocatedPlannedAmount(for: item)
        }
        let draftAllocation: Decimal
        if let editedItem, isIncomeOnly(editedItem) {
            draftAllocation = 0
        } else {
            draftAllocation = draftUnitAmount * draftMultiplier
        }
        let projectedUnallocated = totals.totalFundsReceived - otherAllocated - draftAllocation
        return ItemAllocationPreview(
            planAvailableFunds: totals.totalFundsReceived,
            otherAllocated: otherAllocated,
            draftAllocation: draftAllocation,
            projectedUnallocated: projectedUnallocated
        )
    }

    static func transactionProjection(
        in plan: BudgetPlan,
        destination item: BudgetItem,
        editing transaction: Transaction?,
        draftKind: TransactionKind,
        draftAmount: Decimal,
        draftDate: Date,
        asOf date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> TransactionProjection {
        var itemTotals = itemTotals(for: item, asOf: date, calendar: calendar)
        var planTotals = planTotals(for: plan, asOf: date, calendar: calendar)
        if let transaction {
            let originalIsEffective = isEffective(transaction, asOf: date, calendar: calendar)
            switch transaction.kind {
            case .expense:
                if transaction.budgetItem.id == item.id {
                    itemTotals = ItemTotals(planned: itemTotals.planned, effectiveIncome: itemTotals.effectiveIncome, scheduledIncome: itemTotals.scheduledIncome, expenses: itemTotals.expenses - transaction.amount)
                }
                planTotals = PlanTotals(planned: planTotals.planned, effectiveIncome: planTotals.effectiveIncome, scheduledIncome: planTotals.scheduledIncome, expenses: planTotals.expenses - transaction.amount, startingAmount: planTotals.startingAmount)
            case .income:
                if originalIsEffective {
                    if transaction.budgetItem.id == item.id {
                        itemTotals = ItemTotals(planned: itemTotals.planned, effectiveIncome: itemTotals.effectiveIncome - transaction.amount, scheduledIncome: itemTotals.scheduledIncome, expenses: itemTotals.expenses)
                    }
                    planTotals = PlanTotals(planned: planTotals.planned, effectiveIncome: planTotals.effectiveIncome - transaction.amount, scheduledIncome: planTotals.scheduledIncome, expenses: planTotals.expenses, startingAmount: planTotals.startingAmount)
                } else {
                    if transaction.budgetItem.id == item.id {
                        itemTotals = ItemTotals(planned: itemTotals.planned, effectiveIncome: itemTotals.effectiveIncome, scheduledIncome: itemTotals.scheduledIncome - transaction.amount, expenses: itemTotals.expenses)
                    }
                    planTotals = PlanTotals(planned: planTotals.planned, effectiveIncome: planTotals.effectiveIncome, scheduledIncome: planTotals.scheduledIncome - transaction.amount, expenses: planTotals.expenses, startingAmount: planTotals.startingAmount)
                }
            }
        }

        let draftIsEffective = draftKind == .expense || !calendar.startOfDay(for: draftDate).compare(calendar.startOfDay(for: date)).isAfter
        var scheduledIncome = Decimal(0)
        switch draftKind {
        case .expense:
            itemTotals = ItemTotals(planned: itemTotals.planned, effectiveIncome: itemTotals.effectiveIncome, scheduledIncome: itemTotals.scheduledIncome, expenses: itemTotals.expenses + draftAmount)
            planTotals = PlanTotals(planned: planTotals.planned, effectiveIncome: planTotals.effectiveIncome, scheduledIncome: planTotals.scheduledIncome, expenses: planTotals.expenses + draftAmount, startingAmount: planTotals.startingAmount)
        case .income:
            if draftIsEffective {
                itemTotals = ItemTotals(planned: itemTotals.planned, effectiveIncome: itemTotals.effectiveIncome + draftAmount, scheduledIncome: itemTotals.scheduledIncome, expenses: itemTotals.expenses)
                planTotals = PlanTotals(planned: planTotals.planned, effectiveIncome: planTotals.effectiveIncome + draftAmount, scheduledIncome: planTotals.scheduledIncome, expenses: planTotals.expenses, startingAmount: planTotals.startingAmount)
            } else {
                scheduledIncome = draftAmount
            }
        }
        return TransactionProjection(itemAfter: itemTotals.remaining, planAfter: planTotals.currentBalance, scheduledIncomeAmount: scheduledIncome)
    }

    static func newItemTransactionProjection(
        in plan: BudgetPlan,
        draftKind: TransactionKind,
        draftAmount: Decimal,
        draftDate: Date,
        asOf date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> TransactionProjection {
        let planTotals = planTotals(for: plan, asOf: date, calendar: calendar)
        let draftIsEffective = draftKind == .expense || !calendar.startOfDay(for: draftDate).compare(calendar.startOfDay(for: date)).isAfter
        switch draftKind {
        case .expense:
            return TransactionProjection(itemAfter: 0, planAfter: planTotals.currentBalance - draftAmount, scheduledIncomeAmount: 0)
        case .income:
            if draftIsEffective {
                return TransactionProjection(itemAfter: draftAmount * 2, planAfter: planTotals.currentBalance + draftAmount, scheduledIncomeAmount: 0)
            }
            return TransactionProjection(itemAfter: draftAmount, planAfter: planTotals.currentBalance, scheduledIncomeAmount: draftAmount)
        }
    }

    static func itemClassification(for item: BudgetItem, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> BudgetItemClassification {
        if isIncomeOnly(item) {
            return .income
        }
        let totals = itemTotals(for: item, asOf: date, calendar: calendar)
        if totals.expenses > 0, totals.expenses >= totals.available {
            return .spent
        }
        return .available
    }

    static func itemRowPresentation(for item: BudgetItem, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> ItemRowPresentation {
        let totals = itemTotals(for: item, asOf: date, calendar: calendar)
        if isIncomeOnly(item) {
            return ItemRowPresentation(style: .income, planned: totals.planned, effectiveIncome: totals.effectiveIncome, scheduledIncome: totals.scheduledIncome, spent: totals.expenses, remaining: totals.remaining, overspent: 0)
        }
        if totals.expenses >= totals.available, totals.expenses > 0 {
            let overspent = max(totals.expenses - totals.available, 0)
            return ItemRowPresentation(style: overspent > 0 ? .overspent : .spent, planned: totals.planned, effectiveIncome: totals.effectiveIncome, scheduledIncome: totals.scheduledIncome, spent: totals.expenses, remaining: totals.remaining, overspent: overspent)
        }
        return ItemRowPresentation(style: .available, planned: totals.planned, effectiveIncome: totals.effectiveIncome, scheduledIncome: totals.scheduledIncome, spent: totals.expenses, remaining: totals.remaining, overspent: 0)
    }

    static func markAsSpentPreview(for item: BudgetItem, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> MarkAsSpentPreview {
        let presentation = itemRowPresentation(for: item, asOf: date, calendar: calendar)
        return MarkAsSpentPreview(isEligible: presentation.canMarkAsSpent, amount: max(presentation.remaining, 0))
    }

    static func planTotals(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> PlanTotals {
        let itemSnapshots = plan.budgetItems.map { itemTotals(for: $0, asOf: date, calendar: calendar) }
        return PlanTotals(
            planned: itemSnapshots.reduce(0) { $0 + $1.planned },
            effectiveIncome: itemSnapshots.reduce(0) { $0 + $1.effectiveIncome },
            scheduledIncome: itemSnapshots.reduce(0) { $0 + $1.scheduledIncome },
            expenses: itemSnapshots.reduce(0) { $0 + $1.expenses },
            startingAmount: plan.startingAmount
        )
    }

    static func budgetTotals(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> BudgetTotals {
        let planSnapshots = budget.budgetPlans.map { planTotals(for: $0, asOf: date, calendar: calendar) }
        return BudgetTotals(
            planned: planSnapshots.reduce(0) { $0 + $1.planned },
            effectiveIncome: planSnapshots.reduce(0) { $0 + $1.effectiveIncome },
            scheduledIncome: planSnapshots.reduce(0) { $0 + $1.scheduledIncome },
            expenses: planSnapshots.reduce(0) { $0 + $1.expenses },
            totalFundsReceived: planSnapshots.reduce(0) { $0 + $1.totalFundsReceived },
            currentBalance: planSnapshots.reduce(0) { $0 + $1.currentBalance }
        )
    }

    static func progress(spent: Decimal, funds: Decimal, formatter: CurrencyFormatter) -> ProgressState {
        if funds == 0, spent == 0 {
            return ProgressState(fraction: 0, label: "Not funded", isWarning: false)
        }
        if funds == 0, spent > 0 {
            return ProgressState(fraction: 1, label: "Not funded · \(formatter.string(for: spent)) spent", isWarning: true)
        }
        let fraction = spent / funds
        if fraction > 1 {
            return ProgressState(fraction: 1, label: "Overspent by \(formatter.string(for: spent - funds))", isWarning: true)
        }
        let percent = NSDecimalNumber(decimal: fraction * 100).rounding(accordingToBehavior: nil).intValue
        return ProgressState(fraction: fraction, label: "\(percent)% · \(formatter.string(for: spent)) of \(formatter.string(for: funds))", isWarning: false)
    }
}

private extension ComparisonResult {
    var isAfter: Bool { self == .orderedDescending }
}

enum PlanSortMode: String, CaseIterable, Identifiable {
    case dateAdded
    case lastUpdated
    case name
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: "Date Added"
        case .lastUpdated: "Last Updated"
        case .name: "Name"
        case .manual: "Manual"
        }
    }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
    var title: String { self == .ascending ? "Ascending" : "Descending" }
}

enum ItemSortDirection: String, CaseIterable, Identifiable {
    case highestRemainingFirst
    case lowestRemainingFirst

    var id: String { rawValue }
    var title: String { self == .highestRemainingFirst ? "Highest Remaining" : "Lowest Remaining" }
}

struct DeletionImpact: Equatable {
    var planCount = 0
    var itemCount = 0
    var transactionCount = 0

    var budgetMessage: String {
        "This will permanently delete \(planCount) plan(s), \(itemCount) item(s), and \(transactionCount) transaction(s)."
    }

    var planMessage: String {
        "This will permanently delete \(itemCount) item(s) and \(transactionCount) transaction(s)."
    }

    var itemMessage: String {
        "This will permanently delete \(transactionCount) transaction(s)."
    }
}

enum Phase2ValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidAmount
    case negativeAmount
    case nonPositiveAmount
    case tooManyFractionDigits(Int)
    case invalidMultiplier
    case futureExpenseDate
    case noDestinationItem
    case missingParentRelationship

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case .duplicateName: "That name is already used here."
        case .invalidAmount: "Enter a valid amount."
        case .negativeAmount: "Amount cannot be negative."
        case .nonPositiveAmount: "Amount must be greater than zero."
        case .tooManyFractionDigits(let digits): "Use no more than \(digits) decimal place(s) for this currency."
        case .invalidMultiplier: "Multiplier must be a whole number greater than zero."
        case .futureExpenseDate: "Expenses must be dated today or earlier."
        case .noDestinationItem: "Choose an item."
        case .missingParentRelationship: "This item is no longer available."
        }
    }
}

struct FieldErrors: Equatable {
    var name: String?
    var amount: String?
    var multiplier: String?
    var date: String?
    var destination: String?

    var hasErrors: Bool {
        [name, amount, multiplier, date, destination].contains { $0 != nil }
    }

    var summary: String {
        [name, amount, multiplier, date, destination].compactMap { $0 }.joined(separator: "\n")
    }
}
