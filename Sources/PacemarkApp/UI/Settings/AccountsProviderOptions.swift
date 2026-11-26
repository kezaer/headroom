import SwiftUI
import PacemarkCore

struct AccountsProviderOptions: View {
    let providerID: ProviderID
    let store: UsageStore

    var body: some View {
        if providerID == .antigravity {
            SettingsLedgerSwitch(title: "Show Claude & GPT models", isOn: Binding(
                get: { store.showsAntigravityOtherModels }, set: store.setShowsAntigravityOtherModels
            ))
        }
    }
}
