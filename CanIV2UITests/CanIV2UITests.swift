//
//  CanIV2UITests.swift
//  CanIV2UITests
//
//  Created by Ramon Jr Bahio on 8/2/26.
//

import XCTest
import UIKit

final class CanIV2UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testManualHierarchyCreatesBudgetAndPlan() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetAndPlan(in: app)
        XCTAssertTrue(button(identifier: "plan-row-August", in: app).exists, app.debugDescription)
    }

    @MainActor
    func testManualHierarchyCreatesFirstItem() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetAndPlan(in: app)
        openManualPlan(in: app)
        createManualItem(named: "Meals", unitAmount: "25", in: app)

        XCTAssertTrue(button(identifier: "item-row-Meals", in: app).exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["August"].exists, app.debugDescription)
    }

    @MainActor
    func testManualHierarchyCreatesAdditionalItemFromPlanMenu() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetAndPlan(in: app)
        openManualPlan(in: app)
        createManualItem(named: "Meals", unitAmount: "25", in: app)
        createManualItem(named: "Lodging", unitAmount: "100", in: app)

        XCTAssertTrue(button(identifier: "item-row-Lodging", in: app).exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["August"].exists, app.debugDescription)
    }

    @MainActor
    func testManualHierarchyCreatesExpenseTransaction() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        openManualItem("Meals", in: app)
        createManualTransaction(amount: "12", note: "Lunch", in: app)

        XCTAssertTrue(button(containing: "Lunch", in: app).exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["Meals"].exists, app.debugDescription)
    }

    @MainActor
    func testManualHierarchyCreatesIncomeTransaction() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        openManualItem("Meals", in: app)
        createManualTransaction(type: "Income", amount: "40", note: "Allowance", in: app)

        XCTAssertTrue(button(containing: "Allowance", in: app).exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["Meals"].exists, app.debugDescription)
    }

    @MainActor
    func testPhase4ZeroMetricsCollapseUntilSpendingExists() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetAndPlan(in: app)
        let planRow = button(identifier: "plan-row-August", in: app)
        XCTAssertTrue(planRow.exists, app.debugDescription)
        XCTAssertFalse(planRow.label.contains("0%"), app.debugDescription)
        XCTAssertFalse(planRow.label.contains("Spent"), app.debugDescription)

        openManualPlan(in: app)
        createManualItem(named: "Meals", unitAmount: "25", in: app)
        let itemRow = button(identifier: "item-row-Meals", in: app)
        XCTAssertTrue(itemRow.exists, app.debugDescription)
        XCTAssertFalse(itemRow.label.contains("0%"), app.debugDescription)
        XCTAssertFalse(itemRow.label.contains("Spent"), app.debugDescription)
        XCTAssertFalse(itemRow.label.contains("Remaining"), app.debugDescription)

        openManualItem("Meals", in: app)
        createManualTransaction(amount: "5", note: "Snack", in: app)
        tapButton("BackButton", in: app)

        let spentItemRow = button(identifier: "item-row-Meals", in: app)
        XCTAssertTrue(spentItemRow.label.localizedCaseInsensitiveContains("spent"), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).firstMatch.exists, app.debugDescription)
    }

    @MainActor
    func testManualHierarchyMovesTransactionToDifferentItem() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        openManualItem("Meals", in: app)
        createManualTransaction(amount: "12", note: "Lunch", in: app)

        let editableLunchRow = button(containing: "Lunch", in: app)
        XCTAssertTrue(editableLunchRow.exists, app.debugDescription)
        editableLunchRow.swipeLeft()
        tapButton("Edit", in: app)

        let lodgingDestination = button(identifier: "destination-item-Lodging", in: app)
        XCTAssertTrue(lodgingDestination.exists, app.debugDescription)
        lodgingDestination.tapOrForceTap()
        tapButton("Save", in: app)

        XCTAssertTrue(app.navigationBars["Lodging"].waitForExistence(timeout: 3), app.debugDescription)
        let movedLunchRow = button(containing: "Lunch", in: app)
        XCTAssertTrue(movedLunchRow.exists, app.debugDescription)
    }

    @MainActor
    func testManualHierarchyDeletesTransaction() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        openManualItem("Meals", in: app)
        createManualTransaction(amount: "12", note: "Lunch", in: app)

        let lunchRow = button(containing: "Lunch", in: app)
        XCTAssertTrue(lunchRow.exists, app.debugDescription)
        lunchRow.swipeLeft()
        tapButton("Delete", in: app)
        tapButton("Delete Transaction", in: app)
        XCTAssertFalse(lunchRow.waitForExistence(timeout: 2))
        XCTAssertTrue(app.navigationBars["Meals"].exists, app.debugDescription)
    }

    @MainActor
    func testManualHierarchyDeletesItem() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        openManualItem("Lodging", in: app)
        tapButton("Item Actions", in: app)
        tapButton("Delete Item", in: app)
        tapButton(containingLabel: "Delete \"Lodging\"", in: app)
        XCTAssertTrue(app.navigationBars["August"].waitForExistence(timeout: 3), app.debugDescription)
    }

    @MainActor
    func testManualHierarchyDeletesPlanAndBudget() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetAndPlan(in: app)
        openManualPlan(in: app)

        tapButton("Plan Actions", in: app)
        tapButton("Delete Plan", in: app)
        tapButton(containingLabel: "Delete \"August\"", in: app)
        XCTAssertTrue(app.navigationBars["Trip"].waitForExistence(timeout: 3) || app.navigationBars["Budgets"].waitForExistence(timeout: 3), app.debugDescription)

        if app.buttons["Budget Actions"].waitForExistence(timeout: 3) {
            tapButton("Budget Actions", in: app)
            tapButton("Delete Budget", in: app)
            tapButton(containingLabel: "Delete \"Trip\"", in: app)
        } else {
            let finalTripBudget = button(containing: "Trip", in: app)
            XCTAssertTrue(finalTripBudget.exists, app.debugDescription)
            finalTripBudget.swipeLeft()
            tapButton("Delete", in: app)
            tapButton(containingLabel: "Delete \"Trip\"", in: app)
        }
        XCTAssertTrue(app.buttons["create-budget-empty"].waitForExistence(timeout: 3) || app.buttons["add-budget"].waitForExistence(timeout: 3), app.debugDescription)
    }

    @MainActor
    func testHierarchyDeletionConfirmations() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        app.buttons["Save"].tap()

        let tripBudgetButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Trip'")).firstMatch
        let tripBudgetText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Trip'")).firstMatch
        XCTAssertTrue(tripBudgetButton.waitForExistence(timeout: 5) || tripBudgetText.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["add-plan-empty"].tap()
        type("August", into: app.textFields["plan-name"], app: app)
        type("1000", into: app.textFields["plan-starting-amount"], app: app)
        app.buttons["Save"].tap()

        let augustPlan = app.buttons.matching(NSPredicate(format: "label CONTAINS 'August'")).firstMatch
        XCTAssertTrue(augustPlan.waitForExistence(timeout: 5), app.debugDescription)
        augustPlan.tap()
        tapCreateItem(in: app)
        type("Meals", into: app.textFields["item-name"], app: app)
        type("25", into: app.textFields["item-unit-amount"], app: app)
        app.buttons["Save"].tap()

        let mealsItem = button(containing: "Meals", in: app)
        XCTAssertTrue(mealsItem.exists, app.debugDescription)
        mealsItem.tap()
        XCTAssertTrue(app.navigationBars["Meals"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Item Actions"].tap()
        app.buttons["Delete Item"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Meals"].waitForExistence(timeout: 3), app.debugDescription)
        app.buttons["Item Actions"].tap()
        app.buttons["Delete Item"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Delete \"Meals\"'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["August"].waitForExistence(timeout: 5), app.debugDescription)

        app.buttons["Plan Actions"].tap()
        app.buttons["Delete Plan"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["August"].waitForExistence(timeout: 3))
        app.buttons["Plan Actions"].tap()
        app.buttons["Delete Plan"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Delete \"August\"'")).firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5) || app.navigationBars["Trip"].waitForExistence(timeout: 5))
        if app.buttons["Budget Actions"].waitForExistence(timeout: 3) {
            app.buttons["Budget Actions"].tap()
            app.buttons["Delete Budget"].tap()
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["Budget Actions"].waitForExistence(timeout: 3))
            app.buttons["Budget Actions"].tap()
            app.buttons["Delete Budget"].tap()
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Delete \"Trip\"'")).firstMatch.tap()
        } else {
            let finalTripBudget = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Trip'")).firstMatch
            XCTAssertTrue(finalTripBudget.waitForExistence(timeout: 5))
            finalTripBudget.swipeLeft()
            app.buttons["Delete"].tap()
            app.buttons["Cancel"].tap()
            XCTAssertTrue(finalTripBudget.waitForExistence(timeout: 3))
            finalTripBudget.swipeLeft()
            app.buttons["Delete"].tap()
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Delete \"Trip\"'")).firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["create-budget-empty"].waitForExistence(timeout: 5) || app.buttons["add-budget"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRoundingDisclosurePopover() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "BHD"
        app.launchEnvironment["UI_TESTING_SEED_ROUNDING"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        let seedPlan = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Seed Plan'")).firstMatch
        XCTAssertTrue(seedPlan.waitForExistence(timeout: 10), app.debugDescription)
        seedPlan.tap()

        let disclosure = app.buttons.matching(identifier: "rounding-disclosure").firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Rounding details"].exists, app.debugDescription)
        disclosure.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Exact total: JPY 0.6'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testOnboardingCurrencyFailureDoesNotComplete() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_FAIL_CURRENCY_SAVE"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["MYR"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.alerts["Couldn’t Save"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCanceledFirstBudgetCanKeepCurrency() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launch()

        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.navigationBars["Create Budget"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        app.buttons.matching(identifier: "keep-currency").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testCanceledFirstBudgetCanDiscardCurrency() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launch()

        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.navigationBars["Create Budget"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        app.buttons.matching(identifier: "discard-currency").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testCurrencyRelabelConfirmation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "BHD"
        app.launchEnvironment["UI_TESTING_SEED_ROUNDING"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "settings"
        ]
        app.launch()

        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
        }
        XCTAssertTrue(app.buttons["settings-currency-row"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["settings-currency-row"].forceTap()
        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["currency-option-AED"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["currency-option-AED"].forceTap()
        XCTAssertTrue(app.buttons["confirm-currency-relabel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(identifier: "confirm-currency-relabel").firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'AED'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testOnboardingCurrencyPickerReturnsImmediately() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launch()

        XCTAssertTrue(app.buttons["onboarding-currency-row"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["onboarding-currency-row"].forceTap()
        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["currency-option-AED"].forceTap()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["AED"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testSettingsCurrencyCancelStaysInPickerAndPreservesCurrency() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "BHD"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "settings"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["settings-currency-row"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["settings-currency-row"].forceTap()
        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["currency-option-AED"].forceTap()
        XCTAssertTrue(app.buttons["cancel-currency-relabel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(identifier: "cancel-currency-relabel").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["confirm-currency-relabel"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'BHD'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testSettingsCurrencyFailureKeepsPickerAndPendingSelection() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "BHD"
        app.launchEnvironment["UI_TESTING_FAIL_CURRENCY_SAVE"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "settings"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["settings-currency-row"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'BHD'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["settings-currency-row"].forceTap()
        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["currency-option-AED"].forceTap()
        XCTAssertTrue(app.buttons["confirm-currency-relabel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(identifier: "confirm-currency-relabel").firstMatch.tap()
        XCTAssertTrue(app.alerts["Couldn’t Update Currency"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["OK"].tap()

        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["currency-option-AED"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons["currency-option-AED"].value as? String, "Selected")
        XCTAssertTrue(app.buttons["confirm-currency-relabel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(identifier: "cancel-currency-relabel").firstMatch.tap()
        app.navigationBars["Currency"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'BHD'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'AED'")).firstMatch.exists)
    }

    @MainActor
    func testSettingsCurrencyFailureCanRetryPendingSelection() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "BHD"
        app.launchEnvironment["UI_TESTING_FAIL_CURRENCY_SAVE_ONCE"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "settings"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["settings-currency-row"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'BHD'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["settings-currency-row"].forceTap()
        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["currency-option-AED"].forceTap()
        XCTAssertTrue(app.buttons["confirm-currency-relabel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(identifier: "confirm-currency-relabel").firstMatch.tap()
        XCTAssertTrue(app.alerts["Couldn’t Update Currency"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["OK"].tap()

        XCTAssertTrue(app.navigationBars["Currency"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons["currency-option-AED"].value as? String, "Selected")
        XCTAssertTrue(app.buttons["confirm-currency-relabel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(identifier: "confirm-currency-relabel").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'AED'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testEmptyBudgetsShowOneToolbarAddInPortraitAndLandscape() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["create-budget-empty"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(visibleBudgetAddControlCount(in: app), 1)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["create-budget-empty"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "add-budget").allElementsBoundByIndex.filter(\.exists).count, 1, app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "create-budget-empty").allElementsBoundByIndex.filter(\.exists).count, 1, app.debugDescription)
        XCTAssertEqual(visibleBudgetAddControlCount(in: app), 1)

        app.buttons["create-budget-empty"].tap()
        XCTAssertTrue(app.navigationBars["New Budget"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.textFields.matching(identifier: "budget-name").allElementsBoundByIndex.filter(\.exists).count, 1, app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["create-budget-empty"].waitForExistence(timeout: 5), app.debugDescription)

        app.buttons["add-budget"].tap()
        XCTAssertTrue(app.navigationBars["New Budget"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.textFields.matching(identifier: "budget-name").allElementsBoundByIndex.filter(\.exists).count, 1, app.debugDescription)
    }

    @MainActor
    func testCollapsedBudgetAddOpensBudgetFormDirectly() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        tapButton("Save", in: app)
        let tripBudget = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Trip'")).firstMatch
        XCTAssertTrue(tripBudget.waitForExistence(timeout: 5), app.debugDescription)
        if app.buttons["budgets-add-menu"].exists {
            tripBudget.forceTap()
        }
        XCTAssertTrue(app.buttons["add-budget"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(visibleBudgetAddControlCount(in: app), 1)
        tapButton("add-budget", in: app)
        XCTAssertTrue(app.navigationBars["New Budget"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testTappingAnyPlanOpensThatPlan() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        tapButton("Save", in: app)

        tapButton("add-plan-empty", in: app)
        type("First", into: app.textFields["plan-name"], app: app)
        type("100", into: app.textFields["plan-starting-amount"], app: app)
        tapButton("Save", in: app)

        app.buttons["budgets-add-menu"].tap()
        app.buttons.matching(NSPredicate(format: "label == 'Add Plan'")).firstMatch.tap()
        type("Second", into: app.textFields["plan-name"], app: app)
        type("200", into: app.textFields["plan-starting-amount"], app: app)
        tapButton("Save", in: app)

        let firstPlan = button(identifier: "plan-row-First", in: app)
        XCTAssertTrue(firstPlan.waitForExistence(timeout: 5), app.debugDescription)
        firstPlan.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["First"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.navigationBars["Second"].exists, app.debugDescription)
    }

    @MainActor
    func testContextualAddMenusExposeExpectedActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        app.buttons["Save"].tap()

        XCTAssertTrue(app.buttons["budgets-add-menu"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(visibleBudgetAddControlCount(in: app), 1)
        app.buttons["budgets-add-menu"].tap()
        assertVisibleBudgetContextualActions(in: app)
        app.buttons.matching(NSPredicate(format: "label == 'Add Plan'")).firstMatch.tap()
        type("August", into: app.textFields["plan-name"], app: app)
        type("1000", into: app.textFields["plan-starting-amount"], app: app)
        app.buttons["Save"].tap()

        let augustPlan = app.buttons.matching(NSPredicate(format: "label CONTAINS 'August'")).firstMatch
        XCTAssertTrue(augustPlan.waitForExistence(timeout: 5), app.debugDescription)
        augustPlan.tap()
        XCTAssertTrue(app.navigationBars["August"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["plan-add-menu"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["plan-add-menu"].tap()
        assertVisibleMenuActions(["Add Item", "Add Transaction"], in: app)
        XCTAssertFalse(app.buttons["Add Transaction"].isEnabled)
        app.buttons.matching(identifier: "add-item").firstMatch.tap()
        type("Meals", into: app.textFields["item-name"], app: app)
        type("25", into: app.textFields["item-unit-amount"], app: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["plan-add-menu"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["plan-add-menu"].tap()
        assertVisibleMenuActions(["Add Item", "Add Transaction"], in: app)
        XCTAssertTrue(app.buttons["Add Transaction"].isEnabled)
    }

    @MainActor
    func testExpandedBudgetsLayoutHasOneAddAffordance() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        app.buttons["Save"].tap()

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["budgets-add-menu"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["Budget Actions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "budgets-add-menu").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "add-budget").count, 0)
        app.buttons["budgets-add-menu"].tap()
        XCTAssertTrue(app.buttons["Add Budget"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Add Plan"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons.matching(NSPredicate(format: "label == 'Add Plan'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Plan"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testNarrowLandscapeUsesCompactBudgetAccordion() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        XCUIDevice.shared.orientation = .landscapeLeft
        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        app.buttons["Save"].tap()

        XCTAssertTrue(app.buttons["Budget Actions"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["add-plan-empty"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["budgets-add-menu"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "budgets-add-menu").count, 1)
    }

    @MainActor
    func testRootPlanDraftSurvivesCompactExpandedTransition() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        app.buttons["Save"].tap()
        app.buttons["add-plan-empty"].tap()
        type("Draft August", into: app.textFields["plan-name"], app: app)
        type("123", into: app.textFields["plan-starting-amount"], app: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["New Plan"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.textFields["plan-name"].value as? String, "Draft August")
        XCTAssertEqual(app.textFields["plan-starting-amount"].value as? String, "0123")
    }

    @MainActor
    func testNumericFieldsRejectInvalidProductionEdits() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_NUMERIC"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        openSeededAugustPlan(in: app)
        tapButton("Plan Actions", in: app)
        tapButton("Edit Plan", in: app)
        assertNumericFieldRejectsInvalidEdits(app.textFields["plan-starting-amount"], validText: "12", acceptedCorrection: "3", app: app)
        tapButton("Save", in: app)

        let mealsItem = button(containing: "Meals", in: app)
        XCTAssertTrue(mealsItem.exists, app.debugDescription)
        mealsItem.forceTap()
        tapButton("Item Actions", in: app)
        tapButton("Edit Item", in: app)
        assertNumericFieldRejectsInvalidEdits(app.textFields["item-unit-amount"], validText: "25", acceptedCorrection: "0", app: app)
        assertNumericFieldRejectsInvalidEdits(app.textFields["item-multiplier"], validText: "2", acceptedCorrection: "1", allowsTrailingDecimal: false, app: app)
        tapButton("Save", in: app)
    }

    @MainActor
    func testTransactionNumericFieldRejectsInvalidProductionEdits() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_NUMERIC"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        openSeededAugustPlan(in: app)
        let mealsItem = button(containing: "Meals", in: app)
        XCTAssertTrue(mealsItem.exists, app.debugDescription)
        mealsItem.forceTap()
        tapButton("add-transaction", in: app)
        assertNumericFieldRejectsInvalidEdits(app.textFields["transaction-amount"], validText: "9", acceptedCorrection: "5", app: app)
    }

    @MainActor
    func testNumericFieldRejectsMixedContentPaste() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_NUMERIC"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        openSeededAugustPlan(in: app)
        tapButton("Plan Actions", in: app)
        tapButton("Edit Plan", in: app)
        let field = app.textFields["plan-starting-amount"]
        replaceText(in: field, with: "12", app: app)
        UIPasteboard.general.string = "abc12"
        field.press(forDuration: 0.8)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), app.debugDescription)
        paste.tap()
        XCTAssertEqual(field.value as? String, "12")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Use numbers only'")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
    }

    @MainActor
    func testNumericFieldsApplySaveTimeSemanticValidation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_NUMERIC"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets"
        ]
        app.launch()

        openSeededAugustPlan(in: app)
        tapButton("Plan Actions", in: app)
        tapButton("Edit Plan", in: app)
        replaceText(in: app.textFields["plan-starting-amount"], with: "12.345", app: app)
        tapButton("Save", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2 decimal place'")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        dismissValidationAlert(in: app)
        replaceText(in: app.textFields["plan-starting-amount"], with: "0", app: app)
        tapButton("Save", in: app)

        let mealsItem = button(containing: "Meals", in: app)
        XCTAssertTrue(mealsItem.exists, app.debugDescription)
        mealsItem.forceTap()
        tapButton("Item Actions", in: app)
        tapButton("Edit Item", in: app)
        replaceText(in: app.textFields["item-unit-amount"], with: "10", app: app)
        replaceText(in: app.textFields["item-multiplier"], with: "", app: app)
        tapButton("Save", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Multiplier'")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        dismissValidationAlert(in: app)
        replaceText(in: app.textFields["item-multiplier"], with: "1", app: app)
        tapButton("Save", in: app)

        tapButton("add-transaction", in: app)
        replaceText(in: app.textFields["transaction-amount"], with: "0", app: app)
        tapButton("Save", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'greater than zero'")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
    }

    @MainActor
    func testPhase3TransactionsSearchFiltersAndResultNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_PHASE3"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "transactions"
        ]
        app.launch()

        let search = app.textFields["transactions-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8), app.debugDescription)
        search.tap()
        search.typeText("Cafe")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        app.keyboards.buttons["search"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe breakfast")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 1))

        app.buttons["Filters"].tap()
        app.switches["Expense"].tap()
        replaceText(in: app.textFields["transactions-min-amount"], with: "100", app: app)
        app.buttons["transactions-apply-filters"].tap()
        XCTAssertTrue(app.staticTexts["No Matches"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["transactions-clear-all-chips"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let firstResult = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction-result-")).firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5), app.debugDescription)
        firstResult.tap()
        XCTAssertTrue(app.tabBars.buttons["Budgets"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testPhase3CustomRangeControlsAndInvalidApplyPreservesPriorResults() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_PHASE3"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "transactions"
        ]
        app.launch()

        let search = app.textFields["transactions-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8), app.debugDescription)
        search.tap()
        search.typeText("Hotel")
        app.keyboards.buttons["search"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe breakfast")).firstMatch.waitForExistence(timeout: 1))

        app.buttons["Filters"].tap()
        let dateFilter = app.buttons["transactions-date-filter"].exists ? app.buttons["transactions-date-filter"] : app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Date")).firstMatch
        XCTAssertTrue(dateFilter.waitForExistence(timeout: 5), app.debugDescription)
        dateFilter.tap()
        tapButton("Custom Range", in: app)
        XCTAssertTrue(app.datePickers["transactions-custom-start"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.datePickers["transactions-custom-end"].waitForExistence(timeout: 5), app.debugDescription)

        replaceText(in: app.textFields["transactions-min-amount"], with: "100", app: app)
        replaceText(in: app.textFields["transactions-max-amount"], with: "10", app: app)
        app.buttons["transactions-apply-filters"].tap()
        XCTAssertTrue(app.staticTexts["Minimum amount cannot be greater than maximum amount."].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe breakfast")).firstMatch.exists)
    }

    @MainActor
    func testPhase3HomeSeeAllOpensTemporaryTransactionsResults() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_PHASE3"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "home"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["home-see-all-transactions"].waitForExistence(timeout: 8), app.debugDescription)
        app.swipeUp()
        XCTAssertTrue(app.buttons["home-see-all-transactions"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["home-see-all-transactions"].coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["transactions-search"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Last 30 Days")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testPhase3HomeAndReportDetailNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_PHASE3"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "home"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["home-net-flow-report"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Net cash flow'")).firstMatch.exists, app.debugDescription)
        app.buttons["home-net-flow-report"].tap()
        XCTAssertTrue(app.staticTexts["Breakdown"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Contributing Transactions"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testPhase3FilterChipRemovalAndClearAllBehavior() throws {
        let app = launchPhase3App(selectedTab: "transactions")

        let search = app.textFields["transactions-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8), app.debugDescription)
        search.tap()
        search.typeText("Hotel")
        app.keyboards.buttons["search"].tap()

        app.buttons["Filters"].tap()
        let dateFilter = app.buttons["transactions-date-filter"].exists ? app.buttons["transactions-date-filter"] : app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Date")).firstMatch
        XCTAssertTrue(dateFilter.waitForExistence(timeout: 5), app.debugDescription)
        dateFilter.tap()
        tapButton("Last 7", in: app)
        app.buttons["transactions-apply-filters"].tap()
        XCTAssertFalse(app.textFields["transactions-min-amount"].waitForExistence(timeout: 1), app.debugDescription)

        let dateChip = app.buttons.matching(NSPredicate(format: "identifier == 'transaction-filter-chip' AND label CONTAINS 'Last 7 Days'")).firstMatch
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5), app.debugDescription)
        dateChip.tap()
        XCTAssertFalse(dateChip.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'transaction-filter-chip' AND label CONTAINS 'Search: hotel'")).firstMatch.exists, app.debugDescription)

        app.buttons["transactions-clear-all-chips"].tap()
        XCTAssertFalse(app.buttons["transaction-filter-chip"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe breakfast")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testPhase3ResultNavigationHighlightsTransactionAndRestoresTransactionsState() throws {
        let app = launchPhase3App(selectedTab: "transactions")

        let search = app.textFields["transactions-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8), app.debugDescription)
        search.tap()
        search.typeText("Cafe")
        app.keyboards.buttons["search"].tap()
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction-result-")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        let transactionID = result.identifier.replacingOccurrences(of: "transaction-result-", with: "")
        result.tap()

        XCTAssertTrue(app.buttons["highlighted-transaction-\(transactionID)"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons["highlighted-transaction-\(transactionID)"].label.contains("Cafe breakfast"), app.debugDescription)
        tapTab("Transactions", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe breakfast")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 1))
    }

    @MainActor
    func testPhase3HomeSeeAllDoesNotOverwriteSavedTransactionsQueryInUI() throws {
        let app = launchPhase3App(selectedTab: "transactions")

        let search = app.textFields["transactions-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8), app.debugDescription)
        search.tap()
        search.typeText("Hotel")
        app.keyboards.buttons["search"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe breakfast")).firstMatch.waitForExistence(timeout: 1))

        tapTab("Home", in: app)
        app.swipeUp()
        let seeAll = app.buttons["home-see-all-transactions"]
        XCTAssertTrue(seeAll.waitForExistence(timeout: 5), app.debugDescription)
        seeAll.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["transactions-search"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.textFields["transactions-search"].value as? String, "Search notes, Items, Plans")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'transaction-filter-chip' AND label CONTAINS 'Last 30 Days'")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)

        tapTab("Budgets", in: app)
        tapTab("Transactions", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Hotel")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cafe breakfast")).firstMatch.waitForExistence(timeout: 1))
    }

    @MainActor
    func testObservationRefinementBudgetReportsButtonAndCardRouting() throws {
        let app = launchPhase3App(selectedTab: "budgets")

        let seededBudget = button(containing: "Phase Three Travel Budget", in: app)
        XCTAssertTrue(seededBudget.waitForExistence(timeout: 8), app.debugDescription)
        if !app.buttons["budget-reports-button"].exists {
            seededBudget.tapOrForceTap()
        }
        for _ in 0..<4 where !app.buttons["budget-reports-button"].exists {
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(app.buttons["budget-reports-button"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["budget-reports-button"].tapOrForceTap()

        XCTAssertTrue(app.navigationBars["Budget Reports"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["budget-report-card-plan-net-flow"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["budget-report-card-plan-net-flow"].tap()
        XCTAssertTrue(app.navigationBars["Plan Net Flow"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testPhase3ReportsReachableInPortraitAndLandscape() throws {
        let app = launchPhase3App(selectedTab: "home")

        XCTAssertTrue(app.buttons["home-net-flow-report"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["home-net-flow-report"].tap()
        XCTAssertTrue(app.staticTexts["Breakdown"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Contributing Transactions"].waitForExistence(timeout: 5), app.debugDescription)
        tapButton("BackButton", in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.90)).tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5) || app.navigationBars["Phase Three Travel Budget With A Long Name"].waitForExistence(timeout: 5), app.debugDescription)
        let reportsPlan = button(containing: "August Reports Plan", in: app)
        XCTAssertTrue(reportsPlan.exists, app.debugDescription)
        reportsPlan.tapOrForceTap()
        let scrollView = app.collectionViews.firstMatch
        for _ in 0..<3 where !app.buttons["plan-reports-button"].exists {
            scrollView.swipeUp()
        }
        XCTAssertTrue(app.buttons["plan-reports-button"].waitForExistence(timeout: 8), app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.70)).tap()
        XCTAssertTrue(app.navigationBars["Plan Reports"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["plan-report-card-allocation"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["plan-report-card-allocation"].tap()
        XCTAssertTrue(app.navigationBars["Allocation"].waitForExistence(timeout: 5), app.debugDescription)
        tapButton("BackButton", in: app)
        XCTAssertTrue(app.navigationBars["Plan Reports"].waitForExistence(timeout: 5), app.debugDescription)
        let reportList = app.collectionViews.firstMatch
        for _ in 0..<5 where !app.staticTexts["Spent and Remaining"].exists {
            let start = reportList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            let end = reportList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(app.staticTexts["Spent and Remaining"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<3 where !app.buttons["plan-report-card-timeline"].exists {
            app.collectionViews.firstMatch.swipeUp()
        }
        let timelineCard = app.buttons["plan-report-card-timeline"]
        let timelineTitle = app.staticTexts["Timeline"]
        XCTAssertTrue(timelineCard.waitForExistence(timeout: 8) || timelineTitle.waitForExistence(timeout: 3), app.debugDescription)
    }

    @MainActor
    func testObservationRefinementCreatesNewItemWhileAddingTransaction() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        tapButton("plan-add-menu", in: app)
        tapButton("Add Transaction", in: app)
        XCTAssertTrue(app.segmentedControls["transaction-destination-mode"].waitForExistence(timeout: 5), app.debugDescription)
        tapButton("Create New Item", in: app)
        type("Museum", into: app.textFields["transaction-new-item-name"], app: app)
        type("12", into: app.textFields["transaction-amount"], app: app)
        tapButton("Save", in: app)

        XCTAssertTrue(app.navigationBars["Museum"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(button(containing: "Museum", in: app).exists, app.debugDescription)
    }

    @MainActor
    func testObservationRefinement2ItemAllocationPreviewUpdates() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        tapCreateItem(in: app)
        type("Tickets", into: app.textFields["item-name"], app: app)
        type("100", into: app.textFields["item-unit-amount"], app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "unallocated")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        replaceText(in: app.textFields["item-unit-amount"], with: "1000", app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "overallocated")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testObservationRefinement2TransactionProjectionAndMarkAsSpent() throws {
        let app = launchManualHierarchyApp()

        createManualBudgetPlanAndItems(in: app)
        openManualItem("Meals", in: app)
        tapButton("add-transaction", in: app)
        type("10", into: app.textFields["transaction-amount"], app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Item after transaction")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Plan after transaction")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        tapButton("Cancel", in: app)

        tapButton("Item Actions", in: app)
        tapButton("Mark as Spent", in: app)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(button(containing: "Meals", in: app).waitForExistence(timeout: 1))

        tapButton("Item Actions", in: app)
        tapButton("Mark as Spent", in: app)
        tapButton("Mark Spent", in: app)
        XCTAssertTrue(button(containing: "Meals", in: app).waitForExistence(timeout: 5), app.debugDescription)
        tapButton("BackButton", in: app)
        if app.segmentedControls["plan-item-status-tabs"].exists {
            tapButton("Spent", in: app)
        }
        XCTAssertTrue(button(identifier: "item-row-Meals", in: app).waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testObservationRefinement3SalaryHiddenRevealAndFocusedEditor() throws {
        let app = launchSettingsApp()

        XCTAssertTrue(app.staticTexts["Hidden"].waitForExistence(timeout: 2) || app.staticTexts["Not Set"].waitForExistence(timeout: 5), app.debugDescription)
        tapButton("Edit Salary", in: app)
        XCTAssertTrue(app.navigationBars["Monthly Salary"].waitForExistence(timeout: 5), app.debugDescription)
        type("1000", into: app.textFields["time-effort-salary-field"], app: app)
        tapButton("Save", in: app)

        XCTAssertTrue(app.staticTexts["Hidden"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Show salary"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Show salary"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "MYR")).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Hide salary"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Hide salary"].tap()
        XCTAssertTrue(app.staticTexts["Hidden"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testObservationRefinement3CalculatorMissingSalaryRoutesToEditor() throws {
        let app = launchSettingsApp()

        tapButton("Effort Calculator", in: app)
        XCTAssertTrue(app.navigationBars["Effort Calculator"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["time-effort-missing-salary"].waitForExistence(timeout: 5), app.debugDescription)
        tapButton("Configure Salary", in: app)
        XCTAssertTrue(app.navigationBars["Monthly Salary"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.textFields["time-effort-salary-field"].exists, app.debugDescription)
    }

    @MainActor
    func testObservationRefinement3RepresentativeQuickLookupMissingSalary() throws {
        let app = launchPhase3App(selectedTab: "home")

        let amount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Expense, MYR")).firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 8), app.debugDescription)
        amount.press(forDuration: 0.8)
        tapButton("View Time Effort", in: app, timeout: 5)
        XCTAssertTrue(app.navigationBars["Time Effort"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["quick-effort-amount"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Configure Salary"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchEnvironment["UI_TESTING"] = "1"
            app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
            app.launchArguments = ["-phase2.onboardingComplete", "YES"]
            app.launch()
        }
    }

    private func launchPhase3App(selectedTab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchEnvironment["UI_TESTING_SEED_PHASE3"] = "1"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", selectedTab
        ]
        app.launch()
        return app
    }

    private func launchManualHierarchyApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "budgets",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM"
        ]
        app.launch()
        return app
    }

    private func launchSettingsApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["UI_TESTING_CURRENCY_CODE"] = "MYR"
        app.launchArguments = [
            "-phase2.onboardingComplete", "YES",
            "-phase2.selectedTab", "settings"
        ]
        app.launch()
        return app
    }

    private func createManualBudgetAndPlan(in app: XCUIApplication) {
        tapCreateBudget(in: app)
        type("Trip", into: app.textFields["budget-name"], app: app)
        tapButton("Save", in: app)

        let tripBudgetButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Trip'")).firstMatch
        let tripBudgetText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Trip'")).firstMatch
        XCTAssertTrue(tripBudgetButton.waitForExistence(timeout: 2) || tripBudgetText.waitForExistence(timeout: 2), app.debugDescription)

        tapButton("add-plan-empty", in: app)
        type("August", into: app.textFields["plan-name"], app: app)
        type("1000", into: app.textFields["plan-starting-amount"], app: app)
        tapButton("Save", in: app)

        XCTAssertTrue(button(identifier: "plan-row-August", in: app).exists, app.debugDescription)
    }

    private func openManualPlan(in app: XCUIApplication) {
        let augustPlan = button(identifier: "plan-row-August", in: app)
        XCTAssertTrue(augustPlan.exists, app.debugDescription)
        augustPlan.tapOrForceTap()
        XCTAssertTrue(app.navigationBars["August"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func createManualBudgetPlanAndItems(in app: XCUIApplication) {
        createManualBudgetAndPlan(in: app)
        openManualPlan(in: app)
        createManualItem(named: "Meals", unitAmount: "25", in: app)
        createManualItem(named: "Lodging", unitAmount: "100", in: app)
    }

    private func createManualItem(named name: String, unitAmount: String, in app: XCUIApplication) {
        tapCreateItem(in: app)
        type(name, into: app.textFields["item-name"], app: app)
        type(unitAmount, into: app.textFields["item-unit-amount"], app: app)
        tapButton("Save", in: app)
        XCTAssertTrue(button(identifier: "item-row-\(name)", in: app).exists, app.debugDescription)
    }

    private func openManualItem(_ name: String, in app: XCUIApplication) {
        let item = button(identifier: "item-row-\(name)", in: app)
        XCTAssertTrue(item.exists, app.debugDescription)
        item.tapOrForceTap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func createManualTransaction(type transactionType: String = "Expense", amount: String, note: String, in app: XCUIApplication) {
        tapButton("add-transaction", in: app)
        if transactionType == "Income" {
            tapButton("Income", in: app)
        }
        type(amount, into: app.textFields["transaction-amount"], app: app)
        type(note, into: app.textFields["transaction-note"], app: app)
        tapButton("Save", in: app)
        XCTAssertTrue(button(containing: note, in: app).exists, app.debugDescription)
    }

    private func visibleBudgetAddControlCount(in app: XCUIApplication) -> Int {
        let directAdds = app.buttons.matching(identifier: "add-budget").allElementsBoundByIndex.filter(\.exists).count
        let menuAdds = app.buttons.matching(identifier: "budgets-add-menu").allElementsBoundByIndex.filter(\.exists).count
        return directAdds + menuAdds
    }

    private func tabButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.tabBars.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let identifier: String
        switch label {
        case "Home": identifier = "house"
        case "Budgets": identifier = "wallet.pass"
        case "Transactions": identifier = "list.bullet"
        case "Settings": identifier = "gearshape"
        default: identifier = label
        }
        let identifiedButton = app.tabBars.buttons[identifier]
        if identifiedButton.waitForExistence(timeout: 2) {
            identifiedButton.forceTap()
            return
        }
        let button = tabButton(label, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        let x: CGFloat
        switch label {
        case "Home": x = 0.19
        case "Budgets": x = 0.39
        case "Transactions": x = 0.60
        case "Settings": x = 0.81
        default: x = 0.5
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.94)).tap()
    }

    private func assertVisibleMenuActions(_ labels: [String], in app: XCUIApplication) {
        for label in labels {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch.exists, app.debugDescription)
        }
        let actionLabels = Set(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add '"))
                .allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
                .map(\.label)
        )
        XCTAssertEqual(actionLabels, Set(labels), app.debugDescription)
    }

    private func assertVisibleBudgetContextualActions(in app: XCUIApplication) {
        let menuLabels = ["Add Budget", "Add Plan"]
        for label in menuLabels {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
                .allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty && $0.frame.minX > 100 && $0.frame.maxY < 220 }
            XCTAssertEqual(matches.count, 1, "Expected exactly one visible \(label) action. \(app.debugDescription)")
            XCTAssertTrue(matches.first?.isEnabled == true, "Expected \(label) to be accessible and enabled. \(app.debugDescription)")
        }
        let menuActionLabels = app.buttons.matching(NSPredicate(format: "label IN %@", menuLabels))
            .allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty && $0.frame.minX > 100 && $0.frame.maxY < 220 }
            .map(\.label)
        XCTAssertEqual(menuActionLabels.sorted(), menuLabels.sorted(), app.debugDescription)

        let templateActions = app.buttons.matching(identifier: "add-recurring-template")
            .allElementsBoundByIndex
            .filter { $0.exists && !$0.frame.isEmpty }
        XCTAssertEqual(templateActions.count, 1, "Expected exactly one visible Add Template action. \(app.debugDescription)")
        XCTAssertEqual(templateActions.first?.label, "Add Template")
        XCTAssertTrue(templateActions.first?.isEnabled == true, "Expected Add Template to be accessible and enabled. \(app.debugDescription)")
    }

    private func type(_ text: String, into field: XCUIElement, app: XCUIApplication) {
        for _ in 0..<3 where !field.exists && app.buttons["BackButton"].exists {
            app.buttons["BackButton"].tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.forceTap()
        field.typeText(text)
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
    }

    private func openSeededAugustPlan(in app: XCUIApplication) {
        if app.navigationBars["August"].waitForExistence(timeout: 2) {
            return
        }
        let augustPlan = app.buttons.matching(NSPredicate(format: "label CONTAINS 'August'")).firstMatch
        XCTAssertTrue(augustPlan.waitForExistence(timeout: 8), app.debugDescription)
        augustPlan.forceTap()
        XCTAssertTrue(app.navigationBars["August"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        field.forceTap()
        let current = (field.value as? String) ?? ""
        let placeholders = ["Amount", "Starting Amount", "Unit Amount", "Multiplier", "Name", "Note"]
        if !current.isEmpty, !placeholders.contains(current) {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if !text.isEmpty {
            field.typeText(text)
        }
    }

    private func assertNumericFieldRejectsInvalidEdits(_ field: XCUIElement, validText: String, acceptedCorrection: String, allowsTrailingDecimal: Bool = true, app: XCUIApplication) {
        replaceText(in: field, with: validText, app: app)
        XCTAssertEqual(field.value as? String, validText)
        for invalidText in ["a", "$"] {
            assertRejectedTypedEdit(invalidText, in: field, expectedText: validText, app: app)
        }
        assertRejectedTypedEdit(",", in: field, expectedText: validText, app: app)
        if allowsTrailingDecimal {
            replaceText(in: field, with: "\(validText).", app: app)
            XCTAssertEqual(field.value as? String, "\(validText).")
            assertRejectedTypedEdit(".", in: field, expectedText: "\(validText).", app: app)
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertEqual(field.value as? String, validText)
        }
        field.forceTap()
        field.typeText(acceptedCorrection)
        XCTAssertTrue(((field.value as? String) ?? "").hasSuffix(acceptedCorrection))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Use numbers only'")).firstMatch.exists)
        if allowsTrailingDecimal {
            field.forceTap()
            field.typeText(".")
            XCTAssertTrue(((field.value as? String) ?? "").hasSuffix("."))
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            XCTAssertFalse(((field.value as? String) ?? "").hasSuffix("."))
        }
    }

    private func assertRejectedTypedEdit(_ invalidText: String, in field: XCUIElement, expectedText: String, app: XCUIApplication) {
        field.forceTap()
        field.typeText(invalidText)
        XCTAssertEqual(field.value as? String, expectedText, "Expected \(field) to preserve prior valid text after rejecting \(invalidText)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Use numbers only'")).firstMatch.waitForExistence(timeout: 2), app.debugDescription)
    }

    private func dismissValidationAlert(in app: XCUIApplication) {
        let alert = app.alerts["Check the highlighted fields"]
        if alert.waitForExistence(timeout: 2) {
            alert.buttons["OK"].tap()
        }
    }

    private func tapButton(_ identifierOrLabel: String, in app: XCUIApplication, timeout: TimeInterval = 3) {
        if identifierOrLabel.contains("-") {
            let byIdentifier = app.buttons[identifierOrLabel]
            if byIdentifier.waitForExistence(timeout: timeout) {
                if identifierOrLabel == "add-plan-empty", !byIdentifier.isHittable, app.buttons["budgets-add-menu"].exists {
                    app.buttons["budgets-add-menu"].tapOrForceTap()
                    tapButton("Add Plan", in: app, timeout: timeout)
                    return
                }
                for _ in 0..<5 where !byIdentifier.isHittable {
                    app.swipeUp()
                }
                byIdentifier.tapOrForceTap()
                return
            }
        }
        let byLabel = app.buttons.matching(NSPredicate(format: "label == %@", identifierOrLabel)).firstMatch
        if byLabel.waitForExistence(timeout: 0.75) {
            byLabel.forceTap()
            return
        }
        let byIdentifier = app.buttons[identifierOrLabel]
        if byIdentifier.waitForExistence(timeout: timeout) {
            for _ in 0..<5 where !byIdentifier.isHittable {
                app.swipeUp()
            }
            byIdentifier.forceTap()
            return
        }
        XCTAssertTrue(byLabel.waitForExistence(timeout: 1), app.debugDescription)
        byLabel.forceTap()
    }

    private func tapButton(containingLabel label: String, in app: XCUIApplication, timeout: TimeInterval = 3) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), app.debugDescription)
        button.forceTap()
    }

    private func tapCreateBudget(in app: XCUIApplication) {
        let emptyCreateBudget = app.buttons["create-budget-empty"]
        if emptyCreateBudget.waitForExistence(timeout: 3) {
            emptyCreateBudget.tap()
            return
        }

        let toolbarAddBudget = app.buttons["add-budget"]
        XCTAssertTrue(toolbarAddBudget.waitForExistence(timeout: 12), app.debugDescription)
        toolbarAddBudget.tap()
    }

    private func tapCreateItem(in app: XCUIApplication) {
        let emptyCreateItem = app.buttons["add-item-empty"]
        if emptyCreateItem.waitForExistence(timeout: 1) {
            emptyCreateItem.tap()
            return
        }

        let planAddMenu = app.buttons["plan-add-menu"]
        XCTAssertTrue(planAddMenu.waitForExistence(timeout: 12), app.debugDescription)
        planAddMenu.tap()
        app.buttons["Add Item"].tap()
    }

    private func button(containing label: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        for _ in 0..<5 {
            if button.waitForExistence(timeout: 0.5) {
                return button
            }
            app.swipeUp()
        }
        return button
    }

    private func button(identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        for _ in 0..<5 {
            if button.waitForExistence(timeout: 0.5), button.isHittable {
                return button
            }
            app.swipeUp()
        }
        return button
    }
}

private extension XCUIElement {
    func tapOrForceTap() {
        if isHittable {
            tap()
        } else {
            forceTap()
        }
    }

    func forceTap() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
