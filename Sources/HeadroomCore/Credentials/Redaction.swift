import Foundation

/// Guards against tokens reaching logs, UI, or error text (R10). Failure text is
/// always a `FailureReason` (KTD7), never interpolated from a caught `Error`,
/// `URLRequest`, or `HTTPURLResponse`; this helper is the belt-and-suspenders pass
/// for any string that might have touched a secret.
public enum Redaction {
    /// Replace anything that looks like an OAuth/session token with a marker.
    /// Matches long opaque runs and the known `sk-ant-…` / `sess-…` shapes.
    public static func redact(_ text: String) -> String {
        var result = text
        result = result.replacing(/sk-ant-[A-Za-z0-9_-]+/, with: "‹redacted›")
        result = result.replacing(/sess-[A-Za-z0-9_-]+/, with: "‹redacted›")
        result = result.replacing(/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}/, with: "‹redacted›") // JWTs
        result = result.replacing(/[A-Za-z0-9_-]{40,}/, with: "‹redacted›") // long opaque tokens
        return result
    }
}
