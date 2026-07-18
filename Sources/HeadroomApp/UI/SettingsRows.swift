import SwiftUI

/// Shared row vocabulary for the Settings window (settings-ui audit, Jul 2026): one
/// grammar everywhere — label on the leading edge, control on the trailing edge — so
/// the eye never re-learns a row. Master on/off rows are switches (the System Settings
/// idiom); dependent sub-options stay native checkboxes.
struct SettingsSwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                // Visually hidden; VoiceOver still announces the title, so the row
                // reads label-left/switch-right without duplicating the text.
                .labelsHidden()
        }
    }
}

/// Uniform descriptive fine print — 11pt secondary with opened line spacing, the same
/// step the popover uses for reset countdowns. One style for every help line in the
/// window (the Widgets section previously ran 10pt `.caption`, splitting one role
/// across two sizes).
struct SettingsHelpText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .lineSpacing(2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Persistent configured state for credential rows. Only the checkmark carries the
/// success treatment; the text stays quiet so this reads as status, not a celebratory
/// badge competing with the provider title.
struct SavedCredentialStatus: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(ClaudeSetupStyle.connectedInk(dark: scheme == .dark))
                .frame(width: 16, height: 16)
                .background(
                    ClaudeSetupStyle.connectedBackground(dark: scheme == .dark),
                    in: Circle()
                )
                .accessibilityHidden(true)
            Text("Saved securely")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Key saved securely")
    }
}
