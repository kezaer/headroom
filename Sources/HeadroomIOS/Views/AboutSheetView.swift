import SwiftUI

struct AboutSheetView: View {
    let envelope: WidgetSnapshotEnvelope?
    let syncInfo: IOSCompanionSyncInfo?
    @Binding var appearance: AppearanceSetting

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Sync", value: syncStatus)
                    row("Source", value: syncInfo?.sourceDescription ?? "Mac snapshot")
                    row("Version", value: versionText)
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { setting in
                            Text(setting.title).tag(setting)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text("Refresh interval, API keys, and renewal dates are managed in Headroom on your Mac. This iPhone only mirrors what the Mac sends.")
                        .font(.footnote)
                        .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("About Headroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var syncStatus: String {
        if let publishedAt = syncInfo?.publishedAt {
            return "Synced \(Countdown.updatedLabel(capturedAt: publishedAt, now: .now) ?? "just now")"
        }
        if let generatedAt = envelope?.generatedAt {
            return "Updated \(Countdown.updatedLabel(capturedAt: generatedAt, now: .now) ?? "just now")"
        }
        return "Waiting for Mac"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct IOSCompanionSyncInfo: Equatable {
    let publishedAt: Date?
    let sourceID: String?
    let sourcePlatform: SyncedWidgetSnapshotSourcePlatform?

    var sourceDescription: String {
        switch (sourceID, sourcePlatform) {
        case (let source?, .macOS):
            "\(source) on Mac"
        case (nil, .macOS):
            "Headroom on Mac"
        case (let source?, _):
            source
        case (nil, _):
            "Mac snapshot"
        }
    }
}
