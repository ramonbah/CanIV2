//
//  CanIV2App.swift
//  CanIV2
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct CanIV2App: App {
    init() {
        if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "CanIV2")
            try? KeychainSalaryStore().clearSalary()
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            StartupContainerView()
        }
    }
}

private struct StartupContainerView: View {
    @State private var result = Self.loadContainer()
    @State private var showingResetConfirmation = false
    @State private var recoveryMessage: String?

    var body: some View {
        switch result {
        case .success(let container):
            AppRootView(modelContainer: container)
                .modelContainer(container)
        case .failure(let error):
            ContentUnavailableView {
                Label("CanI Couldn’t Open Your Data", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Your stored data was not deleted or replaced. Retry after resolving the storage issue.")
            } actions: {
                VStack {
                    Button("Retry") {
                        recoveryMessage = nil
                        result = Self.loadContainer()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reset With Backup", role: .destructive) {
                        showingResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    if let recoveryMessage {
                        Text(recoveryMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog(
                "Reset CanI data? This creates a new empty database after backing up the current store files.",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset and Back Up Store", role: .destructive) {
                    recoverStore()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your current store files will be moved into a timestamped backup folder first. This does not recover the data into the app; it starts a new empty database.")
            }
            .accessibilityLabel("CanI could not open your data. Your stored data was not deleted or replaced. Retry after resolving the storage issue. \(error.localizedDescription)")
        }
    }

    private static func loadContainer() -> Result<ModelContainer, Error> {
        do {
            let isUITesting = ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
            return .success(try CanISchema.makeContainer(inMemory: isUITesting))
        } catch {
            return .failure(error)
        }
    }

    private func recoverStore() {
        do {
            let recovered = try CanISchema.recoverPersistentStore()
            recoveryMessage = "Backup created at \(recovered.backupDirectory.path). A new empty database is open."
            result = .success(recovered.container)
        } catch {
            recoveryMessage = error.localizedDescription
            result = Self.loadContainer()
        }
    }
}

private struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: BudgetingCoordinator

    init(modelContainer: ModelContainer) {
        _coordinator = State(initialValue: BudgetingCoordinator(context: modelContainer.mainContext, clock: SystemClock(), preferences: UserDefaultsPhase2PreferenceStore()))
    }

    var body: some View {
        OnboardingGateView()
            .environment(coordinator)
            .task {
#if DEBUG
                coordinator.seedRoundingMismatchForUITesting()
                coordinator.seedNumericEditingForUITesting()
                coordinator.seedPhase3ForUITesting()
                coordinator.seedReadmeScreenshotsForUITesting()
#endif
            }
            .onAppear {
                coordinator.startLocalDayRefreshLoop()
            }
            .onDisappear {
                coordinator.stopLocalDayRefreshLoop()
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                    coordinator.refreshForCalendarOrTimeChange()
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange) {
                    coordinator.refreshForCalendarOrTimeChange()
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: NSLocale.currentLocaleDidChangeNotification) {
                    coordinator.refreshForCalendarOrTimeChange()
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSSystemClockDidChange) {
                    coordinator.refreshForCalendarOrTimeChange()
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.significantTimeChangeNotification) {
                    coordinator.refreshForCalendarOrTimeChange()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    coordinator.refreshIfLocalDayChanged()
                    coordinator.refresh()
                } else if newPhase == .background {
                    coordinator.hideSalary()
                }
            }
    }
}
