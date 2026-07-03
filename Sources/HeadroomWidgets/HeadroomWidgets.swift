import SwiftUI
import WidgetKit

@main
struct HeadroomWidgets: WidgetBundle {
    var body: some Widget {
        HeadroomUsageWidget()
    }
}

struct HeadroomUsageWidget: Widget {
    private let kind = "HeadroomUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HeadroomTimelineProvider()) { entry in
            HeadroomWidgetView(entry: entry)
        }
        .configurationDisplayName("Headroom")
        .description("Claude and Codex usage headroom at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
