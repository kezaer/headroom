import Foundation

/// Demo account management never constructs a config-home or handoff-marker path.
public final class DemoAccountStorage: AccountStorageManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var handoffs: Set<AccountKey> = []
    public init() {}
    public func beginHandoff(_ key: AccountKey) { lock.withLock { _ = handoffs.insert(key) } }
    public func endHandoff(_ key: AccountKey) { lock.withLock { _ = handoffs.remove(key) } }
    public var activeHandoffCount: Int { lock.withLock { handoffs.count } }
    public func ensureDirectories(for account: HeadroomOwnedHome) -> Result<Void, AccountStorageFailure> { .success(()) }
    public func setupHandoffIsActive(for account: SetupCapableAccount) async -> Bool { lock.withLock { handoffs.contains(account.account.key) } }
    public func removeDirectories(for account: HeadroomOwnedHome) async -> Result<Void, AccountStorageFailure> {
        lock.withLock { handoffs.contains(account.account.key) ? .failure(.setupActive) : .success(()) }
    }
}
