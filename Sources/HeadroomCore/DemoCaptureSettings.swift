import Foundation

/// Only the settings read by the captured Mac surfaces.
struct DemoCaptureSettings: Codable, Equatable, Sendable {
    fileprivate static let defaultPreferences = Preferences(defaults: DemoMemoryDefaults())
    static let defaults = Self(defaultPreferences, at: .distantPast)

    let appearancePreference: String
    let usagePercentageMode: String
    let accountTitleInk: String
    let accountLayout: String
    let meterFormat: String
    let meterShape: String
    let meterFill: String
    let menuBarIconStyle: String
    let antigravitySourcePreference: String
    let apiSpendPeriod: String
    let showMenuBarPercentage: Bool
    let showAllProviderAccountsInMenuBar: Bool
    let useEmailAsAccountName: Bool
    let expandAccountsHorizontally: Bool
    let showCodexSparkCountersInApp: Bool
    let showsAntigravityFiveHourWindows: Bool
    let tracksT3Claude: Bool
    let pollIntervalMinutes: Int
    let menuBarProviderOrder: [ProviderID]
    let menuBarFillProviders: [ProviderID]?
    let enabledSurfaces: [UsageSurface]
    let providerSettings: [ProviderSettings]

    struct ProviderSettings: Codable, Equatable, Sendable {
        let provider: ProviderID
        let menuBarWindow: String
        let windowWasChosen: Bool
        let renewalOffset: TimeInterval?
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        appearancePreference = try values.decodeIfPresent(String.self, forKey: .appearancePreference) ?? defaults.appearancePreference
        usagePercentageMode = try values.decodeIfPresent(String.self, forKey: .usagePercentageMode) ?? defaults.usagePercentageMode
        accountTitleInk = try values.decodeIfPresent(String.self, forKey: .accountTitleInk) ?? defaults.accountTitleInk
        accountLayout = try values.decodeIfPresent(String.self, forKey: .accountLayout) ?? defaults.accountLayout
        meterFormat = try values.decodeIfPresent(String.self, forKey: .meterFormat) ?? defaults.meterFormat
        meterShape = try values.decodeIfPresent(String.self, forKey: .meterShape) ?? defaults.meterShape
        meterFill = try values.decodeIfPresent(String.self, forKey: .meterFill) ?? defaults.meterFill
        menuBarIconStyle = try values.decodeIfPresent(String.self, forKey: .menuBarIconStyle) ?? defaults.menuBarIconStyle
        antigravitySourcePreference = try values.decodeIfPresent(String.self, forKey: .antigravitySourcePreference) ?? defaults.antigravitySourcePreference
        apiSpendPeriod = try values.decodeIfPresent(String.self, forKey: .apiSpendPeriod) ?? defaults.apiSpendPeriod
        showMenuBarPercentage = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarPercentage) ?? defaults.showMenuBarPercentage
        showAllProviderAccountsInMenuBar = try values.decodeIfPresent(Bool.self, forKey: .showAllProviderAccountsInMenuBar) ?? defaults.showAllProviderAccountsInMenuBar
        useEmailAsAccountName = try values.decodeIfPresent(Bool.self, forKey: .useEmailAsAccountName) ?? defaults.useEmailAsAccountName
        expandAccountsHorizontally = try values.decodeIfPresent(Bool.self, forKey: .expandAccountsHorizontally) ?? defaults.expandAccountsHorizontally
        showCodexSparkCountersInApp = try values.decodeIfPresent(Bool.self, forKey: .showCodexSparkCountersInApp) ?? defaults.showCodexSparkCountersInApp
        showsAntigravityFiveHourWindows = try values.decodeIfPresent(Bool.self, forKey: .showsAntigravityFiveHourWindows) ?? defaults.showsAntigravityFiveHourWindows
        tracksT3Claude = try values.decodeIfPresent(Bool.self, forKey: .tracksT3Claude) ?? defaults.tracksT3Claude
        pollIntervalMinutes = try values.decodeIfPresent(Int.self, forKey: .pollIntervalMinutes) ?? defaults.pollIntervalMinutes
        menuBarProviderOrder = try values.decodeIfPresent([ProviderID].self, forKey: .menuBarProviderOrder) ?? defaults.menuBarProviderOrder
        menuBarFillProviders = try values.decodeIfPresent([ProviderID].self, forKey: .menuBarFillProviders)
        enabledSurfaces = try values.decodeIfPresent([UsageSurface].self, forKey: .enabledSurfaces) ?? defaults.enabledSurfaces
        providerSettings = try values.decodeIfPresent([ProviderSettings].self, forKey: .providerSettings) ?? defaults.providerSettings
    }

    init(_ preferences: Preferences, at date: Date) {
        appearancePreference = preferences.appearancePreference.rawValue
        usagePercentageMode = preferences.usagePercentageMode.rawValue
        accountTitleInk = preferences.accountTitleInk.rawValue
        accountLayout = preferences.accountLayout.rawValue
        meterFormat = preferences.meterFormat.rawValue
        meterShape = preferences.meterShape.rawValue
        meterFill = preferences.meterFill.rawValue
        menuBarIconStyle = preferences.menuBarIconStyle.rawValue
        antigravitySourcePreference = preferences.antigravitySourcePreference.rawValue
        apiSpendPeriod = preferences.apiSpendPeriod.rawValue
        showMenuBarPercentage = preferences.showMenuBarPercentage
        showAllProviderAccountsInMenuBar = preferences.showAllProviderAccountsInMenuBar
        useEmailAsAccountName = preferences.useEmailAsAccountName
        expandAccountsHorizontally = preferences.expandAccountsHorizontally
        showCodexSparkCountersInApp = preferences.showCodexSparkCountersInApp
        showsAntigravityFiveHourWindows = preferences.showsAntigravityFiveHourWindows
        tracksT3Claude = preferences.tracksT3Claude
        pollIntervalMinutes = preferences.pollIntervalMinutes
        menuBarProviderOrder = preferences.menuBarProviderOrder
        menuBarFillProviders = preferences.menuBarFillSource.providerIDs?.sorted { $0.raw < $1.raw }
        enabledSurfaces = UsageSurface.allCases.filter { preferences.isSurfaceEnabled($0) }
        providerSettings = UsageSurface.allCases.filter(\.isSubscription).map(\.providerID).map { id in
            ProviderSettings(
                provider: id, menuBarWindow: preferences.menuBarWindowChoice(for: id).rawValue,
                windowWasChosen: preferences.hasChosenMenuBarWindow(for: id),
                renewalOffset: preferences.renewalDate(for: id)?.timeIntervalSince(date)
            )
        }
    }

    func apply(to preferences: Preferences, rebasedTo date: Date) {
        preferences.appearancePreference = AppearancePreference(rawValue: appearancePreference) ?? preferences.appearancePreference
        preferences.usagePercentageMode = UsagePercentageMode(rawValue: usagePercentageMode) ?? preferences.usagePercentageMode
        preferences.accountTitleInk = AccountTitleInk(rawValue: accountTitleInk) ?? preferences.accountTitleInk
        preferences.accountLayout = AccountLayout(rawValue: accountLayout) ?? preferences.accountLayout
        preferences.meterFormat = GaugeFormat(rawValue: meterFormat) ?? preferences.meterFormat
        preferences.meterShape = GaugeShape(rawValue: meterShape) ?? preferences.meterShape
        preferences.meterFill = GaugeFill(rawValue: meterFill) ?? preferences.meterFill
        preferences.menuBarIconStyle = MenuBarIconStyle(rawValue: menuBarIconStyle) ?? preferences.menuBarIconStyle
        preferences.antigravitySourcePreference = AntigravitySourcePreference(rawValue: antigravitySourcePreference) ?? preferences.antigravitySourcePreference
        preferences.apiSpendPeriod = APISpendPeriod(rawValue: apiSpendPeriod) ?? preferences.apiSpendPeriod
        preferences.showMenuBarPercentage = showMenuBarPercentage
        preferences.showAllProviderAccountsInMenuBar = showAllProviderAccountsInMenuBar
        preferences.useEmailAsAccountName = useEmailAsAccountName
        preferences.expandAccountsHorizontally = expandAccountsHorizontally
        preferences.showCodexSparkCountersInApp = showCodexSparkCountersInApp
        preferences.showsAntigravityFiveHourWindows = showsAntigravityFiveHourWindows
        preferences.tracksT3Claude = tracksT3Claude
        preferences.pollIntervalMinutes = pollIntervalMinutes
        preferences.menuBarProviderOrder = menuBarProviderOrder
        preferences.menuBarFillSource = menuBarFillProviders.map { .providers(Set($0)) } ?? .auto
        preferences.widgetsEnabled = false
        for surface in UsageSurface.allCases {
            preferences.setSurfaceEnabled(enabledSurfaces.contains(surface), for: surface)
        }
        let inherited = providerSettings.first { !$0.windowWasChosen }?.menuBarWindow
        preferences.setInheritedMenuBarWindow(inherited)
        for entry in providerSettings {
            if entry.windowWasChosen || entry.menuBarWindow != inherited,
               let choice = MenuBarWindowChoice(rawValue: entry.menuBarWindow) {
                preferences.setMenuBarWindowChoice(choice, for: entry.provider)
            }
            preferences.setRenewalDate(entry.renewalOffset.map(date.addingTimeInterval), for: entry.provider)
        }
    }
}

extension DemoCaptureSettings.ProviderSettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try values.decode(ProviderID.self, forKey: .provider)
        let defaults = DemoCaptureSettings.defaultPreferences
        self.init(
            provider: provider,
            menuBarWindow: try values.decodeIfPresent(String.self, forKey: .menuBarWindow)
                ?? defaults.menuBarWindowChoice(for: provider).rawValue,
            windowWasChosen: try values.decodeIfPresent(Bool.self, forKey: .windowWasChosen)
                ?? defaults.hasChosenMenuBarWindow(for: provider),
            renewalOffset: try values.decodeIfPresent(TimeInterval.self, forKey: .renewalOffset)
        )
    }
}
