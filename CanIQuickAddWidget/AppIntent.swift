//
//  AppIntent.swift
//  CanIQuickAddWidget
//
//  Created by Ramon Jr Bahio on 8/31/26.
//

import AppIntents
import WidgetKit

enum QuickAddWidgetAction: String, AppEnum {
    case addExpense
    case scanReceipt

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Default Action" }
    static var caseDisplayRepresentations: [QuickAddWidgetAction: DisplayRepresentation] {
        [
            .addExpense: "Add Expense",
            .scanReceipt: "Scan Receipt"
        ]
    }

    var routeAction: QuickAddAction {
        switch self {
        case .addExpense: .addExpense
        case .scanReceipt: .scanReceipt
        }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "CanI Quick Add" }
    static var description: IntentDescription { "Choose which CanI action this widget should open." }

    @Parameter(title: "Default Action", default: .addExpense)
    var defaultAction: QuickAddWidgetAction

    @Parameter(title: "Destination UUID", default: "")
    var destinationID: String

    var resolvedDestinationID: UUID? {
        UUID(uuidString: destinationID)
    }
}
