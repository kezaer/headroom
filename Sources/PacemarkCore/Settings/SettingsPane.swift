import Foundation

/// One destination in the Settings sidebar (R1). The case order *is* the sidebar order
/// and `Group` *is* the section split, so the window never keeps a second hand-ordered
/// list that can drift from this one.
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case menuBar
    case notifications
    case warmUp
    case accounts
    case apiSpend
    case about

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .general: "General"
        case .appearance: "Popover"
        case .menuBar: "Menu Bar"
        case .warmUp: "Warm-up"
        case .notifications: "Notifications"
        case .accounts: "Accounts"
        case .apiSpend: "API Spend"
        case .about: "About"
        }
    }

    public var group: Group {
        switch self {
        case .general, .appearance, .menuBar, .notifications, .warmUp: .preferences
        case .accounts, .apiSpend: .sources
        case .about: .about
        }
    }

    /// Sidebar section headers: what the app does (`App`) versus where the numbers come
    /// from (`Sources`).
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case preferences
        case sources
        case about

        public var id: String { rawValue }

        /// R2B1: "App", not "Preferences" — the latter is the pre-Ventura word for the whole
        /// window, so it read as a section named after its own container inside "Pacemark
        /// Settings". The raw value stays `preferences` so nothing persisted migrates.
        public var label: String? {
            switch self {
            case .preferences: "App"
            case .sources: "Sources"
            case .about: nil
            }
        }

        /// Derived, never hand-listed, so the groups always partition every pane.
        public var panes: [SettingsPane] { SettingsPane.allCases.filter { $0.group == self } }
    }
}
