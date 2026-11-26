import Foundation

public struct AccountRowPolicy: Sendable, Equatable {
    public enum Badge: Sendable, Equatable {
        case cliLogin, pacemark, t3(instanceName: String), folder(abbreviatedPath: String)

        public var title: String? {
            switch self {
            case .cliLogin: "CLI login"
            case .pacemark: nil
            case .t3(let name): "T3 Code · \(name)"
            case .folder: "CLI folder"
            }
        }
    }

    public enum Removal: Sendable, Equatable {
        case deleteOwnedHome, stopTrackingCLIDefault, hideT3Home, forgetFolder

        public var confirmationMessage: String {
            switch self {
            case .deleteOwnedHome: "Pacemark will remove this account and its sign-in on this Mac."
            case .stopTrackingCLIDefault: "Pacemark will stop showing usage for this CLI login."
            case .hideT3Home: "Pacemark will hide this account. Restore it from Hidden T3 Accounts."
            case .forgetFolder: "Pacemark will remove this folder from your tracked accounts."
            }
        }
    }

    public let badge: Badge
    public let offersPacemarkSignIn: Bool
    public let removal: Removal?
    public let showsPath: CanonicalHomePath?

    public static func make(
        for account: ProviderAccount, canStopTrackingBuiltIn: Bool, userHome: String = NSHomeDirectory()
    ) -> Self {
        switch account.origin {
        case .cliDefault:
            .init(badge: .cliLogin, offersPacemarkSignIn: true,
                  removal: canStopTrackingBuiltIn ? .stopTrackingCLIDefault : nil, showsPath: nil)
        case .pacemarkOwned:
            .init(badge: .pacemark, offersPacemarkSignIn: true, removal: .deleteOwnedHome, showsPath: nil)
        case .borrowed(let home):
            switch home.source {
            case .t3Instance(let id, let name):
                .init(badge: .t3(instanceName: name ?? id), offersPacemarkSignIn: false,
                      removal: .hideT3Home, showsPath: home.path)
            case .manual:
                .init(badge: .folder(abbreviatedPath: home.path.abbreviated(userHome: userHome)),
                      offersPacemarkSignIn: false, removal: .forgetFolder, showsPath: home.path)
            }
        }
    }
}
