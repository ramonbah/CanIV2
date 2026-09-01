//
//  TransactionsRootView.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI
import SwiftData

struct TransactionsRootView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    @State private var filtersExpanded = false
    @State private var showingReceiptInbox = false

    var body: some View {
        List {
            if let notice = coordinator.pendingReceiptNotice {
                Section {
                    HStack {
                        Label("New receipt ready for review", systemImage: "tray.and.arrow.down")
                            .font(.subheadline)
                        Spacer()
                        Button("Review") {
                            showingReceiptInbox = true
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("pending-notice-review")
                        Button("Review Later") {
                            coordinator.dismissPendingReceiptNotice(notice)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("pending-notice-review-later")
                    }
                    .frame(minHeight: 44)
                    .task(id: notice.id) {
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        await MainActor.run {
                            coordinator.dismissPendingReceiptNotice(notice)
                        }
                    }
                }
            }

            Section {
                TextField("Search notes, Items, Plans, receipts", text: Binding(get: { coordinator.transactionSearchDraft }, set: { coordinator.transactionSearchDraft = $0 }))
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { coordinator.submitTransactionSearch() }
                    .accessibilityIdentifier("transactions-search")
                DisclosureGroup(isExpanded: $filtersExpanded) {
                    TransactionFilterPanel()
                    Button("Apply Filters") {
                        coordinator.applyTransactionFilters()
                        if coordinator.transactionQueryErrorMessage == nil {
                            filtersExpanded = false
                        }
                    }
                    .accessibilityIdentifier("transactions-apply-filters")
                    Button("Clear All", role: .destructive) {
                        coordinator.clearTransactionQuery()
                        filtersExpanded = false
                    }
                    .accessibilityIdentifier("transactions-clear-all")
                    if let message = coordinator.transactionQueryErrorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .accessibilityIdentifier("transactions-filter-error")
                    }
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }

            let chips = coordinator.transactionFilterChips()
            if !chips.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(chips, id: \.self) { chip in
                                Button {
                                    coordinator.removeTransactionFilterChip(chip)
                                } label: {
                                    Label(coordinator.label(for: chip), systemImage: "xmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("transaction-filter-chip")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button("Clear All", role: .destructive) {
                        coordinator.clearTransactionQuery()
                    }
                    .accessibilityIdentifier("transactions-clear-all-chips")
                }
            }

            if !coordinator.hasAnyTransactions {
                Section {
                    ContentUnavailableView("No Data", systemImage: "tray", description: Text("Create transactions from a Plan or Item first."))
                }
            } else if coordinator.transactionResultSections.isEmpty {
                Section {
                    ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("Adjust the submitted search or filters."))
                    Button("Clear All") { coordinator.clearTransactionQuery() }
                }
            } else {
                ForEach(coordinator.transactionResultSections) { section in
                    Section {
                        ForEach(section.transactions) { transaction in
                            Button {
                                coordinator.openTransactionRoute(transaction.route)
                                coordinator.selectedTab = .budgets
                            } label: {
                                TransactionResultRow(snapshot: transaction, formatter: coordinator.formatter)
                            }
                            .accessibilityIdentifier("transaction-result-\(transaction.id.uuidString)")
                        }
                    } header: {
                        Text(section.header)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingReceiptInbox = true
                } label: {
                    Label("Receipt Inbox, \(coordinator.pendingReceipts.count) pending", systemImage: coordinator.pendingReceipts.isEmpty ? "tray" : "tray.full")
                }
                .accessibilityIdentifier("receipt-inbox")
                .accessibilityLabel("Receipt Inbox, \(coordinator.pendingReceipts.count) pending")
            }
        }
        .sheet(isPresented: $showingReceiptInbox) {
            PendingReceiptsView(formatter: coordinator.formatter) { record, imageData in
                showingReceiptInbox = false
                coordinator.requestPendingReceiptReview(record, imageData: imageData)
            }
        }
        .task { coordinator.refresh() }
        .onDisappear {
            if coordinator.selectedTab != .transactions {
                coordinator.restoreTransactionsStateAfterHomeSeeAll()
            }
        }
    }
}

private struct TransactionFilterPanel: View {
    @Environment(BudgetingCoordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterGroup("Budgets", values: coordinator.budgets.map { ($0.id, $0.name) }, selection: coordinator.transactionFilterDraft.budgetIDs) { id, selected in
                coordinator.setTransactionDraftBudgetSelected(id, selected: selected)
            }
            if !coordinator.transactionFilterDraft.budgetIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plans")
                        .font(.subheadline.bold())
                    ForEach(coordinator.transactionDraftPlansByBudget(), id: \.budget.id) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.budget.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(group.plans) { plan in
                                Toggle("\(plan.name) in \(group.budget.name)", isOn: Binding(get: { coordinator.transactionFilterDraft.planIDs.contains(plan.id) }, set: { coordinator.setTransactionDraftPlanSelected(plan.id, selected: $0) }))
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("transaction-filter-plan-\(plan.id.uuidString)")
                            }
                        }
                    }
                }
            }
            if !coordinator.transactionFilterDraft.planIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Items")
                        .font(.subheadline.bold())
                    ForEach(coordinator.transactionDraftItemsByPlan(), id: \.plan.id) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(group.budget.name) / \(group.plan.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { item in
                                Toggle("\(item.name) in \(group.plan.name)", isOn: Binding(get: { coordinator.transactionFilterDraft.itemIDs.contains(item.id) }, set: { coordinator.setTransactionDraftItemSelected(item.id, selected: $0) }))
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("transaction-filter-item-\(item.id.uuidString)")
                            }
                        }
                    }
                }
            }
            HStack {
                Toggle("Income", isOn: kindBinding(.income))
                Toggle("Expense", isOn: kindBinding(.expense))
            }
            Picker("Date", selection: Binding(get: { datePreset }, set: setDatePreset)) {
                Text("All Time").tag("allTime")
                Text("Last 7").tag("last7Days")
                Text("Last 30").tag("last30Days")
                Text("Last 90").tag("last90Days")
                Text("Current Month").tag("currentMonth")
                Text("Custom Range").tag("custom")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("transactions-date-filter")
            if case .custom = coordinator.transactionFilterDraft.dateCriterion {
                DatePicker("Start", selection: customStartBinding, displayedComponents: .date)
                    .accessibilityIdentifier("transactions-custom-start")
                DatePicker("End", selection: customEndBinding, displayedComponents: .date)
                    .accessibilityIdentifier("transactions-custom-end")
                if customStartBinding.wrappedValue > customEndBinding.wrappedValue {
                    Text("Start date cannot be later than end date.")
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityIdentifier("transactions-custom-date-error")
                }
            }
            HStack {
                TextField("Min", text: Binding(get: { coordinator.transactionFilterDraft.minimumAmountText }, set: { coordinator.transactionFilterDraft.minimumAmountText = $0 }))
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("transactions-min-amount")
                TextField("Max", text: Binding(get: { coordinator.transactionFilterDraft.maximumAmountText }, set: { coordinator.transactionFilterDraft.maximumAmountText = $0 }))
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("transactions-max-amount")
            }
            Picker("Receipt", selection: Binding(get: { coordinator.transactionFilterDraft.receiptCriterion }, set: { coordinator.transactionFilterDraft.receiptCriterion = $0 })) {
                ForEach(ReceiptAttachmentCriterion.allCases) { criterion in
                    Text(criterion.title).tag(criterion)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("transactions-receipt-filter")
        }
    }

    private var datePreset: String {
        switch coordinator.transactionFilterDraft.dateCriterion {
        case .none: "allTime"
        case .preset(let period): period.rawValue
        case .custom: "custom"
        }
    }

    private func setDatePreset(_ value: String) {
        if value == "custom" {
            let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
            coordinator.transactionFilterDraft.dateCriterion = .custom(start: today, end: today)
        } else if value == "allTime" {
            coordinator.transactionFilterDraft.dateCriterion = .preset(.allTime)
        } else if let period = ReportingPeriod(rawValue: value) {
            coordinator.transactionFilterDraft.dateCriterion = .preset(period)
        }
    }

    private var customStartBinding: Binding<Date> {
        Binding {
            if case .custom(let start, _) = coordinator.transactionFilterDraft.dateCriterion {
                return start
            }
            return Calendar.autoupdatingCurrent.startOfDay(for: Date())
        } set: { newValue in
            let end = customEndBinding.wrappedValue
            coordinator.transactionFilterDraft.dateCriterion = .custom(start: newValue, end: end)
        }
    }

    private var customEndBinding: Binding<Date> {
        Binding {
            if case .custom(_, let end) = coordinator.transactionFilterDraft.dateCriterion {
                return end
            }
            return Calendar.autoupdatingCurrent.startOfDay(for: Date())
        } set: { newValue in
            let start = customStartBinding.wrappedValue
            coordinator.transactionFilterDraft.dateCriterion = .custom(start: start, end: newValue)
        }
    }

    private func kindBinding(_ kind: TransactionKind) -> Binding<Bool> {
        Binding {
            coordinator.transactionFilterDraft.kinds.contains(kind)
        } set: { selected in
            if selected {
                coordinator.transactionFilterDraft.kinds.insert(kind)
            } else {
                coordinator.transactionFilterDraft.kinds.remove(kind)
            }
        }
    }

    private func filterGroup(_ title: String, values: [(UUID, String)], selection: Set<UUID>, change: @escaping (UUID, Bool) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            if values.isEmpty {
                Text("No available \(title.lowercased()).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.0) { id, name in
                    Toggle(name, isOn: Binding(get: { selection.contains(id) }, set: { change(id, $0) }))
                        .frame(minHeight: 44)
                }
            }
        }
    }
}

private struct TransactionResultRow: View {
    let snapshot: TransactionResultSnapshot
    let formatter: CurrencyFormatter

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.note?.isEmpty == false ? snapshot.note! : snapshot.itemName)
                Text("\(snapshot.planName) / \(snapshot.itemName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if snapshot.isScheduledIncome {
                    Text("Scheduled income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if snapshot.hasReceipt {
                    Label("Receipt attached", systemImage: "doc.text.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(formatter.string(for: snapshot.amount))
                .foregroundStyle(snapshot.kind == .income ? .green : .red)
                .monospacedDigit()
                .moneyEffortLookup(amount: snapshot.amount, formatter: formatter)
        }
        .frame(minHeight: 44)
        .accessibilityLabel("\(snapshot.kind == .income ? "Income" : "Expense"), \(formatter.string(for: snapshot.amount)), \(snapshot.note ?? ""), \(snapshot.planName), \(snapshot.itemName)\(snapshot.hasReceipt ? ", has receipt" : "")")
    }
}

#if DEBUG
#Preview {
    TransactionsRootView()
        .environment(BudgetingCoordinator(context: try! SampleData.makePreviewContainer().mainContext, clock: SystemClock(), preferences: MemoryPhase2PreferenceStore()))
}
#endif
