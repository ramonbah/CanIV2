import Foundation
import SwiftData
import Testing
@testable import CanIV2

@Suite("Refinement 1 coverage")
struct Refinement1Tests {
    @Test("Localized numeric editing accepts valid English and comma-decimal states")
    func localizedNumericValidStates() throws {
        let english = LocalizedNumericEditingPolicy(locale: Locale(identifier: "en_US"))
        #expect(english.validateEdit("").isAcceptedEdit)
        #expect(!english.validateEdit("").isCompleteNumber)
        #expect(english.validateEdit("1,234.50").decimal == Decimal(string: "1234.50"))
        #expect(english.validateEdit("12.").isAcceptedEdit)
        #expect(!english.validateEdit("12.").isCompleteNumber)

        let german = LocalizedNumericEditingPolicy(locale: Locale(identifier: "de_DE"))
        #expect(german.validateEdit("1.234,50").decimal == Decimal(string: "1234.50"))
        #expect(german.validateEdit("12,").isAcceptedEdit)
        #expect(!german.validateEdit("12,").isCompleteNumber)
    }

    @Test("Localized numeric editing rejects malformed and mixed-content edits")
    func localizedNumericInvalidStates() {
        let policy = LocalizedNumericEditingPolicy(locale: Locale(identifier: "en_US"))
        for text in ["A12", "$12", "1,23", "1.2.3", "12abc", "1,234.5.6", "-1", " 12", "12 "] {
            let result = policy.validateEdit(text)
            #expect(!result.isAcceptedEdit, "Expected rejection for \(text)")
            #expect(result.error != nil)
        }
    }

    @Test("Whole-number numeric editing rejects decimal multipliers")
    func wholeNumberEditing() {
        let policy = LocalizedNumericEditingPolicy(locale: Locale(identifier: "en_US"), kind: .wholeNumber)
        #expect(policy.validateEdit("12").decimal == 12)
        #expect(!policy.validateEdit("12.5").isAcceptedEdit)
    }

    @Test("Currency formatter parses Decimal directly and enforces minor units")
    func formatterParsingAndMinorUnits() throws {
        let formatter = CurrencyFormatter(currencyCode: "MYR", locale: Locale(identifier: "en_US"))
        #expect(formatter.parse("1,234.50") == Decimal(string: "1234.50"))
        #expect(formatter.hasValidMinorUnits("12.34"))
        #expect(!formatter.hasValidMinorUnits("12.345"))
    }

    @Test("Existing Decimal values format as locale-valid editable text")
    func editableDecimalStringsUseLocaleSeparators() throws {
        let value = try #require(Decimal(string: "1234.50"))
        let english = LocalizedNumericEditingPolicy(locale: Locale(identifier: "en_US"))
        let german = LocalizedNumericEditingPolicy(locale: Locale(identifier: "de_DE"))

        #expect(english.editableString(for: value) == "1234.5")
        #expect(german.editableString(for: value) == "1234,5")
        #expect(english.completeDecimal(from: english.editableString(for: value)) == value)
        #expect(german.completeDecimal(from: german.editableString(for: value)) == value)
    }

    @MainActor
    @Test("Transactions are grouped by local day with required headers and ordering")
    func transactionGrouping() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8)))
        let older = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 8)))
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Item", budgetPlan: plan)
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let later = Transaction(id: laterID, name: "Expense", amount: 3, kind: .expense, date: today, createdAt: today.addingTimeInterval(30), budgetItem: item)
        let earlier = Transaction(id: earlierID, name: "Expense", amount: 2, kind: .expense, date: today, createdAt: today, budgetItem: item)
        let y = Transaction(name: "Income", amount: 4, kind: .income, date: yesterday, createdAt: yesterday, budgetItem: item)
        let old = Transaction(name: "Expense", amount: 5, kind: .expense, date: older, createdAt: older, budgetItem: item)

        let sections = TransactionDayGrouper(calendar: calendar, locale: Locale(identifier: "en_US"), now: now)
            .sections(for: [earlier, old, later, y])

        #expect(sections.map(\.header) == ["Today · Tuesday", "Yesterday · Monday", "Sunday, 9 Aug"])
        #expect(sections[0].transactions.map(\.id) == [laterID, earlierID])
    }

    @MainActor
    @Test("Transaction grouping updates across midnight calendar and time-zone changes")
    func transactionGroupingRegroupsForTemporalEnvironmentChanges() throws {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try #require(utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 23, minute: 30)))
        let created = try #require(utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 23, minute: 45)))
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Item", budgetPlan: plan)
        let transaction = Transaction(name: "Income", amount: 4, kind: .income, date: date, createdAt: created, budgetItem: item)

        let beforeMidnight = try #require(utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 23, minute: 50)))
        let afterMidnight = try #require(utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 10)))
        #expect(TransactionDayGrouper(calendar: utcCalendar, locale: Locale(identifier: "en_US"), now: beforeMidnight).sections(for: [transaction]).map(\.header) == ["Today · Tuesday"])
        #expect(TransactionDayGrouper(calendar: utcCalendar, locale: Locale(identifier: "en_US"), now: afterMidnight).sections(for: [transaction]).map(\.header) == ["Yesterday · Tuesday"])

        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(TransactionDayGrouper(calendar: tokyoCalendar, locale: Locale(identifier: "en_US"), now: afterMidnight).sections(for: [transaction]).map(\.header) == ["Today · Wednesday"])

        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(TransactionDayGrouper(calendar: buddhistCalendar, locale: Locale(identifier: "en_US"), now: afterMidnight).sections(for: [transaction]).map(\.header) == ["Yesterday · Tuesday"])
    }

    @MainActor
    @Test("Transaction grouping uses UUID order for equal createdAt values")
    func transactionGroupingUsesUUIDTieBreaker() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12)))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9)))
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Item", budgetPlan: plan)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let second = Transaction(id: secondID, name: "Expense", amount: 2, kind: .expense, date: date, createdAt: date, budgetItem: item)
        let first = Transaction(id: firstID, name: "Expense", amount: 3, kind: .expense, date: date, createdAt: date, budgetItem: item)

        let sections = TransactionDayGrouper(calendar: calendar, locale: Locale(identifier: "en_US"), now: now)
            .sections(for: [second, first])

        #expect(sections.map(\.transactions).flatMap { $0 }.map(\.id) == [firstID, secondID])
    }

    @Test("Budget navigation selection preserves identity and clears descendants intentionally")
    func budgetNavigationSelection() {
        let budgetID = UUID()
        let planID = UUID()
        let itemID = UUID()
        let nextBudgetID = UUID()
        var selection = BudgetNavigationSelection(budgetID: budgetID, planID: planID, itemID: itemID)
        selection.selectPlan(nil)
        #expect(selection.budgetID == budgetID)
        #expect(selection.planID == nil)
        #expect(selection.itemID == nil)
        selection.selectBudget(nextBudgetID)
        #expect(selection.budgetID == nextBudgetID)
        #expect(selection.planID == nil)
        #expect(selection.itemID == nil)
    }

    @MainActor
    @Test("Adaptive Budget selection keeps wide and compact state synchronized")
    func adaptiveBudgetSelectionSynchronizesAcrossRepeatedLayoutChanges() throws {
        let container = try TestFixtures.container()
        let firstBudget = Budget(id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!, name: "First")
        let secondBudget = Budget(id: UUID(uuidString: "00000000-0000-0000-0000-000000000222")!, name: "Second")
        let secondPlan = BudgetPlan(id: UUID(uuidString: "00000000-0000-0000-0000-000000000333")!, name: "Second Plan", budget: secondBudget)
        let secondItem = BudgetItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000444")!, name: "Second Item", budgetPlan: secondPlan)
        secondPlan.budgetItems = [secondItem]
        secondBudget.budgetPlans = [secondPlan]
        container.mainContext.insert(firstBudget)
        container.mainContext.insert(secondBudget)
        try ModelMutationService.saveValidated(container.mainContext)

        let coordinator = BudgetingCoordinator(
            context: container.mainContext,
            clock: FixedClock(now: TestFixtures.date, calendar: Calendar(identifier: .gregorian)),
            preferences: MemoryPhase2PreferenceStore()
        )

        coordinator.selectAdaptiveBudget(firstBudget.id)
        #expect(coordinator.navigationSelection.budgetID == firstBudget.id)
        #expect(coordinator.expandedBudgetID == firstBudget.id)

        coordinator.navigationSelection.selectBudget(secondBudget.id)
        coordinator.navigationSelection.selectPlan(secondPlan.id)
        coordinator.navigationSelection.selectItem(secondItem.id)
        coordinator.synchronizeAdaptiveBudgetSelection(preferNavigationSelection: true)
        #expect(coordinator.expandedBudgetID == secondBudget.id)
        #expect(coordinator.navigationSelection.budgetID == secondBudget.id)
        #expect(coordinator.navigationSelection.planID == secondPlan.id)
        #expect(coordinator.navigationSelection.itemID == secondItem.id)

        coordinator.expandedBudgetID = firstBudget.id
        coordinator.synchronizeAdaptiveBudgetSelection(preferNavigationSelection: false)
        #expect(coordinator.navigationSelection.budgetID == firstBudget.id)
        #expect(coordinator.expandedBudgetID == firstBudget.id)
        #expect(coordinator.navigationSelection.planID == nil)
        #expect(coordinator.navigationSelection.itemID == nil)

        coordinator.navigationSelection.selectBudget(secondBudget.id)
        coordinator.navigationSelection.selectPlan(secondPlan.id)
        coordinator.navigationSelection.selectItem(secondItem.id)
        coordinator.synchronizeAdaptiveBudgetSelection(preferNavigationSelection: true)
        #expect(coordinator.navigationSelection.budgetID == secondBudget.id)
        #expect(coordinator.expandedBudgetID == secondBudget.id)
        #expect(coordinator.navigationSelection.planID == secondPlan.id)
        #expect(coordinator.navigationSelection.itemID == secondItem.id)
    }

    @MainActor
    @Test("Coordinator transaction sections regroup after temporal refreshes")
    func coordinatorTransactionSectionsRegroupAfterRefreshPath() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let beforeMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 23, minute: 50)))
        let afterMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 10)))
        let transactionDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9)))
        let container = try TestFixtures.container()
        let budget = Budget(name: "Budget")
        let plan = BudgetPlan(name: "Plan", budget: budget)
        let item = BudgetItem(name: "Item", budgetPlan: plan)
        let income = Transaction(name: "Income", amount: 10, kind: .income, date: afterMidnight.addingTimeInterval(3_600), createdAt: transactionDate, budgetItem: item)
        let expense = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Expense", amount: 5, kind: .expense, date: transactionDate, createdAt: transactionDate, budgetItem: item)
        let tiedExpense = Transaction(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Tie", amount: 6, kind: .expense, date: transactionDate, createdAt: transactionDate, budgetItem: item)
        item.transactions = [expense, income, tiedExpense]
        plan.budgetItems = [item]
        budget.budgetPlans = [plan]
        container.mainContext.insert(budget)
        try ModelMutationService.saveValidated(container.mainContext)

        let clock = MutableRefinementClock(now: beforeMidnight, calendar: calendar)
        let coordinator = BudgetingCoordinator(context: container.mainContext, clock: clock, preferences: MemoryPhase2PreferenceStore())
        #expect(coordinator.transactionDaySections(for: item).map(\.header) == ["Wednesday, 12 Aug", "Today · Tuesday"])
        #expect(coordinator.transactionDaySections(for: item)[1].transactions.map(\.id) == [tiedExpense.id, expense.id])
        #expect(coordinator.isScheduledIncome(income))

        clock.now = afterMidnight
        coordinator.refreshIfLocalDayChanged()
        #expect(coordinator.transactionDaySections(for: item).map(\.header) == ["Today · Wednesday", "Yesterday · Tuesday"])
        #expect(!coordinator.isScheduledIncome(income))

        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        clock.calendar = calendar
        coordinator.refreshForCalendarOrTimeChange()
        #expect(coordinator.transactionDaySections(for: item).map(\.header) == ["Today · Wednesday", "Yesterday · Tuesday"])
    }
}

private final class MutableRefinementClock: AppClock {
    var now: Date
    var calendar: Calendar

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }
}
