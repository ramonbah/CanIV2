//
//  Phase3Support.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation

enum ReportingPeriod: String, CaseIterable, Identifiable, Hashable {
    case last7Days
    case last30Days
    case last90Days
    case currentMonth
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        case .last90Days: "Last 90 Days"
        case .currentMonth: "Current Month"
        case .allTime: "All Time"
        }
    }
}

enum ReportBucketInterval: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PlanTimelineMode: String, CaseIterable, Identifiable {
    case balance
    case flow

    var id: String { rawValue }
    var title: String { self == .balance ? "Balance" : "Flow" }
}

struct ReportPeriodRange: Equatable {
    let period: ReportingPeriod
    let start: Date?
    let end: Date

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard date <= end else { return false }
        guard let start else { return true }
        return date >= start && date <= end
            || calendar.isDate(date, inSameDayAs: start)
            || calendar.isDate(date, inSameDayAs: end)
    }

    var title: String {
        period.title
    }

    func localizedDescription(calendar: Calendar, locale: Locale) -> String {
        UserVisibleDateFormatter(calendar: calendar, locale: locale, referenceDate: end)
            .rangeDescription(title: title, start: start, end: end)
    }
}

enum TransactionDateCriterion: Hashable {
    case none
    case preset(ReportingPeriod)
    case custom(start: Date, end: Date)
}

struct TransactionFilterDraft: Equatable {
    var budgetIDs: Set<UUID> = []
    var planIDs: Set<UUID> = []
    var itemIDs: Set<UUID> = []
    var kinds: Set<TransactionKind> = []
    var dateCriterion: TransactionDateCriterion = .none
    var minimumAmountText = ""
    var maximumAmountText = ""

    static let empty = TransactionFilterDraft()
}

struct TransactionQuery: Equatable {
    var submittedSearchText = ""
    var budgetIDs: Set<UUID> = []
    var planIDs: Set<UUID> = []
    var itemIDs: Set<UUID> = []
    var kinds: Set<TransactionKind> = []
    var dateCriterion: TransactionDateCriterion = .none
    var minimumAmount: Decimal?
    var maximumAmount: Decimal?

    static let empty = TransactionQuery()

    var hasActiveFilters: Bool {
        !budgetIDs.isEmpty || !planIDs.isEmpty || !itemIDs.isEmpty || !kinds.isEmpty || dateCriterion != .none || minimumAmount != nil || maximumAmount != nil
    }

    var hasSubmittedSearch: Bool {
        !submittedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum TransactionFilterChip: Hashable {
    case search(String)
    case budget(UUID)
    case plan(UUID)
    case item(UUID)
    case kind(TransactionKind)
    case date(TransactionDateCriterion)
    case minimumAmount
    case maximumAmount
}

struct TransactionRouteSnapshot: Hashable {
    let budgetID: UUID
    let planID: UUID
    let itemID: UUID
    let transactionID: UUID
}

struct TransactionResultSnapshot: Identifiable, Hashable {
    let id: UUID
    let route: TransactionRouteSnapshot
    let note: String?
    let itemName: String
    let planName: String
    let amount: Decimal
    let kind: TransactionKind
    let date: Date
    let createdAt: Date
    let isScheduledIncome: Bool
}

struct TransactionResultSection: Identifiable {
    let day: Date
    let header: String
    let transactions: [TransactionResultSnapshot]

    var id: Date { day }
}

enum TransactionQueryValidationError: LocalizedError, Equatable {
    case invalidMinimumAmount
    case invalidMaximumAmount
    case amountRange
    case invalidCustomDateRange

    var errorDescription: String? {
        switch self {
        case .invalidMinimumAmount: "Enter a valid minimum amount."
        case .invalidMaximumAmount: "Enter a valid maximum amount."
        case .amountRange: "Minimum amount cannot be greater than maximum amount."
        case .invalidCustomDateRange: "Start date cannot be later than end date."
        }
    }
}

struct TransactionQueryService {
    var calendar: Calendar
    var locale: Locale
    var asOf: Date

    func query(from draft: TransactionFilterDraft, submittedSearchText: String, formatter: CurrencyFormatter) throws -> TransactionQuery {
        let minimum = try parseAmount(draft.minimumAmountText, formatter: formatter, error: .invalidMinimumAmount)
        let maximum = try parseAmount(draft.maximumAmountText, formatter: formatter, error: .invalidMaximumAmount)
        if let minimum, let maximum, minimum > maximum {
            throw TransactionQueryValidationError.amountRange
        }
        if case .custom(let start, let end) = draft.dateCriterion,
           calendar.startOfDay(for: start) > calendar.startOfDay(for: end) {
            throw TransactionQueryValidationError.invalidCustomDateRange
        }
        return TransactionQuery(
            submittedSearchText: normalizedSearch(submittedSearchText),
            budgetIDs: draft.budgetIDs,
            planIDs: draft.planIDs,
            itemIDs: draft.itemIDs,
            kinds: draft.kinds,
            dateCriterion: draft.dateCriterion,
            minimumAmount: minimum,
            maximumAmount: maximum
        )
    }

    func results(for budgets: [Budget], query: TransactionQuery) -> [TransactionResultSnapshot] {
        allSnapshots(from: budgets)
            .filter { matches($0, query: query) }
            .sorted(by: sortSnapshots)
    }

    func sections(for results: [TransactionResultSnapshot]) -> [TransactionResultSection] {
        let grouped = Dictionary(grouping: results) { calendar.startOfDay(for: $0.date) }
        let grouper = TransactionDayGrouper(calendar: calendar, locale: locale, now: asOf)
        return grouped.keys.sorted(by: >).map { day in
            TransactionResultSection(day: day, header: grouper.header(for: day), transactions: grouped[day] ?? [])
        }
    }

    func availablePlans(in budgets: [Budget], for draft: TransactionFilterDraft) -> [BudgetPlan] {
        budgets
            .filter { draft.budgetIDs.isEmpty || draft.budgetIDs.contains($0.id) }
            .flatMap(\.budgetPlans)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func availableItems(in budgets: [Budget], for draft: TransactionFilterDraft) -> [BudgetItem] {
        availablePlans(in: budgets, for: draft)
            .filter { draft.planIDs.isEmpty || draft.planIDs.contains($0.id) }
            .flatMap(\.budgetItems)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func draftByClearingIncompatibleDescendants(_ draft: TransactionFilterDraft, budgets: [Budget]) -> TransactionFilterDraft {
        var copy = draft
        if copy.budgetIDs.isEmpty {
            copy.planIDs = []
            copy.itemIDs = []
            return copy
        }
        let planIDs = Set(availablePlans(in: budgets, for: copy).map(\.id))
        copy.planIDs = copy.planIDs.intersection(planIDs)
        if copy.planIDs.isEmpty {
            copy.itemIDs = []
            return copy
        }
        let itemIDs = Set(availableItems(in: budgets, for: copy).map(\.id))
        copy.itemIDs = copy.itemIDs.intersection(itemIDs)
        return copy
    }

    private func parseAmount(_ text: String, formatter: CurrencyFormatter, error: TransactionQueryValidationError) throws -> Decimal? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let amount = formatter.parse(text), amount >= 0 else { throw error }
        return amount
    }

    private func matches(_ snapshot: TransactionResultSnapshot, query: TransactionQuery) -> Bool {
        if !query.budgetIDs.isEmpty, !query.budgetIDs.contains(snapshot.route.budgetID) { return false }
        if !query.planIDs.isEmpty, !query.planIDs.contains(snapshot.route.planID) { return false }
        if !query.itemIDs.isEmpty, !query.itemIDs.contains(snapshot.route.itemID) { return false }
        if !query.kinds.isEmpty, !query.kinds.contains(snapshot.kind) { return false }
        if let minimum = query.minimumAmount, snapshot.amount < minimum { return false }
        if let maximum = query.maximumAmount, snapshot.amount > maximum { return false }
        if !matchesDate(snapshot.date, criterion: query.dateCriterion) { return false }
        let search = normalizedSearch(query.submittedSearchText)
        guard !search.isEmpty else { return true }
        return [snapshot.note ?? "", snapshot.itemName, snapshot.planName].contains {
            normalizedSearch($0).contains(search)
        }
    }

    private func matchesDate(_ date: Date, criterion: TransactionDateCriterion) -> Bool {
        switch criterion {
        case .none:
            return true
        case .preset(let period):
            if period == .allTime { return true }
            return periodRange(period, budgets: []).contains(date, calendar: calendar)
        case .custom(let start, let end):
            let day = calendar.startOfDay(for: date)
            return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
        }
    }

    func periodRange(_ period: ReportingPeriod, budgets: [Budget]) -> ReportPeriodRange {
        let end = asOf
        let today = calendar.startOfDay(for: asOf)
        switch period {
        case .last7Days:
            return ReportPeriodRange(period: period, start: calendar.date(byAdding: .day, value: -6, to: today), end: end)
        case .last30Days:
            return ReportPeriodRange(period: period, start: calendar.date(byAdding: .day, value: -29, to: today), end: end)
        case .last90Days:
            return ReportPeriodRange(period: period, start: calendar.date(byAdding: .day, value: -89, to: today), end: end)
        case .currentMonth:
            let components = calendar.dateComponents([.year, .month], from: today)
            return ReportPeriodRange(period: period, start: calendar.date(from: components), end: end)
        case .allTime:
            let earliest = allSnapshots(from: budgets).map(\.date).min().map { calendar.startOfDay(for: $0) }
            return ReportPeriodRange(period: period, start: earliest, end: end)
        }
    }

    private func allSnapshots(from budgets: [Budget]) -> [TransactionResultSnapshot] {
        budgets.flatMap { budget in
            budget.budgetPlans.flatMap { plan in
                plan.budgetItems.flatMap { item in
                    item.transactions.map { transaction in
                        TransactionResultSnapshot(
                            id: transaction.id,
                            route: TransactionRouteSnapshot(budgetID: budget.id, planID: plan.id, itemID: item.id, transactionID: transaction.id),
                            note: transaction.notes,
                            itemName: item.name,
                            planName: plan.name,
                            amount: transaction.amount,
                            kind: transaction.kind,
                            date: transaction.date,
                            createdAt: transaction.createdAt,
                            isScheduledIncome: transaction.kind == .income && !Phase2Calculations.isEffective(transaction, asOf: asOf, calendar: calendar)
                        )
                    }
                }
            }
        }
    }

    private func sortSnapshots(_ lhs: TransactionResultSnapshot, _ rhs: TransactionResultSnapshot) -> Bool {
        if !calendar.isDate(lhs.date, inSameDayAs: rhs.date) { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func normalizedSearch(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }
}

struct MoneyBucket: Identifiable, Equatable {
    let id: String
    let label: String
    let start: Date
    let income: Decimal
    let expense: Decimal
    let balance: Decimal

    var net: Decimal { income - expense }
}

struct AllocationSnapshot: Equatable {
    let primary: Decimal
    let secondary: Decimal
    let total: Decimal
    let primaryTitle: String
    let secondaryTitle: String
}

struct ReportTransactionReference: Identifiable, Hashable {
    let id: UUID
    let route: TransactionRouteSnapshot
    let note: String?
    let amount: Decimal
    let kind: TransactionKind
    let date: Date
    let createdAt: Date
}

struct ReportBreakdownRow: Identifiable, Equatable {
    let id: String
    let title: String
    let value: Decimal
}

struct HomeReportSnapshot {
    let range: ReportPeriodRange
    let buckets: [MoneyBucket]
    let netFlow: Decimal
    let recentTransactions: [ReportTransactionReference]
    let activePlans: [PlanActivitySnapshot]
    let allTransactions: [ReportTransactionReference]
    let summary: String
}

struct PlanActivitySnapshot: Identifiable, Hashable {
    let id: UUID
    let budgetID: UUID
    let planID: UUID
    let name: String
    let latestTransactionDate: Date
    let latestCreatedAt: Date
}

struct BudgetReportSnapshot {
    let range: ReportPeriodRange
    let interval: ReportBucketInterval
    let planComparisons: [ReportBreakdownRow]
    let expenseBuckets: [MoneyBucket]
    let flowBuckets: [MoneyBucket]
    let incomeTotal: Decimal
    let expenseTotal: Decimal
    let transactions: [ReportTransactionReference]
    let summary: String
}

struct PlanReportSnapshot {
    let range: ReportPeriodRange
    let timelineMode: PlanTimelineMode
    let availableFunds: Decimal
    let allocated: Decimal
    let unallocated: Decimal
    let spent: Decimal
    let remaining: Decimal
    let itemComparisons: [ReportBreakdownRow]
    let timelineBuckets: [MoneyBucket]
    let transactions: [ReportTransactionReference]
    let summary: String

    var allocationSnapshot: AllocationSnapshot {
        AllocationSnapshot(primary: allocated, secondary: unallocated, total: max(availableFunds, allocated), primaryTitle: "Allocated", secondaryTitle: "Unallocated")
    }

    var spentRemainingSnapshot: AllocationSnapshot {
        AllocationSnapshot(primary: spent, secondary: remaining, total: max(spent, spent + max(remaining, 0)), primaryTitle: "Spent", secondaryTitle: "Remaining")
    }
}

protocol ReportService {
    func homeSnapshot(budgets: [Budget], period: ReportingPeriod, formatter: CurrencyFormatter) -> HomeReportSnapshot
    func budgetSnapshot(budget: Budget, period: ReportingPeriod, interval: ReportBucketInterval, formatter: CurrencyFormatter) -> BudgetReportSnapshot
    func planSnapshot(plan: BudgetPlan, period: ReportingPeriod, timelineMode: PlanTimelineMode, formatter: CurrencyFormatter) -> PlanReportSnapshot
    func hasMeaningfulBudgetReports(budget: Budget, formatter: CurrencyFormatter) -> Bool
    func hasMeaningfulPlanReports(plan: BudgetPlan, formatter: CurrencyFormatter) -> Bool
}

struct DefaultReportService: ReportService {
    var calendar: Calendar
    var locale: Locale
    var asOf: Date

    func homeSnapshot(budgets: [Budget], period: ReportingPeriod, formatter: CurrencyFormatter) -> HomeReportSnapshot {
        let range = queryService.periodRange(period, budgets: budgets)
        let transactions = reportTransactions(in: budgets, range: range)
        let buckets = bucketsFor(transactions: transactions, range: range, interval: automaticInterval(for: period), startingBalance: 0)
        let income = transactions.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = transactions.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        let activePlans = activePlans(in: budgets, range: range)
        let recent = Array(transactions.sorted(by: sortReportTransactions).prefix(3))
        let period = range.localizedDescription(calendar: calendar, locale: locale)
        let summary = "Net cash flow \(formatter.string(for: income - expense)) for \(period). Income \(formatter.string(for: income)); expenses \(formatter.string(for: expense))."
        return HomeReportSnapshot(range: range, buckets: buckets, netFlow: income - expense, recentTransactions: recent, activePlans: Array(activePlans.prefix(3)), allTransactions: transactions, summary: summary)
    }

    func budgetSnapshot(budget: Budget, period: ReportingPeriod, interval: ReportBucketInterval, formatter: CurrencyFormatter) -> BudgetReportSnapshot {
        let range = queryService.periodRange(period, budgets: [budget])
        let transactions = reportTransactions(in: [budget], range: range)
        let comparisons = budget.budgetPlans.compactMap { plan -> ReportBreakdownRow? in
            let planTransactions = reportTransactions(in: [budget], range: range).filter { $0.route.planID == plan.id }
            guard !planTransactions.isEmpty else { return nil }
            let income = planTransactions.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
            let expense = planTransactions.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
            return ReportBreakdownRow(id: plan.id.uuidString, title: plan.name, value: income - expense)
        }.sorted { $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value }
        let buckets = bucketsFor(transactions: transactions, range: range, interval: interval, startingBalance: 0)
        let income = transactions.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = transactions.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        let summary = "\(budget.name) report for \(range.localizedDescription(calendar: calendar, locale: locale)). Income \(formatter.string(for: income)); expenses \(formatter.string(for: expense)); net \(formatter.string(for: income - expense))."
        return BudgetReportSnapshot(range: range, interval: interval, planComparisons: comparisons, expenseBuckets: buckets, flowBuckets: buckets, incomeTotal: income, expenseTotal: expense, transactions: transactions, summary: summary)
    }

    func planSnapshot(plan: BudgetPlan, period: ReportingPeriod, timelineMode: PlanTimelineMode, formatter: CurrencyFormatter) -> PlanReportSnapshot {
        guard let budget = plan.budget else {
            return emptyPlanSnapshot(plan: plan, period: period, timelineMode: timelineMode, formatter: formatter)
        }
        let range = queryService.periodRange(period, budgets: [budget])
        let transactions = reportTransactions(in: [budget], range: range).filter { $0.route.planID == plan.id }
        let endpointTotals = planTotals(for: plan, at: range.end)
        let availableFunds = endpointTotals.startingFunds + endpointTotals.effectiveIncome
        let allocated = endpointTotals.planned
        let spentThroughEnd = endpointTotals.expenses
        let itemRows = plan.budgetItems.compactMap { item -> ReportBreakdownRow? in
            let itemTransactions = transactions.filter { $0.route.itemID == item.id }
            guard !itemTransactions.isEmpty else { return nil }
            let income = itemTransactions.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
            let expense = itemTransactions.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
            return ReportBreakdownRow(id: item.id.uuidString, title: item.name, value: income - expense)
        }.sorted { $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value }
        let startingBalance = balanceBeforePeriod(for: plan, range: range)
        let buckets = bucketsFor(transactions: transactions, range: range, interval: automaticInterval(for: period), startingBalance: startingBalance)
        let summary = "\(plan.name) report for \(range.localizedDescription(calendar: calendar, locale: locale)). Available \(formatter.string(for: availableFunds)); allocated \(formatter.string(for: allocated)); remaining \(formatter.string(for: availableFunds - spentThroughEnd))."
        return PlanReportSnapshot(range: range, timelineMode: timelineMode, availableFunds: availableFunds, allocated: allocated, unallocated: availableFunds - allocated, spent: spentThroughEnd, remaining: availableFunds - spentThroughEnd, itemComparisons: itemRows, timelineBuckets: buckets, transactions: transactions, summary: summary)
    }

    func hasMeaningfulBudgetReports(budget: Budget, formatter: CurrencyFormatter) -> Bool {
        let snapshot = budgetSnapshot(budget: budget, period: .allTime, interval: automaticInterval(for: .allTime), formatter: formatter)
        return !snapshot.transactions.isEmpty || !snapshot.planComparisons.isEmpty || snapshot.incomeTotal != 0 || snapshot.expenseTotal != 0
    }

    func hasMeaningfulPlanReports(plan: BudgetPlan, formatter: CurrencyFormatter) -> Bool {
        guard plan.budget != nil else { return false }
        let snapshot = planSnapshot(plan: plan, period: .allTime, timelineMode: .balance, formatter: formatter)
        return snapshot.availableFunds != 0
            || snapshot.allocated != 0
            || snapshot.spent != 0
            || snapshot.remaining != 0
            || !snapshot.transactions.isEmpty
            || !snapshot.itemComparisons.isEmpty
    }

    private func balanceBeforePeriod(for plan: BudgetPlan, range: ReportPeriodRange) -> Decimal {
        guard let start = range.start else { return Decimal(0) }
        return planTotals(for: plan, at: start.addingTimeInterval(-0.001)).currentBalance
    }

    private func emptyPlanSnapshot(plan: BudgetPlan, period: ReportingPeriod, timelineMode: PlanTimelineMode, formatter: CurrencyFormatter) -> PlanReportSnapshot {
        let range = queryService.periodRange(period, budgets: [])
        let summary = "\(plan.name) report for \(range.localizedDescription(calendar: calendar, locale: locale)). Available \(formatter.string(for: 0)); allocated \(formatter.string(for: 0)); remaining \(formatter.string(for: 0))."
        return PlanReportSnapshot(
            range: range,
            timelineMode: timelineMode,
            availableFunds: 0,
            allocated: 0,
            unallocated: 0,
            spent: 0,
            remaining: 0,
            itemComparisons: [],
            timelineBuckets: [],
            transactions: [],
            summary: summary
        )
    }

    private func planTotals(for plan: BudgetPlan, at endpoint: Date) -> (planned: Decimal, startingFunds: Decimal, effectiveIncome: Decimal, expenses: Decimal, currentBalance: Decimal) {
        let planExists = plan.createdAt <= endpoint
        let planned = planExists ? plan.budgetItems.reduce(Decimal(0)) { $0 + Phase2Calculations.allocatedPlannedAmount(for: $1) } : 0
        let startingFunds = planExists ? plan.startingAmount : 0
        let endpointDay = calendar.startOfDay(for: endpoint)
        let transactions = plan.budgetItems.flatMap(\.transactions)
        let income = transactions
            .filter { $0.kind == .income && calendar.startOfDay(for: $0.date) <= endpointDay }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let expenses = transactions
            .filter { $0.kind == .expense && $0.date <= endpoint }
            .reduce(Decimal(0)) { $0 + $1.amount }
        return (planned, startingFunds, income, expenses, startingFunds + income - expenses)
    }

    private var queryService: TransactionQueryService {
        TransactionQueryService(calendar: calendar, locale: locale, asOf: asOf)
    }

    private func automaticInterval(for period: ReportingPeriod) -> ReportBucketInterval {
        switch period {
        case .last7Days, .last30Days, .currentMonth: .day
        case .last90Days: .week
        case .allTime: .month
        }
    }

    private func activePlans(in budgets: [Budget], range: ReportPeriodRange) -> [PlanActivitySnapshot] {
        budgets.flatMap { budget in
            budget.budgetPlans.compactMap { plan in
                let transactions = plan.budgetItems.flatMap(\.transactions).filter { range.contains($0.date, calendar: calendar) }
                guard let latestDate = transactions.map(\.date).max(),
                      let latestCreatedAt = transactions.map(\.createdAt).max() else { return nil }
                return PlanActivitySnapshot(id: plan.id, budgetID: budget.id, planID: plan.id, name: plan.name, latestTransactionDate: latestDate, latestCreatedAt: latestCreatedAt)
            }
        }.sorted {
            if $0.latestTransactionDate != $1.latestTransactionDate { return $0.latestTransactionDate > $1.latestTransactionDate }
            if $0.latestCreatedAt != $1.latestCreatedAt { return $0.latestCreatedAt > $1.latestCreatedAt }
            return $0.planID.uuidString < $1.planID.uuidString
        }
    }

    private func reportTransactions(in budgets: [Budget], range: ReportPeriodRange) -> [ReportTransactionReference] {
        budgets.flatMap { budget in
            budget.budgetPlans.flatMap { plan in
                plan.budgetItems.flatMap { item in
                    item.transactions.compactMap { transaction in
                        guard range.contains(transaction.date, calendar: calendar) else { return nil }
                        return ReportTransactionReference(id: transaction.id, route: TransactionRouteSnapshot(budgetID: budget.id, planID: plan.id, itemID: item.id, transactionID: transaction.id), note: transaction.notes, amount: transaction.amount, kind: transaction.kind, date: transaction.date, createdAt: transaction.createdAt)
                    }
                }
            }
        }.sorted(by: sortReportTransactions)
    }

    private func sortReportTransactions(_ lhs: ReportTransactionReference, _ rhs: ReportTransactionReference) -> Bool {
        if !calendar.isDate(lhs.date, inSameDayAs: rhs.date) { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func bucketsFor(transactions: [ReportTransactionReference], range: ReportPeriodRange, interval: ReportBucketInterval, startingBalance: Decimal) -> [MoneyBucket] {
        guard range.start != nil || !transactions.isEmpty else { return [] }
        let starts = bucketStarts(range: range, interval: interval)
        var running = startingBalance
        return starts.map { start in
            let end = bucketEnd(for: start, interval: interval)
            let bucketTransactions = transactions.filter { $0.date >= start && $0.date < end }
            let income = bucketTransactions.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
            let expense = bucketTransactions.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
            running += income - expense
            return MoneyBucket(id: "\(interval.rawValue)-\(start.timeIntervalSince1970)", label: bucketLabel(start, interval: interval), start: start, income: income, expense: expense, balance: running)
        }
    }

    private func bucketStarts(range: ReportPeriodRange, interval: ReportBucketInterval) -> [Date] {
        guard let start = range.start else { return [] }
        var values: [Date] = []
        var current = alignedBucketStart(start, interval: interval)
        while current <= range.end {
            values.append(current)
            current = bucketEnd(for: current, interval: interval)
        }
        return values
    }

    private func alignedBucketStart(_ date: Date, interval: ReportBucketInterval) -> Date {
        switch interval {
        case .day:
            calendar.startOfDay(for: date)
        case .week:
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private func bucketEnd(for start: Date, interval: ReportBucketInterval) -> Date {
        switch interval {
        case .day:
            calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .week:
            calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        case .month:
            calendar.date(byAdding: .month, value: 1, to: start) ?? start
        }
    }

    private func bucketLabel(_ date: Date, interval: ReportBucketInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = interval == .month ? "MMM y" : "d MMM"
        return formatter.string(from: date)
    }
}
