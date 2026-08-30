//
//  HomeRootView.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI
import Charts
import SwiftData

struct HomeRootView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator

    var body: some View {
        let snapshot = coordinator.homeSnapshot()
        List {
            Section {
                ReportingPeriodPicker(period: Binding(get: { coordinator.reportingPeriod }, set: { coordinator.reportingPeriod = $0 }))
                NavigationLink {
                    ReportDetailView(
                        title: "Net Cash Flow",
                        rangeTitle: coordinator.reportRangeDescription(snapshot.range),
                        summary: snapshot.summary,
                        chartKind: .netFlow,
                        buckets: snapshot.buckets,
                        rows: [
                            ReportBreakdownRow(id: "net", title: "Net", value: snapshot.netFlow)
                        ],
                        transactions: snapshot.allTransactions,
                        formatter: coordinator.formatter
                    )
                } label: {
                    ReportCard(title: "Net Cash Flow", amount: coordinator.formatter.string(for: snapshot.netFlow), amountValue: snapshot.netFlow, formatter: coordinator.formatter, summary: snapshot.summary) {
                        FlowChart(buckets: snapshot.buckets, formatter: coordinator.formatter)
                    }
                }
                .accessibilityIdentifier("home-net-flow-report")
            }

            Section {
                if snapshot.allTransactions.isEmpty {
                    ContentUnavailableView(coordinator.hasAnyTransactions ? "No Activity" : "No Data", systemImage: "chart.line.uptrend.xyaxis", description: Text("No transactions contribute to \(snapshot.range.title)."))
                } else {
                    ForEach(snapshot.recentTransactions) { transaction in
                        Button {
                            coordinator.openTransactionRoute(transaction.route)
                            coordinator.selectedTab = .budgets
                        } label: {
                            ReportTransactionRow(transaction: transaction, formatter: coordinator.formatter)
                        }
                    }
                    Button {
                        coordinator.beginHomeSeeAllTransactions()
                        coordinator.selectedTab = .transactions
                    } label: {
                        HStack {
                            Text("See All")
                            Spacer()
                            Image(systemName: "list.bullet")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-see-all-transactions")
                }
            } header: {
                Text("Recent Transactions")
            }

            Section("Active Plans") {
                if snapshot.activePlans.isEmpty {
                    ContentUnavailableView("No Active Plans", systemImage: "rectangle.stack", description: Text("Plans appear here when they have transactions in \(snapshot.range.title)."))
                } else {
                    ForEach(snapshot.activePlans) { plan in
                        Button {
                            coordinator.navigationSelection.selectBudget(plan.budgetID)
                            coordinator.navigationSelection.selectPlan(plan.planID)
                            coordinator.selectedTab = .budgets
                        } label: {
                            HStack {
                                Text(plan.name)
                                Spacer()
                                Text(coordinator.displayDate(plan.latestTransactionDate))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
        .navigationTitle("Home")
        .task { coordinator.refresh() }
    }
}

struct ReportingPeriodPicker: View {
    @Binding var period: ReportingPeriod

    var body: some View {
        Picker("Reporting Period", selection: $period) {
            ForEach(ReportingPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("reporting-period")
    }
}

struct ReportCard<Content: View>: View {
    let title: String
    let amount: String?
    let amountValue: Decimal?
    let formatter: CurrencyFormatter?
    let summary: String
    let minimumContentHeight: CGFloat
    @ViewBuilder let content: Content

    init(title: String, amount: String? = nil, amountValue: Decimal? = nil, formatter: CurrencyFormatter? = nil, summary: String, minimumContentHeight: CGFloat = 160, @ViewBuilder content: () -> Content) {
        self.title = title
        self.amount = amount
        self.amountValue = amountValue
        self.formatter = formatter
        self.summary = summary
        self.minimumContentHeight = minimumContentHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let amount {
                    if let amountValue, let formatter {
                        Text(amount)
                            .font(.headline)
                            .monospacedDigit()
                            .moneyEffortLookup(amount: abs(amountValue), formatter: formatter)
                    } else {
                        Text(amount)
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }
            content
                .frame(minHeight: minimumContentHeight)
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(title)-text-summary")
        }
        .padding(.vertical, 4)
    }
}

struct FlowChart: View {
    let buckets: [MoneyBucket]
    let formatter: CurrencyFormatter

    var body: some View {
        if !Phase4PresentationRules.reportHasMeaningfulData(buckets: buckets, rows: [], transactions: []) {
            ContentUnavailableView("No data to show for this filter yet.", systemImage: "chart.xyaxis.line")
        } else {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.label),
                    y: .value("Net", NSDecimalNumber(decimal: bucket.net).doubleValue)
                )
                .foregroundStyle(bucket.net >= 0 ? Color.green : Color.red)
            }
            .chartYAxisLabel("Net")
            .accessibilityLabel("Net cash flow chart")
            .accessibilityValue(buckets.map { "\($0.label): \(formatter.string(for: $0.net))" }.joined(separator: ", "))
        }
    }
}

enum ReportChartKind {
    case netFlow
    case signedFlow
    case expenseTrend
    case comparison
    case allocation(AllocationSnapshot)
    case balance
}

struct ReportTransactionRow: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let transaction: ReportTransactionReference
    let formatter: CurrencyFormatter

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note?.isEmpty == false ? transaction.note! : (transaction.kind == .income ? "Income" : "Expense"))
                Text(coordinator.displayDate(transaction.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatter.string(for: transaction.amount))
                .foregroundStyle(transaction.kind == .income ? .green : .red)
                .monospacedDigit()
                .moneyEffortLookup(amount: transaction.amount, formatter: formatter)
        }
        .frame(minHeight: 44)
        .accessibilityLabel("\(transaction.kind == .income ? "Income" : "Expense"), \(formatter.string(for: transaction.amount))")
    }
}

struct ReportDetailView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let title: String
    let rangeTitle: String
    let summary: String
    let chartKind: ReportChartKind
    let buckets: [MoneyBucket]
    let rows: [ReportBreakdownRow]
    let transactions: [ReportTransactionReference]
    let formatter: CurrencyFormatter

    var body: some View {
        List {
            Section {
                Text(rangeTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ReportDetailChart(kind: chartKind, buckets: buckets, rows: rows, transactions: transactions, formatter: formatter)
                    .frame(minHeight: 220)
                Text(summary)
                    .font(.callout)
                    .accessibilityIdentifier("report-detail-text-summary")
            } header: {
                Text("Summary")
            }

            Section("Breakdown") {
                let visibleRows = rows.filter { $0.value != 0 || !transactions.isEmpty }
                if !Phase4PresentationRules.reportHasMeaningfulData(buckets: buckets, rows: rows, transactions: transactions) {
                    ContentUnavailableView("No data to show for this filter yet.", systemImage: "list.bullet.rectangle")
                } else {
                    ForEach(visibleRows) { row in
                        LabeledContent(row.title) {
                            Text(formatter.string(for: row.value))
                                .moneyEffortLookup(amount: abs(row.value), formatter: formatter)
                        }
                            .frame(minHeight: 44)
                    }
                }
            }

            Section("Contributing Transactions") {
                if transactions.isEmpty {
                    ContentUnavailableView("No Transactions", systemImage: "tray")
                } else {
                    ForEach(reportTransactionSections) { section in
                        Section {
                            ForEach(section.transactions) { transaction in
                                Button {
                                    coordinator.openTransactionRoute(transaction.route)
                                    coordinator.selectedTab = .budgets
                                } label: {
                                    ReportTransactionRow(transaction: transaction, formatter: formatter)
                                }
                            }
                        } header: {
                            Text(section.header)
                                .textCase(nil)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .accessibilityIdentifier("report-detail-\(title)")
    }

    private var reportTransactionSections: [ReportTransactionSection] {
        let calendar = Calendar.autoupdatingCurrent
        let grouper = TransactionDayGrouper(calendar: calendar, locale: .autoupdatingCurrent, now: coordinator.asOfDate)
        let grouped = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let rows = (grouped[day] ?? []).sorted {
                if !calendar.isDate($0.date, inSameDayAs: $1.date) { return $0.date > $1.date }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            return ReportTransactionSection(day: day, header: grouper.header(for: day), transactions: rows)
        }
    }
}

private struct ReportTransactionSection: Identifiable {
    let day: Date
    let header: String
    let transactions: [ReportTransactionReference]

    var id: Date { day }
}

struct ReportDetailChart: View {
    let kind: ReportChartKind
    let buckets: [MoneyBucket]
    let rows: [ReportBreakdownRow]
    let transactions: [ReportTransactionReference]
    let formatter: CurrencyFormatter

    var body: some View {
        switch kind {
        case .netFlow:
            FlowChart(buckets: buckets, formatter: formatter)
        case .signedFlow:
            SignedFlowChart(buckets: buckets, formatter: formatter)
        case .expenseTrend:
            ExpenseTrendChart(buckets: buckets, formatter: formatter)
        case .comparison:
            ComparisonChart(rows: rows, transactions: transactions, formatter: formatter)
        case .allocation(let snapshot):
            AllocationDetailChart(snapshot: snapshot, formatter: formatter)
        case .balance:
            BalanceTimelineChart(buckets: buckets, formatter: formatter)
        }
    }
}

struct SignedFlowChart: View {
    let buckets: [MoneyBucket]
    let formatter: CurrencyFormatter

    var body: some View {
        if !Phase4PresentationRules.reportHasMeaningfulData(buckets: buckets, rows: [], transactions: []) {
            ContentUnavailableView("No data to show for this filter yet.", systemImage: "chart.xyaxis.line")
        } else {
            Chart {
                ForEach(buckets) { bucket in
                    BarMark(x: .value("Period", bucket.label), y: .value("Income", NSDecimalNumber(decimal: bucket.income).doubleValue))
                        .foregroundStyle(Color.green)
                    BarMark(x: .value("Period", bucket.label), y: .value("Expense", -NSDecimalNumber(decimal: bucket.expense).doubleValue))
                        .foregroundStyle(Color.red)
                }
            }
            .accessibilityLabel("Income and expense chart")
            .accessibilityValue(buckets.map { "\($0.label): income \(formatter.string(for: $0.income)), expenses \(formatter.string(for: $0.expense))" }.joined(separator: ", "))
        }
    }
}

struct ExpenseTrendChart: View {
    let buckets: [MoneyBucket]
    let formatter: CurrencyFormatter

    var body: some View {
        if !Phase4PresentationRules.reportHasMeaningfulData(buckets: buckets, rows: [], transactions: []) {
            ContentUnavailableView("No data to show for this filter yet.", systemImage: "chart.xyaxis.line")
        } else {
            Chart(buckets) { bucket in
                LineMark(x: .value("Period", bucket.label), y: .value("Expenses", NSDecimalNumber(decimal: bucket.expense).doubleValue))
                    .foregroundStyle(Color.red)
            }
            .accessibilityLabel("Expense trend chart")
            .accessibilityValue(buckets.map { "\($0.label): \(formatter.string(for: $0.expense))" }.joined(separator: ", "))
        }
    }
}

struct BalanceTimelineChart: View {
    let buckets: [MoneyBucket]
    let formatter: CurrencyFormatter

    var body: some View {
        if !Phase4PresentationRules.reportHasMeaningfulData(buckets: buckets, rows: [], transactions: []) {
            ContentUnavailableView("No data to show for this filter yet.", systemImage: "chart.xyaxis.line")
        } else {
            Chart(buckets) { bucket in
                LineMark(x: .value("Period", bucket.label), y: .value("Balance", NSDecimalNumber(decimal: bucket.balance).doubleValue))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Cumulative balance chart")
            .accessibilityValue(buckets.map { "\($0.label): \(formatter.string(for: $0.balance))" }.joined(separator: ", "))
        }
    }
}

struct ComparisonChart: View {
    let rows: [ReportBreakdownRow]
    let transactions: [ReportTransactionReference]
    let formatter: CurrencyFormatter

    var body: some View {
        if !Phase4PresentationRules.reportHasMeaningfulData(buckets: [], rows: rows, transactions: transactions) {
            ContentUnavailableView("No data to show for this filter yet.", systemImage: "chart.bar.xaxis")
        } else {
            Chart(rows) { row in
                BarMark(xStart: .value("Zero", 0), xEnd: .value("Value", NSDecimalNumber(decimal: row.value).doubleValue), y: .value("Name", row.title))
                    .foregroundStyle(row.value >= 0 ? Color.green : Color.red)
            }
            .chartXScale(domain: comparisonDomain)
            .accessibilityLabel("Comparison chart")
            .accessibilityValue(rows.map { "\($0.title): \(formatter.string(for: $0.value))" }.joined(separator: ", "))
        }
    }

    private var comparisonDomain: ClosedRange<Double> {
        let maxAbs = rows.map { abs(NSDecimalNumber(decimal: $0.value).doubleValue) }.max() ?? 1
        let safe = max(maxAbs, 1)
        return -safe...safe
    }
}

struct AllocationDetailChart: View {
    let snapshot: AllocationSnapshot
    let formatter: CurrencyFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let denominator = max(NSDecimalNumber(decimal: snapshot.total).doubleValue, 1)
                let numerator = max(NSDecimalNumber(decimal: snapshot.primary).doubleValue, 0)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: proxy.size.width * min(numerator / denominator, 1))
                    }
            }
            .frame(height: 18)
            Text("\(snapshot.primaryTitle): \(formatter.string(for: snapshot.primary))")
            Text("\(snapshot.secondaryTitle): \(formatter.string(for: snapshot.secondary))")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.primaryTitle) \(formatter.string(for: snapshot.primary)); \(snapshot.secondaryTitle) \(formatter.string(for: snapshot.secondary))")
    }
}

#if DEBUG
#Preview {
    HomeRootView()
        .environment(BudgetingCoordinator(context: try! SampleData.makePreviewContainer().mainContext, clock: SystemClock(), preferences: MemoryPhase2PreferenceStore()))
}
#endif
