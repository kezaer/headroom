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
        for pattern in [
            #"sk-ant-[A-Za-z0-9_-]+"#,
            #"sess-[A-Za-z0-9_-]+"#,
            #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}"#, // JWTs
            #"[A-Za-z0-9_-]{40,}"#, // long opaque tokens
        ] {
            if let re = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = re.stringByReplacingMatches(
                    in: result, range: range, withTemplate: "‹redacted›"
                )
            }
        }
        return result
    }
}
