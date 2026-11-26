import Foundation

extension Preferences {
    static let menuBarMetersKey = "t3.menuBar.meters.v1"

    public var menuBarMeterSelection: MenuBarMeterSelection? {
        get {
            defaults.data(forKey: Self.menuBarMetersKey)
                .flatMap { try? JSONDecoder().decode(MenuBarMeterSelection.self, from: $0) }
        }
        nonmutating set {
            // A newer build may have stored a selection this build cannot decode.
            guard defaults.object(forKey: Self.menuBarMetersKey) == nil || menuBarMeterSelection != nil else { return }
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.menuBarMetersKey)
        }
    }
}
