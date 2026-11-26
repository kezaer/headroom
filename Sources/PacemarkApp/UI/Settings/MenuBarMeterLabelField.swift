#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct MenuBarMeterLabelField: View {
    let value: String
    let accountLabel: String
    static let placeholder = "Add label"
    let onCommit: (String?) -> Void
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        TextField("Label", text: $draft, prompt: Text(Self.placeholder).foregroundStyle(PDS.Ink.inkTertiary))
            .font(SettingsType.help.monospaced())
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity)
            .controlSize(.small)
            .focused($editing)
            .help("Menu bar label. Up to eight characters.")
            .accessibilityLabel("Menu bar label for \(accountLabel)")
            .onAppear { draft = value }
            .onChange(of: value) { _, value in if !editing { draft = value } }
            .onChange(of: editing) { _, editing in if !editing { commit() } }
            .onSubmit { editing = false }
            .onDisappear { if editing { commit() } }
    }

    private func commit() {
        let edited = MenuBarMeterSelection.Item.trimmedLabel(draft)
        if edited != value { onCommit(edited) }
        draft = edited
    }
}
