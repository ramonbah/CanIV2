//
//  CanIQuickAddWidget.swift
//  CanIQuickAddWidget
//
//  Created by Ramon Jr Bahio on 8/31/26.
//

import SwiftUI
import WidgetKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry {
        QuickAddEntry(date: Date(), configuration: ConfigurationAppIntent(), destinationName: nil)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> QuickAddEntry {
        QuickAddEntry(date: Date(), configuration: configuration, destinationName: destinationName(for: configuration))
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<QuickAddEntry> {
        let entry = QuickAddEntry(date: Date(), configuration: configuration, destinationName: destinationName(for: configuration))
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 30)))
    }

    private func destinationName(for configuration: ConfigurationAppIntent) -> String? {
        guard let destinationID = configuration.resolvedDestinationID,
              let snapshot = try? WidgetDestinationSnapshotStore.appGroupStore().read(),
              let item = snapshot.items.first(where: { $0.id == destinationID }) else {
            return nil
        }
        return item.name
    }
}

struct QuickAddEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let destinationName: String?
}

struct CanIQuickAddWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: QuickAddEntry

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            medium
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CanI")
                .font(.headline)
            actionLink("Add Expense", systemImage: "plus.circle.fill", action: .addExpense, prominent: true)
            actionLink("Scan", systemImage: "doc.text.viewfinder", action: .scanReceipt, prominent: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            actionTile("Add Expense", systemImage: "plus.circle.fill", action: .addExpense)
            actionTile("Scan Receipt", systemImage: "doc.text.viewfinder", action: .scanReceipt)
        }
    }

    private var circular: some View {
        Link(destination: route(for: entry.configuration.defaultAction.routeAction).url) {
            Image(systemName: entry.configuration.defaultAction == .addExpense ? "plus.circle.fill" : "doc.text.viewfinder")
                .font(.title2)
                .accessibilityLabel(entry.configuration.defaultAction == .addExpense ? "Add Expense in CanI" : "Scan Receipt in CanI")
                .accessibilityHint("Opens CanI.")
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            actionLink("Expense", systemImage: "plus.circle.fill", action: .addExpense, prominent: false)
            actionLink("Receipt", systemImage: "doc.text.viewfinder", action: .scanReceipt, prominent: false)
        }
    }

    private func actionTile(_ title: String, systemImage: String, action: QuickAddAction) -> some View {
        Link(destination: route(for: action).url) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                if let destinationName = entry.destinationName {
                    Text(destinationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("\(title) in CanI")
        .accessibilityHint("Opens CanI.")
    }

    private func actionLink(_ title: String, systemImage: String, action: QuickAddAction, prominent: Bool) -> some View {
        Link(destination: route(for: action).url) {
            Label(title, systemImage: systemImage)
                .font(prominent ? .headline : .caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityLabel("\(title) in CanI")
        .accessibilityHint("Opens CanI.")
    }

    private func route(for action: QuickAddAction) -> QuickAddRoute {
        QuickAddRoute(action: action, destinationID: entry.configuration.resolvedDestinationID)
    }
}

struct CanIQuickAddWidget: Widget {
    let kind: String = "CanIQuickAddWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            CanIQuickAddWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CanI Quick Add")
        .description("Open CanI to add an expense or scan a receipt.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    CanIQuickAddWidget()
} timeline: {
    QuickAddEntry(date: .now, configuration: ConfigurationAppIntent(), destinationName: "Meals")
}
