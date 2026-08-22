//
//  SettingsRootView.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI
import SwiftData

struct SettingsRootView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator

    @State private var selectedCurrencyCode: String?
    @State private var showingCurrencyPicker = false
    @State private var pendingCurrencyCode: String?
    @State private var showingCurrencyRelabelConfirmation = false
    @State private var currencyErrorMessage: String?
    @State private var showingSalaryEditor = false
    @State private var showingClearSalaryConfirmation = false

    private var currentCurrencyCode: String {
        coordinator.currencyCode
    }

    var body: some View {
        List {
            Section("Currency") {
                Button {
                    selectedCurrencyCode = currentCurrencyCode
                    showingCurrencyPicker = true
                } label: {
                    HStack {
                        Label("App Currency", systemImage: "banknote")
                        Spacer()
                        Text(currentCurrencyCode)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-currency-row")
                Text("Changing currency relabels stored values. Amounts are not converted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Time Effort") {
                HStack {
                    Label("Monthly Salary", systemImage: "lock")
                    Spacer()
                    Text(salaryDisplay)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(!coordinator.isSalaryVisible)
                        .accessibilityIdentifier("time-effort-salary-display")
                    Button {
                        coordinator.isSalaryVisible.toggle()
                    } label: {
                        Image(systemName: coordinator.isSalaryVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(coordinator.isSalaryVisible ? "Hide salary" : "Show salary")
                }
                .frame(minHeight: 44)
                HStack {
                    Button("Edit Salary") { showingSalaryEditor = true }
                    Spacer()
                    Button("Clear Salary", role: .destructive) { showingClearSalaryConfirmation = true }
                        .disabled(coordinator.monthlySalary == nil)
                }
                NavigationLink {
                    EffortCalculatorView(prefilledAmount: nil)
                } label: {
                    Label("Effort Calculator", systemImage: "clock")
                }
                ScheduleSettingsView()
                Text("Press and hold amounts throughout the app to view their time effort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .task {
            _ = coordinator.ensureSettings(defaultCurrencyCode: CurrencyCatalog.suggestedCurrencyCode())
#if DEBUG
            if let code = ProcessInfo.processInfo.environment["UI_TESTING_PENDING_CURRENCY_RELABEL"], !code.isEmpty {
                try? await Task.sleep(nanoseconds: 500_000_000)
                pendingCurrencyCode = code
            }
#endif
        }
        .sheet(isPresented: $showingCurrencyPicker) {
            NavigationStack {
                CurrencySettingsPicker(
                    selectedCode: Binding(get: { selectedCurrencyCode ?? currentCurrencyCode }, set: { selectedCurrencyCode = $0 }),
                    pendingCode: $pendingCurrencyCode,
                    showingConfirmation: $showingCurrencyRelabelConfirmation,
                    onConfirm: applyCurrencyChange,
                    onSelectCurrent: { showingCurrencyPicker = false }
                )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                pendingCurrencyCode = nil
                                showingCurrencyRelabelConfirmation = false
                                selectedCurrencyCode = currentCurrencyCode
                                showingCurrencyPicker = false
                            }
                        }
                    }
                    .alert("Couldn’t Update Currency", isPresented: Binding(get: { currencyErrorMessage != nil }, set: { if !$0 { currencyErrorMessage = nil } })) {
                        Button("OK", role: .cancel) {
                            currencyErrorMessage = nil
                            showingCurrencyRelabelConfirmation = pendingCurrencyCode != nil
                        }
                    } message: {
                        Text(currencyErrorMessage ?? "")
                    }
            }
        }
        .alert("Couldn’t Update Currency", isPresented: Binding(get: { coordinator.lastErrorMessage != nil }, set: { if !$0 { coordinator.clearError() } })) {
            Button("OK", role: .cancel) { coordinator.clearError() }
        } message: { Text(coordinator.lastErrorMessage ?? "") }
        .sheet(isPresented: $showingSalaryEditor) {
            NavigationStack {
                SalaryEditorView()
            }
        }
        .confirmationDialog("Clear monthly salary? This disables effort calculations.", isPresented: $showingClearSalaryConfirmation, titleVisibility: .visible) {
            Button("Clear Salary", role: .destructive) {
                _ = coordinator.clearMonthlySalary()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var salaryDisplay: String {
        guard let salary = coordinator.monthlySalary else { return "Not Set" }
        return coordinator.isSalaryVisible ? coordinator.formatter.string(for: salary) : "Hidden"
    }

    private func applyCurrencyChange() {
        guard let pendingCurrencyCode else { return }
        showingCurrencyRelabelConfirmation = false
        if coordinator.saveCurrency(pendingCurrencyCode) {
            self.pendingCurrencyCode = nil
            showingCurrencyRelabelConfirmation = false
            selectedCurrencyCode = pendingCurrencyCode
            showingCurrencyPicker = false
        } else {
            currencyErrorMessage = coordinator.lastErrorMessage
            coordinator.clearError()
        }
    }
}

struct SalaryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BudgetingCoordinator.self) private var coordinator
    @State private var salaryText = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Monthly Salary") {
                TextField("Salary", text: $salaryText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("time-effort-salary-field")
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Stored securely. Changing currency relabels this value without conversion.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Monthly Salary")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            if let salary = coordinator.monthlySalary {
                salaryText = LocalizedNumericEditingPolicy(locale: coordinator.formatter.locale).editableString(for: salary)
            }
        }
    }

    private func save() {
        guard let salary = coordinator.formatter.parse(salaryText), salary > 0, coordinator.formatter.hasValidMinorUnits(salaryText) else {
            error = TimeEffortError.invalidSalary.localizedDescription
            return
        }
        if coordinator.saveMonthlySalary(salary) {
            dismiss()
        } else {
            error = coordinator.lastErrorMessage
            coordinator.clearError()
        }
    }
}

private struct ScheduleSettingsView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    @State private var monthlyHours = "160"
    @State private var workdayHours = "8"
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Monthly Working Hours", text: $monthlyHours)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("time-effort-monthly-hours-field")
            Text("This determines one work month.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Hours per Workday", text: $workdayHours)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("time-effort-workday-hours-field")
            Text("This affects day-level formatting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Save Work Schedule") { save() }
                .buttonStyle(.bordered)
        }
        .onAppear {
            let config = coordinator.timeEffortConfiguration
            monthlyHours = NSDecimalNumber(decimal: config.monthlyWorkingHours).stringValue
            workdayHours = NSDecimalNumber(decimal: config.hoursPerWorkday).stringValue
        }
    }

    private func save() {
        let policy = LocalizedNumericEditingPolicy(locale: coordinator.formatter.locale)
        guard
            policy.validateEdit(monthlyHours).isAcceptedEdit,
            policy.validateEdit(workdayHours).isAcceptedEdit,
            let monthly = policy.completeDecimal(from: monthlyHours),
            let workday = policy.completeDecimal(from: workdayHours)
        else {
            error = TimeEffortError.invalidMonthlyHours.localizedDescription
            return
        }
        do {
            try coordinator.saveTimeEffortSchedule(monthlyWorkingHours: monthly, hoursPerWorkday: workday)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EffortCalculatorView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let prefilledAmount: Decimal?
    @State private var amountText = ""

    var body: some View {
        Form {
            Section("Amount") {
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("time-effort-calculator-amount")
            }
            Section("Result") {
                if coordinator.monthlySalary == nil {
                    Text(TimeEffortError.missingSalary.localizedDescription)
                        .accessibilityIdentifier("time-effort-missing-salary")
                    NavigationLink("Configure Salary") {
                        SalaryEditorView()
                    }
                } else if let amount = coordinator.formatter.parse(amountText), amount > 0 {
                    calculatorResult(for: amount)
                } else {
                    Text("Enter a valid positive amount.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Assumptions") {
                let config = coordinator.timeEffortConfiguration
                LabeledContent("Monthly working hours", value: NSDecimalNumber(decimal: config.monthlyWorkingHours).stringValue)
                LabeledContent("Hours per workday", value: NSDecimalNumber(decimal: config.hoursPerWorkday).stringValue)
            }
        }
        .navigationTitle("Effort Calculator")
        .onAppear {
            if let prefilledAmount {
                amountText = LocalizedNumericEditingPolicy(locale: coordinator.formatter.locale).editableString(for: prefilledAmount)
            }
#if DEBUG
            if amountText.isEmpty, let testingAmount = ProcessInfo.processInfo.environment["UI_TESTING_TIME_EFFORT_AMOUNT"] {
                amountText = testingAmount
            }
#endif
        }
    }

    @ViewBuilder
    private func calculatorResult(for amount: Decimal) -> some View {
        if let snapshot = try? coordinator.effortSnapshot(for: amount) {
            Text(snapshot.formattedDuration)
                .font(.headline)
                .textSelection(.enabled)
                .accessibilityIdentifier("time-effort-result")
        } else {
            Text("Time effort is unavailable for this amount.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CurrencySettingsPicker: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    @Binding var selectedCode: String
    @Binding var pendingCode: String?
    @Binding var showingConfirmation: Bool
    let onConfirm: () -> Void
    let onSelectCurrent: () -> Void
    @State private var searchText = ""

    private var currencies: [CurrencyCatalog.Currency] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CurrencyCatalog.currencies }
        return CurrencyCatalog.currencies.filter {
            $0.code.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            ForEach(Array(currencies.enumerated()), id: \.element.code) { _, currency in
                Button {
                    if currency.code == coordinator.currencyCode {
                        selectedCode = currency.code
                        onSelectCurrent()
                    } else {
                        selectedCode = currency.code
                        pendingCode = currency.code
                        showingConfirmation = true
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(currency.code).font(.headline)
                            Text(currency.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedCode == currency.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("currency-option-\(currency.code)")
                .accessibilityValue(selectedCode == currency.code ? "Selected" : "")
            }
        }
        .navigationTitle("Currency")
        .searchable(text: $searchText, prompt: "Search currencies")
        .confirmationDialog("Change Currency to \(pendingCode ?? "")?", isPresented: Binding(get: { showingConfirmation }, set: { showingConfirmation = $0 }), titleVisibility: .visible) {
            Button("Relabel \(coordinator.budgetCount()) Budget\(coordinator.budgetCount() == 1 ? "" : "s")") { onConfirm() }
                .accessibilityIdentifier("confirm-currency-relabel")
            Button("Cancel") {
                showingConfirmation = false
                pendingCode = nil
                selectedCode = coordinator.currencyCode
            }
            .accessibilityIdentifier("cancel-currency-relabel")
        } message: {
            Text("This affects \(coordinator.budgetCount()) Budget\(coordinator.budgetCount() == 1 ? "" : "s"). Existing values are relabeled, not converted.")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SettingsRootView()
    }
    .modelContainer(try! SampleData.makePreviewContainer())
}
#endif
