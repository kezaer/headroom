import SwiftUI
import WidgetKit

@main
struct HeadroomIOSWidgets: WidgetBundle {
    var body: some Widget {
        HeadroomIOSUsageWidget()
    }
}

struct HeadroomIOSUsageWidget: Widget {
    private let kind = "HeadroomIOSUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HeadroomIOSTimelineProvider()) { entry in
            HeadroomIOSWidgetView(entry: entry)
        }
        .configurationDisplayName("Headroom")
        .description("Claude and Codex usage from your Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
