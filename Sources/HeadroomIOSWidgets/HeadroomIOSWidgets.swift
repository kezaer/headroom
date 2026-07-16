import SwiftUI
import WidgetKit

@main
struct HeadroomIOSWidgets: WidgetBundle {
    var body: some Widget {
        HeadroomIOSUsageWidget()
    }
}

struct HeadroomIOSUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HeadroomIOSWidgetConfiguration.kind, provider: HeadroomIOSTimelineProvider()) { entry in
            HeadroomIOSWidgetView(entry: entry)
        }
        .configurationDisplayName("Headroom")
        .description("Claude and Codex usage headroom at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .disfavoredLocations([.iPhoneWidgetsOnMac], for: [.systemSmall, .systemMedium, .systemLarge])
        // Content draws its own edge-to-edge background to dodge the Liquid Glass sheen on
        // the containerBackground layer; the system margins are re-applied in the view.
        .contentMarginsDisabled()
    }
}
