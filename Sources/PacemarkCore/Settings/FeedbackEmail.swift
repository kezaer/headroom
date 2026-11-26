import Foundation

// Feedback by email (2026-11-03 plan, KTD1): every surface opens a pre-filled email that the
// user reads, edits and sends from their own mail account, so Pacemark itself sends nothing.
// This file is the one recipe for that email. Its inputs are closed enums, counts and version
// strings that pass a shape check (R4); it never takes a `UsageSnapshot`, so emails, account
// names, plan names and failure messages cannot reach the text.


/// One provider CLI's version as the diagnostics block reports it.
public enum FeedbackCLIVersion: Sendable, Equatable {
    case version(String)
    case notInstalled
    case unknown

    /// R4: only a bare version survives. Output that names a path is dropped whole, because a
    /// path can carry the user's name, and anything without a version-shaped token is
    /// "unknown" rather than raw CLI text.
    public init(versionOutput: String?) {
        guard let versionOutput else {
            self = .unknown
            return
        }
        let firstLine = versionOutput.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard !firstLine.contains("/"), !firstLine.contains("\\") else {
            self = .unknown
            return
        }
        let token = firstLine
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]")) }
            .first { $0.wholeMatch(of: Self.versionShape) != nil }
        self = token.map { .version($0.hasPrefix("v") ? String($0.dropFirst()) : $0) } ?? .unknown
    }

    // "2.1.317", "0.155.1", "2026.10.18-ea085cb", "v1.0.70".
    nonisolated(unsafe) private static let versionShape = /v?[0-9]{1,6}(\.[0-9]{1,6}){1,3}(-[A-Za-z0-9]{1,16})?/

    var text: String {
        switch self {
        case .version(let value): value
        case .notInstalled: "not installed"
        case .unknown: "unknown"
        }
    }
}

/// One account's state, by case name only (R4).
public enum FeedbackAccountStatus: Sendable, Equatable {
    case waiting
    case live
    case stale(String)

    public init(freshness: Freshness) {
        switch freshness {
        case .pending: self = .waiting
        case .live: self = .live
        case .stale(let reason): self = .stale(Self.caseName(reason))
        }
    }

    /// The failure's case name, never its message: messages can quote CLI output, and a
    /// `notLoggedIn` message has carried an email address.
    static func caseName(_ reason: FailureReason) -> String {
        switch reason {
        case .transient: "transient"
        case .needsReauth: "needsReauth"
        case .scopeDenied: "scopeDenied"
        case .decode: "decode"
        case .notLoggedIn: "notLoggedIn"
        case .providerSetup(let outcome):
            // `ProviderSetupOutcome` has no associated values today; cutting at "(" keeps a
            // future one from printing its payload.
            "setup." + String(String(describing: outcome).prefix { $0 != "(" })
        }
    }

    var text: String {
        switch self {
        case .waiting: "waiting"
        case .live: "live"
        case .stale(let caseName): "stale (\(caseName))"
        }
    }
}

public struct FeedbackDiagnostics: Sendable, Equatable {
    public struct CLI: Sendable, Equatable {
        public let providerID: ProviderID
        public let version: FeedbackCLIVersion

        public init(providerID: ProviderID, version: FeedbackCLIVersion) {
            self.providerID = providerID
            self.version = version
        }
    }

    public struct Account: Sendable, Equatable {
        public let providerID: ProviderID
        /// 1-based position in the provider's display order: "Claude #2".
        public let position: Int
        public let status: FeedbackAccountStatus

        public init(providerID: ProviderID, position: Int, status: FeedbackAccountStatus) {
            self.providerID = providerID
            self.position = position
            self.status = status
        }
    }

    public let appVersion: String?
    public let operatingSystem: String
    public let architecture: String?
    public let cliVersions: [CLI]
    public let providersOff: [ProviderID]
    public let accounts: [Account]

    public init(
        appVersion: String?,
        operatingSystem: String,
        architecture: String? = nil,
        cliVersions: [CLI] = [],
        providersOff: [ProviderID] = [],
        accounts: [Account] = []
    ) {
        self.appVersion = appVersion
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.cliVersions = cliVersions
        self.providersOff = providersOff
        self.accounts = accounts
    }

    /// Fixed lines in a fixed order, so the preview and the sent email always agree.
    var lines: [String] {
        var header = ["Pacemark \(appVersion ?? "unknown")", operatingSystem]
        if let architecture { header.append(architecture) }
        var lines = [header.joined(separator: " · ")]
        if !cliVersions.isEmpty {
            lines.append("CLIs: " + cliVersions
                .map { "\($0.providerID.displayName) \($0.version.text)" }
                .joined(separator: " · "))
        }
        if !providersOff.isEmpty {
            lines.append("Off: " + providersOff.map(\.displayName).joined(separator: ", "))
        }
        lines += accounts.map { "\($0.providerID.displayName) #\($0.position): \($0.status.text)" }
        return lines
    }
}

enum FeedbackEmail {
    static let diagnosticsHeading = "--- Diagnostics (you can edit or delete this) ---"
    static let trimmedNote = "(Some diagnostics were left out to fit.)"

    private static let prompts = "What happened?\n\n\nWhat did you expect instead?\n\n"

    static func boundedURL(
        diagnostics: FeedbackDiagnostics?, maximumLength: Int,
        makeURL: (String, String) -> URL
    ) -> URL {
        let title = "[Pacemark Mac] Feedback"
        var kept = diagnostics?.lines ?? []
        var url = makeURL(title, body(prompts: prompts, diagnostics: kept, trimmed: false))
        while url.absoluteString.utf8.count > maximumLength, !kept.isEmpty {
            kept.removeLast()
            url = makeURL(title, body(prompts: prompts, diagnostics: kept, trimmed: true))
        }
        return url
    }

    private static func body(prompts: String, diagnostics: [String], trimmed: Bool) -> String {
        guard !diagnostics.isEmpty || trimmed else { return prompts }
        var block = [diagnosticsHeading] + diagnostics
        if trimmed { block.append(trimmedNote) }
        return prompts + "\n" + block.joined(separator: "\n") + "\n"
    }

}
