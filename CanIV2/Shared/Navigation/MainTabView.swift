//
//  MainTabView.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI
import SwiftData

enum MainTab: String {
    case home
    case budgets
    case transactions
    case settings
}

struct MainTabView: View {
    @Environment(BudgetingCoordinator.self) private var coordinator

    private var selectedTab: Binding<MainTab> {
        Binding(get: { coordinator.selectedTab }, set: { coordinator.selectedTab = $0 })
    }

    var body: some View {
        tabContent
            .canIMinimizeTabBarOnScroll()
    }

    private var tabContent: some View {
        TabView(selection: selectedTab) {
            NavigationStack {
                HomeRootView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(MainTab.home)

            BudgetsRootView()
            .tabItem {
                Label("Budgets", systemImage: "wallet.pass")
            }
            .tag(MainTab.budgets)
            .accessibilityIdentifier("budgets-tab")

            NavigationStack {
                TransactionsRootView()
            }
            .tabItem {
                Label("Transactions", systemImage: "list.bullet")
            }
            .tag(MainTab.transactions)

            NavigationStack {
                SettingsRootView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
        }
    }
}

private extension View {
    @ViewBuilder
    func canIMinimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

#if DEBUG
#Preview {
    MainTabView()
        .modelContainer(try! SampleData.makePreviewContainer())
}
#endif
