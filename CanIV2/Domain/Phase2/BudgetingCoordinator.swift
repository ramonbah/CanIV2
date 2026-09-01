//
//  BudgetingCoordinator.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class BudgetingCoordinator {
    private let context: ModelContext
    private let clock: AppClock
    private var preferences: Phase2PreferenceStore
    private let budgetRepository: SwiftDataBudgetRepository
    private let planRepository: SwiftDataBudgetPlanRepository
    private let itemRepository: SwiftDataBudgetItemRepository
    private let transactionRepository: SwiftDataTransactionRepository
    private let localDayScheduler: LocalDayRefreshScheduler
    private let salaryStore: SalarySecureStore
    @ObservationIgnored private let receiptScanner: any ReceiptScanningService
    @ObservationIgnored private var recurrenceCoordinator: RecurrenceGenerationCoordinator
    @ObservationIgnored private var quickAddRouter = QuickAddRouteRouter()

    private(set) var budgets: [Budget] = []
    private(set) var settings: AppSettings?
    private(set) var asOfDate: Date
    private(set) var nextLocalDayRefreshDate: Date?
    var navigationSelection = BudgetNavigationSelection()
    private var planSortModes: [UUID: PlanSortMode] = [:]
    private var planSortDirections: [UUID: SortDirection] = [:]
    private var itemSortDirections: [UUID: ItemSortDirection] = [:]
    var selectedTab: MainTab {
        didSet {
            UserDefaults.standard.set(selectedTab.rawValue, forKey: "phase2.selectedTab")
        }
    }
    var reportingPeriod: ReportingPeriod = .last30Days
    var transactionSearchDraft = ""
    private(set) var transactionQuery = TransactionQuery.empty
    var transactionFilterDraft = TransactionFilterDraft.empty
    private(set) var transactionQueryErrorMessage: String?
    var highlightedTransactionID: UUID?
    @ObservationIgnored private var savedTransactionsStateForHomeSeeAll: (searchDraft: String, query: TransactionQuery, filterDraft: TransactionFilterDraft)?
    @ObservationIgnored private var localDayRefreshCancellation: LocalDayRefreshCancellable?
    @ObservationIgnored private var localDayRefreshIsActive = false
    @ObservationIgnored private var injectedCurrencySaveFailureHasFired = false
    @ObservationIgnored private var markAsSpentInFlight: Set<UUID> = []
    private(set) var monthlySalary: Decimal?
    var isSalaryVisible = false
    private(set) var pendingReceipts: [SharedReceiptManifestRecord] = []
    private(set) var quickAddCommand: QuickAddNavigationCommand?
    private(set) var pendingReceiptReviewRequest: PendingReceiptReviewRequest?
    private var dismissedPendingReceiptNoticeIDs: Set<UUID> = []
    var expandedBudgetID: UUID? {
        didSet { preferences.expandedBudgetID = expandedBudgetID }
    }
    private(set) var lastErrorMessage: String?

    convenience init(context: ModelContext, clock: AppClock, preferences: Phase2PreferenceStore) {
        self.init(context: context, clock: clock, preferences: preferences, localDayScheduler: TaskLocalDayRefreshScheduler(), salaryStore: KeychainSalaryStore())
    }

    init(context: ModelContext, clock: AppClock, preferences: Phase2PreferenceStore, localDayScheduler: LocalDayRefreshScheduler, salaryStore: SalarySecureStore = KeychainSalaryStore(), receiptScanner: (any ReceiptScanningService)? = nil) {
        self.context = context
        self.clock = clock
        self.preferences = preferences
        self.localDayScheduler = localDayScheduler
        self.salaryStore = salaryStore
        self.budgetRepository = SwiftDataBudgetRepository(context: context)
        self.planRepository = SwiftDataBudgetPlanRepository(context: context)
        self.itemRepository = SwiftDataBudgetItemRepository(context: context)
        self.transactionRepository = SwiftDataTransactionRepository(context: context)
#if DEBUG
        if ProcessInfo.processInfo.environment["UI_TESTING_FAKE_RECEIPT_SCANNER"] == "1" {
            if ProcessInfo.processInfo.environment["UI_TESTING_FAKE_RECEIPT_SCANNER_ERROR"] == "1" {
                self.receiptScanner = receiptScanner ?? FakeReceiptScanningService(result: ReceiptParser(calendar: clock.calendar, locale: .autoupdatingCurrent).parse(lines: []), error: Phase5ValidationError.scanningFailed)
            } else if ProcessInfo.processInfo.environment["UI_TESTING_FAKE_RECEIPT_SCANNER_PARTIAL"] == "1" {
                self.receiptScanner = receiptScanner ?? FakeReceiptScanningService(result: ReceiptParser(calendar: clock.calendar, locale: .autoupdatingCurrent).parse(lines: [
                    "Synthetic Drink RM 4.50"
                ]))
            } else {
                self.receiptScanner = receiptScanner ?? FakeReceiptScanningService.uiTesting(calendar: clock.calendar)
            }
        } else {
            self.receiptScanner = receiptScanner ?? VisionReceiptScanningService(calendar: clock.calendar)
        }
#else
        self.receiptScanner = receiptScanner ?? VisionReceiptScanningService(calendar: clock.calendar)
#endif
        self.recurrenceCoordinator = RecurrenceGenerationCoordinator(context: context)
        self.asOfDate = clock.now
        self.selectedTab = MainTab(rawValue: UserDefaults.standard.string(forKey: "phase2.selectedTab") ?? "") ?? .home
        self.expandedBudgetID = preferences.expandedBudgetID
        self.monthlySalary = try? salaryStore.readSalary()
        refresh()
    }

    var currencyCode: String {
        settings?.currencyCode ?? CurrencyCatalog.suggestedCurrencyCode()
    }

    var formatter: CurrencyFormatter {
        CurrencyFormatter(currencyCode: currencyCode)
    }

    func selectAdaptiveBudget(_ id: UUID?) {
        expandedBudgetID = id
        navigationSelection.selectBudget(id)
    }

    func synchronizeAdaptiveBudgetSelection(preferNavigationSelection: Bool = true) {
        let selectedID = preferNavigationSelection ? navigationSelection.budgetID ?? expandedBudgetID : expandedBudgetID ?? navigationSelection.budgetID
        expandedBudgetID = selectedID
        if navigationSelection.budgetID == selectedID {
            navigationSelection.budgetID = selectedID
        } else {
            navigationSelection.selectBudget(selectedID)
        }
    }

    func refresh() {
        do {
            asOfDate = clock.now
            settings = try budgetRepository.existingSettings()
            monthlySalary = try salaryStore.readSalary()
            budgets = try budgetRepository.budgets()
            transactionFilterDraft = transactionQueryService.draftByClearingIncompatibleDescendants(transactionFilterDraft, budgets: budgets)
            refreshWidgetDestinationSnapshot()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func reloadPendingReceipts() async {
        do {
            let service = try SharedReceiptInboxService(inboxURL: SharedReceiptInboxLocator().inboxURL())
            pendingReceipts = try await service.pendingReceipts()
        } catch {
            pendingReceipts = []
        }
    }

    func data(forPendingReceipt record: SharedReceiptManifestRecord) async throws -> Data {
        let service = try SharedReceiptInboxService(inboxURL: SharedReceiptInboxLocator().inboxURL())
        return try await service.data(for: record)
    }

    func deletePendingReceipt(_ record: SharedReceiptManifestRecord) async throws {
        let service = try SharedReceiptInboxService(inboxURL: SharedReceiptInboxLocator().inboxURL())
        try await service.delete(record)
        pendingReceipts.removeAll { $0.id == record.id }
    }

    func handleQuickAddURL(_ url: URL) {
        guard let route = QuickAddRoute(url: url),
              let command = quickAddRouter.command(for: route) else { return }
        selectedTab = .budgets
        quickAddCommand = command
    }

    func clearQuickAddCommand() {
        quickAddCommand = nil
    }

    func quickAddDestination(for id: UUID?) -> BudgetItem? {
        guard let id else { return nil }
        return budgets
            .flatMap(\.budgetPlans)
            .flatMap(\.budgetItems)
            .first { $0.id == id }
    }

    func quickAddPlan(fallbackDestinationID: UUID?) -> BudgetPlan? {
        if let destination = quickAddDestination(for: fallbackDestinationID) {
            return destination.budgetPlan
        }
        let selectedBudget = budgets.first { $0.id == navigationSelection.budgetID } ?? budgets.first
        return selectedBudget?.budgetPlans.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    var pendingReceiptNotice: SharedReceiptManifestRecord? {
        pendingReceipts.first { !dismissedPendingReceiptNoticeIDs.contains($0.id) }
    }

    func dismissPendingReceiptNotice(_ record: SharedReceiptManifestRecord) {
        dismissedPendingReceiptNoticeIDs.insert(record.id)
    }

    func requestPendingReceiptReview(_ record: SharedReceiptManifestRecord, imageData: Data) {
        selectedTab = .budgets
        pendingReceiptReviewRequest = PendingReceiptReviewRequest(record: record, imageData: imageData)
        dismissPendingReceiptNotice(record)
    }

    func clearPendingReceiptReviewRequest() {
        pendingReceiptReviewRequest = nil
    }

    private func refreshWidgetDestinationSnapshot() {
        do {
            var items: [WidgetDestinationSnapshot.Item] = []
            for budget in budgets {
                for plan in budget.budgetPlans {
                    for item in plan.budgetItems {
                        items.append(WidgetDestinationSnapshot.Item(id: item.id, name: item.name, planName: plan.name))
                    }
                }
            }
            items.sort { lhs, rhs in
                lhs.planName == rhs.planName ? lhs.name < rhs.name : lhs.planName < rhs.planName
            }
            try WidgetDestinationSnapshotStore.appGroupStore().write(WidgetDestinationSnapshot(updatedAt: clock.now, items: items))
        } catch {
            // Widget data is a non-authoritative snapshot; app behavior cannot depend on it.
        }
    }

    @discardableResult
    func processDueRecurringTransactions(limit: Int = 100) throws -> Int {
        let count = try recurrenceCoordinator.processDueTemplates(in: budgets, clock: FixedClock(now: clock.now, calendar: clock.calendar), limit: limit)
        refresh()
        return count
    }

    func clearError() {
        lastErrorMessage = nil
    }

    var timeEffortConfiguration: TimeEffortConfiguration {
        TimeEffortConfiguration(
            monthlySalary: monthlySalary,
            monthlyWorkingHours: preferences.monthlyWorkingHoursText.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } ?? 160,
            hoursPerWorkday: preferences.hoursPerWorkdayText.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } ?? 8
        )
    }

    func saveMonthlySalary(_ salary: Decimal) -> Bool {
        do {
            try salaryStore.saveSalary(salary)
            monthlySalary = salary
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func clearMonthlySalary() -> Bool {
        do {
            try salaryStore.clearSalary()
            monthlySalary = nil
            isSalaryVisible = false
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func saveTimeEffortSchedule(monthlyWorkingHours: Decimal, hoursPerWorkday: Decimal) throws {
        var config = timeEffortConfiguration
        config.monthlyWorkingHours = monthlyWorkingHours
        config.hoursPerWorkday = hoursPerWorkday
        try config.validateSchedule()
        preferences.monthlyWorkingHoursText = NSDecimalNumber(decimal: monthlyWorkingHours).stringValue
        preferences.hoursPerWorkdayText = NSDecimalNumber(decimal: hoursPerWorkday).stringValue
    }

    func hideSalary() {
        isSalaryVisible = false
    }

    func effortSnapshot(for amount: Decimal) throws -> TimeEffortSnapshot {
        try TimeEffortCalculator(locale: formatter.locale).snapshot(amount: amount, configuration: timeEffortConfiguration)
    }

    func refreshIfLocalDayChanged() {
        let newDate = clock.now
        if !clock.calendar.isDate(asOfDate, inSameDayAs: newDate) {
            asOfDate = newDate
            refresh()
        }
        scheduleNextLocalDayRefresh()
    }

    func setAsOfDateForTesting(_ date: Date) {
        asOfDate = date
        scheduleNextLocalDayRefresh()
    }

    func scheduleNextLocalDayRefresh() {
        nextLocalDayRefreshDate = Self.nextLocalDayBoundary(after: clock.now, calendar: clock.calendar)
        restartLocalDayRefreshIfNeeded()
    }

    func refreshForCalendarOrTimeChange() {
        asOfDate = clock.now
        refresh()
        scheduleNextLocalDayRefresh()
    }

    func startLocalDayRefreshLoop() {
        localDayRefreshIsActive = true
        scheduleNextLocalDayRefresh()
    }

    func stopLocalDayRefreshLoop() {
        localDayRefreshIsActive = false
        localDayRefreshCancellation?.cancel()
        localDayRefreshCancellation = nil
    }

    private func restartLocalDayRefreshIfNeeded() {
        localDayRefreshCancellation?.cancel()
        localDayRefreshCancellation = nil
        guard localDayRefreshIsActive, let boundary = nextLocalDayRefreshDate else { return }
        localDayRefreshCancellation = localDayScheduler.schedule(at: boundary, clock: clock) { [weak self] in
            self?.refreshIfLocalDayChanged()
        }
    }

    static func nextLocalDayBoundary(after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    func ensureSettings(defaultCurrencyCode: String) -> Bool {
        do {
            settings = try budgetRepository.settings(defaultCurrencyCode: defaultCurrencyCode)
            try budgetRepository.save()
            refresh()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func saveCurrency(_ currencyCode: String) -> Bool {
#if DEBUG
        if ProcessInfo.processInfo.environment["UI_TESTING_FAIL_CURRENCY_SAVE"] == "1" {
            lastErrorMessage = "Injected currency save failure."
            return false
        }
        if ProcessInfo.processInfo.environment["UI_TESTING_FAIL_CURRENCY_SAVE_ONCE"] == "1", !injectedCurrencySaveFailureHasFired {
            injectedCurrencySaveFailureHasFired = true
            lastErrorMessage = "Injected currency save failure."
            return false
        }
#endif
        do {
            let appSettings = try budgetRepository.settings(defaultCurrencyCode: currencyCode)
            try SettingsUseCase(repository: budgetRepository).setCurrencyCode(currencyCode, on: appSettings, at: clock.now)
            settings = appSettings
            refresh()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func budgetCount() -> Int {
        (try? budgetRepository.budgetCount()) ?? budgets.count
    }

    func createBudget(name: String) throws -> Budget {
        let budget = try BudgetUseCase(repository: budgetRepository).create(name: name, now: clock.now)
        expandedBudgetID = budget.id
        refresh()
        return budget
    }

    func renameBudget(_ budget: Budget, name: String) throws {
        try BudgetUseCase(repository: budgetRepository).rename(budget, name: name, now: clock.now)
        refresh()
    }

    func deleteBudget(_ budget: Budget) throws {
        try BudgetUseCase(repository: budgetRepository).delete(budget)
        if expandedBudgetID == budget.id {
            expandedBudgetID = nil
        }
        refresh()
    }

    func budgetDeletionImpact(for budget: Budget) -> DeletionImpact {
        DeletionImpactUseCase().impact(for: budget)
    }

    func budgetTotals(for budget: Budget) -> BudgetTotals {
        Phase2Calculations.budgetTotals(for: budget, asOf: asOfDate, calendar: clock.calendar)
    }

    func createPlan(name: String, amountText: String, in budget: Budget) throws -> BudgetPlan {
        let amount = try parseNonNegativeAmount(amountText)
        let plan = try PlanUseCase(repository: planRepository).create(name: name, startingAmount: amount, in: budget, now: clock.now)
        refresh()
        return plan
    }

    func updatePlan(_ plan: BudgetPlan, name: String, amountText: String) throws {
        let amount = try parseNonNegativeAmount(amountText)
        try PlanUseCase(repository: planRepository).update(plan, name: name, startingAmount: amount, now: clock.now)
        refresh()
    }

    func deletePlan(_ plan: BudgetPlan) throws {
        try PlanUseCase(repository: planRepository).delete(plan, now: clock.now)
        refresh()
    }

    func reorderPlans(_ plans: [BudgetPlan]) throws {
        try PlanUseCase(repository: planRepository).reorder(plans, now: clock.now)
        refresh()
    }

    func planDeletionImpact(for plan: BudgetPlan) -> DeletionImpact {
        DeletionImpactUseCase().impact(for: plan)
    }

    func planSortMode(for budget: Budget) -> PlanSortMode {
        if let cached = planSortModes[budget.id] { return cached }
        let value = preferences.planSortMode(for: budget.id)
        planSortModes[budget.id] = value
        return value
    }

    func planSortDirection(for budget: Budget) -> SortDirection {
        if let cached = planSortDirections[budget.id] { return cached }
        let value = preferences.planSortDirection(for: budget.id)
        planSortDirections[budget.id] = value
        return value
    }

    @discardableResult
    func requestPlanSortMode(_ mode: PlanSortMode, for budget: Budget) -> Bool {
        if mode == .manual, planSortMode(for: budget) != .manual {
            return true
        }
        setPlanSortMode(mode, for: budget)
        return false
    }

    func restoreManualPlanOrder(for budget: Budget) {
        setPlanSortMode(.manual, for: budget)
    }

    func replaceManualPlanOrder(with plans: [BudgetPlan], for budget: Budget) throws {
        try reorderPlans(plans)
        setPlanSortMode(.manual, for: budget)
    }

    func setPlanSortMode(_ mode: PlanSortMode, for budget: Budget) {
        planSortModes[budget.id] = mode
        preferences.setPlanSortMode(mode, for: budget.id)
    }

    func setPlanSortDirection(_ direction: SortDirection, for budget: Budget) {
        planSortDirections[budget.id] = direction
        preferences.setPlanSortDirection(direction, for: budget.id)
    }

    func sortedPlans(for budget: Budget) -> [BudgetPlan] {
        SortUseCase().plans(budget.budgetPlans, mode: planSortMode(for: budget), direction: planSortDirection(for: budget))
    }

    func plan(with id: UUID) -> BudgetPlan? {
        budgets.flatMap(\.budgetPlans).first { $0.id == id }
    }

    func item(with id: UUID) -> BudgetItem? {
        budgets.flatMap(\.budgetPlans).flatMap(\.budgetItems).first { $0.id == id }
    }

    func transaction(with id: UUID) -> Transaction? {
        budgets.flatMap(\.budgetPlans).flatMap(\.budgetItems).flatMap(\.transactions).first { $0.id == id }
    }

    func planTotals(for plan: BudgetPlan) -> PlanTotals {
        Phase2Calculations.planTotals(for: plan, asOf: asOfDate, calendar: clock.calendar)
    }

    func createItem(name: String, unitAmountText: String, multiplierText: String, in plan: BudgetPlan) throws -> BudgetItem {
        let unitAmount = try parseNonNegativeAmount(unitAmountText)
        let multiplier = try parseMultiplier(multiplierText)
        let item = try ItemUseCase(repository: itemRepository).create(name: name, unitAmount: unitAmount, multiplier: multiplier, in: plan, now: clock.now)
        refresh()
        return item
    }

    func updateItem(_ item: BudgetItem, name: String, unitAmountText: String, multiplierText: String) throws {
        let unitAmount = try parseNonNegativeAmount(unitAmountText)
        let multiplier = try parseMultiplier(multiplierText)
        try ItemUseCase(repository: itemRepository).update(item, name: name, unitAmount: unitAmount, multiplier: multiplier, now: clock.now)
        refresh()
    }

    func deleteItem(_ item: BudgetItem) throws {
        try ItemUseCase(repository: itemRepository).delete(item, now: clock.now)
        refresh()
    }

    func itemDeletionImpact(for item: BudgetItem) -> DeletionImpact {
        DeletionImpactUseCase().impact(for: item)
    }

    func itemSortDirection(for plan: BudgetPlan) -> ItemSortDirection {
        if let cached = itemSortDirections[plan.id] { return cached }
        let value = preferences.itemSortDirection(for: plan.id)
        itemSortDirections[plan.id] = value
        return value
    }

    func setItemSortDirection(_ direction: ItemSortDirection, for plan: BudgetPlan) {
        itemSortDirections[plan.id] = direction
        preferences.setItemSortDirection(direction, for: plan.id)
    }

    func sortedItems(for plan: BudgetPlan) -> [BudgetItem] {
        SortUseCase().items(plan.budgetItems, direction: itemSortDirection(for: plan), asOf: asOfDate, calendar: clock.calendar)
    }

    func rolloverSourcePlans(for destinationPlan: BudgetPlan) -> [RolloverSourcePlan] {
        RolloverUseCase(context: context).sourcePlans(for: destinationPlan)
    }

    @discardableResult
    func rollItems(from sourcePlan: BudgetPlan, itemIDs: Set<UUID>, into destinationPlan: BudgetPlan) throws -> [BudgetItem] {
        let items = try RolloverUseCase(context: context).rollItems(from: sourcePlan, itemIDs: itemIDs, into: destinationPlan, now: clock.now)
        refresh()
        return items
    }

    func visibleItemClassifications(for plan: BudgetPlan) -> [BudgetItemClassification] {
        let classifications = Set(sortedItems(for: plan).map { itemClassification(for: $0) })
        return [.available, .spent, .income].filter { classifications.contains($0) }
    }

    func sortedItems(for plan: BudgetPlan, classification: BudgetItemClassification) -> [BudgetItem] {
        sortedItems(for: plan).filter { itemClassification(for: $0) == classification }
    }

    func itemClassification(for item: BudgetItem) -> BudgetItemClassification {
        Phase2Calculations.itemClassification(for: item, asOf: asOfDate, calendar: clock.calendar)
    }

    func itemTotals(for item: BudgetItem) -> ItemTotals {
        Phase2Calculations.itemTotals(for: item, asOf: asOfDate, calendar: clock.calendar)
    }

    func itemRowPresentation(for item: BudgetItem) -> ItemRowPresentation {
        Phase2Calculations.itemRowPresentation(for: item, asOf: asOfDate, calendar: clock.calendar)
    }

    func itemAllocationPreview(for plan: BudgetPlan, editing item: BudgetItem?, unitAmountText: String, multiplierText: String) -> ItemAllocationPreview? {
        let amountPolicy = LocalizedNumericEditingPolicy(locale: formatter.locale)
        let multiplierPolicy = LocalizedNumericEditingPolicy(locale: formatter.locale, kind: .wholeNumber)
        guard let unitAmount = amountPolicy.completeDecimal(from: unitAmountText),
              let multiplier = multiplierPolicy.completeDecimal(from: multiplierText),
              unitAmount >= 0,
              multiplier > 0 else {
            return nil
        }
        return Phase2Calculations.allocationPreview(for: plan, editing: item, draftUnitAmount: unitAmount, draftMultiplier: multiplier, asOf: asOfDate, calendar: clock.calendar)
    }

    func transactionProjection(kind: TransactionKind, amountText: String, date: Date, destination item: BudgetItem?, transaction: Transaction?, createsNewItem: Bool, plan: BudgetPlan) -> TransactionProjection? {
        guard let amount = formatter.parse(amountText), amount > 0, formatter.hasValidMinorUnits(amountText) else {
            return nil
        }
        if createsNewItem {
            return Phase2Calculations.newItemTransactionProjection(in: plan, draftKind: kind, draftAmount: amount, draftDate: date, asOf: asOfDate, calendar: clock.calendar)
        }
        guard let item else { return nil }
        return Phase2Calculations.transactionProjection(in: plan, destination: item, editing: transaction, draftKind: kind, draftAmount: amount, draftDate: date, asOf: asOfDate, calendar: clock.calendar)
    }

    func scanReceipt(imageData: Data) async throws -> ReceiptScanResult {
        try await receiptScanner.scan(imageData: imageData)
    }

    func markAsSpentPreview(for item: BudgetItem) -> MarkAsSpentPreview {
        var preview = Phase2Calculations.markAsSpentPreview(for: item, asOf: asOfDate, calendar: clock.calendar)
        if markAsSpentInFlight.contains(item.id) {
            preview = MarkAsSpentPreview(isEligible: false, amount: preview.amount)
        }
        return preview
    }

    func sortedTransactions(for item: BudgetItem) -> [Transaction] {
        SortUseCase().transactions(item.transactions)
    }

    func transactionDaySections(for item: BudgetItem) -> [TransactionDaySection] {
        TransactionDayGrouper(calendar: clock.calendar, locale: .autoupdatingCurrent, now: asOfDate)
            .sections(for: item.transactions)
    }

    var transactionResults: [TransactionResultSnapshot] {
        transactionQueryService.results(for: budgets, query: transactionQuery)
    }

    var transactionResultSections: [TransactionResultSection] {
        transactionQueryService.sections(for: transactionResults)
    }

    var hasAnyTransactions: Bool {
        budgets.flatMap(\.budgetPlans).flatMap(\.budgetItems).contains { !$0.transactions.isEmpty }
    }

    func submitTransactionSearch() {
        do {
            transactionQuery = try transactionQueryService.query(from: transactionFilterDraft, submittedSearchText: transactionSearchDraft, formatter: formatter)
            transactionQueryErrorMessage = nil
        } catch {
            transactionQueryErrorMessage = error.localizedDescription
        }
    }

    func applyTransactionFilters() {
        do {
            transactionQuery = try transactionQueryService.query(from: transactionFilterDraft, submittedSearchText: transactionQuery.submittedSearchText, formatter: formatter)
            transactionSearchDraft = transactionQuery.submittedSearchText
            transactionQueryErrorMessage = nil
        } catch {
            transactionQueryErrorMessage = error.localizedDescription
        }
    }

    func clearTransactionQuery() {
        transactionSearchDraft = ""
        transactionFilterDraft = .empty
        transactionQuery = .empty
        transactionQueryErrorMessage = nil
        savedTransactionsStateForHomeSeeAll = nil
    }

    func removeTransactionFilterChip(_ chip: TransactionFilterChip) {
        switch chip {
        case .search:
            transactionSearchDraft = ""
            transactionQuery.submittedSearchText = ""
        case .budget(let id):
            transactionFilterDraft.budgetIDs.remove(id)
            transactionFilterDraft = transactionQueryService.draftByClearingIncompatibleDescendants(transactionFilterDraft, budgets: budgets)
        case .plan(let id):
            transactionFilterDraft.planIDs.remove(id)
            transactionFilterDraft = transactionQueryService.draftByClearingIncompatibleDescendants(transactionFilterDraft, budgets: budgets)
        case .item(let id):
            transactionFilterDraft.itemIDs.remove(id)
        case .kind(let kind):
            transactionFilterDraft.kinds.remove(kind)
        case .date:
            transactionFilterDraft.dateCriterion = .none
        case .minimumAmount:
            transactionFilterDraft.minimumAmountText = ""
        case .maximumAmount:
            transactionFilterDraft.maximumAmountText = ""
        case .receipt:
            transactionFilterDraft.receiptCriterion = .all
        }
        do {
            transactionQuery = try transactionQueryService.query(from: transactionFilterDraft, submittedSearchText: transactionSearchDraft, formatter: formatter)
            transactionQueryErrorMessage = nil
        } catch {
            transactionQueryErrorMessage = error.localizedDescription
        }
    }

    func setTransactionDraftBudgetSelected(_ budgetID: UUID, selected: Bool) {
        if selected {
            transactionFilterDraft.budgetIDs.insert(budgetID)
        } else {
            transactionFilterDraft.budgetIDs.remove(budgetID)
        }
        transactionFilterDraft = transactionQueryService.draftByClearingIncompatibleDescendants(transactionFilterDraft, budgets: budgets)
    }

    func setTransactionDraftPlanSelected(_ planID: UUID, selected: Bool) {
        if selected {
            transactionFilterDraft.planIDs.insert(planID)
        } else {
            transactionFilterDraft.planIDs.remove(planID)
        }
        transactionFilterDraft = transactionQueryService.draftByClearingIncompatibleDescendants(transactionFilterDraft, budgets: budgets)
    }

    func setTransactionDraftItemSelected(_ itemID: UUID, selected: Bool) {
        if selected {
            transactionFilterDraft.itemIDs.insert(itemID)
        } else {
            transactionFilterDraft.itemIDs.remove(itemID)
        }
    }

    func transactionDraftPlans() -> [BudgetPlan] {
        transactionQueryService.availablePlans(in: budgets, for: transactionFilterDraft)
    }

    func transactionDraftItems() -> [BudgetItem] {
        transactionQueryService.availableItems(in: budgets, for: transactionFilterDraft)
    }

    func transactionDraftPlansByBudget() -> [(budget: Budget, plans: [BudgetPlan])] {
        guard !transactionFilterDraft.budgetIDs.isEmpty else { return [] }
        return budgets
            .filter { transactionFilterDraft.budgetIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { budget in
                let plans = budget.budgetPlans.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return (budget, plans)
            }
            .filter { !$0.plans.isEmpty }
    }

    func transactionDraftItemsByPlan() -> [(budget: Budget, plan: BudgetPlan, items: [BudgetItem])] {
        guard !transactionFilterDraft.planIDs.isEmpty else { return [] }
        return transactionDraftPlansByBudget().flatMap { budget, plans in
            plans
                .filter { transactionFilterDraft.planIDs.contains($0.id) }
                .map { plan in
                    let items = plan.budgetItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    return (budget, plan, items)
                }
        }
        .filter { !$0.items.isEmpty }
    }

    func transactionFilterChips() -> [TransactionFilterChip] {
        var chips: [TransactionFilterChip] = []
        if transactionQuery.hasSubmittedSearch { chips.append(.search(transactionQuery.submittedSearchText)) }
        chips += transactionQuery.budgetIDs.sorted { $0.uuidString < $1.uuidString }.map(TransactionFilterChip.budget)
        chips += transactionQuery.planIDs.sorted { $0.uuidString < $1.uuidString }.map(TransactionFilterChip.plan)
        chips += transactionQuery.itemIDs.sorted { $0.uuidString < $1.uuidString }.map(TransactionFilterChip.item)
        chips += transactionQuery.kinds.sorted { $0.rawValue < $1.rawValue }.map(TransactionFilterChip.kind)
        if transactionQuery.dateCriterion != .none { chips.append(.date(transactionQuery.dateCriterion)) }
        if transactionQuery.minimumAmount != nil { chips.append(.minimumAmount) }
        if transactionQuery.maximumAmount != nil { chips.append(.maximumAmount) }
        if transactionQuery.receiptCriterion != .all { chips.append(.receipt(transactionQuery.receiptCriterion)) }
        return chips
    }

    func label(for chip: TransactionFilterChip) -> String {
        switch chip {
        case .search(let text): "Search: \(text)"
        case .budget(let id): "Budget: \(budgets.first { $0.id == id }?.name ?? "Deleted")"
        case .plan(let id): "Plan: \(contextLabel(forPlanID: id))"
        case .item(let id): "Item: \(contextLabel(forItemID: id))"
        case .kind(let kind): kind == .income ? "Income" : "Expense"
        case .date(let criterion):
            switch criterion {
            case .none: "Date"
            case .preset(let period): period.title
            case .custom: "Custom Range"
            }
        case .minimumAmount: "Minimum"
        case .maximumAmount: "Maximum"
        case .receipt(let criterion): criterion.title
        }
    }

    func contextLabel(forPlanID id: UUID) -> String {
        guard let plan = plan(with: id) else { return "Deleted" }
        return "\(plan.budget.name) / \(plan.name)"
    }

    func contextLabel(forItemID id: UUID) -> String {
        guard let item = item(with: id) else { return "Deleted" }
        return "\(item.budgetPlan.budget.name) / \(item.budgetPlan.name) / \(item.name)"
    }

    func openTransactionRoute(_ route: TransactionRouteSnapshot) {
        navigationSelection.selectBudget(route.budgetID)
        navigationSelection.selectPlan(route.planID)
        navigationSelection.selectItem(route.itemID)
        highlightedTransactionID = route.transactionID
    }

    func openBudgetReports(for budget: Budget) {
        navigationSelection = BudgetNavigationSelection(budgetID: budget.id, report: .budget(budget.id))
    }

    func openPlanReports(for plan: BudgetPlan) {
        navigationSelection = BudgetNavigationSelection(budgetID: plan.budget.id, planID: plan.id, report: .plan(plan.id))
    }

    func beginHomeSeeAllTransactions() {
        if savedTransactionsStateForHomeSeeAll == nil {
            savedTransactionsStateForHomeSeeAll = (transactionSearchDraft, transactionQuery, transactionFilterDraft)
        }
        transactionSearchDraft = ""
        transactionFilterDraft = TransactionFilterDraft(dateCriterion: .preset(reportingPeriod))
        do {
            transactionQuery = try transactionQueryService.query(from: transactionFilterDraft, submittedSearchText: "", formatter: formatter)
            transactionQueryErrorMessage = nil
        } catch {
            transactionQueryErrorMessage = error.localizedDescription
        }
    }

    func restoreTransactionsStateAfterHomeSeeAll() {
        guard let savedTransactionsStateForHomeSeeAll else { return }
        transactionSearchDraft = savedTransactionsStateForHomeSeeAll.searchDraft
        transactionQuery = savedTransactionsStateForHomeSeeAll.query
        transactionFilterDraft = savedTransactionsStateForHomeSeeAll.filterDraft
        self.savedTransactionsStateForHomeSeeAll = nil
    }

    func homeSnapshot() -> HomeReportSnapshot {
        reportService.homeSnapshot(budgets: budgets, period: reportingPeriod, formatter: formatter)
    }

    func budgetReportSnapshot(for budget: Budget) -> BudgetReportSnapshot {
        let interval = budgetReportInterval(for: budget)
        return reportService.budgetSnapshot(budget: budget, period: reportingPeriod, interval: interval, formatter: formatter)
    }

    func recurringReportSnapshot(for budget: Budget) -> RecurringBudgetReportSnapshot {
        RecurringReportService(calendar: clock.calendar, asOf: asOfDate, formatter: formatter).snapshot(for: budget)
    }

    func recurringStatus(for template: RecurringTransactionTemplate) -> RecurringTemplateStatus {
        RecurringReportService(calendar: clock.calendar, asOf: asOfDate, formatter: formatter).status(for: template)
    }

    func planReportSnapshot(for plan: BudgetPlan) -> PlanReportSnapshot {
        reportService.planSnapshot(plan: plan, period: reportingPeriod, timelineMode: planTimelineMode(for: plan), formatter: formatter)
    }

    func reportRangeDescription(_ range: ReportPeriodRange) -> String {
        range.localizedDescription(calendar: clock.calendar, locale: .autoupdatingCurrent)
    }

    func displayDate(_ date: Date) -> String {
        UserVisibleDateFormatter(calendar: clock.calendar, locale: .autoupdatingCurrent, referenceDate: asOfDate).string(for: date)
    }

    func hasMeaningfulBudgetReports(for budget: Budget) -> Bool {
        reportService.hasMeaningfulBudgetReports(budget: budget, formatter: formatter)
    }

    func hasMeaningfulPlanReports(for plan: BudgetPlan) -> Bool {
        reportService.hasMeaningfulPlanReports(plan: plan, formatter: formatter)
    }

    func automaticBudgetReportInterval() -> ReportBucketInterval {
        switch reportingPeriod {
        case .last7Days, .last30Days, .currentMonth: .day
        case .last90Days: .week
        case .allTime: .month
        }
    }

    func budgetReportInterval(for budget: Budget) -> ReportBucketInterval {
        preferences.budgetReportInterval(for: budget.id, periodID: reportingPeriod.id) ?? automaticBudgetReportInterval()
    }

    func setBudgetReportInterval(_ interval: ReportBucketInterval, for budget: Budget) {
        preferences.setBudgetReportInterval(interval, for: budget.id, periodID: reportingPeriod.id)
    }

    func planTimelineMode(for plan: BudgetPlan) -> PlanTimelineMode {
        preferences.planTimelineMode(for: plan.id) ?? .balance
    }

    func setPlanTimelineMode(_ mode: PlanTimelineMode, for plan: BudgetPlan) {
        preferences.setPlanTimelineMode(mode, for: plan.id)
    }

    private var transactionQueryService: TransactionQueryService {
        TransactionQueryService(calendar: clock.calendar, locale: .autoupdatingCurrent, asOf: asOfDate)
    }

    private var reportService: DefaultReportService {
        DefaultReportService(calendar: clock.calendar, locale: .autoupdatingCurrent, asOf: asOfDate)
    }

    func isScheduledIncome(_ transaction: Transaction) -> Bool {
        transaction.kind == .income && !Phase2Calculations.isEffective(transaction, asOf: asOfDate, calendar: clock.calendar)
    }

    @discardableResult
    func createRecurringTemplate(name: String, amountText: String, kind: TransactionKind, frequency: RecurrenceFrequency, intervalText: String, startDate: Date, endDate: Date?, budget: Budget, destination: BudgetItem?) throws -> RecurringTransactionTemplate {
        let amount = try parsePositiveAmount(amountText)
        let interval = try parsePositiveWholeNumber(intervalText)
        let template = try RecurringTemplateUseCase(context: context).create(
            name: name,
            amount: amount,
            kind: kind,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            endDate: endDate,
            budget: budget,
            destination: destination,
            clock: FixedClock(now: clock.now, calendar: clock.calendar)
        )
        refresh()
        return template
    }

    func updateRecurringTemplate(_ template: RecurringTransactionTemplate, name: String, amountText: String, kind: TransactionKind, frequency: RecurrenceFrequency, intervalText: String, startDate: Date, endDate: Date?, destination: BudgetItem?) throws {
        let amount = try parsePositiveAmount(amountText)
        let interval = try parsePositiveWholeNumber(intervalText)
        try RecurringTemplateUseCase(context: context).update(
            template,
            name: name,
            amount: amount,
            kind: kind,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            endDate: endDate,
            destination: destination,
            clock: FixedClock(now: clock.now, calendar: clock.calendar)
        )
        refresh()
    }

    func setRecurringTemplateEnabled(_ template: RecurringTransactionTemplate, enabled: Bool) throws {
        try RecurringTemplateUseCase(context: context).setEnabled(enabled, for: template, clock: FixedClock(now: clock.now, calendar: clock.calendar))
        refresh()
    }

    func repairRecurringTemplate(_ template: RecurringTransactionTemplate, destination: BudgetItem) throws {
        try RecurringTemplateUseCase(context: context).repairDestination(destination, for: template, clock: FixedClock(now: clock.now, calendar: clock.calendar))
        refresh()
    }

    func deleteRecurringTemplate(_ template: RecurringTransactionTemplate) throws {
        try RecurringTemplateUseCase(context: context).delete(template)
        refresh()
    }

    func createTransaction(kind: TransactionKind, amountText: String, date: Date, notes: String, item: BudgetItem, receiptDraft: ReceiptAttachmentDraft? = nil) throws -> Transaction {
        let amount = try parsePositiveAmount(amountText)
        let transaction = try TransactionUseCase(repository: transactionRepository).create(kind: kind, amount: amount, date: date, notes: notes, item: item, receiptDraft: receiptDraft, clock: FixedClock(now: clock.now, calendar: clock.calendar))
        refresh()
        return transaction
    }

    func createItemAndTransaction(kind: TransactionKind, amountText: String, date: Date, itemName: String, in plan: BudgetPlan, receiptDraft: ReceiptAttachmentDraft? = nil) throws -> (transaction: Transaction, item: BudgetItem) {
        let amount = try parsePositiveAmount(amountText)
        let trimmedName = NameNormalizer.trimmed(itemName)
        try ValidationUseCase.validateName(trimmedName, siblings: plan.budgetItems.map(\.name))
        try ValidationUseCase.validateItemAmounts(unitAmount: amount, multiplier: 1)
        try ValidationUseCase.validateTransaction(kind: kind, amount: amount, date: date, calendar: clock.calendar, asOf: clock.now)

        let originalPlanUpdatedAt = plan.updatedAt
        let originalBudgetUpdatedAt = plan.budget.updatedAt
        let nextOrder = ((plan.budgetItems.map(\.sortOrder).max() ?? -1) + 1)
        let item = BudgetItem(name: trimmedName, unitAmount: amount, multiplier: 1, sortOrder: nextOrder, createdAt: clock.now, updatedAt: clock.now, budgetPlan: plan)
        let transaction = Transaction(
            name: TransactionUseCase(repository: transactionRepository).generatedName(for: kind),
            amount: amount,
            kind: kind,
            date: date,
            notes: trimmedName,
            createdAt: clock.now,
            updatedAt: clock.now,
            budgetItem: item
        )
        let receipt = receiptDraft.map {
            ReceiptCapture(
                imageData: $0.imageData,
                merchant: $0.merchant,
                date: $0.date,
                total: $0.total,
                createdAt: clock.now,
                updatedAt: clock.now,
                transaction: transaction
            )
        }
        let receiptLines = receiptDraft?.lines.map { draft in
            ReceiptLineItem(
                rawText: draft.rawText,
                name: draft.name,
                amount: draft.amount,
                isSelected: draft.isSelected,
                createdAt: clock.now,
                updatedAt: clock.now,
                receiptCapture: receipt!
            )
        } ?? []
        receipt?.lineItems = receiptLines
        transaction.receipt = receipt
        plan.budgetItems.append(item)
        item.transactions.append(transaction)
        plan.updatedAt = clock.now
        plan.budget.updatedAt = clock.now
        context.insert(item)
        context.insert(transaction)
        if let receipt {
            context.insert(receipt)
            receiptLines.forEach(context.insert)
        }
        do {
            try ModelMutationService.saveValidated(context)
            refresh()
            return (transaction, item)
        } catch {
            item.transactions.removeAll { $0.id == transaction.id }
            plan.budgetItems.removeAll { $0.id == item.id }
            plan.updatedAt = originalPlanUpdatedAt
            plan.budget.updatedAt = originalBudgetUpdatedAt
            receiptLines.forEach(context.delete)
            if let receipt {
                context.delete(receipt)
            }
            context.delete(transaction)
            context.delete(item)
            context.rollback()
            throw error
        }
    }

    @discardableResult
    func markItemAsSpent(_ item: BudgetItem) throws -> Transaction {
        let preview = markAsSpentPreview(for: item)
        guard preview.isEligible, preview.amount > 0 else {
            throw Phase2ValidationError.invalidAmount
        }
        guard !markAsSpentInFlight.contains(item.id) else {
            throw Phase2ValidationError.invalidAmount
        }
        markAsSpentInFlight.insert(item.id)
        defer { markAsSpentInFlight.remove(item.id) }
        let transaction = try TransactionUseCase(repository: transactionRepository).create(
            kind: .expense,
            amount: preview.amount,
            date: clock.calendar.startOfDay(for: clock.now),
            notes: item.name,
            item: item,
            clock: FixedClock(now: clock.now, calendar: clock.calendar)
        )
        refresh()
        return transaction
    }

    func updateTransaction(_ transaction: Transaction, kind: TransactionKind, amountText: String, date: Date, notes: String, destinationItem: BudgetItem) throws -> BudgetItem? {
        guard let sourceItem = transaction.budgetItem else { throw Phase2ValidationError.missingParentRelationship }
        let amount = try parsePositiveAmount(amountText)
        try TransactionUseCase(repository: transactionRepository).update(transaction, kind: kind, amount: amount, date: date, notes: notes, destinationItem: destinationItem, clock: FixedClock(now: clock.now, calendar: clock.calendar))
        refresh()
        return sourceItem.id == destinationItem.id ? nil : destinationItem
    }

    func deleteTransaction(_ transaction: Transaction) throws {
        try TransactionUseCase(repository: transactionRepository).delete(transaction, now: clock.now)
        refresh()
    }

    func replaceReceipt(on transaction: Transaction, with draft: ReceiptAttachmentDraft) throws {
        try ReceiptUseCase(context: context).replaceReceipt(on: transaction, with: draft, now: clock.now)
        refresh()
    }

    func updateReceiptDetails(on transaction: Transaction, with draft: ReceiptAttachmentDraft, transactionAmount: Decimal?) throws {
        try ReceiptUseCase(context: context).updateReceiptDetails(on: transaction, with: draft, transactionAmount: transactionAmount, now: clock.now)
        refresh()
    }

    func removeReceipt(from transaction: Transaction) throws {
        try ReceiptUseCase(context: context).removeReceipt(from: transaction, now: clock.now)
        refresh()
    }

    func transactionDeletionTitle(for transaction: Transaction) -> String {
        let date = UserVisibleDateFormatter(calendar: clock.calendar, locale: .autoupdatingCurrent, referenceDate: asOfDate).string(for: transaction.date)
        let receiptSuffix = transaction.receipt == nil ? "" : " The attached receipt and recognized lines will also be deleted."
        return "Delete \(transaction.kind == .income ? "income" : "expense") \(formatter.string(for: transaction.amount)) from \(date)?\(receiptSuffix)"
    }

    func transactionAccessibilityLabel(for transaction: Transaction) -> String {
        let date = UserVisibleDateFormatter(calendar: clock.calendar, locale: .autoupdatingCurrent, referenceDate: asOfDate).string(for: transaction.date)
        let receiptSuffix = transaction.receipt == nil ? "" : ", has receipt"
        return "\(transaction.kind == .income ? "Income" : "Expense"), \(formatter.string(for: transaction.amount)), \(date)\(transaction.notes.map { ", \($0)" } ?? "")\(receiptSuffix)"
    }

    func progress(spent: Decimal, funds: Decimal) -> ProgressState {
        Phase2Calculations.progress(spent: spent, funds: funds, formatter: formatter)
    }

    func roundingDisclosure(components: [Decimal], total: Decimal) -> RoundingDisclosure? {
        formatter.displayMismatch(components: components, total: total)
    }

    func plannedComponents(for item: BudgetItem) -> [Decimal] {
        let count = Int(truncating: item.multiplier as NSDecimalNumber)
        guard count > 0, Decimal(count) == item.multiplier, count <= 500 else {
            return [item.unitAmount * item.multiplier]
        }
        return Array(repeating: item.unitAmount, count: count)
    }

    func incomeComponents(for item: BudgetItem) -> [Decimal] {
        item.transactions
            .filter { $0.kind == .income && Phase2Calculations.isEffective($0, asOf: asOfDate, calendar: clock.calendar) }
            .map(\.amount)
    }

    func expenseComponents(for item: BudgetItem) -> [Decimal] {
        item.transactions
            .filter { $0.kind == .expense }
            .map(\.amount)
    }

    func parseNonNegativeAmount(_ text: String) throws -> Decimal {
        guard let amount = formatter.parse(text) else { throw Phase2ValidationError.invalidAmount }
        guard formatter.hasValidMinorUnits(text) else { throw Phase2ValidationError.tooManyFractionDigits(formatter.minorUnits) }
        guard amount >= 0 else { throw Phase2ValidationError.negativeAmount }
        return amount
    }

    func parsePositiveAmount(_ text: String) throws -> Decimal {
        guard let amount = formatter.parse(text) else { throw Phase2ValidationError.invalidAmount }
        guard formatter.hasValidMinorUnits(text) else { throw Phase2ValidationError.tooManyFractionDigits(formatter.minorUnits) }
        guard amount > 0 else { throw Phase2ValidationError.nonPositiveAmount }
        return amount
    }

    func parseMultiplier(_ text: String) throws -> Decimal {
        let policy = LocalizedNumericEditingPolicy(locale: .autoupdatingCurrent, kind: .wholeNumber)
        guard let multiplier = policy.completeDecimal(from: text), multiplier > 0, multiplier == Decimal(Int(truncating: multiplier as NSDecimalNumber)) else {
            throw Phase2ValidationError.invalidMultiplier
        }
        return multiplier
    }

    func parsePositiveWholeNumber(_ text: String) throws -> Int {
        let value = try parseMultiplier(text)
        return Int(truncating: value as NSDecimalNumber)
    }

#if DEBUG
    func seedRoundingMismatchForUITesting() {
        guard ProcessInfo.processInfo.environment["UI_TESTING_SEED_ROUNDING"] == "1", budgets.isEmpty else { return }
        do {
            _ = saveCurrency("BHD")
            let budget = try BudgetUseCase(repository: budgetRepository).create(name: "Rounding", now: clock.now)
            let plan = try PlanUseCase(repository: planRepository).create(name: "Seed Plan", startingAmount: 0, in: budget, now: clock.now)
            _ = try ItemUseCase(repository: itemRepository).create(name: "First", unitAmount: Decimal(string: "0.3")!, multiplier: 1, in: plan, now: clock.now)
            _ = try ItemUseCase(repository: itemRepository).create(name: "Second", unitAmount: Decimal(string: "0.3")!, multiplier: 1, in: plan, now: clock.now)
            _ = saveCurrency("JPY")
            expandedBudgetID = budget.id
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func seedNumericEditingForUITesting() {
        guard ProcessInfo.processInfo.environment["UI_TESTING_SEED_NUMERIC"] == "1", budgets.isEmpty else { return }
        do {
            _ = saveCurrency("MYR")
            let budget = try BudgetUseCase(repository: budgetRepository).create(name: "Trip", now: clock.now)
            let plan = try PlanUseCase(repository: planRepository).create(name: "August", startingAmount: 0, in: budget, now: clock.now)
            _ = try ItemUseCase(repository: itemRepository).create(name: "Meals", unitAmount: 10, multiplier: 1, in: plan, now: clock.now)
            expandedBudgetID = budget.id
            navigationSelection.selectBudget(budget.id)
            navigationSelection.selectPlan(plan.id)
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func seedSavedReceiptForUITesting() {
        guard ProcessInfo.processInfo.environment["UI_TESTING_SEED_SAVED_RECEIPT"] == "1", budgets.isEmpty else { return }
        do {
            _ = saveCurrency("MYR")
            let now = clock.now
            let budget = try BudgetUseCase(repository: budgetRepository).create(name: "Trip", now: now)
            let plan = try PlanUseCase(repository: planRepository).create(name: "August", startingAmount: 0, in: budget, now: now)
            let meals = try ItemUseCase(repository: itemRepository).create(name: "Meals", unitAmount: 10, multiplier: 1, in: plan, now: now)
            let transaction = try TransactionUseCase(repository: transactionRepository).create(kind: .expense, amount: Decimal(string: "12.30")!, date: now, notes: "Kedai Makan Contoh", item: meals, clock: FixedClock(now: now, calendar: clock.calendar))
            let receipt = ReceiptAttachmentDraft(
                imageData: Data("synthetic saved receipt".utf8),
                merchant: "Kedai Makan Contoh",
                date: now,
                total: Decimal(string: "12.30"),
                lines: [
                    ReceiptLineDraft(rawText: "Nasi Lemak RM 8.50", name: "Nasi Lemak", amount: Decimal(string: "8.50"), isSelected: true),
                    ReceiptLineDraft(rawText: "Teh Ais RM 3.20", name: "Teh Ais", amount: Decimal(string: "3.20"), isSelected: false),
                    ReceiptLineDraft(rawText: "Service Charge RM 0.60", name: "Service Charge", amount: Decimal(string: "0.60"), isSelected: true)
                ]
            )
            try ReceiptUseCase(context: context).attach(receipt, to: transaction, now: now)
            expandedBudgetID = budget.id
            navigationSelection.selectBudget(budget.id)
            navigationSelection.selectPlan(plan.id)
            navigationSelection.selectItem(meals.id)
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func seedPhase3ForUITesting() {
        guard ProcessInfo.processInfo.environment["UI_TESTING_SEED_PHASE3"] == "1", budgets.isEmpty else { return }
        do {
            _ = saveCurrency("MYR")
            let now = clock.now
            let budget = try BudgetUseCase(repository: budgetRepository).create(name: "Phase Three Travel Budget With A Long Name", now: now)
            let plan = try PlanUseCase(repository: planRepository).create(name: "August Reports Plan", startingAmount: 500, in: budget, now: now)
            let meals = try ItemUseCase(repository: itemRepository).create(name: "Meals and Snacks", unitAmount: 100, multiplier: 2, in: plan, now: now)
            let lodging = try ItemUseCase(repository: itemRepository).create(name: "Lodging", unitAmount: 400, multiplier: 1, in: plan, now: now)
            let yesterday = clock.calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let twoDaysAgo = clock.calendar.date(byAdding: .day, value: -2, to: now) ?? now
            let future = clock.calendar.date(byAdding: .day, value: 2, to: now) ?? now
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .expense, amount: 20, date: now, notes: "Cafe breakfast", item: meals, clock: FixedClock(now: now, calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .expense, amount: 100, date: yesterday, notes: "Hotel", item: lodging, clock: FixedClock(now: now.addingTimeInterval(1), calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .income, amount: 300, date: twoDaysAgo, notes: "Salary", item: lodging, clock: FixedClock(now: now.addingTimeInterval(2), calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .income, amount: 900, date: future, notes: "Future grant", item: meals, clock: FixedClock(now: now.addingTimeInterval(3), calendar: clock.calendar))
            expandedBudgetID = budget.id
            navigationSelection.selectBudget(budget.id)
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func seedReadmeScreenshotsForUITesting() {
        guard ProcessInfo.processInfo.environment["UI_TESTING_SEED_README_SCREENSHOTS"] == "1", budgets.isEmpty else { return }
        do {
            _ = saveCurrency("MYR")
            try salaryStore.saveSalary(6_400)
            monthlySalary = 6_400
            isSalaryVisible = false

            let now = clock.now
            let yesterday = clock.calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let twoDaysAgo = clock.calendar.date(byAdding: .day, value: -2, to: now) ?? now
            let fiveDaysAgo = clock.calendar.date(byAdding: .day, value: -5, to: now) ?? now
            let eightDaysAgo = clock.calendar.date(byAdding: .day, value: -8, to: now) ?? now

            let household = try BudgetUseCase(repository: budgetRepository).create(name: "Household Budget", now: now)
            let august = try PlanUseCase(repository: planRepository).create(name: "August Essentials", startingAmount: 1_200, in: household, now: now)
            let groceries = try ItemUseCase(repository: itemRepository).create(name: "Groceries", unitAmount: 220, multiplier: 1, in: august, now: now)
            let hotel = try ItemUseCase(repository: itemRepository).create(name: "Hotel Balance", unitAmount: 300, multiplier: 1, in: august, now: now)
            let reimbursement = try ItemUseCase(repository: itemRepository).create(name: "Client Reimbursement", unitAmount: 0, multiplier: 1, in: august, now: now)

            let julyDate = clock.calendar.date(byAdding: .month, value: -1, to: now) ?? now.addingTimeInterval(-2_592_000)
            let july = try PlanUseCase(repository: planRepository).create(name: "July Essentials", startingAmount: 1_100, in: household, now: julyDate)
            _ = try ItemUseCase(repository: itemRepository).create(name: "Weekly groceries", unitAmount: 200, multiplier: 1, in: july, now: julyDate)
            _ = try ItemUseCase(repository: itemRepository).create(name: "Utility reserve", unitAmount: 140, multiplier: 1, in: july, now: julyDate.addingTimeInterval(1))

            let travel = try BudgetUseCase(repository: budgetRepository).create(name: "City Break Budget", now: now.addingTimeInterval(-20))
            let weekend = try PlanUseCase(repository: planRepository).create(name: "Weekend Plan", startingAmount: 450, in: travel, now: now.addingTimeInterval(-20))
            let transit = try ItemUseCase(repository: itemRepository).create(name: "Transit Passes", unitAmount: 80, multiplier: 1, in: weekend, now: now.addingTimeInterval(-20))
            let meals = try ItemUseCase(repository: itemRepository).create(name: "Cafe Meals", unitAmount: 160, multiplier: 1, in: weekend, now: now.addingTimeInterval(-20))

            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .expense, amount: 65, date: now, notes: "Market groceries", item: groceries, clock: FixedClock(now: now.addingTimeInterval(1), calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .expense, amount: 360, date: yesterday, notes: "Hotel balance paid", item: hotel, clock: FixedClock(now: now.addingTimeInterval(2), calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .income, amount: 180, date: twoDaysAgo, notes: "Client meal reimbursement", item: reimbursement, clock: FixedClock(now: now.addingTimeInterval(3), calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .expense, amount: 42, date: twoDaysAgo, notes: "Train tickets", item: transit, clock: FixedClock(now: now.addingTimeInterval(4), calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .expense, amount: 58, date: fiveDaysAgo, notes: "Cafe lunch", item: meals, clock: FixedClock(now: now.addingTimeInterval(5), calendar: clock.calendar))
            _ = try TransactionUseCase(repository: transactionRepository).create(kind: .income, amount: 90, date: eightDaysAgo, notes: "Travel refund", item: transit, clock: FixedClock(now: now.addingTimeInterval(6), calendar: clock.calendar))

            let nextWeek = clock.calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(604_800)
            _ = try createRecurringTemplate(name: "Weekly groceries", amountText: "120", kind: .expense, frequency: .weekly, intervalText: "1", startDate: nextWeek, endDate: nil, budget: household, destination: groceries)
            _ = try createRecurringTemplate(name: "Streaming renewal", amountText: "35", kind: .expense, frequency: .monthly, intervalText: "1", startDate: nextWeek, endDate: nil, budget: household, destination: nil)

            expandedBudgetID = household.id
            navigationSelection.selectBudget(household.id)
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
#endif
}
