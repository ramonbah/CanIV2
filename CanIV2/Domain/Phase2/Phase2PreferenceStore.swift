//
//  Phase2PreferenceStore.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation

protocol Phase2PreferenceStore {
    var expandedBudgetID: UUID? { get set }
    func planSortMode(for budgetID: UUID) -> PlanSortMode
    func setPlanSortMode(_ mode: PlanSortMode, for budgetID: UUID)
    func planSortDirection(for budgetID: UUID) -> SortDirection
    func setPlanSortDirection(_ direction: SortDirection, for budgetID: UUID)
    func itemSortDirection(for planID: UUID) -> ItemSortDirection
    func setItemSortDirection(_ direction: ItemSortDirection, for planID: UUID)
    func budgetReportInterval(for budgetID: UUID, periodID: String) -> ReportBucketInterval?
    func setBudgetReportInterval(_ interval: ReportBucketInterval, for budgetID: UUID, periodID: String)
    func planTimelineMode(for planID: UUID) -> PlanTimelineMode?
    func setPlanTimelineMode(_ mode: PlanTimelineMode, for planID: UUID)
    var monthlyWorkingHoursText: String? { get set }
    var hoursPerWorkdayText: String? { get set }
}

struct UserDefaultsPhase2PreferenceStore: Phase2PreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var expandedBudgetID: UUID? {
        get {
            guard let raw = defaults.string(forKey: "phase2.expandedBudgetID") else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            defaults.set(newValue?.uuidString ?? "", forKey: "phase2.expandedBudgetID")
        }
    }

    func planSortMode(for budgetID: UUID) -> PlanSortMode {
        guard let raw = defaults.string(forKey: key("planSortMode", budgetID)), let value = PlanSortMode(rawValue: raw) else {
            return .dateAdded
        }
        return value
    }

    func setPlanSortMode(_ mode: PlanSortMode, for budgetID: UUID) {
        defaults.set(mode.rawValue, forKey: key("planSortMode", budgetID))
    }

    func planSortDirection(for budgetID: UUID) -> SortDirection {
        guard let raw = defaults.string(forKey: key("planSortDirection", budgetID)), let value = SortDirection(rawValue: raw) else {
            return .descending
        }
        return value
    }

    func setPlanSortDirection(_ direction: SortDirection, for budgetID: UUID) {
        defaults.set(direction.rawValue, forKey: key("planSortDirection", budgetID))
    }

    func itemSortDirection(for planID: UUID) -> ItemSortDirection {
        guard let raw = defaults.string(forKey: key("itemSortDirection", planID)), let value = ItemSortDirection(rawValue: raw) else {
            return .highestRemainingFirst
        }
        return value
    }

    func setItemSortDirection(_ direction: ItemSortDirection, for planID: UUID) {
        defaults.set(direction.rawValue, forKey: key("itemSortDirection", planID))
    }

    func budgetReportInterval(for budgetID: UUID, periodID: String) -> ReportBucketInterval? {
        defaults.string(forKey: key("budgetReportInterval.\(periodID)", budgetID)).flatMap(ReportBucketInterval.init(rawValue:))
    }

    func setBudgetReportInterval(_ interval: ReportBucketInterval, for budgetID: UUID, periodID: String) {
        defaults.set(interval.rawValue, forKey: key("budgetReportInterval.\(periodID)", budgetID))
    }

    func planTimelineMode(for planID: UUID) -> PlanTimelineMode? {
        defaults.string(forKey: key("planTimelineMode", planID)).flatMap(PlanTimelineMode.init(rawValue:))
    }

    func setPlanTimelineMode(_ mode: PlanTimelineMode, for planID: UUID) {
        defaults.set(mode.rawValue, forKey: key("planTimelineMode", planID))
    }

    var monthlyWorkingHoursText: String? {
        get { defaults.string(forKey: "phase3.timeEffort.monthlyWorkingHours") }
        set { defaults.set(newValue, forKey: "phase3.timeEffort.monthlyWorkingHours") }
    }

    var hoursPerWorkdayText: String? {
        get { defaults.string(forKey: "phase3.timeEffort.hoursPerWorkday") }
        set { defaults.set(newValue, forKey: "phase3.timeEffort.hoursPerWorkday") }
    }

    private func key(_ name: String, _ id: UUID) -> String {
        "phase2.\(name).\(id.uuidString)"
    }
}

final class MemoryPhase2PreferenceStore: Phase2PreferenceStore {
    var expandedBudgetID: UUID?
    private var values: [String: String] = [:]

    func planSortMode(for budgetID: UUID) -> PlanSortMode {
        values[key("planSortMode", budgetID)].flatMap(PlanSortMode.init(rawValue:)) ?? .dateAdded
    }

    func setPlanSortMode(_ mode: PlanSortMode, for budgetID: UUID) {
        values[key("planSortMode", budgetID)] = mode.rawValue
    }

    func planSortDirection(for budgetID: UUID) -> SortDirection {
        values[key("planSortDirection", budgetID)].flatMap(SortDirection.init(rawValue:)) ?? .descending
    }

    func setPlanSortDirection(_ direction: SortDirection, for budgetID: UUID) {
        values[key("planSortDirection", budgetID)] = direction.rawValue
    }

    func itemSortDirection(for planID: UUID) -> ItemSortDirection {
        values[key("itemSortDirection", planID)].flatMap(ItemSortDirection.init(rawValue:)) ?? .highestRemainingFirst
    }

    func setItemSortDirection(_ direction: ItemSortDirection, for planID: UUID) {
        values[key("itemSortDirection", planID)] = direction.rawValue
    }

    func budgetReportInterval(for budgetID: UUID, periodID: String) -> ReportBucketInterval? {
        values[key("budgetReportInterval.\(periodID)", budgetID)].flatMap(ReportBucketInterval.init(rawValue:))
    }

    func setBudgetReportInterval(_ interval: ReportBucketInterval, for budgetID: UUID, periodID: String) {
        values[key("budgetReportInterval.\(periodID)", budgetID)] = interval.rawValue
    }

    func planTimelineMode(for planID: UUID) -> PlanTimelineMode? {
        values[key("planTimelineMode", planID)].flatMap(PlanTimelineMode.init(rawValue:))
    }

    func setPlanTimelineMode(_ mode: PlanTimelineMode, for planID: UUID) {
        values[key("planTimelineMode", planID)] = mode.rawValue
    }

    var monthlyWorkingHoursText: String? {
        get { values["timeEffort.monthlyWorkingHours"] }
        set { values["timeEffort.monthlyWorkingHours"] = newValue }
    }

    var hoursPerWorkdayText: String? {
        get { values["timeEffort.hoursPerWorkday"] }
        set { values["timeEffort.hoursPerWorkday"] = newValue }
    }

    private func key(_ name: String, _ id: UUID) -> String {
        "\(name).\(id.uuidString)"
    }
}
