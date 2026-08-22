//
//  BudgetsRootView.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI
import SwiftData
import Charts

struct BudgetsRootView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    @State private var activeSheet: BudgetSheet?
    @State private var activePlanSheet: ActivePlanSheet?
    @State private var activeItemSheet: ActiveItemSheet?
    @State private var activeTransactionSheet: ActiveTransactionSheet?
    @State private var deletion: BudgetDeletion?
    @State private var planDeletion: PlanDeletion?
    @State private var itemDeletion: ItemDeletion?
    @State private var transactionDeletion: TransactionDeletion?
    @State private var errorMessage: String?

    private var budgets: [Budget] { coordinator.budgets }
    private var selectedBudget: Budget? {
        budgets.first { $0.id == coordinator.navigationSelection.budgetID }
            ?? budgets.first { $0.id == coordinator.expandedBudgetID }
            ?? budgets.first
    }

    var body: some View {
        adaptiveContent
        .task {
            coordinator.refresh()
            coordinator.synchronizeAdaptiveBudgetSelection()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                BudgetFormView(mode: .create, existingBudget: nil, onSave: saveBudget)
            case .edit(let budget):
                BudgetFormView(mode: .edit, existingBudget: budget, onSave: saveBudget)
            }
        }
        .sheet(item: $activePlanSheet) { sheet in
            switch sheet {
            case .create(let budget):
                PlanFormView(mode: .create, plan: nil, budget: budget, formatter: coordinator.formatter, onSave: savePlan)
            case .edit(let plan):
                PlanFormView(mode: .edit, plan: plan, budget: plan.budget, formatter: coordinator.formatter, onSave: savePlan)
            }
        }
        .sheet(item: $activeItemSheet) { sheet in
            switch sheet {
            case .create(let plan):
                ItemFormView(mode: .create, item: nil, plan: plan, formatter: coordinator.formatter, onSave: saveItem)
            case .edit(let item):
                ItemFormView(mode: .edit, item: item, plan: item.budgetPlan, formatter: coordinator.formatter, onSave: saveItem)
            }
        }
        .sheet(item: $activeTransactionSheet) { sheet in
            switch sheet {
            case .create(let plan, let destination):
                TransactionFormView(plan: plan, transactionSheet: .create(destination: destination), formatter: coordinator.formatter, defaultDate: coordinator.asOfDate) { transaction, movedItem in
                    activeTransactionSheet = nil
                    if let movedItem {
                        coordinator.navigationSelection.selectPlan(plan.id)
                        coordinator.navigationSelection.selectItem(movedItem.id)
                    } else if let transaction {
                        coordinator.navigationSelection.selectPlan(plan.id)
                        coordinator.navigationSelection.selectItem(transaction.budgetItem.id)
                    }
                }
            case .edit(let transaction):
                TransactionFormView(plan: transaction.budgetItem.budgetPlan, transactionSheet: .edit(transaction), formatter: coordinator.formatter, defaultDate: coordinator.asOfDate) { _, movedItem in
                    activeTransactionSheet = nil
                    if let movedItem {
                        coordinator.navigationSelection.selectPlan(movedItem.budgetPlan.id)
                        coordinator.navigationSelection.selectItem(movedItem.id)
                    }
                }
            }
        }
        .confirmationDialog(
            deletion.map { "Delete \"\($0.budget.name)\"?" } ?? "Delete Budget?",
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            titleVisibility: .visible,
            presenting: deletion
        ) { deletion in
            Button("Delete \"\(deletion.budget.name)\"", role: .destructive) {
                deleteBudget(deletion.budget)
            }
            Button("Cancel") { self.deletion = nil }
        } message: { deletion in
            Text(deletion.impact.budgetMessage)
        }
        .confirmationDialog(planDeletion.map { "Delete \"\($0.plan.name)\"?" } ?? "Delete Plan?", isPresented: Binding(get: { planDeletion != nil }, set: { if !$0 { planDeletion = nil } }), titleVisibility: .visible, presenting: planDeletion) { deletion in
            Button("Delete \"\(deletion.plan.name)\"", role: .destructive) { deletePlan(deletion.plan) }
            Button("Cancel") { planDeletion = nil }
        } message: { deletion in
            Text(deletion.impact.planMessage)
        }
        .confirmationDialog(itemDeletion.map { "Delete \"\($0.itemName)\"?" } ?? "Delete Item?", isPresented: Binding(get: { itemDeletion != nil }, set: { if !$0 { itemDeletion = nil } }), titleVisibility: .visible, presenting: itemDeletion) { deletion in
            Button("Delete \"\(deletion.itemName)\"", role: .destructive) { deleteItem(id: deletion.itemID, fallbackPlanID: deletion.planID) }
            Button("Cancel") { itemDeletion = nil }
        } message: { deletion in
            Text(deletion.impact.itemMessage)
        }
        .confirmationDialog("Delete Transaction?", isPresented: Binding(get: { transactionDeletion != nil }, set: { if !$0 { transactionDeletion = nil } }), titleVisibility: .visible, presenting: transactionDeletion) { deletion in
            Button("Delete Transaction", role: .destructive) { deleteTransaction(deletion.transaction) }
            Button("Cancel") { transactionDeletion = nil }
        } message: { deletion in
            Text(coordinator.transactionDeletionTitle(for: deletion.transaction))
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var adaptiveContent: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 700 {
                BudgetSplitRootView(
                    activeSheet: $activeSheet,
                    activePlanSheet: $activePlanSheet,
                    activeItemSheet: $activeItemSheet,
                    activeTransactionSheet: $activeTransactionSheet,
                    deletion: $deletion,
                    planDeletion: $planDeletion,
                    itemDeletion: $itemDeletion,
                    transactionDeletion: $transactionDeletion
                )
            } else {
                NavigationStack(path: navigationPath) {
                    CompactBudgetsRootView(
                        activeSheet: $activeSheet,
                        activePlanSheet: $activePlanSheet,
                        activeItemSheet: $activeItemSheet,
                        activeTransactionSheet: $activeTransactionSheet,
                        deletion: $deletion,
                        planDeletion: $planDeletion,
                        itemDeletion: $itemDeletion,
                        transactionDeletion: $transactionDeletion
                    )
                    .navigationDestination(for: BudgetNavigationRoute.self) { route in
                        navigationDestination(for: route)
                    }
                }
            }
        }
    }

    private var navigationPath: Binding<[BudgetNavigationRoute]> {
        Binding {
            BudgetNavigationRoute.path(from: coordinator.navigationSelection)
        } set: { path in
            coordinator.navigationSelection = BudgetNavigationRoute.selection(from: path, fallbackBudgetID: coordinator.navigationSelection.budgetID)
            coordinator.synchronizeAdaptiveBudgetSelection()
        }
    }

    @ViewBuilder
    private func navigationDestination(for route: BudgetNavigationRoute) -> some View {
        switch route {
        case .plan(let planID):
            if let plan = coordinator.plan(with: planID) {
                PlanDetailView(
                    plan: plan,
                    formatter: coordinator.formatter,
                    onEditPlan: { activePlanSheet = .edit(plan) },
                    onDeletePlan: { planDeletion = PlanDeletion(plan: plan, impact: coordinator.planDeletionImpact(for: plan)) },
                    onCreateItem: { activeItemSheet = .create(plan) },
                    onEditItem: { activeItemSheet = .edit($0) },
                    onDeleteItem: { itemDeletion = ItemDeletion(item: $0, impact: coordinator.itemDeletionImpact(for: $0)) },
                    onCreateTransaction: { activeTransactionSheet = .create(plan: plan, destination: $0) }
                )
            } else {
                ContentUnavailableView("Plan Not Found", systemImage: "exclamationmark.triangle")
            }
        case .item(let itemID):
            if let item = coordinator.item(with: itemID) {
                ItemDetailView(
                    item: item,
                    formatter: coordinator.formatter,
                    onEditItem: { activeItemSheet = .edit(item) },
                    onDeleteItem: { itemDeletion = ItemDeletion(item: item, impact: coordinator.itemDeletionImpact(for: item)) },
                    onCreateTransaction: { activeTransactionSheet = .create(plan: item.budgetPlan, destination: item) },
                    onEditTransaction: { activeTransactionSheet = .edit($0) },
                    onDeleteTransaction: { transactionDeletion = TransactionDeletion(transaction: $0) }
                )
            } else {
                ContentUnavailableView("Item Not Found", systemImage: "exclamationmark.triangle")
            }
        case .budgetReports(let budgetID):
            if let budget = coordinator.budgets.first(where: { $0.id == budgetID }) {
                BudgetReportsScreen(budget: budget, formatter: coordinator.formatter)
            } else {
                ContentUnavailableView("Budget Not Found", systemImage: "exclamationmark.triangle")
            }
        case .planReports(let planID):
            if let plan = coordinator.plan(with: planID) {
                PlanReportsScreen(plan: plan, formatter: coordinator.formatter)
            } else {
                ContentUnavailableView("Plan Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func saveBudget(_ name: String, _ completion: (Bool, FieldErrors) -> Void) {
        do {
            if case .edit(let budget) = activeSheet {
                try coordinator.renameBudget(budget, name: name)
            } else {
                let budget = try coordinator.createBudget(name: name)
                coordinator.selectAdaptiveBudget(budget.id)
            }
            completion(true, FieldErrors())
            activeSheet = nil
        } catch {
            completion(false, fieldErrors(for: error))
        }
    }

    private func savePlan(_ name: String, _ amountText: String, _ completion: (Bool, FieldErrors) -> Void) {
        do {
            switch activePlanSheet {
            case .edit(let plan):
                try coordinator.updatePlan(plan, name: name, amountText: amountText)
            case .create(let budget):
                _ = try coordinator.createPlan(name: name, amountText: amountText, in: budget)
                coordinator.selectAdaptiveBudget(budget.id)
            case nil:
                throw Phase2ValidationError.invalidAmount
            }
            completion(true, FieldErrors())
            activePlanSheet = nil
        } catch {
            completion(false, fieldErrors(for: error))
        }
    }

    private func saveItem(_ name: String, _ unitAmountText: String, _ multiplierText: String, _ completion: (Bool, FieldErrors) -> Void) {
        do {
            switch activeItemSheet {
            case .edit(let item):
                try coordinator.updateItem(item, name: name, unitAmountText: unitAmountText, multiplierText: multiplierText)
            case .create(let plan):
                _ = try coordinator.createItem(name: name, unitAmountText: unitAmountText, multiplierText: multiplierText, in: plan)
                coordinator.navigationSelection.selectPlan(plan.id)
            case nil:
                throw Phase2ValidationError.invalidAmount
            }
            completion(true, FieldErrors())
            activeItemSheet = nil
        } catch {
            completion(false, fieldErrors(for: error))
        }
    }

    private func deleteBudget(_ budget: Budget) {
        do {
            try coordinator.deleteBudget(budget)
        coordinator.selectAdaptiveBudget(selectedBudget?.id)
            deletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePlan(_ plan: BudgetPlan) {
        do {
            let budgetID = plan.budget.id
            try coordinator.deletePlan(plan)
            coordinator.navigationSelection.selectBudget(budgetID)
            planDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem(id itemID: UUID, fallbackPlanID planID: UUID) {
        do {
            itemDeletion = nil
            guard let item = coordinator.item(with: itemID) else {
                coordinator.navigationSelection.selectPlan(planID)
                return
            }
            try coordinator.deleteItem(item)
            coordinator.navigationSelection.selectPlan(planID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTransaction(_ transaction: Transaction) {
        do {
            try coordinator.deleteTransaction(transaction)
            transactionDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum BudgetNavigationRoute: Hashable {
    case plan(UUID)
    case item(UUID)
    case budgetReports(UUID)
    case planReports(UUID)

    static func path(from selection: BudgetNavigationSelection) -> [BudgetNavigationRoute] {
        var path: [BudgetNavigationRoute] = []
        if let planID = selection.planID {
            path.append(.plan(planID))
        }
        if let itemID = selection.itemID {
            path.append(.item(itemID))
        }
        if let report = selection.report {
            switch report {
            case .budget(let budgetID):
                path.append(.budgetReports(budgetID))
            case .plan(let planID):
                path.append(.planReports(planID))
            }
        }
        return path
    }

    static func selection(from path: [BudgetNavigationRoute], fallbackBudgetID: UUID?) -> BudgetNavigationSelection {
        var selection = BudgetNavigationSelection(budgetID: fallbackBudgetID)
        for route in path {
            switch route {
            case .plan(let planID):
                selection.planID = planID
                selection.itemID = nil
            case .item(let itemID):
                selection.itemID = itemID
            case .budgetReports, .planReports:
                switch route {
                case .budgetReports(let budgetID):
                    selection.report = .budget(budgetID)
                case .planReports(let planID):
                    selection.report = .plan(planID)
                case .plan, .item:
                    break
                }
            }
        }
        return selection
    }
}

private struct BudgetEmptyState: View {
    let onCreateBudget: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "wallet.pass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No Budgets")
                    .font(.title2.bold())
                Text("Create a Budget to start building plans, items, and transactions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Create Budget", action: onCreateBudget)
                    .accessibilityIdentifier("create-budget-empty")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 420)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct BudgetSplitRootView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    @Binding var activeSheet: BudgetSheet?
    @Binding var activePlanSheet: ActivePlanSheet?
    @Binding var activeItemSheet: ActiveItemSheet?
    @Binding var activeTransactionSheet: ActiveTransactionSheet?
    @Binding var deletion: BudgetDeletion?
    @Binding var planDeletion: PlanDeletion?
    @Binding var itemDeletion: ItemDeletion?
    @Binding var transactionDeletion: TransactionDeletion?

    private var budgets: [Budget] { coordinator.budgets }
    private var selectedBudget: Budget? {
        budgets.first { $0.id == coordinator.navigationSelection.budgetID }
            ?? budgets.first { $0.id == coordinator.expandedBudgetID }
            ?? budgets.first
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if budgets.isEmpty {
                    BudgetEmptyState { activeSheet = .create }
                } else {
                    List(selection: Binding(get: { selectedBudget?.id }, set: { coordinator.selectAdaptiveBudget($0) })) {
                        ForEach(budgets) { budget in
                            Text(budget.name)
                                .tag(budget.id)
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                if budgets.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { activeSheet = .create } label: {
                            Label("Add", systemImage: "plus")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Add")
                        .accessibilityIdentifier("add-budget")
                    }
                }
            }
        } detail: {
            NavigationStack(path: navigationPath) {
                if let selectedBudget {
                    List {
                        BudgetPlanListView(
                            budget: selectedBudget,
                            formatter: coordinator.formatter,
                            onEditBudget: { activeSheet = .edit(selectedBudget) },
                            onDeleteBudget: { deletion = BudgetDeletion(budget: selectedBudget, impact: coordinator.budgetDeletionImpact(for: selectedBudget)) },
                            onCreatePlan: { activePlanSheet = .create(selectedBudget) },
                            onEditPlan: { activePlanSheet = .edit($0) },
                            onDeletePlan: { planDeletion = PlanDeletion(plan: $0, impact: coordinator.planDeletionImpact(for: $0)) }
                        )
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle(selectedBudget.name)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Menu {
                                Button("Add Budget") { activeSheet = .create }
                                Button("Add Plan") { activePlanSheet = .create(selectedBudget) }
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("Add")
                            .accessibilityIdentifier("budgets-add-menu")

                            Menu {
                                Button("Edit Budget") { activeSheet = .edit(selectedBudget) }
                                Button("Delete Budget", role: .destructive) {
                                    deletion = BudgetDeletion(
                                        budget: selectedBudget,
                                        impact: coordinator.budgetDeletionImpact(for: selectedBudget)
                                    )
                                }
                            } label: {
                                Label("Budget Actions", systemImage: "ellipsis.circle")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                    }
                    .navigationDestination(for: BudgetNavigationRoute.self) { route in
                        navigationDestination(for: route)
                    }
                } else {
                    ContentUnavailableView("No Budgets", systemImage: "wallet.pass", description: Text("Create a Budget to start building plans, items, and transactions."))
                        .navigationTitle("Budgets")
                }
            }
        }
        .task {
            coordinator.refresh()
            if coordinator.navigationSelection.budgetID == nil {
                coordinator.selectAdaptiveBudget(selectedBudget?.id)
            } else {
                coordinator.synchronizeAdaptiveBudgetSelection()
            }
        }
    }

    private var navigationPath: Binding<[BudgetNavigationRoute]> {
        Binding {
            BudgetNavigationRoute.path(from: coordinator.navigationSelection)
        } set: { path in
            coordinator.navigationSelection = BudgetNavigationRoute.selection(from: path, fallbackBudgetID: selectedBudget?.id)
            coordinator.synchronizeAdaptiveBudgetSelection()
        }
    }

    @ViewBuilder
    private func navigationDestination(for route: BudgetNavigationRoute) -> some View {
        switch route {
        case .plan(let planID):
            if let plan = coordinator.plan(with: planID) {
                PlanDetailView(
                    plan: plan,
                    formatter: coordinator.formatter,
                    onEditPlan: { activePlanSheet = .edit(plan) },
                    onDeletePlan: { planDeletion = PlanDeletion(plan: plan, impact: coordinator.planDeletionImpact(for: plan)) },
                    onCreateItem: { activeItemSheet = .create(plan) },
                    onEditItem: { activeItemSheet = .edit($0) },
                    onDeleteItem: { itemDeletion = ItemDeletion(item: $0, impact: coordinator.itemDeletionImpact(for: $0)) },
                    onCreateTransaction: { activeTransactionSheet = .create(plan: plan, destination: $0) }
                )
            } else {
                ContentUnavailableView("Plan Not Found", systemImage: "exclamationmark.triangle")
            }
        case .item(let itemID):
            if let item = coordinator.item(with: itemID) {
                ItemDetailView(
                    item: item,
                    formatter: coordinator.formatter,
                    onEditItem: { activeItemSheet = .edit(item) },
                    onDeleteItem: { itemDeletion = ItemDeletion(item: item, impact: coordinator.itemDeletionImpact(for: item)) },
                    onCreateTransaction: { activeTransactionSheet = .create(plan: item.budgetPlan, destination: item) },
                    onEditTransaction: { activeTransactionSheet = .edit($0) },
                    onDeleteTransaction: { transactionDeletion = TransactionDeletion(transaction: $0) }
                )
            } else {
                ContentUnavailableView("Item Not Found", systemImage: "exclamationmark.triangle")
            }
        case .budgetReports(let budgetID):
            if let budget = coordinator.budgets.first(where: { $0.id == budgetID }) {
                BudgetReportsScreen(budget: budget, formatter: coordinator.formatter)
            } else {
                ContentUnavailableView("Budget Not Found", systemImage: "exclamationmark.triangle")
            }
        case .planReports(let planID):
            if let plan = coordinator.plan(with: planID) {
                PlanReportsScreen(plan: plan, formatter: coordinator.formatter)
            } else {
                ContentUnavailableView("Plan Not Found", systemImage: "exclamationmark.triangle")
            }
        }
    }

}

private struct CompactBudgetsRootView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator

    @Binding var activeSheet: BudgetSheet?
    @Binding var activePlanSheet: ActivePlanSheet?
    @Binding var activeItemSheet: ActiveItemSheet?
    @Binding var activeTransactionSheet: ActiveTransactionSheet?
    @Binding var deletion: BudgetDeletion?
    @Binding var planDeletion: PlanDeletion?
    @Binding var itemDeletion: ItemDeletion?
    @Binding var transactionDeletion: TransactionDeletion?

    private var budgets: [Budget] { coordinator.budgets }
    private var formatter: CurrencyFormatter {
        coordinator.formatter
    }

    var body: some View {
        Group {
            if budgets.isEmpty {
                BudgetEmptyState { activeSheet = .create }
            } else {
                List {
                    ForEach(budgets) { budget in
                        BudgetAccordionRow(
                            budget: budget,
                            isExpanded: coordinator.expandedBudgetID == budget.id,
                            formatter: formatter,
                            onToggle: { toggle(budget) },
                            onEdit: { activeSheet = .edit(budget) },
                            onDelete: { deletion = BudgetDeletion(budget: budget, impact: coordinator.budgetDeletionImpact(for: budget)) },
                            onCreatePlan: { activePlanSheet = .create(budget) },
                            onEditPlan: { activePlanSheet = .edit($0) },
                            onDeletePlan: { planDeletion = PlanDeletion(plan: $0, impact: coordinator.planDeletionImpact(for: $0)) }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Budgets")
        .task { coordinator.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let expandedBudget = budgets.first(where: { $0.id == coordinator.expandedBudgetID }) {
                    Menu {
                        Button("Add Budget") { activeSheet = .create }
                        Button("Add Plan") { activePlanSheet = .create(expandedBudget) }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Add")
                    .accessibilityIdentifier("budgets-add-menu")
                } else {
                    Button { activeSheet = .create } label: {
                        Label("Add", systemImage: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Add")
                    .accessibilityIdentifier("add-budget")
                }
            }
        }
    }

    private func toggle(_ budget: Budget) {
        coordinator.selectAdaptiveBudget(coordinator.expandedBudgetID == budget.id ? nil : budget.id)
    }

}

private enum BudgetSheet: Identifiable {
    case create
    case edit(Budget)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let budget): "edit-\(budget.id)"
        }
    }
}

private enum ActivePlanSheet: Identifiable {
    case create(Budget)
    case edit(BudgetPlan)

    var id: String {
        switch self {
        case .create(let budget): "create-plan-\(budget.id)"
        case .edit(let plan): "edit-plan-\(plan.id)"
        }
    }
}

private enum ActiveItemSheet: Identifiable {
    case create(BudgetPlan)
    case edit(BudgetItem)

    var id: String {
        switch self {
        case .create(let plan): "create-item-\(plan.id)"
        case .edit(let item): "edit-item-\(item.id)"
        }
    }
}

private enum ActiveTransactionSheet: Identifiable {
    case create(plan: BudgetPlan, destination: BudgetItem?)
    case edit(Transaction)

    var id: String {
        switch self {
        case .create(let plan, let destination): "create-transaction-\(plan.id)-\(destination?.id.uuidString ?? "none")"
        case .edit(let transaction): "edit-transaction-\(transaction.id)"
        }
    }
}

private struct BudgetDeletion: Identifiable {
    var id: UUID { budget.id }
    let budget: Budget
    let impact: DeletionImpact
}

private struct BudgetAccordionRow: View {
    let budget: Budget
    let isExpanded: Bool
    let formatter: CurrencyFormatter
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCreatePlan: () -> Void
    let onEditPlan: (BudgetPlan) -> Void
    let onDeletePlan: (BudgetPlan) -> Void

    var body: some View {
        Section {
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(budget.name)
                            .font(.headline)
                        Text("\(budget.budgetPlans.count) plan\(budget.budgetPlans.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                    .tint(.blue)
            }

            if isExpanded {
                BudgetExpandedView(budget: budget, formatter: formatter, onEditBudget: onEdit, onDeleteBudget: onDelete, onCreatePlan: onCreatePlan, onEditPlan: onEditPlan, onDeletePlan: onDeletePlan)
            }
        }
    }
}

private struct BudgetExpandedView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let budget: Budget
    let formatter: CurrencyFormatter
    let onEditBudget: () -> Void
    let onDeleteBudget: () -> Void
    let onCreatePlan: () -> Void
    let onEditPlan: (BudgetPlan) -> Void
    let onDeletePlan: (BudgetPlan) -> Void

    @State private var errorMessage: String?
    @State private var showingManualChoice = false
    @State private var editMode: EditMode = .inactive

    private var sortMode: PlanSortMode { coordinator.planSortMode(for: budget) }
    private var direction: SortDirection { coordinator.planSortDirection(for: budget) }

    private var sortedPlans: [BudgetPlan] {
        coordinator.sortedPlans(for: budget)
    }

    var body: some View {
        let totals = coordinator.budgetTotals(for: budget)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(budget.name).font(.title3.bold())
                    TotalsGrid(rows: [
                        ("Funds", formatter.string(for: totals.totalFundsReceived)),
                        ("Spending", formatter.string(for: totals.expenses)),
                        ("Balance", formatter.string(for: totals.currentBalance))
                    ], amounts: [
                        "Funds": totals.totalFundsReceived,
                        "Spending": totals.expenses,
                        "Balance": totals.currentBalance
                    ], disclosures: [
                        "Funds": coordinator.roundingDisclosure(components: budget.budgetPlans.map { coordinator.planTotals(for: $0).totalFundsReceived }, total: totals.totalFundsReceived),
                        "Spending": coordinator.roundingDisclosure(components: budget.budgetPlans.map { coordinator.planTotals(for: $0).expenses }, total: totals.expenses),
                        "Balance": coordinator.roundingDisclosure(components: budget.budgetPlans.map { coordinator.planTotals(for: $0).currentBalance }, total: totals.currentBalance)
                    ])
                    if totals.expenses > 0 {
                        let progress = coordinator.progress(spent: totals.expenses, funds: max(totals.totalFundsReceived, 0))
                        LabeledProgressView(progress: progress)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit Budget", action: onEditBudget)
                    Button("Delete Budget", role: .destructive, action: onDeleteBudget)
                } label: {
                    Label("Budget Actions", systemImage: "ellipsis.circle")
                }
            }

            PlanSortControls(
                mode: sortMode,
                direction: direction,
                onModeChange: setSortMode,
                onDirectionChange: { coordinator.setPlanSortDirection($0, for: budget) }
            )
            if sortMode == .manual, !sortedPlans.isEmpty {
                Button(editMode.isEditing ? "Done Reordering" : "Reorder Plans") {
                    editMode = editMode.isEditing ? .inactive : .active
                }
                .accessibilityIdentifier("reorder-plans")
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }

            if sortedPlans.isEmpty {
                ContentUnavailableView("No Plans", systemImage: "rectangle.stack.badge.plus", description: Text("Add a Plan inside this Budget."))
                    Button("Add Plan", action: onCreatePlan)
                        .accessibilityIdentifier("add-plan-empty")
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            } else {
                planRows
            }

            if coordinator.hasMeaningfulBudgetReports(for: budget) {
                Button {
                    coordinator.openBudgetReports(for: budget)
                } label: {
                    Label("Reports", systemImage: "chart.bar.doc.horizontal")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onTapGesture { coordinator.openBudgetReports(for: budget) }
                .accessibilityIdentifier("budget-reports-button")
            }
        }
        .padding(.vertical, 8)
        .environment(\.editMode, $editMode)
        .confirmationDialog("Manual Plan Order", isPresented: $showingManualChoice, titleVisibility: .visible) {
            Button("Restore Saved Manual Order") {
                coordinator.restoreManualPlanOrder(for: budget)
            }
            Button("Replace With Current Order") {
                do {
                    try coordinator.replaceManualPlanOrder(with: sortedPlans, for: budget)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel") { }
        } message: {
            Text("Choose how Manual sorting should arrange this Budget’s Plans.")
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private var planRows: some View {
        if sortMode == .manual {
            ForEach(sortedPlans) { plan in
                planNavigationRow(plan)
            }
            .onMove(perform: movePlans)
        } else {
            ForEach(sortedPlans) { plan in
                planNavigationRow(plan)
            }
        }
    }

    private func planNavigationRow(_ plan: BudgetPlan) -> some View {
        Button {
            coordinator.navigationSelection.selectPlan(plan.id)
        } label: {
            PlanRowView(plan: plan, formatter: formatter)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("plan-row-\(plan.name)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDeletePlan(plan)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                onEditPlan(plan)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func setSortMode(_ mode: PlanSortMode) {
        if coordinator.requestPlanSortMode(mode, for: budget) {
            showingManualChoice = true
        }
    }

    private func movePlans(from source: IndexSet, to destination: Int) {
        var plans = sortedPlans
        plans.move(fromOffsets: source, toOffset: destination)
        do {
            try coordinator.reorderPlans(plans)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private struct BudgetPlanListView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let budget: Budget
    let formatter: CurrencyFormatter
    let onEditBudget: () -> Void
    let onDeleteBudget: () -> Void
    let onCreatePlan: () -> Void
    let onEditPlan: (BudgetPlan) -> Void
    let onDeletePlan: (BudgetPlan) -> Void

    @State private var errorMessage: String?
    @State private var showingManualChoice = false
    @State private var editMode: EditMode = .inactive

    private var sortMode: PlanSortMode { coordinator.planSortMode(for: budget) }
    private var direction: SortDirection { coordinator.planSortDirection(for: budget) }
    private var sortedPlans: [BudgetPlan] { coordinator.sortedPlans(for: budget) }

    var body: some View {
        Group {
            Section {
                PlanSortControls(
                    mode: sortMode,
                    direction: direction,
                    onModeChange: setSortMode,
                    onDirectionChange: { coordinator.setPlanSortDirection($0, for: budget) }
                )
                if sortMode == .manual, !sortedPlans.isEmpty {
                    Button(editMode.isEditing ? "Done Reordering" : "Reorder Plans") {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                    .accessibilityIdentifier("reorder-plans")
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }
            }

            Section("Plans") {
                if sortedPlans.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No Plans", systemImage: "rectangle.stack.badge.plus")
                            .font(.headline)
                        Text("Add a Plan inside this Budget.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    Button("Add Plan", action: onCreatePlan)
                        .accessibilityIdentifier("add-plan-empty")
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                } else {
                    planRows
                }
            }

            if coordinator.hasMeaningfulBudgetReports(for: budget) {
                Section("Reports") {
                    Button {
                        coordinator.openBudgetReports(for: budget)
                    } label: {
                        Label("Reports", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.openBudgetReports(for: budget) }
                    .accessibilityIdentifier("budget-reports-button")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .confirmationDialog("Manual Plan Order", isPresented: $showingManualChoice, titleVisibility: .visible) {
            Button("Restore Saved Manual Order") {
                coordinator.restoreManualPlanOrder(for: budget)
            }
            Button("Replace With Current Order") {
                do {
                    try coordinator.replaceManualPlanOrder(with: sortedPlans, for: budget)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel") { }
        } message: {
            Text("Choose how Manual sorting should arrange this Budget’s Plans.")
        }
        .alert("Couldn’t Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private var planRows: some View {
        if sortMode == .manual {
            ForEach(sortedPlans) { plan in
                planNavigationRow(plan)
            }
            .onMove(perform: movePlans)
        } else {
            ForEach(sortedPlans) { plan in
                planNavigationRow(plan)
            }
        }
    }

    private func planNavigationRow(_ plan: BudgetPlan) -> some View {
        Button {
            coordinator.navigationSelection.selectPlan(plan.id)
        } label: {
            PlanRowView(plan: plan, formatter: formatter)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDeletePlan(plan)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                onEditPlan(plan)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func setSortMode(_ mode: PlanSortMode) {
        if coordinator.requestPlanSortMode(mode, for: budget) {
            showingManualChoice = true
        }
    }

    private func movePlans(from source: IndexSet, to destination: Int) {
        var plans = sortedPlans
        plans.move(fromOffsets: source, toOffset: destination)
        do {
            try coordinator.reorderPlans(plans)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private struct PlanDeletion: Identifiable {
    var id: UUID { plan.id }
    let plan: BudgetPlan
    let impact: DeletionImpact
}

private struct BudgetReportsScreen: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let budget: Budget
    let formatter: CurrencyFormatter

    var body: some View {
        let snapshot = coordinator.budgetReportSnapshot(for: budget)
        List {
            Section {
                ReportingPeriodPicker(period: Binding(get: { coordinator.reportingPeriod }, set: { coordinator.reportingPeriod = $0 }))
                Picker("Trend Interval", selection: Binding(get: { coordinator.budgetReportInterval(for: budget) }, set: { coordinator.setBudgetReportInterval($0, for: budget) })) {
                    ForEach(ReportBucketInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("budget-report-interval")
            }
            Section("Reports") {
                NavigationLink {
                    ReportDetailView(title: "Plan Net Flow", rangeTitle: coordinator.reportRangeDescription(snapshot.range), summary: snapshot.summary, chartKind: .comparison, buckets: snapshot.flowBuckets, rows: snapshot.planComparisons, transactions: snapshot.transactions, formatter: formatter)
                } label: {
                    ReportCard(title: "Plan Net Flow", summary: snapshot.summary) {
                        DivergingRows(rows: snapshot.planComparisons, formatter: formatter)
                    }
                }
                .accessibilityIdentifier("budget-report-card-plan-net-flow")
                NavigationLink {
                    ReportDetailView(title: "Expense Trend", rangeTitle: coordinator.reportRangeDescription(snapshot.range), summary: "Expenses by \(snapshot.interval.title.lowercased()) for \(coordinator.reportRangeDescription(snapshot.range)).", chartKind: .expenseTrend, buckets: snapshot.expenseBuckets, rows: [ReportBreakdownRow(id: "expenses", title: "Expenses", value: snapshot.expenseTotal)], transactions: snapshot.transactions.filter { $0.kind == .expense }, formatter: formatter)
                } label: {
                    ReportCard(title: "Expense Trend", amount: formatter.string(for: snapshot.expenseTotal), amountValue: snapshot.expenseTotal, formatter: formatter, summary: "Expenses by \(snapshot.interval.title.lowercased()) for \(snapshot.range.title).") {
                        ExpenseChart(buckets: snapshot.expenseBuckets, formatter: formatter)
                    }
                }
                .accessibilityIdentifier("budget-report-card-expense-trend")
                NavigationLink {
                    ReportDetailView(title: "Income and Expense", rangeTitle: coordinator.reportRangeDescription(snapshot.range), summary: "Income \(formatter.string(for: snapshot.incomeTotal)); expenses \(formatter.string(for: snapshot.expenseTotal)).", chartKind: .signedFlow, buckets: snapshot.flowBuckets, rows: [ReportBreakdownRow(id: "income", title: "Income", value: snapshot.incomeTotal), ReportBreakdownRow(id: "expense", title: "Expense", value: snapshot.expenseTotal)], transactions: snapshot.transactions, formatter: formatter)
                } label: {
                    ReportCard(title: "Income and Expense", summary: "Income \(formatter.string(for: snapshot.incomeTotal)); expenses \(formatter.string(for: snapshot.expenseTotal)).") {
                        SignedFlowChart(buckets: snapshot.flowBuckets, formatter: formatter)
                    }
                }
                .accessibilityIdentifier("budget-report-card-income-expense")
            }
        }
        .navigationTitle("Budget Reports")
    }
}

private struct PlanReportsScreen: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let plan: BudgetPlan
    let formatter: CurrencyFormatter

    var body: some View {
        let snapshot = coordinator.planReportSnapshot(for: plan)
        List {
            Section {
                ReportingPeriodPicker(period: Binding(get: { coordinator.reportingPeriod }, set: { coordinator.reportingPeriod = $0 }))
                Picker("Timeline", selection: Binding(get: { coordinator.planTimelineMode(for: plan) }, set: { coordinator.setPlanTimelineMode($0, for: plan) })) {
                    ForEach(PlanTimelineMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("plan-timeline-mode")
            }
            Section("Reports") {
                NavigationLink {
                    ReportDetailView(title: "Allocation", rangeTitle: coordinator.reportRangeDescription(snapshot.range), summary: "Available \(formatter.string(for: snapshot.availableFunds)); allocated \(formatter.string(for: snapshot.allocated)); unallocated \(formatter.string(for: snapshot.unallocated)).", chartKind: .allocation(snapshot.allocationSnapshot), buckets: snapshot.timelineBuckets, rows: [ReportBreakdownRow(id: "available", title: "Available", value: snapshot.availableFunds), ReportBreakdownRow(id: "allocated", title: "Allocated", value: snapshot.allocated), ReportBreakdownRow(id: "unallocated", title: "Unallocated", value: snapshot.unallocated)], transactions: snapshot.transactions, formatter: formatter)
                } label: {
                    ReportCard(title: "Allocation", summary: "Available \(formatter.string(for: snapshot.availableFunds)); allocated \(formatter.string(for: snapshot.allocated)); unallocated \(formatter.string(for: snapshot.unallocated)).", minimumContentHeight: 34) {
                        ProportionalBar(primary: snapshot.allocated, total: max(snapshot.availableFunds, snapshot.allocated), primaryTitle: "Allocated", formatter: formatter)
                    }
                }
                .accessibilityIdentifier("plan-report-card-allocation")
                NavigationLink {
                    ReportDetailView(title: "Spent and Remaining", rangeTitle: coordinator.reportRangeDescription(snapshot.range), summary: "Spent \(formatter.string(for: snapshot.spent)); remaining \(formatter.string(for: snapshot.remaining)).", chartKind: .allocation(snapshot.spentRemainingSnapshot), buckets: snapshot.timelineBuckets, rows: [ReportBreakdownRow(id: "spent", title: "Spent", value: snapshot.spent), ReportBreakdownRow(id: "remaining", title: "Remaining", value: snapshot.remaining)], transactions: snapshot.transactions, formatter: formatter)
                } label: {
                    ReportCard(title: "Spent and Remaining", summary: "Spent \(formatter.string(for: snapshot.spent)); remaining \(formatter.string(for: snapshot.remaining)).", minimumContentHeight: 34) {
                        ProportionalBar(primary: snapshot.spent, total: max(snapshot.spent, snapshot.spent + max(snapshot.remaining, 0)), primaryTitle: "Spent", formatter: formatter)
                    }
                }
                .accessibilityIdentifier("plan-report-card-spent-remaining")
                NavigationLink {
                    ReportDetailView(title: "Item Net Flow", rangeTitle: coordinator.reportRangeDescription(snapshot.range), summary: snapshot.summary, chartKind: .comparison, buckets: snapshot.timelineBuckets, rows: snapshot.itemComparisons, transactions: snapshot.transactions, formatter: formatter)
                } label: {
                    ReportCard(title: "Item Net Flow", summary: snapshot.summary) {
                        DivergingRows(rows: snapshot.itemComparisons, formatter: formatter)
                    }
                }
                .accessibilityIdentifier("plan-report-card-item-net-flow")
                NavigationLink {
                    ReportDetailView(title: "Timeline", rangeTitle: coordinator.reportRangeDescription(snapshot.range), summary: snapshot.summary, chartKind: snapshot.timelineMode == .balance ? .balance : .signedFlow, buckets: snapshot.timelineBuckets, rows: [ReportBreakdownRow(id: "remaining", title: "Remaining", value: snapshot.remaining)], transactions: snapshot.transactions, formatter: formatter)
                } label: {
                    ReportCard(title: "Timeline", summary: snapshot.summary) {
                        if snapshot.timelineMode == .balance {
                            BalanceChart(buckets: snapshot.timelineBuckets, formatter: formatter)
                        } else {
                            SignedFlowChart(buckets: snapshot.timelineBuckets, formatter: formatter)
                        }
                    }
                }
                .accessibilityIdentifier("plan-report-card-timeline")
            }
        }
        .navigationTitle("Plan Reports")
    }
}

private struct DivergingRows: View {
    let rows: [ReportBreakdownRow]
    let formatter: CurrencyFormatter

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView("No Activity", systemImage: "chart.bar.xaxis", description: Text("No contributing transactions in this period."))
        } else {
            ComparisonChart(rows: rows, formatter: formatter)
                .frame(minHeight: 120)
        }
    }
}

private struct ExpenseChart: View {
    let buckets: [MoneyBucket]
    let formatter: CurrencyFormatter

    var body: some View {
        if buckets.isEmpty {
            ContentUnavailableView("No Activity", systemImage: "chart.xyaxis.line")
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

private struct BalanceChart: View {
    let buckets: [MoneyBucket]
    let formatter: CurrencyFormatter

    var body: some View {
        if buckets.isEmpty {
            ContentUnavailableView("No Activity", systemImage: "chart.xyaxis.line")
        } else {
            Chart(buckets) { bucket in
                LineMark(x: .value("Period", bucket.label), y: .value("Balance", NSDecimalNumber(decimal: bucket.balance).doubleValue))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Balance timeline chart")
            .accessibilityValue(buckets.map { "\($0.label): \(formatter.string(for: $0.balance))" }.joined(separator: ", "))
        }
    }
}

private struct ProportionalBar: View {
    let primary: Decimal
    let total: Decimal
    let primaryTitle: String
    let formatter: CurrencyFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let denominator = max(NSDecimalNumber(decimal: total).doubleValue, 1)
                let numerator = max(NSDecimalNumber(decimal: primary).doubleValue, 0)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: proxy.size.width * min(numerator / denominator, 1))
                    }
            }
            .frame(height: 14)
            Text("\(primaryTitle): \(formatter.string(for: primary))")
                .font(.callout)
                .moneyEffortLookup(amount: abs(primary), formatter: formatter)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(primaryTitle), \(formatter.string(for: primary))")
    }
}

private struct PlanDetailView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let plan: BudgetPlan
    let formatter: CurrencyFormatter
    let onEditPlan: () -> Void
    let onDeletePlan: () -> Void
    let onCreateItem: () -> Void
    let onEditItem: (BudgetItem) -> Void
    let onDeleteItem: (BudgetItem) -> Void
    let onCreateTransaction: (BudgetItem?) -> Void

    @State private var selectedClassification: BudgetItemClassification = .available
    @State private var showingReports = false
    @State private var markAsSpentItem: BudgetItem?
    @State private var markAsSpentError: String?

    private var itemDirection: ItemSortDirection { coordinator.itemSortDirection(for: plan) }
    private var sortedItems: [BudgetItem] {
        coordinator.sortedItems(for: plan)
    }

    var body: some View {
        let totals = coordinator.planTotals(for: plan)
        let visibleClassifications = coordinator.visibleItemClassifications(for: plan)
        let activeClassification = visibleClassifications.contains(selectedClassification) ? selectedClassification : visibleClassifications.first ?? .available
        let displayedItems = visibleClassifications.count <= 1 ? sortedItems : coordinator.sortedItems(for: plan, classification: activeClassification)
        List {
            Section {
                TotalsGrid(rows: [
                    ("Funds", formatter.string(for: totals.totalFundsReceived)),
                    ("Planned", formatter.string(for: totals.planned)),
                    ("Spent", formatter.string(for: totals.expenses)),
                    ("Balance", formatter.string(for: totals.currentBalance))
                ], amounts: [
                    "Funds": totals.totalFundsReceived,
                    "Planned": totals.planned,
                    "Spent": totals.expenses,
                    "Balance": totals.currentBalance
                ], disclosures: [
                    "Funds": coordinator.roundingDisclosure(components: [plan.startingAmount] + plan.budgetItems.map { coordinator.itemTotals(for: $0).effectiveIncome }, total: totals.totalFundsReceived),
                    "Planned": coordinator.roundingDisclosure(components: plan.budgetItems.map { coordinator.itemTotals(for: $0).planned }, total: totals.planned),
                    "Spent": coordinator.roundingDisclosure(components: plan.budgetItems.map { coordinator.itemTotals(for: $0).expenses }, total: totals.expenses),
                    "Balance": coordinator.roundingDisclosure(components: [totals.totalFundsReceived, -totals.expenses], total: totals.currentBalance)
                ])
                LabeledProgressView(progress: coordinator.progress(spent: totals.expenses, funds: totals.totalFundsReceived))
            }

            Section {
                Picker("Item Sort", selection: Binding(get: { itemDirection }, set: { coordinator.setItemSortDirection($0, for: plan) })) {
                    ForEach(ItemSortDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Items") {
                if sortedItems.isEmpty {
                    ContentUnavailableView("No Items", systemImage: "checklist", description: Text("Add an Item before entering Plan-level transactions."))
                    Button("Add Item", action: onCreateItem)
                        .accessibilityIdentifier("add-item-empty")
                } else {
                    if visibleClassifications.count > 1 {
                        Picker("Item Status", selection: $selectedClassification) {
                            ForEach(visibleClassifications) { classification in
                                Text(classification.title).tag(classification)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("plan-item-status-tabs")
                    }
                    ForEach(displayedItems) { item in
                        NavigationLink(value: BudgetNavigationRoute.item(item.id)) {
                            ItemRowView(item: item, formatter: formatter)
                        }
                        .accessibilityIdentifier("item-row-\(item.name)")
                        .accessibilityValue(item.id.uuidString)
                        .swipeActions(allowsFullSwipe: true) {
                            Button(role: .destructive) { onDeleteItem(item) } label: { Label("Delete", systemImage: "trash") }
                            Button { onEditItem(item) } label: { Label("Edit", systemImage: "pencil") }
                                .tint(.blue)
                            if coordinator.markAsSpentPreview(for: item).isEligible {
                                Button { markAsSpentItem = item } label: { Label("Mark Spent", systemImage: "checkmark.circle") }
                                    .tint(.orange)
                            }
                        }
                    }
                }
            }

            if coordinator.hasMeaningfulPlanReports(for: plan) {
                Section("Reports") {
                    Button {
                        showingReports = true
                    } label: {
                        Label("Reports", systemImage: "chart.bar.doc.horizontal")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .onTapGesture { showingReports = true }
                    .accessibilityIdentifier("plan-reports-button")
                }
            }
        }
        .navigationTitle(plan.name)
        .navigationDestination(isPresented: $showingReports) {
            PlanReportsScreen(plan: plan, formatter: formatter)
        }
        .alert("Mark as Spent", isPresented: Binding(get: { markAsSpentItem != nil }, set: { if !$0 { markAsSpentItem = nil } })) {
            Button("Cancel", role: .cancel) { markAsSpentItem = nil }
            Button("Mark Spent") {
                guard let item = markAsSpentItem else { return }
                do {
                    try coordinator.markItemAsSpent(item)
                    markAsSpentItem = nil
                } catch {
                    markAsSpentError = error.localizedDescription
                    markAsSpentItem = nil
                }
            }
        } message: {
            Text(markAsSpentTitle)
        }
        .alert("Couldn’t Mark as Spent", isPresented: Binding(get: { markAsSpentError != nil }, set: { if !$0 { markAsSpentError = nil } })) {
            Button("OK", role: .cancel) { markAsSpentError = nil }
        } message: {
            Text(markAsSpentError ?? "")
        }
        .onAppear { selectedClassification = normalizedClassification(visibleClassifications) }
        .onChange(of: visibleClassifications) { _, newValue in
            selectedClassification = normalizedClassification(newValue)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Add Item", action: onCreateItem)
                        .accessibilityIdentifier("add-item")
                    Button("Add Transaction") { onCreateTransaction(plan.budgetItems.first) }
                        .accessibilityIdentifier("add-transaction")
                        .disabled(plan.budgetItems.isEmpty)
                        .accessibilityHint(plan.budgetItems.isEmpty ? "Add an Item before adding a Transaction." : "")
                } label: {
                    Label("Add", systemImage: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Add")
                .accessibilityIdentifier("plan-add-menu")
                Menu {
                    Button("Edit Plan", action: onEditPlan)
                    Button("Delete Plan", role: .destructive, action: onDeletePlan)
                } label: { Label("Plan Actions", systemImage: "ellipsis.circle") }
            }
        }
    }

    private func normalizedClassification(_ visibleClassifications: [BudgetItemClassification]) -> BudgetItemClassification {
        if visibleClassifications.contains(selectedClassification) {
            return selectedClassification
        }
        return [.available, .spent, .income].first { visibleClassifications.contains($0) } ?? .available
    }

    private var markAsSpentTitle: String {
        guard let item = markAsSpentItem else { return "Mark Item as spent?" }
        let amount = coordinator.markAsSpentPreview(for: item).amount
        return "Mark '\(item.name)' as spent? This creates an expense of \(formatter.string(for: amount)) dated today."
    }

}

private struct ItemDeletion: Identifiable {
    var id: UUID { itemID }
    let itemID: UUID
    let planID: UUID
    let itemName: String
    let impact: DeletionImpact

    init(item: BudgetItem, impact: DeletionImpact) {
        self.itemID = item.id
        self.planID = item.budgetPlan.id
        self.itemName = item.name
        self.impact = impact
    }
}

private struct ItemDetailView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let item: BudgetItem
    let formatter: CurrencyFormatter
    let onEditItem: () -> Void
    let onDeleteItem: () -> Void
    let onCreateTransaction: () -> Void
    let onEditTransaction: (Transaction) -> Void
    let onDeleteTransaction: (Transaction) -> Void
    @State private var markAsSpentItem: BudgetItem?
    @State private var markAsSpentError: String?

    private var transactionSections: [TransactionDaySection] {
        coordinator.transactionDaySections(for: item)
    }

    var body: some View {
        let totals = coordinator.itemTotals(for: item)
        List {
            Section {
                TotalsGrid(rows: [
                    ("Planned", formatter.string(for: totals.planned)),
                    ("Income", formatter.string(for: totals.effectiveIncome)),
                    ("Spent", formatter.string(for: totals.expenses)),
                    ("Remaining", formatter.string(for: totals.remaining))
                ], amounts: [
                    "Planned": totals.planned,
                    "Income": totals.effectiveIncome,
                    "Spent": totals.expenses,
                    "Remaining": totals.remaining
                ], disclosures: [
                    "Planned": coordinator.roundingDisclosure(components: coordinator.plannedComponents(for: item), total: totals.planned),
                    "Income": coordinator.roundingDisclosure(components: coordinator.incomeComponents(for: item), total: totals.effectiveIncome),
                    "Spent": coordinator.roundingDisclosure(components: coordinator.expenseComponents(for: item), total: totals.expenses),
                    "Remaining": coordinator.roundingDisclosure(components: [totals.planned, totals.effectiveIncome, -totals.expenses], total: totals.remaining)
                ])
                if totals.scheduledIncome > 0 {
                    Label("Scheduled income: \(formatter.string(for: totals.scheduledIncome))", systemImage: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                }
                LabeledProgressView(progress: coordinator.progress(spent: totals.expenses, funds: max(totals.available, 0)))
            }

            if transactionSections.isEmpty {
                Section("Transactions") {
                    ContentUnavailableView("No Transactions", systemImage: "tray", description: Text("Add income or expenses for this Item."))
                    Button("Add Transaction", action: onCreateTransaction)
                        .accessibilityIdentifier("add-transaction-empty")
                }
            } else {
                ForEach(transactionSections) { section in
                    Section {
                        ForEach(section.transactions) { transaction in
                            Button {
                                onEditTransaction(transaction)
                            } label: {
                                TransactionRowView(transaction: transaction, formatter: formatter)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(coordinator.highlightedTransactionID == transaction.id ? Color.accentColor.opacity(0.18) : nil)
                            .accessibilityHint(coordinator.highlightedTransactionID == transaction.id ? "Highlighted transaction from search or report." : "")
                            .accessibilityIdentifier(coordinator.highlightedTransactionID == transaction.id ? "highlighted-transaction-\(transaction.id.uuidString)" : "transaction-\(transaction.id.uuidString)")
                            .swipeActions(allowsFullSwipe: true) {
                                Button(role: .destructive) { onDeleteTransaction(transaction) } label: { Label("Delete", systemImage: "trash") }
                                Button { onEditTransaction(transaction) } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.blue)
                            }
                        }
                    } header: {
                        Text(section.header)
                            .font(.headline)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("transaction-section-\(section.day.timeIntervalSince1970)")
                    }
                }
            }
        }
        .navigationTitle(item.name)
        .alert("Mark as Spent", isPresented: Binding(get: { markAsSpentItem != nil }, set: { if !$0 { markAsSpentItem = nil } })) {
            Button("Cancel", role: .cancel) { markAsSpentItem = nil }
            Button("Mark Spent") {
                do {
                    try coordinator.markItemAsSpent(item)
                    markAsSpentItem = nil
                } catch {
                    markAsSpentError = error.localizedDescription
                    markAsSpentItem = nil
                }
            }
        } message: {
            Text(markAsSpentTitle)
        }
        .alert("Couldn’t Mark as Spent", isPresented: Binding(get: { markAsSpentError != nil }, set: { if !$0 { markAsSpentError = nil } })) {
            Button("OK", role: .cancel) { markAsSpentError = nil }
        } message: {
            Text(markAsSpentError ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: onCreateTransaction) { Label("Add Transaction", systemImage: "plus") }
                    .accessibilityIdentifier("add-transaction")
                Menu {
                    if coordinator.markAsSpentPreview(for: item).isEligible {
                        Button("Mark as Spent") { markAsSpentItem = item }
                    }
                    Button("Edit Item", action: onEditItem)
                    Button("Delete Item", role: .destructive, action: onDeleteItem)
                } label: { Label("Item Actions", systemImage: "ellipsis.circle") }
            }
        }
    }

    private var markAsSpentTitle: String {
        let amount = coordinator.markAsSpentPreview(for: item).amount
        return "Mark '\(item.name)' as spent? This creates an expense of \(formatter.string(for: amount)) dated today."
    }
}

private enum TransactionSheet: Identifiable {
    case create(destination: BudgetItem?)
    case edit(Transaction)

    var id: String {
        switch self {
        case .create(let item): "create-transaction-\(item?.id.uuidString ?? "none")"
        case .edit(let transaction): "edit-transaction-\(transaction.id)"
        }
    }
}

private struct TransactionDeletion: Identifiable {
    var id: UUID { transaction.id }
    let transaction: Transaction
}

private enum TransactionDestinationMode: String, CaseIterable, Identifiable {
    case existing
    case newItem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existing: "Existing Item"
        case .newItem: "Create New Item"
        }
    }
}

private struct BudgetFormView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: FormMode
    let existingBudget: Budget?
    let onSave: (String, (Bool, FieldErrors) -> Void) -> Void

    @State private var name: String
    @State private var errors = FieldErrors()
    @State private var showSummary = false

    init(mode: FormMode, existingBudget: Budget?, onSave: @escaping (String, (Bool, FieldErrors) -> Void) -> Void) {
        self.mode = mode
        self.existingBudget = existingBudget
        self.onSave = onSave
        _name = State(initialValue: existingBudget?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Budget") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("budget-name")
                    InlineErrorText(errors.name)
                }
            }
            .navigationTitle(mode.title("Budget"))
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
        onSave(name) { success, newErrors in
            errors = newErrors
            if success { dismiss() } else { showSummary = true }
        }
    }
}

private struct PlanFormView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: FormMode
    let plan: BudgetPlan?
    let budget: Budget
    let formatter: CurrencyFormatter
    let onSave: (String, String, (Bool, FieldErrors) -> Void) -> Void

    @State private var name: String
    @State private var startingAmount: String
    @State private var errors = FieldErrors()
    @State private var showSummary = false

    init(mode: FormMode, plan: BudgetPlan?, budget: Budget, formatter: CurrencyFormatter, onSave: @escaping (String, String, (Bool, FieldErrors) -> Void) -> Void) {
        self.mode = mode
        self.plan = plan
        self.budget = budget
        self.formatter = formatter
        self.onSave = onSave
        _name = State(initialValue: plan?.name ?? "")
        _startingAmount = State(initialValue: plan.map { LocalizedNumericEditingPolicy(locale: formatter.locale).editableString(for: $0.startingAmount) } ?? "0")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("plan-name")
                    InlineErrorText(errors.name)
                    NumericTextField("Starting Amount", text: $startingAmount, kind: .decimal, locale: formatter.locale, error: $errors.amount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("plan-starting-amount")
                    InlineErrorText(errors.amount)
                }
            }
            .navigationTitle(mode.title("Plan"))
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
        onSave(name, startingAmount) { success, newErrors in
            errors = newErrors
            if success { dismiss() } else { showSummary = true }
        }
    }
}

private struct ItemFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BudgetingCoordinator.self) private var coordinator
    let mode: FormMode
    let item: BudgetItem?
    let plan: BudgetPlan
    let formatter: CurrencyFormatter
    let onSave: (String, String, String, (Bool, FieldErrors) -> Void) -> Void

    @State private var name: String
    @State private var unitAmount: String
    @State private var multiplier: String
    @State private var errors = FieldErrors()
    @State private var showSummary = false

    private var allocationPreview: ItemAllocationPreview? {
        coordinator.itemAllocationPreview(for: plan, editing: item, unitAmountText: unitAmount, multiplierText: multiplier)
    }

    init(mode: FormMode, item: BudgetItem?, plan: BudgetPlan, formatter: CurrencyFormatter, onSave: @escaping (String, String, String, (Bool, FieldErrors) -> Void) -> Void) {
        self.mode = mode
        self.item = item
        self.plan = plan
        self.formatter = formatter
        self.onSave = onSave
        _name = State(initialValue: item?.name ?? "")
        _unitAmount = State(initialValue: item.map { LocalizedNumericEditingPolicy(locale: formatter.locale).editableString(for: $0.unitAmount) } ?? "0")
        _multiplier = State(initialValue: item.map { LocalizedNumericEditingPolicy(locale: formatter.locale, kind: .wholeNumber).editableString(for: $0.multiplier) } ?? "1")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("item-name")
                    InlineErrorText(errors.name)
                    NumericTextField("Unit Amount", text: $unitAmount, kind: .decimal, locale: formatter.locale, error: $errors.amount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("item-unit-amount")
                    InlineErrorText(errors.amount)
                    NumericTextField("Multiplier", text: $multiplier, kind: .wholeNumber, locale: formatter.locale, error: $errors.multiplier)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("item-multiplier")
                    InlineErrorText(errors.multiplier)
                    if let allocationPreview {
                        let projected = allocationPreview.projectedUnallocated
                        let status = projected < 0 ? "\(formatter.string(for: abs(projected))) overallocated" : "\(formatter.string(for: projected)) unallocated"
                        LabeledContent("Allocation") {
                            Text(status)
                                .foregroundStyle(projected < 0 ? .orange : .green)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Allocation preview, \(status)")
                        .accessibilityIdentifier("item-allocation-preview")
                    }
                }
            }
            .navigationTitle(mode.title("Item"))
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
        onSave(name, unitAmount, multiplier) { success, newErrors in
            errors = newErrors
            if success { dismiss() } else { showSummary = true }
        }
    }
}

private struct TransactionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BudgetingCoordinator.self) private var coordinator
    let plan: BudgetPlan
    let transactionSheet: TransactionSheet
    let formatter: CurrencyFormatter
    let defaultDate: Date
    let onComplete: (Transaction?, BudgetItem?) -> Void

    @State private var kind: TransactionKind
    @State private var amount: String
    @State private var date: Date
    @State private var notes: String
    @State private var destinationID: UUID?
    @State private var destinationMode: TransactionDestinationMode
    @State private var newItemName = ""
    @State private var errors = FieldErrors()
    @State private var showSummary = false

    private var transaction: Transaction? {
        if case .edit(let transaction) = transactionSheet { return transaction }
        return nil
    }

    private var selectedDestination: BudgetItem? {
        guard let destinationID else { return nil }
        return plan.budgetItems.first { $0.id == destinationID }
    }

    private var projection: TransactionProjection? {
        coordinator.transactionProjection(
            kind: kind,
            amountText: amount,
            date: date,
            destination: selectedDestination,
            transaction: transaction,
            createsNewItem: transaction == nil && destinationMode == .newItem,
            plan: plan
        )
    }

    init(plan: BudgetPlan, transactionSheet: TransactionSheet, formatter: CurrencyFormatter, defaultDate: Date, onComplete: @escaping (Transaction?, BudgetItem?) -> Void) {
        self.plan = plan
        self.transactionSheet = transactionSheet
        self.formatter = formatter
        self.defaultDate = defaultDate
        self.onComplete = onComplete
        switch transactionSheet {
        case .create(let destination):
            _kind = State(initialValue: .expense)
            _amount = State(initialValue: "")
            _date = State(initialValue: defaultDate)
            _notes = State(initialValue: "")
            _destinationID = State(initialValue: destination?.id ?? plan.budgetItems.first?.id)
            _destinationMode = State(initialValue: plan.budgetItems.isEmpty ? .newItem : .existing)
        case .edit(let transaction):
            _kind = State(initialValue: transaction.kind)
            _amount = State(initialValue: LocalizedNumericEditingPolicy(locale: formatter.locale).editableString(for: transaction.amount))
            _date = State(initialValue: transaction.date)
            _notes = State(initialValue: transaction.notes ?? "")
            _destinationID = State(initialValue: transaction.budgetItem.id)
            _destinationMode = State(initialValue: .existing)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    Picker("Type", selection: $kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)
                    NumericTextField("Amount", text: $amount, kind: .decimal, locale: formatter.locale, error: $errors.amount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("transaction-amount")
                    InlineErrorText(errors.amount)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    InlineErrorText(errors.date)
                    TextField("Note", text: $notes, axis: .vertical)
                        .accessibilityIdentifier("transaction-note")
                }

                Section("Destination Item") {
                    if transaction == nil {
                        Picker("Destination", selection: $destinationMode) {
                            ForEach(TransactionDestinationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("transaction-destination-mode")
                    }
                    if destinationMode == .existing {
                        if plan.budgetItems.isEmpty {
                            ContentUnavailableView("No Items", systemImage: "checklist", description: Text("Create a new Item to continue."))
                        }
                        ForEach(plan.budgetItems.sorted { $0.sortOrder < $1.sortOrder }) { item in
                            Button {
                                destinationID = item.id
                            } label: {
                                HStack {
                                    Text(item.name)
                                    Spacer()
                                    if destinationID == item.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("destination-item-\(item.name)")
                            .accessibilityLabel("Destination Item, \(item.name)")
                        }
                    } else {
                        TextField("New Item Name", text: $newItemName)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("transaction-new-item-name")
                        InlineErrorText(errors.name)
                    }
                    InlineErrorText(errors.destination)
                }

                if let projection {
                    Section("Projected Balances") {
                        ProjectionRow(title: "Item after transaction", amount: projection.itemAfter, formatter: formatter, positiveLabel: kind == .income ? "available" : "remaining", negativeLabel: "overspent")
                            .accessibilityIdentifier("transaction-item-projection")
                        ProjectionRow(title: "Plan after transaction", amount: projection.planAfter, formatter: formatter, positiveLabel: "remaining", negativeLabel: "overspent")
                            .accessibilityIdentifier("transaction-plan-projection")
                        if projection.hasScheduledIncome {
                            Label("Scheduled income—not included in current balance", systemImage: "calendar.badge.clock")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("transaction-scheduled-income-preview")
                        }
                    }
                }
            }
            .navigationTitle(transaction == nil ? "Add Transaction" : "Edit Transaction")
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
        errors = FieldErrors()
        do {
            if let transaction {
                guard let destinationID, let item = plan.budgetItems.first(where: { $0.id == destinationID }) else {
                    errors.destination = Phase2ValidationError.noDestinationItem.localizedDescription
                    showSummary = true
                    return
                }
                let movedItem = try coordinator.updateTransaction(transaction, kind: kind, amountText: amount, date: date, notes: notes, destinationItem: item)
                onComplete(transaction, movedItem)
            } else if destinationMode == .newItem {
                let result = try coordinator.createItemAndTransaction(kind: kind, amountText: amount, date: date, itemName: newItemName, in: plan)
                onComplete(result.transaction, result.item)
            } else {
                guard let destinationID, let item = plan.budgetItems.first(where: { $0.id == destinationID }) else {
                    errors.destination = Phase2ValidationError.noDestinationItem.localizedDescription
                    showSummary = true
                    return
                }
                let transaction = try coordinator.createTransaction(kind: kind, amountText: amount, date: date, notes: notes, item: item)
                onComplete(transaction, nil)
            }
            dismiss()
        } catch {
            errors = fieldErrors(for: error)
            showSummary = true
        }
    }
}

private struct ProjectionRow: View {
    let title: String
    let amount: Decimal
    let formatter: CurrencyFormatter
    let positiveLabel: String
    let negativeLabel: String

    var body: some View {
        let label = amount < 0 ? negativeLabel : positiveLabel
        let displayAmount = amount < 0 ? abs(amount) : amount
        LabeledContent(title) {
            Text("\(formatter.string(for: displayAmount)) \(label)")
                .foregroundStyle(amount < 0 ? .orange : .green)
                .moneyEffortLookup(amount: displayAmount, formatter: formatter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(formatter.string(for: displayAmount)) \(label)")
    }
}

private enum FormMode {
    case create
    case edit

    func title(_ noun: String) -> String {
        self == .create ? "New \(noun)" : "Edit \(noun)"
    }
}

private struct PlanSortControls: View {
    let mode: PlanSortMode
    let direction: SortDirection
    let onModeChange: (PlanSortMode) -> Void
    let onDirectionChange: (SortDirection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Sort Plans", selection: Binding(get: { mode }, set: onModeChange)) {
                ForEach(PlanSortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            if mode != .manual {
                Picker("Direction", selection: Binding(get: { direction }, set: onDirectionChange)) {
                    ForEach(SortDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PlanRowView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let plan: BudgetPlan
    let formatter: CurrencyFormatter

    var body: some View {
        let totals = coordinator.planTotals(for: plan)
        let progress = coordinator.progress(spent: totals.expenses, funds: totals.totalFundsReceived)
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.name).font(.headline)
            ProgressView(value: progress.cappedFraction)
                .tint(progress.isWarning ? .orange : .accentColor)
            Text(progress.label)
                .font(.subheadline)
                .foregroundStyle(progress.isWarning ? .orange : .secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.name), \(progress.label)")
    }
}

private struct ItemRowView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let item: BudgetItem
    let formatter: CurrencyFormatter

    var body: some View {
        let presentation = coordinator.itemRowPresentation(for: item)
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name).font(.headline)
            switch presentation.style {
            case .income:
                Text("Income: \(formatter.string(for: presentation.effectiveIncome))")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .moneyEffortLookup(amount: presentation.effectiveIncome, formatter: formatter)
                if presentation.scheduledIncome > 0 {
                    Text("Scheduled income: \(formatter.string(for: presentation.scheduledIncome))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .moneyEffortLookup(amount: presentation.scheduledIncome, formatter: formatter)
                        .accessibilityIdentifier("item-row-scheduled-income")
                }
            case .spent:
                Text("Spent: \(formatter.string(for: presentation.spent))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .moneyEffortLookup(amount: presentation.spent, formatter: formatter)
            case .overspent:
                Text("Spent: \(formatter.string(for: presentation.spent))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .moneyEffortLookup(amount: presentation.spent, formatter: formatter)
                Text("Overspent by \(formatter.string(for: presentation.overspent))")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .moneyEffortLookup(amount: presentation.overspent, formatter: formatter)
                    .accessibilityIdentifier("item-row-overspent")
            case .available:
                let progress = coordinator.progress(spent: presentation.spent, funds: max(presentation.planned + presentation.effectiveIncome, 0))
                HStack {
                    Text("Remaining: \(formatter.string(for: presentation.remaining))")
                        .moneyEffortLookup(amount: abs(presentation.remaining), formatter: formatter)
                    Spacer()
                    Text("Planned: \(formatter.string(for: presentation.planned))")
                        .foregroundStyle(.secondary)
                        .moneyEffortLookup(amount: presentation.planned, formatter: formatter)
                }
                .font(.subheadline)
                ProgressView(value: progress.cappedFraction)
                    .tint(progress.isWarning ? .orange : .accentColor)
                Text(progress.label)
                    .font(.subheadline)
                    .foregroundStyle(progress.isWarning ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: presentation))
    }

    private func accessibilityLabel(for presentation: ItemRowPresentation) -> String {
        switch presentation.style {
        case .income:
            return "\(item.name), income \(formatter.string(for: presentation.effectiveIncome)), scheduled income \(formatter.string(for: presentation.scheduledIncome))"
        case .spent:
            return "\(item.name), spent \(formatter.string(for: presentation.spent))"
        case .overspent:
            return "\(item.name), spent \(formatter.string(for: presentation.spent)), overspent by \(formatter.string(for: presentation.overspent))"
        case .available:
            return "\(item.name), planned \(formatter.string(for: presentation.planned)), spent \(formatter.string(for: presentation.spent)), remaining \(formatter.string(for: presentation.remaining))"
        }
    }
}

private struct TransactionRowView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let transaction: Transaction
    let formatter: CurrencyFormatter

    private var isScheduled: Bool {
        coordinator.isScheduledIncome(transaction)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(coordinator.displayDate(transaction.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let notes = transaction.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                }
            }
            Spacer()
            Text(formatter.string(for: transaction.amount))
                .font(.headline)
                .foregroundStyle(transaction.kind == .income ? .green : .red)
                .moneyEffortLookup(amount: transaction.amount, formatter: formatter)
        }
        .opacity(isScheduled ? 0.55 : 1)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coordinator.transactionAccessibilityLabel(for: transaction))
        .accessibilityIdentifier("transaction-row-\(transaction.id.uuidString)")
    }
}

private struct TotalsGrid: View {
    @Environment(BudgetingCoordinator.self) private var coordinator
    let rows: [(String, String)]
    var amounts: [String: Decimal] = [:]
    var disclosures: [String: RoundingDisclosure?] = [:]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if let amount = amounts[row.0] {
                            Text(row.1)
                                .fontWeight(.semibold)
                                .moneyEffortLookup(amount: abs(amount), formatter: coordinator.formatter)
                        } else {
                            Text(row.1)
                                .fontWeight(.semibold)
                        }
                        if let disclosure = disclosures[row.0] ?? nil {
                            RoundingDisclosureButton(disclosure: disclosure)
                        }
                    }
                }
            }
        }
    }
}

private struct RoundingDisclosureButton: View {
    let disclosure: RoundingDisclosure
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Rounding details")
        .accessibilityIdentifier("rounding-disclosure")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                Text(disclosure.explanation)
                Text("Exact total: \(disclosure.exactTotalDescription)")
                    .fontWeight(.semibold)
            }
            .padding()
            .frame(minWidth: 260)
        }
    }
}

private struct LabeledProgressView: View {
    let progress: ProgressState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.cappedFraction)
                .tint(progress.isWarning ? .orange : .accentColor)
            Text(progress.label)
                .font(.caption)
                .foregroundStyle(progress.isWarning ? .orange : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.label)
    }
}

private struct InlineErrorText: View {
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

private struct NumericTextField: View {
    let title: String
    @Binding var text: String
    let kind: NumericEditKind
    let locale: Locale
    @Binding var error: String?
    @State private var visibleText: String
    @State private var isRestoringRejectedEdit = false

    init(_ title: String, text: Binding<String>, kind: NumericEditKind, locale: Locale, error: Binding<String?>) {
        self.title = title
        _text = text
        self.kind = kind
        self.locale = locale
        _error = error
        _visibleText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        TextField(title, text: $visibleText)
            .onChange(of: visibleText, validateAndCommit)
            .onChange(of: text) { _, newText in
                guard visibleText != newText else { return }
                isRestoringRejectedEdit = true
                visibleText = newText
            }
    }

    private func validateAndCommit(_ oldText: String, _ proposedText: String) {
        if isRestoringRejectedEdit {
            isRestoringRejectedEdit = false
            return
        }

        let policy = LocalizedNumericEditingPolicy(locale: locale, kind: kind)
        let result = policy.validateEdit(proposedText)
        if result.isAcceptedEdit {
            text = proposedText
            if error == Self.formatError {
                error = nil
            }
        } else {
            error = result.error ?? Self.formatError
            isRestoringRejectedEdit = true
            visibleText = oldText
        }
    }

    private static let formatError = "Use numbers only, with valid separators for your locale."
}

private func fieldErrors(for error: Error) -> FieldErrors {
    guard let validation = error as? Phase2ValidationError else {
        return FieldErrors(name: error.localizedDescription)
    }
    switch validation {
    case .emptyName, .duplicateName:
        return FieldErrors(name: validation.localizedDescription)
    case .invalidAmount, .negativeAmount, .nonPositiveAmount, .tooManyFractionDigits:
        return FieldErrors(amount: validation.localizedDescription)
    case .invalidMultiplier:
        return FieldErrors(multiplier: validation.localizedDescription)
    case .futureExpenseDate:
        return FieldErrors(date: validation.localizedDescription)
    case .noDestinationItem:
        return FieldErrors(destination: validation.localizedDescription)
    case .missingParentRelationship:
        return FieldErrors(name: validation.localizedDescription)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BudgetsRootView()
    }
    .modelContainer(try! SampleData.makePreviewContainer())
}
#endif
