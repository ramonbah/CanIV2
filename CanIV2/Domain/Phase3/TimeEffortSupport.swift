//
//  TimeEffortSupport.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import Foundation
import Security

protocol SalarySecureStore {
    func readSalary() throws -> Decimal?
    func saveSalary(_ salary: Decimal) throws
    func clearSalary() throws
}

enum TimeEffortError: LocalizedError, Equatable {
    case missingSalary
    case invalidSalary
    case invalidAmount
    case invalidMonthlyHours
    case invalidWorkdayHours
    case amountTooLarge
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingSalary: "Configure monthly salary to calculate time effort."
        case .invalidSalary: "Salary must be greater than zero."
        case .invalidAmount: "Enter an amount greater than zero."
        case .invalidMonthlyHours: "Monthly working hours must be greater than zero."
        case .invalidWorkdayHours: "Hours per workday must be greater than zero and cannot exceed one work week."
        case .amountTooLarge: "Amount is too large to calculate time effort."
        case .keychainFailure: "Couldn’t update salary. Your previous salary setting was preserved."
        }
    }
}

struct KeychainSalaryStore: SalarySecureStore {
    private let service = "CanIV2.TimeEffort"
    private let account = "monthlySalary"

    func readSalary() throws -> Decimal? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TimeEffortError.keychainFailure(status) }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8), let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw TimeEffortError.keychainFailure(errSecDecode)
        }
        return decimal
    }

    func saveSalary(_ salary: Decimal) throws {
        guard salary > 0 else { throw TimeEffortError.invalidSalary }
        let string = NSDecimalNumber(decimal: salary).stringValue
        let data = Data(string.utf8)
        var update = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(update as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw TimeEffortError.keychainFailure(status) }
        update[kSecValueData as String] = data
        let addStatus = SecItemAdd(update as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TimeEffortError.keychainFailure(addStatus) }
    }

    func clearSalary() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TimeEffortError.keychainFailure(status) }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}

struct TimeEffortConfiguration: Equatable {
    var monthlySalary: Decimal?
    var monthlyWorkingHours: Decimal
    var hoursPerWorkday: Decimal

    static let defaults = TimeEffortConfiguration(monthlySalary: nil, monthlyWorkingHours: 160, hoursPerWorkday: 8)

    var hoursPerWorkWeek: Decimal {
        monthlyWorkingHours / 4
    }

    func validateSchedule() throws {
        guard monthlyWorkingHours > 0 else { throw TimeEffortError.invalidMonthlyHours }
        guard hoursPerWorkday > 0, hoursPerWorkday <= hoursPerWorkWeek else { throw TimeEffortError.invalidWorkdayHours }
    }
}

struct TimeEffortDuration: Equatable {
    var years: Int
    var months: Int
    var weeks: Int
    var days: Int
    var hours: Int
    var minutes: Int
    var seconds: Int
    var milliseconds: Int
}

struct TimeEffortSnapshot: Equatable {
    let amount: Decimal
    let duration: TimeEffortDuration
    let formattedDuration: String
    let monthlyWorkingHours: Decimal
    let hoursPerWorkday: Decimal
}

struct TimeEffortCalculator {
    var locale: Locale = .autoupdatingCurrent

    func snapshot(amount: Decimal, configuration: TimeEffortConfiguration) throws -> TimeEffortSnapshot {
        guard amount > 0 else { throw TimeEffortError.invalidAmount }
        guard let salary = configuration.monthlySalary, salary > 0 else { throw TimeEffortError.missingSalary }
        try configuration.validateSchedule()
        let effortHours = amount / salary * configuration.monthlyWorkingHours
        let duration = try duration(fromHours: effortHours, configuration: configuration)
        return TimeEffortSnapshot(
            amount: amount,
            duration: duration,
            formattedDuration: format(duration, locale: locale),
            monthlyWorkingHours: configuration.monthlyWorkingHours,
            hoursPerWorkday: configuration.hoursPerWorkday
        )
    }

    func duration(fromHours hours: Decimal, configuration: TimeEffortConfiguration) throws -> TimeEffortDuration {
        let millisecondsPerHour = Decimal(3_600_000)
        var totalMilliseconds = try roundedInt(hours * millisecondsPerHour)
        let monthMilliseconds = try roundedInt(configuration.monthlyWorkingHours * millisecondsPerHour)
        let yearMilliseconds = monthMilliseconds * 12
        let weekMilliseconds = try roundedInt(configuration.hoursPerWorkWeek * millisecondsPerHour)
        let dayMilliseconds = try roundedInt(configuration.hoursPerWorkday * millisecondsPerHour)
        let hourMilliseconds = 3_600_000
        let minuteMilliseconds = 60_000
        let secondMilliseconds = 1_000

        let years = consume(&totalMilliseconds, unit: yearMilliseconds)
        let months = consume(&totalMilliseconds, unit: monthMilliseconds)
        let weeks = consume(&totalMilliseconds, unit: weekMilliseconds)
        let days = consume(&totalMilliseconds, unit: dayMilliseconds)
        let wholeHours = consume(&totalMilliseconds, unit: hourMilliseconds)
        let minutes = consume(&totalMilliseconds, unit: minuteMilliseconds)
        let seconds = consume(&totalMilliseconds, unit: secondMilliseconds)
        return TimeEffortDuration(years: years, months: months, weeks: weeks, days: days, hours: wholeHours, minutes: minutes, seconds: seconds, milliseconds: totalMilliseconds)
    }

    func format(_ duration: TimeEffortDuration, locale: Locale? = nil) -> String {
        let labels = UnitLabels(locale: locale ?? self.locale)
        let components: [(TimeEffortUnit, Int)] = [
            (.year, duration.years),
            (.month, duration.months),
            (.week, duration.weeks),
            (.day, duration.days),
            (.hour, duration.hours),
            (.minute, duration.minutes),
            (.second, duration.seconds),
            (.millisecond, duration.milliseconds)
        ]
        let nonzero = components.filter { $0.1 != 0 }.prefix(3)
        guard !nonzero.isEmpty else { return "0 \(labels.label(for: .millisecond, count: 0))" }
        return nonzero.map { "\($0.1) \(labels.label(for: $0.0, count: $0.1))" }.joined(separator: " ")
    }

    private func roundedInt(_ decimal: Decimal) throws -> Int {
        guard decimal >= 0, decimal <= Decimal(Int.max) else { throw TimeEffortError.amountTooLarge }
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded <= Decimal(Int.max) else { throw TimeEffortError.amountTooLarge }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private func consume(_ total: inout Int, unit: Int) -> Int {
        guard unit > 0 else { return 0 }
        let count = total / unit
        total -= count * unit
        return count
    }
}

private enum TimeEffortUnit {
    case year, month, week, day, hour, minute, second, millisecond
}

private struct UnitLabels {
    let locale: Locale

    func label(for unit: TimeEffortUnit, count: Int) -> String {
        let language = locale.language.languageCode?.identifier
        if language == "ms" || language == "id" {
            return switch unit {
            case .year: "tahun"
            case .month: "bulan"
            case .week: "minggu"
            case .day: "hari"
            case .hour: "jam"
            case .minute: "minit"
            case .second: "saat"
            case .millisecond: "milisaat"
            }
        } else {
            let singular: String
            switch unit {
            case .year: singular = "year"
            case .month: singular = "month"
            case .week: singular = "week"
            case .day: singular = "day"
            case .hour: singular = "hour"
            case .minute: singular = "minute"
            case .second: singular = "second"
            case .millisecond: singular = "millisecond"
            }
            return count == 1 ? singular : "\(singular)s"
        }
    }
}
