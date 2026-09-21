import AppIntents
import SummonKit
import SwiftUI
import WidgetKit

/// The pinned items, on the home screen.
///
/// A widget is the shortest path Summon has: the thing you reach for, one tap, on the
/// clipboard. Tapping a row runs `SummonItemIntent` in place rather than opening the
/// app, because opening the app to copy something is the long way round.
struct PinnedEntry: TimelineEntry {
    let date: Date
    let items: [SummonItemEntity]
    let failure: String?
}

struct PinnedProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedEntry {
        PinnedEntry(date: .now, items: [
            SummonItemEntity(id: UUID(), title: "IBAN · Studio account", kind: "Snippet", isLocked: false),
            SummonItemEntity(id: UUID(), title: "VAT number", kind: "Snippet", isLocked: false),
        ], failure: nil)
    }

    // WidgetKit calls these on the main thread, and reading the library is fast — one
    // store open and a filter. Answering synchronously keeps the timeline off a task
    // that would have to carry the completion handler across actors to get back.
    func getSnapshot(in context: Context, completion: @escaping (PinnedEntry) -> Void) {
        completion(MainActor.assumeIsolated { load() })
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedEntry>) -> Void) {
        // No schedule of its own: the app reloads the timeline when the library
        // changes, so a poll would only spend battery confirming nothing happened.
        completion(Timeline(entries: [MainActor.assumeIsolated { load() }], policy: .never))
    }

    @MainActor
    private func load() -> PinnedEntry {
        do {
            let items = try IntentLibrary.shared().pinned.map { SummonItemEntity($0) }
            return PinnedEntry(date: .now, items: Array(items.prefix(6)), failure: nil)
        } catch {
            return PinnedEntry(date: .now, items: [], failure: "Open Summon to set this up.")
        }
    }
}

struct PinnedWidgetView: View {
    var entry: PinnedEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure = entry.failure {
                Text(failure).font(.caption).foregroundStyle(.secondary)
            } else if entry.items.isEmpty {
                Text("Pin an item in Summon and it will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(limit)) { item in
                    Button(intent: SummonItemIntent(item: item)) {
                        HStack(spacing: 8) {
                            Image(systemName: item.isLocked ? "lock.fill" : "doc.on.doc")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                            Text(item.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct PinnedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SummonPinned", provider: PinnedProvider()) { entry in
            PinnedWidgetView(entry: entry)
        }
        .configurationDisplayName("Pinned")
        .description("Your pinned items. Tap one to copy it.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// One button in the Control Centre, for the item you reach for most.
struct SummonControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SummonControl") {
            ControlWidgetButton(action: OpenSummonIntent()) {
                Label("Summon", systemImage: "sparkles")
            }
        }
        .displayName("Summon")
        .description("Open Summon.")
    }
}

/// The Control Centre opens the app rather than copying: which item you want is a
/// question, and a control button has no room to ask it.
struct OpenSummonIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Summon"
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult { .result() }
}

@main
struct SummonWidgetBundle: WidgetBundle {
    var body: some Widget {
        PinnedWidget()
        SummonControl()
    }
}
