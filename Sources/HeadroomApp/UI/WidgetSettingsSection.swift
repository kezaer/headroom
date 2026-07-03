import SwiftUI

struct WidgetSettingsSection: View {
    @Binding var widgetsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Share data with widgets", isOn: $widgetsEnabled)
            Text("Add or remove widgets from macOS. This controls whether Headroom supplies usage data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
