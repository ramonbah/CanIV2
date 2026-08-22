//
//  MoneyEffortPresentation.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI

struct MoneyEffortModifier: ViewModifier {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let amount: Decimal
    let formatter: CurrencyFormatter
    @State private var showingEffort = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("View Time Effort") {
                    showingEffort = true
                }
            }
            .accessibilityAction(named: Text("View Time Effort")) {
                showingEffort = true
            }
            .sheet(isPresented: $showingEffort) {
                NavigationStack {
                    TimeEffortLookupView(amount: amount, formatter: formatter)
                }
            }
    }
}

extension View {
    func moneyEffortLookup(amount: Decimal, formatter: CurrencyFormatter) -> some View {
        modifier(MoneyEffortModifier(amount: amount, formatter: formatter))
    }
}

private struct TimeEffortLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BudgetingCoordinator.self) private var coordinator
    let amount: Decimal
    let formatter: CurrencyFormatter

    var body: some View {
        List {
            Section("Amount") {
                Text(formatter.string(for: amount))
                    .font(.headline)
                    .accessibilityIdentifier("quick-effort-amount")
            }
            Section("Time Effort") {
                if coordinator.monthlySalary == nil {
                    Text(TimeEffortError.missingSalary.localizedDescription)
                    NavigationLink("Configure Salary") {
                        SalaryEditorView()
                    }
                } else {
                    effortResult
                }
            }
            Section {
                NavigationLink("Open Effort Calculator") {
                    EffortCalculatorView(prefilledAmount: amount)
                }
            }
        }
        .navigationTitle("Time Effort")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .accessibilityLabel("Time effort for \(formatter.string(for: amount))")
    }

    @ViewBuilder
    private var effortResult: some View {
        if let snapshot = try? coordinator.effortSnapshot(for: amount) {
            Text(snapshot.formattedDuration)
                .font(.headline)
                .textSelection(.enabled)
                .accessibilityIdentifier("quick-effort-result")
            LabeledContent("Monthly working hours", value: NSDecimalNumber(decimal: snapshot.monthlyWorkingHours).stringValue)
            LabeledContent("Hours per workday", value: NSDecimalNumber(decimal: snapshot.hoursPerWorkday).stringValue)
        } else {
            Text("Time effort is unavailable for this amount.")
        }
    }
}
