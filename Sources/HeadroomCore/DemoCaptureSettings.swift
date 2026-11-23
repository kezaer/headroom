import Foundation

/// Only the settings read by the captured Mac surfaces.
struct DemoCaptureSettings: Codable, Equatable, Sendable {
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
