import Foundation

/// The single seam the polling engine depends on (R13). Concrete providers
/// (Claude, Codex, and any third later) implement this; the engine and shell
/// never reference a concrete provider.
///
/// `fetchSnapshot()` returns a stale/failed snapshot rather than throwing, so one
/// provider's failure can never abort the cycle or hide another provider (KTD7).
/// `Sendable` because the engine fetches providers concurrently (KTD10).
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    func fetchSnapshot() async -> UsageSnapshot
}
