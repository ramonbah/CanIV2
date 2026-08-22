//
//  OnboardingGateView.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI
import SwiftData

struct OnboardingGateView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    @AppStorage("phase2.onboardingComplete") private var onboardingComplete = false
    @AppStorage("phase2.selectedTab") private var selectedTabRaw = MainTab.home.rawValue
    @State private var selectedCurrencyCode = CurrencyCatalog.suggestedCurrencyCode()
    @State private var showingCurrencyPicker = false
    @State private var showingFirstBudget = false
    @State private var showingDiscardCurrency = false
    @State private var firstBudgetCompleted = false

    var body: some View {
        if onboardingComplete {
            MainTabView()
                .task { _ = coordinator.ensureSettings(defaultCurrencyCode: CurrencyCatalog.suggestedCurrencyCode()) }
        } else {
            NavigationStack {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CanI")
                            .font(.largeTitle.bold())
                        Text("Build a Budget, add Plans, split them into Items, then record income and expenses as Transactions.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingCurrencyPicker = true
                    } label: {
                        HStack {
                            Label("Currency", systemImage: "banknote")
                            Spacer()
                            Text(selectedCurrencyCode)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding-currency-row")

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            if coordinator.saveCurrency(selectedCurrencyCode) {
                                showingFirstBudget = true
                            }
                        } label: {
                            Text("Continue")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("onboarding-continue")
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            if coordinator.saveCurrency(selectedCurrencyCode) {
                                selectedTabRaw = MainTab.budgets.rawValue
                                coordinator.selectedTab = .budgets
                                onboardingComplete = true
                            }
                        } label: {
                            Text("Skip for Now")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("onboarding-skip")
                        .controlSize(.large)
                    }
                }
                .padding(20)
                .navigationTitle("Welcome")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showingCurrencyPicker) {
                    CurrencySelectionView(selectedCode: $selectedCurrencyCode) {
                        showingCurrencyPicker = false
                    }
                }
                .sheet(isPresented: $showingFirstBudget, onDismiss: {
                    if !onboardingComplete && !firstBudgetCompleted { showingDiscardCurrency = true }
                }) {
                    FirstBudgetCreationView(currencyCode: selectedCurrencyCode) { created in
                        firstBudgetCompleted = true
                        selectedTabRaw = MainTab.budgets.rawValue
                        coordinator.selectedTab = .budgets
                        onboardingComplete = true
                        showingFirstBudget = false
                    }
                }
                .confirmationDialog("Keep \(selectedCurrencyCode)?", isPresented: $showingDiscardCurrency, titleVisibility: .visible) {
                    Button("Keep Currency") {
                        if coordinator.saveCurrency(selectedCurrencyCode) {
                            selectedTabRaw = MainTab.budgets.rawValue
                            coordinator.selectedTab = .budgets
                            onboardingComplete = true
                        }
                    }
                    .accessibilityIdentifier("keep-currency")
                    Button("Discard and Skip", role: .destructive) {
                        let suggested = CurrencyCatalog.suggestedCurrencyCode()
                        selectedCurrencyCode = suggested
                        if coordinator.saveCurrency(suggested) {
                            selectedTabRaw = MainTab.budgets.rawValue
                            coordinator.selectedTab = .budgets
                            onboardingComplete = true
                        }
                    }
                    .accessibilityIdentifier("discard-currency")
                    Button("Continue Setup", role: .cancel) { showingFirstBudget = true }
                } message: {
                    Text("You selected a currency but canceled first Budget creation.")
                }
                .alert("Couldn’t Save", isPresented: Binding(get: { coordinator.lastErrorMessage != nil }, set: { if !$0 { coordinator.clearError() } })) {
                    Button("OK", role: .cancel) { coordinator.clearError() }
                } message: { Text(coordinator.lastErrorMessage ?? "") }
            }
        }
    }
}

private struct CurrencySelectionView: View {
    @Binding var selectedCode: String
    let onSelect: () -> Void
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
                    selectedCode = currency.code
                    onSelect()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(currency.code).font(.headline)
                            Text(currency.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if currency.code == selectedCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("currency-option-\(currency.code)")
            }
        }
        .navigationTitle("Currency")
        .searchable(text: $searchText, prompt: "Search currencies")
    }
}

private struct FirstBudgetCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BudgetingCoordinator.self) private var coordinator
    let currencyCode: String
    let onComplete: (Budget) -> Void

    @State private var name = ""
    @State private var errors = FieldErrors()
    @State private var showSummary = false

    var body: some View {
        NavigationStack {
            Form {
                Section("First Budget") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("first-budget-name")
                    InlineOnboardingErrorText(errors.name)
                }
            }
            .navigationTitle("Create Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .alert("Check the highlighted fields", isPresented: $showSummary) {
                Button("OK", role: .cancel) { }
            } message: { Text(errors.summary) }
        }
    }

    private func save() {
        do {
            guard coordinator.saveCurrency(currencyCode) else {
                errors = FieldErrors(name: coordinator.lastErrorMessage)
                showSummary = true
                return
            }
            let budget = try coordinator.createBudget(name: name)
            onComplete(budget)
        } catch {
            if let validation = error as? Phase2ValidationError {
                errors = FieldErrors(name: validation.localizedDescription)
            } else {
                errors = FieldErrors(name: error.localizedDescription)
            }
            showSummary = true
        }
    }
}

private struct InlineOnboardingErrorText: View {
    let text: String?

    init(_ text: String?) {
        self.text = text
    }

    var body: some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(text)")
        }
    }
}

#if DEBUG
#Preview {
    OnboardingGateView()
        .modelContainer(try! CanISchema.makeContainer(inMemory: true))
}
#endif
