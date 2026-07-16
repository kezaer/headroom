/// The single seam the polling engine depends on (R13). Concrete providers
/// (Claude, Codex, and any third later) implement this; the engine and shell
/// never reference a concrete provider.
///
/// `fetchSnapshot()` returns a stale/failed snapshot rather than throwing, so one
/// provider's failure can never abort the cycle or hide another provider (KTD7).
/// `Sendable` because the engine fetches providers concurrently (KTD10).
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Which configured account this instance fetches for. Defaults to `.primary` so
    /// single-account providers (and tests) don't have to know accounts exist.
    var accountID: AccountID { get }
    var displayName: String { get }
    func fetchSnapshot() async -> UsageSnapshot
}

public extension UsageProvider {
    var accountID: AccountID { .primary }
    var accountKey: AccountKey { AccountKey(providerID: id, accountID: accountID) }
}

/// Money-based API cost providers are intentionally separate from subscription quota
/// providers: a dollar total over a billing period is not a resettable usage window.
public protocol APISpendProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot
}
