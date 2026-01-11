//
//  WidgetExtension.swift
//  WidgetExtension
//
//  Shows recent Pad items on the home screen.
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Timeline Provider

struct PadWidgetProvider: TimelineProvider {
    private var appGroupId: String {
        #if DEBUG
        "group.dev.groo.ios.debug"
        #else
        "group.dev.groo.ios"
        #endif
    }

    func placeholder(in context: Context) -> PadWidgetEntry {
        PadWidgetEntry(date: Date(), items: [
            WidgetItem(id: "1", text: "Quick capture from anywhere"),
            WidgetItem(id: "2", text: "Access on any device"),
        ], isLocked: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PadWidgetEntry) -> Void) {
        let (items, isLocked) = loadItems()
        completion(PadWidgetEntry(date: Date(), items: items, isLocked: isLocked))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PadWidgetEntry>) -> Void) {
        let (items, isLocked) = loadItems()
        let entry = PadWidgetEntry(date: Date(), items: items, isLocked: isLocked)

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadItems() -> (items: [WidgetItem], isLocked: Bool) {
        // Load from App Group shared container
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return ([], true) }

        let cacheURL = containerURL.appendingPathComponent("widget_cache.json")

        guard let data = try? Data(contentsOf: cacheURL),
              let items = try? JSONDecoder().decode([WidgetItem].self, from: data) else {
            // No cache file means Pad is locked
            return ([], true)
        }

        return (Array(items.prefix(5)), false)
    }
}

// MARK: - Entry

struct PadWidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]
    let isLocked: Bool
}

struct WidgetItem: Codable, Identifiable {
    let id: String
    let text: String
}

// MARK: - Widget Views

struct PadWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: PadWidgetEntry

    var body: some View {
        if entry.isLocked {
            lockedView
        } else {
            switch family {
            case .systemSmall:
                smallWidget
            case .systemMedium:
                mediumWidget
            case .systemLarge:
                largeWidget
            default:
                smallWidget
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.title)
                .foregroundStyle(.purple)
            Text("Pad Locked")
                .font(.headline)
            Text("Open Groo to unlock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(.purple)
                Text("Pad")
                    .font(.headline)
            }

            if entry.items.isEmpty {
                Text("No items yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.items.first?.text ?? "")
                    .font(.caption)
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding()
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(.purple)
                Text("Pad")
                    .font(.headline)
                Spacer()
            }

            if entry.items.isEmpty {
                Text("No items yet. Add your first item!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(2)) { item in
                    Text(item.text)
                        .font(.caption)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding()
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(.purple)
                Text("Pad")
                    .font(.headline)
                Spacer()
            }

            if entry.items.isEmpty {
                Spacer()
                Text("No items yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.items.prefix(5)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text)
                            .font(.caption)
                            .lineLimit(2)
                        Divider()
                    }
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Widget Configuration

struct WidgetExtension: Widget {
    let kind: String = "PadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PadWidgetProvider()) { entry in
            PadWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pad")
        .description("Quick access to your recent Pad items.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    WidgetExtension()
} timeline: {
    PadWidgetEntry(date: .now, items: [
        WidgetItem(id: "1", text: "This is a sample item"),
    ], isLocked: false)
    PadWidgetEntry(date: .now, items: [], isLocked: true)
}

#Preview(as: .systemMedium) {
    WidgetExtension()
} timeline: {
    PadWidgetEntry(date: .now, items: [
        WidgetItem(id: "1", text: "This is a sample item"),
        WidgetItem(id: "2", text: "Another item here"),
    ], isLocked: false)
}
