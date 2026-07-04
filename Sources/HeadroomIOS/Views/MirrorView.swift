import SwiftUI

struct MirrorView: View {
    let envelope: WidgetSnapshotEnvelope
    let syncInfo: IOSCompanionSyncInfo?
    let now: Date
    @Binding var appearance: AppearanceSetting
    var onRefresh: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAbout = false
    @State private var headerAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(spacing: 12) {
                    ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                        ProviderTileView(
                            provider: provider,
                            now: now,
                            entranceDelay: reduceMotion ? 0 : Double(index) * 0.055
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .background(HeadroomTheme.background(scheme).ignoresSafeArea())
        .refreshable { onRefresh() }
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About Headroom")
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutSheetView(envelope: envelope, syncInfo: syncInfo, appearance: $appearance)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Usage")
                .font(.system(size: 34, weight: .bold))
            Text(updatedText)
                .font(.subheadline)
                .foregroundStyle(HeadroomTheme.secondaryText(scheme))
        }
        .opacity(reduceMotion || headerAppeared ? 1 : 0)
        .offset(y: reduceMotion || headerAppeared ? 0 : 8)
        .onAppear {
            guard !headerAppeared else { return }
            if reduceMotion {
                headerAppeared = true
            } else {
                withAnimation(HeadroomTheme.entranceAnimation) {
                    headerAppeared = true
                }
            }
        }
    }

    private var updatedText: String {
        if let updated = MirrorPresentation.updatedLabel(generatedAt: envelope.generatedAt, now: now) {
            return "Updated \(updated)"
        }
        return "Latest Mac snapshot"
    }
}
