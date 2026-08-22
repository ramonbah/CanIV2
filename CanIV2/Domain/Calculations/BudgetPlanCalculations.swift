//
//  BudgetPlanCalculations.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation

struct BudgetPlanCalculations {
    static func plannedTotal(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar).planned
    }

    static func incomeTotal(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar).effectiveIncome
    }

    static func scheduledIncomeTotal(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar).scheduledIncome
    }

    static func expenseTotal(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar).expenses
    }

    static func totalFundsReceived(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar).totalFundsReceived
    }

    static func unallocatedAmount(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar).unallocated
    }

    static func currentCashBalance(for plan: BudgetPlan, asOf date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Decimal {
        Phase2Calculations.planTotals(for: plan, asOf: date, calendar: calendar).currentBalance
    }
}
