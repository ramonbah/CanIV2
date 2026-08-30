//
//  Phase4Support.swift
//  CanIV2
//
//  Created by Codex on 8/30/26.
//

import Foundation
import SwiftData

enum Phase4ValidationError: LocalizedError, Equatable {
    case emptyRolloverSelection
    case sourcePlanOutsideBudget
    case sourcePlanIsNotEarlier
    case duplicateSourceSelection
    case alreadyRolledOver(String)
    case rolloverNameConflict(String)
    case missingDestination
    case invalidRecurrenceInterval
    case invalidRecurrenceDateRange
    case recurrenceEnded

    var errorDescription: String? {
        switch self {
        case .emptyRolloverSelection:
            "Select at least one Item to roll over."
        case .sourcePlanOutsideBudget:
            "Choose a source Plan from the same Budget."
        case .sourcePlanIsNotEarlier:
            "Choose an earlier Plan as the rollover source."
        case .duplicateSourceSelection:
            "Each source Item can be selected only once."
        case .alreadyRolledOver(let name):
            "\"\(name)\" was already rolled into this Plan."
        case .rolloverNameConflict(let name):
            "\"\(name)\" conflicts with an Item already in the destination Plan."
        case .missingDestination:
            "Choose a destination Item before generating recurring transactions."
        case .invalidRecurrenceInterval:
            "Recurrence interval must be at least 1."
        case .invalidRecurrenceDateRange:
            "End date cannot be before the start date."
        case .recurrenceEnded:
            "This recurring template has ended."
        }
    }
}

struct RolloverCandidate: Identifiable, Hashable {
    let id: UUID
    let itemID: UUID
    let name: String
    let unitAmount: Decimal
    let multiplier: Decimal
    let sortOrder: Int
    let isAlreadyRolledOver: Bool
    let hasNameConflict: Bool

    init(item: BudgetItem, destinationPlan: BudgetPlan) {
        id = item.id
        itemID = item.id
        name = item.name
        unitAmount = item.unitAmount
        multiplier = item.multiplier
        sortOrder = item.sortOrder
        isAlreadyRolledOver = destinationPlan.budgetItems.contains { $0.sourceItemID == item.id }
        hasNameConflict = NameNormalizer.isDuplicate(item.name, among: destinationPlan.budgetItems.map(\.name))
    }
}

struct RolloverSourcePlan: Identifiable, Hashable {
    let id: UUID
    let planID: UUID
    let name: String
    let candidates: [RolloverCandidate]

    init(plan: BudgetPlan, destinationPlan: BudgetPlan) {
        id = plan.id
        planID = plan.id
        name = plan.name
        candidates = plan.budgetItems
            .sorted { $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder }
            .map { RolloverCandidate(item: $0, destinationPlan: destinationPlan) }
    }
}

@MainActor
struct RolloverUseCase {
    let context: ModelContext

    func sourcePlans(for destinationPlan: BudgetPlan) -> [RolloverSourcePlan] {
        guard let budget = destinationPlan.budget else { return [] }
        return budget.budgetPlans
            .filter { isEarlier($0, than: destinationPlan) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.descriptiveDate ?? lhs.createdAt
                let rhsDate = rhs.descriptiveDate ?? rhs.createdAt
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map { RolloverSourcePlan(plan: $0, destinationPlan: destinationPlan) }
    }

    @discardableResult
    func rollItems(from sourcePlan: BudgetPlan, itemIDs: Set<UUID>, into destinationPlan: BudgetPlan, now: Date) throws -> [BudgetItem] {
        guard !itemIDs.isEmpty else { throw Phase4ValidationError.emptyRolloverSelection }
        guard let sourceBudget = sourcePlan.budget, let destinationBudget = destinationPlan.budget else {
            throw Phase2ValidationError.missingParentRelationship
        }
        guard sourceBudget.id == destinationBudget.id else { throw Phase4ValidationError.sourcePlanOutsideBudget }
        guard isEarlier(sourcePlan, than: destinationPlan) else { throw Phase4ValidationError.sourcePlanIsNotEarlier }

        let sourceItems = sourcePlan.budgetItems
            .filter { itemIDs.contains($0.id) }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder }
        guard sourceItems.count == itemIDs.count else { throw Phase4ValidationError.duplicateSourceSelection }
        guard Set(sourceItems.map(\.id)).count == sourceItems.count else { throw Phase4ValidationError.duplicateSourceSelection }

        let destinationNames = destinationPlan.budgetItems.map(\.name)
        for item in sourceItems {
            if destinationPlan.budgetItems.contains(where: { $0.sourceItemID == item.id }) {
                throw Phase4ValidationError.alreadyRolledOver(item.name)
            }
            if NameNormalizer.isDuplicate(item.name, among: destinationNames) {
                throw Phase4ValidationError.rolloverNameConflict(item.name)
            }
        }

        let originalPlanUpdatedAt = destinationPlan.updatedAt
        let originalBudgetUpdatedAt = destinationBudget.updatedAt
        let originalItems = destinationPlan.budgetItems
        let firstOrder = (destinationPlan.budgetItems.map(\.sortOrder).max() ?? -1) + 1
        let created = sourceItems.enumerated().map { offset, source in
            BudgetItem(
                name: source.name,
                unitAmount: source.unitAmount,
                multiplier: source.multiplier,
                sortOrder: firstOrder + offset,
                sourceItemID: source.id,
                createdAt: now,
                updatedAt: now,
                budgetPlan: destinationPlan
            )
        }

        destinationPlan.budgetItems.append(contentsOf: created)
        destinationPlan.updatedAt = now
        destinationBudget.updatedAt = now
        created.forEach(context.insert)

        do {
            try ModelMutationService.saveValidated(context)
            return created
        } catch {
            destinationPlan.budgetItems = originalItems
            destinationPlan.updatedAt = originalPlanUpdatedAt
            destinationBudget.updatedAt = originalBudgetUpdatedAt
            created.forEach(context.delete)
            context.rollback()
            throw error
        }
    }

    private func isEarlier(_ source: BudgetPlan, than destination: BudgetPlan) -> Bool {
        if source.id == destination.id { return false }
        let sourceDate = source.descriptiveDate ?? source.createdAt
        let destinationDate = destination.descriptiveDate ?? destination.createdAt
        if sourceDate != destinationDate { return sourceDate < destinationDate }
        return source.sortOrder < destination.sortOrder
    }
}

struct RecurrenceSchedule: Equatable {
    var frequency: RecurrenceFrequency
    var interval: Int
    var startDate: Date
    var endDate: Date?

    func validate() throws {
        guard interval >= 1 else { throw Phase4ValidationError.invalidRecurrenceInterval }
        if let endDate, endDate < startDate {
            throw Phase4ValidationError.invalidRecurrenceDateRange
        }
    }

    func next(after occurrence: Date, calendar: Calendar) -> Date {
        advanced(from: occurrence, steps: interval, calendar: calendar)
    }

    func firstOccurrence(onOrAfter date: Date, calendar: Calendar) throws -> Date {
        try validate()
        var candidate = startDate
        let targetDay = calendar.startOfDay(for: date)
        while calendar.startOfDay(for: candidate) < targetDay {
            candidate = next(after: candidate, calendar: calendar)
        }
        if isAfterEnd(candidate, calendar: calendar) {
            throw Phase4ValidationError.recurrenceEnded
        }
        return candidate
    }

    func isDue(_ occurrence: Date, asOf date: Date, calendar: Calendar) -> Bool {
        !isAfterEnd(occurrence, calendar: calendar) && calendar.startOfDay(for: occurrence) <= calendar.startOfDay(for: date)
    }

    func isAfterEnd(_ occurrence: Date, calendar: Calendar) -> Bool {
        guard let endDate else { return false }
        return calendar.startOfDay(for: occurrence) > calendar.startOfDay(for: endDate)
    }

    private func advanced(from date: Date, steps: Int, calendar: Calendar) -> Date {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: steps, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: steps, to: date) ?? date
        case .monthly:
            return anchoredDate(from: date, adding: .month, value: steps, calendar: calendar)
        case .yearly:
            return anchoredDate(from: date, adding: .year, value: steps, calendar: calendar)
        }
    }

    private func anchoredDate(from date: Date, adding component: Calendar.Component, value: Int, calendar: Calendar) -> Date {
        let anchor = calendar.component(.day, from: startDate)
        let advanced = calendar.date(byAdding: component, value: value, to: date) ?? date
        var parts = calendar.dateComponents([.year, .month, .hour, .minute, .second, .nanosecond], from: advanced)
        let range = calendar.range(of: .day, in: .month, for: advanced)
        parts.day = min(anchor, range?.count ?? anchor)
        return calendar.date(from: parts) ?? advanced
    }
}

enum RecurringTemplateStatus: String, Equatable {
    case active
    case paused
    case ended
    case needsDestination

    var title: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .ended: "Ended"
        case .needsDestination: "Needs Destination"
        }
    }
}

struct RecurringTemplateReportRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let amount: Decimal
    let kind: TransactionKind
    let frequency: RecurrenceFrequency
    let interval: Int
    let status: RecurringTemplateStatus
    let nextOccurrence: Date?
    let destinationName: String?
}

struct RecurringBudgetReportSnapshot: Equatable {
    let rows: [RecurringTemplateReportRow]
    let summary: String
}

struct PlanMetricVisibility: Equatable {
    let showsPlanned: Bool
    let showsSpent: Bool
    let showsBalance: Bool
    let showsProgress: Bool
}

struct ItemMetricVisibility: Equatable {
    let showsPlanned: Bool
    let showsIncome: Bool
    let showsSpent: Bool
    let showsRemaining: Bool
    let showsProgress: Bool
}

enum Phase4PresentationRules {
    static func hasRelevantActivity(_ plan: BudgetPlan) -> Bool {
        plan.budgetItems.contains { !$0.transactions.isEmpty }
    }

    static func hasRelevantActivity(_ item: BudgetItem) -> Bool {
        !item.transactions.isEmpty
    }

    static func planVisibility(for plan: BudgetPlan, totals: PlanTotals) -> PlanMetricVisibility {
        let hasActivity = hasRelevantActivity(plan)
        return PlanMetricVisibility(
            showsPlanned: totals.planned != 0,
            showsSpent: totals.expenses != 0,
            showsBalance: totals.currentBalance != totals.totalFundsReceived || hasActivity,
            showsProgress: totals.expenses != 0
        )
    }

    static func itemVisibility(for item: BudgetItem, totals: ItemTotals) -> ItemMetricVisibility {
        let hasActivity = hasRelevantActivity(item)
        return ItemMetricVisibility(
            showsPlanned: totals.planned != 0,
            showsIncome: totals.effectiveIncome != 0,
            showsSpent: totals.expenses != 0,
            showsRemaining: totals.remaining != totals.planned || hasActivity,
            showsProgress: totals.expenses != 0
        )
    }

    static func itemRowVisibility(for item: BudgetItem, presentation: ItemRowPresentation) -> ItemMetricVisibility {
        let totals = ItemTotals(planned: presentation.planned, effectiveIncome: presentation.effectiveIncome, scheduledIncome: presentation.scheduledIncome, expenses: presentation.spent)
        return itemVisibility(for: item, totals: totals)
    }

    static func reportHasMeaningfulData(buckets: [MoneyBucket], rows: [ReportBreakdownRow], transactions: [ReportTransactionReference]) -> Bool {
        if !transactions.isEmpty { return true }
        if rows.contains(where: { $0.value != 0 }) { return true }
        return buckets.contains { $0.income != 0 || $0.expense != 0 || $0.balance != 0 || $0.net != 0 }
    }
}

@MainActor
struct RecurringTemplateUseCase {
    let context: ModelContext

    @discardableResult
    func create(
        name: String,
        amount: Decimal,
        kind: TransactionKind,
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date?,
        budget: Budget,
        destination: BudgetItem?,
        clock: AppClock
    ) throws -> RecurringTransactionTemplate {
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: budget.recurringTemplates.map(\.name))
        try validate(amount: amount, interval: interval, startDate: startDate, endDate: endDate)
        if let destination, destination.budgetPlan.budget.id != budget.id {
            throw Phase4ValidationError.missingDestination
        }
        let schedule = RecurrenceSchedule(frequency: frequency, interval: interval, startDate: startDate, endDate: endDate)
        let next = (try? schedule.firstOccurrence(onOrAfter: clock.now, calendar: clock.calendar)) ?? startDate
        let originalBudgetUpdatedAt = budget.updatedAt
        let template = RecurringTransactionTemplate(
            name: trimmed,
            amount: amount,
            kind: kind,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            endDate: endDate,
            nextOccurrence: next,
            isEnabled: true,
            createdAt: clock.now,
            updatedAt: clock.now,
            budget: budget,
            destinationBudgetItem: destination
        )
        budget.recurringTemplates.append(template)
        budget.updatedAt = clock.now
        context.insert(template)
        do {
            try ModelMutationService.saveValidated(context)
            return template
        } catch {
            budget.recurringTemplates.removeAll { $0.id == template.id }
            budget.updatedAt = originalBudgetUpdatedAt
            context.delete(template)
            context.rollback()
            throw error
        }
    }

    func update(
        _ template: RecurringTransactionTemplate,
        name: String,
        amount: Decimal,
        kind: TransactionKind,
        frequency: RecurrenceFrequency,
        interval: Int,
        startDate: Date,
        endDate: Date?,
        destination: BudgetItem?,
        clock: AppClock
    ) throws {
        guard let budget = template.budget else { throw Phase2ValidationError.missingParentRelationship }
        let trimmed = NameNormalizer.trimmed(name)
        try ValidationUseCase.validateName(trimmed, siblings: budget.recurringTemplates.filter { $0.id != template.id }.map(\.name))
        try validate(amount: amount, interval: interval, startDate: startDate, endDate: endDate)
        if let destination, destination.budgetPlan.budget.id != budget.id {
            throw Phase4ValidationError.missingDestination
        }
        let original = snapshot(template, budget: budget)
        let schedule = RecurrenceSchedule(frequency: frequency, interval: interval, startDate: startDate, endDate: endDate)
        template.name = trimmed
        template.amount = amount
        template.kind = kind
        template.frequency = frequency
        template.interval = interval
        template.startDate = startDate
        template.endDate = endDate
        template.nextOccurrence = (try? schedule.firstOccurrence(onOrAfter: max(clock.now, startDate), calendar: clock.calendar)) ?? startDate
        template.destinationBudgetItem = destination
        template.updatedAt = clock.now
        budget.updatedAt = clock.now
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            restore(template, from: original)
            context.rollback()
            throw error
        }
    }

    func setEnabled(_ enabled: Bool, for template: RecurringTransactionTemplate, clock: AppClock) throws {
        guard let budget = template.budget else { throw Phase2ValidationError.missingParentRelationship }
        let original = snapshot(template, budget: budget)
        template.isEnabled = enabled
        if enabled {
            let schedule = RecurrenceSchedule(template: template)
            template.nextOccurrence = (try? schedule.firstOccurrence(onOrAfter: clock.now, calendar: clock.calendar)) ?? template.nextOccurrence
        }
        template.updatedAt = clock.now
        budget.updatedAt = clock.now
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            restore(template, from: original)
            context.rollback()
            throw error
        }
    }

    func repairDestination(_ destination: BudgetItem, for template: RecurringTransactionTemplate, clock: AppClock) throws {
        guard let budget = template.budget, destination.budgetPlan.budget.id == budget.id else {
            throw Phase4ValidationError.missingDestination
        }
        let original = snapshot(template, budget: budget)
        template.destinationBudgetItem = destination
        template.nextOccurrence = (try? RecurrenceSchedule(template: template).firstOccurrence(onOrAfter: clock.now, calendar: clock.calendar)) ?? template.nextOccurrence
        template.updatedAt = clock.now
        budget.updatedAt = clock.now
        do {
            try ModelMutationService.saveValidated(context)
        } catch {
            restore(template, from: original)
            context.rollback()
            throw error
        }
    }

    func delete(_ template: RecurringTransactionTemplate) throws {
        guard let budget = template.budget else { throw Phase2ValidationError.missingParentRelationship }
        budget.recurringTemplates.removeAll { $0.id == template.id }
        context.delete(template)
        try ModelMutationService.saveValidated(context)
    }

    private func validate(amount: Decimal, interval: Int, startDate: Date, endDate: Date?) throws {
        guard amount > 0 else { throw DomainValidationError.nonPositiveRecurringAmount }
        try RecurrenceSchedule(frequency: .daily, interval: interval, startDate: startDate, endDate: endDate).validate()
    }

    private func snapshot(_ template: RecurringTransactionTemplate, budget: Budget) -> TemplateSnapshot {
        TemplateSnapshot(
            name: template.name,
            amount: template.amount,
            kind: template.kind,
            frequency: template.frequency,
            interval: template.interval,
            startDate: template.startDate,
            endDate: template.endDate,
            nextOccurrence: template.nextOccurrence,
            isEnabled: template.isEnabled,
            destination: template.destinationBudgetItem,
            updatedAt: template.updatedAt,
            budgetUpdatedAt: budget.updatedAt
        )
    }

    private func restore(_ template: RecurringTransactionTemplate, from snapshot: TemplateSnapshot) {
        template.name = snapshot.name
        template.amount = snapshot.amount
        template.kind = snapshot.kind
        template.frequency = snapshot.frequency
        template.interval = snapshot.interval
        template.startDate = snapshot.startDate
        template.endDate = snapshot.endDate
        template.nextOccurrence = snapshot.nextOccurrence
        template.isEnabled = snapshot.isEnabled
        template.destinationBudgetItem = snapshot.destination
        template.updatedAt = snapshot.updatedAt
        template.budget?.updatedAt = snapshot.budgetUpdatedAt
    }

    private struct TemplateSnapshot {
        let name: String
        let amount: Decimal
        let kind: TransactionKind
        let frequency: RecurrenceFrequency
        let interval: Int
        let startDate: Date
        let endDate: Date?
        let nextOccurrence: Date
        let isEnabled: Bool
        let destination: BudgetItem?
        let updatedAt: Date
        let budgetUpdatedAt: Date
    }
}

@MainActor
final class RecurrenceGenerationCoordinator {
    private let context: ModelContext
    private var isProcessing = false

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func processDueTemplates(in budgets: [Budget], clock: AppClock, limit: Int = 100) throws -> Int {
        guard !isProcessing else { return 0 }
        isProcessing = true
        defer { isProcessing = false }

        var createdCount = 0
        for template in budgets.flatMap(\.recurringTemplates).sorted(by: templateOrder) {
            guard createdCount < limit else { break }
            createdCount += try process(template, clock: clock, remainingLimit: limit - createdCount)
        }
        return createdCount
    }

    private func process(_ template: RecurringTransactionTemplate, clock: AppClock, remainingLimit: Int) throws -> Int {
        guard template.isEnabled else { return 0 }
        guard let destination = template.destinationBudgetItem else { return 0 }
        guard let plan = destination.budgetPlan, let budget = plan.budget else { throw Phase2ValidationError.missingParentRelationship }

        let schedule = RecurrenceSchedule(template: template)
        var occurrence = template.nextOccurrence
        var occurrences: [Date] = []
        while occurrences.count < remainingLimit, schedule.isDue(occurrence, asOf: clock.now, calendar: clock.calendar) {
            occurrences.append(occurrence)
            occurrence = schedule.next(after: occurrence, calendar: clock.calendar)
        }
        guard !occurrences.isEmpty else { return 0 }

        let originalNext = template.nextOccurrence
        let originalTemplateUpdatedAt = template.updatedAt
        let originalItemUpdatedAt = destination.updatedAt
        let originalPlanUpdatedAt = plan.updatedAt
        let originalBudgetUpdatedAt = budget.updatedAt
        let originalTransactions = destination.transactions
        var inserted: [Transaction] = []

        for occurrenceDate in occurrences {
            if hasExistingOccurrence(for: template, occurrenceDate: occurrenceDate, in: budget, calendar: clock.calendar) {
                continue
            }
            let transaction = Transaction(
                name: TransactionUseCase(repository: NoopPhase4TransactionRepository()).generatedName(for: template.kind),
                amount: template.amount,
                kind: template.kind,
                date: occurrenceDate,
                notes: template.name,
                createdAt: clock.now,
                updatedAt: clock.now,
                sourceTemplateID: template.id,
                budgetItem: destination
            )
            destination.transactions.append(transaction)
            context.insert(transaction)
            inserted.append(transaction)
        }

        template.nextOccurrence = occurrence
        template.updatedAt = clock.now
        destination.updatedAt = clock.now
        plan.updatedAt = clock.now
        budget.updatedAt = clock.now

        do {
            try ModelMutationService.saveValidated(context)
            return inserted.count
        } catch {
            template.nextOccurrence = originalNext
            template.updatedAt = originalTemplateUpdatedAt
            destination.transactions = originalTransactions
            destination.updatedAt = originalItemUpdatedAt
            plan.updatedAt = originalPlanUpdatedAt
            budget.updatedAt = originalBudgetUpdatedAt
            inserted.forEach(context.delete)
            context.rollback()
            throw error
        }
    }

    private func hasExistingOccurrence(for template: RecurringTransactionTemplate, occurrenceDate: Date, in budget: Budget, calendar: Calendar) -> Bool {
        budget.budgetPlans.contains { plan in
            plan.budgetItems.contains { item in
                item.transactions.contains {
                    $0.sourceTemplateID == template.id && calendar.isDate($0.date, inSameDayAs: occurrenceDate)
                }
            }
        }
    }

    private func templateOrder(_ lhs: RecurringTransactionTemplate, _ rhs: RecurringTransactionTemplate) -> Bool {
        if lhs.nextOccurrence != rhs.nextOccurrence { return lhs.nextOccurrence < rhs.nextOccurrence }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

extension RecurrenceSchedule {
    init(template: RecurringTransactionTemplate) {
        self.init(
            frequency: template.frequency,
            interval: template.interval,
            startDate: template.startDate,
            endDate: template.endDate
        )
    }
}

struct RecurringReportService {
    var calendar: Calendar
    var asOf: Date
    var formatter: CurrencyFormatter

    func snapshot(for budget: Budget) -> RecurringBudgetReportSnapshot {
        let rows = budget.recurringTemplates
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(row)
        let active = rows.filter { $0.status == .active }.count
        let needsDestination = rows.filter { $0.status == .needsDestination }.count
        let summary = "\(rows.count) recurring template\(rows.count == 1 ? "" : "s"). \(active) active. \(needsDestination) need destination repair."
        return RecurringBudgetReportSnapshot(rows: rows, summary: summary)
    }

    func row(for template: RecurringTransactionTemplate) -> RecurringTemplateReportRow {
        RecurringTemplateReportRow(
            id: template.id,
            name: template.name,
            amount: template.amount,
            kind: template.kind,
            frequency: template.frequency,
            interval: template.interval,
            status: status(for: template),
            nextOccurrence: status(for: template) == .ended ? nil : template.nextOccurrence,
            destinationName: template.destinationBudgetItem?.name
        )
    }

    func status(for template: RecurringTransactionTemplate) -> RecurringTemplateStatus {
        if template.destinationBudgetItem == nil { return .needsDestination }
        if !template.isEnabled { return .paused }
        if RecurrenceSchedule(template: template).isAfterEnd(template.nextOccurrence, calendar: calendar) { return .ended }
        return .active
    }
}

@MainActor
private struct NoopPhase4TransactionRepository: TransactionRepository {
    func insert(_ transaction: Transaction) { }
    func delete(_ transaction: Transaction) throws { }
    func save() throws { }
}
