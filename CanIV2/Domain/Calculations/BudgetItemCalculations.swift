//
//  BudgetItemCalculations.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation

struct BudgetItemCalculations {
    static func plannedAmount(for item: BudgetItem) -> Decimal {
        Phase2Calculations.itemTotals(for: item).planned
    }

    static func expenseTotal(for item: BudgetItem) -> Decimal {
        Phase2Calculations.itemTotals(for: item).expenses
    }

    static func incomeTotal(for item: BudgetItem, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.itemTotals(for: item, asOf: date, calendar: calendar).effectiveIncome
    }

    static func scheduledIncomeTotal(for item: BudgetItem, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.itemTotals(for: item, asOf: date, calendar: calendar).scheduledIncome
    }

    static func netRemaining(for item: BudgetItem, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.itemTotals(for: item, asOf: date, calendar: calendar).remaining
    }
}
