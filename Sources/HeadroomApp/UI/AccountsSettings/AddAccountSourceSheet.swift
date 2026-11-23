import SwiftUI
import AppKit
import HeadroomCore

struct AccountSourceSheetRequest: Identifiable {
    let id: ProviderID
}

struct SharedT3AccountSources: Sendable {
    var claudeName: String?
    var antigravityPath: String?

    @MainActor func builtInSource(for providerID: ProviderID, in store: UsageStore) -> AccountSourceKind {
        store.builtInAccountSource(for: providerID, hasT3Claude: claudeName != nil,
                                   hasT3Antigravity: antigravityPath != nil)
    }

    @MainActor static func discover() async -> Self {
        if let capture = AppComposition.capturedDemo {
            return Self(claudeName: capture.hasT3Claude ? "Claude" : nil,
                        antigravityPath: capture.hasT3Antigravity ? "/demo-capture/antigravity" : nil)
        }
        guard !AppComposition.usesInertAntigravity() else { return Self() }
        return await Task.detached(priority: .utility) {
            let installation = T3Installation()
            let antigravity = installation.antigravity().map {
                ($0.dataDirectory.path as NSString).abbreviatingWithTildeInPath
            }
            return Self(claudeName: installation.claudeInstanceName(), antigravityPath: antigravity)
        }.value
    }
}

struct AddAccountSourceSheet: View {
    private enum Step { case choose, t3, cli, separate }
    @Environment(\.dismiss) private var dismiss
    let providerID: ProviderID
    let displayName: String
    let store: UsageStore
    @Binding var t3Sources: SharedT3AccountSources
    let enableProvider: () -> Void
    let addSeparateLogin: () -> Bool
    @State private var step = Step.choose
    @State private var status: String?
    @State private var busy = false
    @State private var folderPath = ""
    @State private var folderLabel = ""

    private var defaultPath: String { AccountsSettingsInteractions.defaultCLIPath(for: providerID) ?? "" }
    private var builtIn: ProviderAccount? { store.accounts(for: providerID).first(where: \.isBuiltIn) }
    private var showsT3: Bool { [.codex, .claude, .antigravity].contains(providerID) }
    private var sharesBuiltIn: Bool { providerID == .claude || providerID == .antigravity }
    private var builtInSource: AccountSourceKind { t3Sources.builtInSource(for: providerID, in: store) }
    private var tracksSharedT3: Bool { builtInSource == .t3Code }
    private var tracksDefault: Bool { builtIn != nil && builtInSource == .existingCLI }
    private var canChangeBuiltIn: Bool {
        builtIn.map { !SetupSessions.hasActiveHandoff(for: $0) } ?? true
    }
    private var title: String {
        switch step {
        case .choose: "Add \(displayName) source"
        case .t3: "T3 Code · \(displayName)"
        case .cli: "Existing CLI · \(displayName)"
        case .separate: "Separate \(displayName) login"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if step != .choose {
                Button {
                    navigate(to: .choose)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(busy)
            }
            Text(title).font(.system(size: 15, weight: .semibold))
            switch step {
            case .choose: choices
            case .t3: t3Selector
            case .cli: existingCLI
            case .separate: separateLogin
            }
            if let status {
                SettingsHelpText(text: status)
            }
            footer
        }
        .padding(18)
        .frame(width: 390)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHelpText(text: "Choose where Headroom should read \(displayName) usage from.")
            VStack(spacing: 0) {
                if showsT3 {
                    choice("T3 Code", detail: "Choose from discovered T3 Code logins", icon: "macwindow", destination: .t3)
                    Divider()
                }
                choice("Existing CLI", detail: "Default \(defaultPath) or another CLI folder", icon: "folder", destination: .cli)
                Divider()
                choice("Separate login", detail: "Sign in to a Headroom-managed home via CLI", icon: "terminal", destination: .separate)
            }
            .accountSettingsInset(radius: 10)
        }
    }

    private func choice(_ title: String, detail: String, icon: String, destination: Step) -> some View {
        Button {
            navigate(to: destination)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 28, height: 28)
                    .accountSettingsInset(radius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    SettingsHelpText(text: detail)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccountSourceOptionStyle())
    }

    private var t3Selector: some View {
        let homes = providerID == .codex ? store.discoveredT3CodexAccounts() : []
        return VStack(alignment: .leading, spacing: 10) {
            SettingsHelpText(text: "Select a T3 Code login to start or stop tracking it.")
            let catalog =
                VStack(spacing: 0) {
                    if providerID == .codex, !homes.isEmpty {
                        ForEach(homes) { account in
                            if account.id != homes.first?.id { Divider() }
                            let tracked = store.accounts(for: .codex).contains { $0.key == account.key }
                            let path = account.borrowedHome?.path.abbreviated(userHome: NSHomeDirectory()) ?? ""
                            let plan = PlanLabelPresentation.displayName(store.snapshot(for: account.key).planLabel, provider: .codex)
                            trackingChoice(plan.map { "\(account.label) · Codex \($0)" } ?? account.label,
                                           path: path, tracked: tracked) {
                                toggleT3Codex(account, tracked: tracked)
                            }
                            .disabled(busy || (!tracked && !store.canAddAccount(for: .codex)))
                        }
                    } else if providerID == .claude, let name = t3Sources.claudeName {
                        sharedT3Choice(name, path: defaultPath)
                    } else if providerID == .antigravity, let path = t3Sources.antigravityPath {
                        sharedT3Choice("Antigravity", path: path)
                    } else {
                        SettingsHelpText(text: "No T3 Code \(displayName) logins found.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
            if providerID == .codex, homes.count > 5 {
                ScrollView { catalog }
                    .frame(height: 250)
                    .accountSettingsInset(radius: 10)
            } else {
                catalog.accountSettingsInset(radius: 10)
            }
            if providerID == .claude, t3Sources.claudeName != nil {
                SettingsHelpText(text: "T3 Code and Terminal share the same ~/.claude login.")
            }
        }
    }

    private func sharedT3Choice(_ name: String, path: String) -> some View {
        trackingChoice(name, path: path, tracked: builtIn != nil && tracksSharedT3) {
            if tracksSharedT3, let builtIn {
                stop(builtIn)
            } else {
                activateBuiltIn(useT3: true)
            }
        }
        .disabled(busy || !canChangeBuiltIn)
    }

    private var existingCLI: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsHelpText(text: "Track an existing CLI login without signing in again.")
            trackingChoice("Default CLI", path: defaultPath, tracked: tracksDefault) {
                if tracksDefault, let builtIn {
                    stop(builtIn)
                } else {
                    activateBuiltIn(useT3: false)
                }
            }
            .disabled(busy || !canChangeBuiltIn)
            .accountSettingsInset(radius: 10)

            Text("Or track another CLI config folder")
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
            HStack {
                TextField("~/path/to/config-home", text: $folderPath)
                    .accessibilityLabel("CLI config folder path")
                    .onChange(of: folderPath) { status = nil }
                Button("Choose Folder…", action: chooseFolder)
            }
            TextField("Label (optional)", text: $folderLabel)
            if providerID != .codex {
                SettingsHelpText(text: "Headroom supports only the default \(displayName) CLI folder here.")
            } else if !store.canAddAccount(for: providerID) {
                SettingsHelpText(text: "Stop tracking an account to add another folder.")
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func trackingChoice(_ title: String, path: String, tracked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
                Spacer(minLength: 4)
                Text(tracked ? "Tracking ✓" : "Add")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tracked ? Color.green : Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tracked ? Color.green.opacity(0.12) : Color.primary.opacity(0.07), in: Capsule())
                    .fixedSize()
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccountSourceOptionStyle())
        .accessibilityHint(tracked ? "Stop tracking this login" : "Track this login")
    }

    private var separateLogin: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.accountCapacity(for: providerID) == 1 {
                SettingsHelpText(text: "\(displayName) supports one CLI account. Use Existing CLI to track that login.")
            } else if !store.canAddAccount(for: providerID) {
                SettingsHelpText(text: "Stop tracking an account to make room for a separate login.")
            } else {
                SettingsHelpText(text: "Headroom creates an isolated config home and opens Terminal so you can sign in through the official \(displayName) CLI.")
                if let note = AccountsSettingsInteractions.providerGroupNote(for: providerID) {
                    SettingsHelpText(text: note)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if step == .t3 {
                Button("Rescan", systemImage: "arrow.clockwise", action: rescan).disabled(busy)
            }
            Spacer()
            if step == .t3 {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else if step == .cli {
                Button("Done", role: .cancel) { dismiss() }
                Button("Add Folder", action: addFolder)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || providerID != .codex || !store.canAddAccount(for: providerID)
                              || folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button("Cancel", role: .cancel) { dismiss() }
                if step == .separate, store.accountCapacity(for: providerID) > 1, store.canAddAccount(for: providerID) {
                    Button("Add Separate Login") {
                        if addSeparateLogin() { dismiss() }
                        else { status = "Headroom couldn’t create a separate login. Try again." }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func navigate(to destination: Step) {
        status = nil
        step = destination
    }

    private func rescan() {
        if store.isReplayingDemoCapture {
            status = "Using captured T3 Code logins."
            return
        }
        busy = true
        Task { @MainActor in
            let summary = providerID == .codex ? store.rescanBorrowedHomes() : nil
            t3Sources = await SharedT3AccountSources.discover()
            busy = false
            if let summary, !summary.read {
                status = "Couldn’t read T3 Code settings. Kept your current accounts."
            } else {
                status = "Rescanned T3 Code settings."
            }
        }
    }

    private func toggleT3Codex(_ account: ProviderAccount, tracked: Bool) {
        if tracked {
            stop(account)
        } else if store.restoreBorrowedAccount(account.key) {
            enableProvider()
            store.refreshAccountNow(account.key)
            status = nil
        } else {
            status = BorrowedHomeRejection.atCapacity.message
        }
    }

    private func activateBuiltIn(useT3: Bool) {
        guard canChangeBuiltIn else { return }
        if sharesBuiltIn {
            if providerID == .claude { store.setTracksT3Claude(useT3) }
            else { store.setAntigravitySourcePreference(useT3 ? .autoPreferT3 : .systemCLI) }
        }
        if providerID == .codex {
            store.setTracksCLIDefaultAlongsideT3(true)
        } else if builtIn == nil {
            store.resumeTrackingBuiltInAccount(for: providerID)
        }
        guard let builtIn else {
            status = "Headroom couldn’t start tracking this login."
            return
        }
        enableProvider()
        store.refreshAccountNow(builtIn.key)
        status = nil
    }

    private func stop(_ account: ProviderAccount) {
        busy = true
        Task { @MainActor in
            let row = DisplayAccount(account: account, kind: .engine)
            let result = await AccountsSettingsInteractions.stopTrackingSource(row, in: store)
            busy = false
            switch result {
            case .removed: status = nil
            case .setupActive: status = "Finish or stop the sign-in in progress, then try again."
            default: status = "Headroom couldn’t stop tracking this source. Try again."
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    private func addFolder() {
        let path = (folderPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else {
            status = "Enter an absolute path or choose a folder."
            return
        }
        switch store.addExternalCodexHome(at: URL(fileURLWithPath: path, isDirectory: true), label: folderLabel) {
        case .success(let account):
            enableProvider()
            store.refreshAccountNow(account.key)
            dismiss()
        case .failure(let reason):
            status = reason.message
        }
    }
}
private struct AccountSourceOptionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(isEnabled && (hovering || configuration.isPressed) ? 0.06 : 0))
            .opacity(isEnabled ? 1 : 0.55)
            .onHover { hovering = $0 }
    }
}
