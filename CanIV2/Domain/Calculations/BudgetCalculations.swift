//
//  BudgetCalculations.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation

struct BudgetCalculations {
    static func plannedTotal(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.budgetTotals(for: budget, asOf: date, calendar: calendar).planned
    }

    static func incomeTotal(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.budgetTotals(for: budget, asOf: date, calendar: calendar).effectiveIncome
    }

    static func scheduledIncomeTotal(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.budgetTotals(for: budget, asOf: date, calendar: calendar).scheduledIncome
    }

    static func expenseTotal(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.budgetTotals(for: budget, asOf: date, calendar: calendar).expenses
    }

    static func totalFundsReceived(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.budgetTotals(for: budget, asOf: date, calendar: calendar).totalFundsReceived
    }

    static func unallocatedAmount(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        totalFundsReceived(for: budget, asOf: date, calendar: calendar) - plannedTotal(for: budget, asOf: date, calendar: calendar)
    }

    static func currentCashBalance(for budget: Budget, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.budgetTotals(for: budget, asOf: date, calendar: calendar).currentBalance
    }
}
