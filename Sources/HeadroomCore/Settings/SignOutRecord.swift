import Foundation

/// One observed signed-in → signed-out change. R16/R18: an entry carries the time
/// Headroom detected the change and the account key, and nothing else — no email, no
/// organization, no provider-side account identifier, no CLI output.
public struct SignOutEvent: Codable, Equatable, Hashable, Sendable {
    public let account: AccountKey
    public let detectedAt: Date

    public init(account: AccountKey, detectedAt: Date) {
        self.account = account
        self.detectedAt = detectedAt
    }
}

/// KTD14 (2026-09-19 sign-in plan): the diagnostics-only record of Claude sign-outs,
/// persisted in UserDefaults under one versioned key like `AccountRegistry`.
///
/// Only the *edge* is recorded — a last-known-signed-in account observed signed out —
/// so a signed-out account that is polled every five minutes produces one entry, not
/// one per poll. The persisted flag is what makes a sign-out that happened while
/// Headroom was closed a single entry at the next launch rather than one per launch.
///
/// R17: nothing here reaches the interface. It is read through `--probe-claude` only.
public struct SignOutRecord: @unchecked Sendable { // UserDefaults is thread-safe
    /// Bound on the stored list. Sign-outs are rare and only the recent ones are
    /// diagnostically interesting, so the oldest entry is dropped past this.
    public static let maxEvents = 50

    private static let storageKey = "claudeSignOutRecord.v1"

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    /// Every recorded change, oldest first.
    public var events: [SignOutEvent] { load().events }

    public func events(for key: AccountKey) -> [SignOutEvent] {
        load().events.filter { $0.account == key }
    }

    public func isLastKnownSignedIn(_ key: AccountKey) -> Bool {
        load().signedIn.contains(key)
    }

    /// A live reading: this account is signed in, so the next signed-out reading is an
    /// edge worth recording.
    public func noteSignedIn(_ key: AccountKey) {
        var stored = load()
        guard stored.signedIn.insert(key).inserted else { return }
        save(stored)
    }

    /// A signed-out reading. Records one entry only when this account was last known to
    /// be signed in; repeated signed-out polls after that change nothing.
    public func noteSignedOut(_ key: AccountKey) {
        var stored = load()
        guard stored.signedIn.remove(key) != nil else { return }
        stored.events.append(SignOutEvent(account: key, detectedAt: now()))
        if stored.events.count > Self.maxEvents {
            stored.events.removeFirst(stored.events.count - Self.maxEvents)
        }
        save(stored)
    }

    /// Durable exclusion: a deliberate sign-out (reset staging), a detach, and a
    /// stop-track all drop the flag, so the signed-out reading that follows is not an
    /// observed change. Only a later live reading arms the account again.
    public func clearLastKnownSignedIn(for key: AccountKey) {
        var stored = load()
        guard stored.signedIn.remove(key) != nil else { return }
        save(stored)
    }

    /// Removing an account takes its history with it, alongside its config home.
    public func purgeEvents(for key: AccountKey) {
        var stored = load()
        let remaining = stored.events.filter { $0.account != key }
        guard remaining.count != stored.events.count || stored.signedIn.contains(key) else { return }
        stored.events = remaining
        stored.signedIn.remove(key)
        save(stored)
    }

    // MARK: - Storage

    private struct Stored: Codable {
        var events: [SignOutEvent] = []
        /// Accounts whose last reading was signed in — the per-account flag, stored as
        /// the set of accounts it is true for. A `Set` rather than an array kept unique
        /// by hand; `v1` has never shipped, so no stored payload needs migrating.
        var signedIn: Set<AccountKey> = []
    }

    private func load() -> Stored {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return Stored() }
        return stored
    }

    private func save(_ stored: Stored) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
