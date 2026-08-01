import Foundation

public enum APISpendPresentation {
    public static func amountText(amount: Double?, currency: String?) -> String? {
        guard let amount, let currency, !currency.isEmpty else { return nil }
        let code = currency.uppercased()
        if code == "USD" {
            return String(format: "$%.2f", amount)
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(code) \(String(format: "%.2f", amount))"
    }

    public static func statusText(freshness: WidgetProviderFreshness, capturedAt: Date?, now: Date) -> String? {
        switch freshness {
        case .pending:
            "Waiting for cost data"
        case .live:
            Countdown.updatedLabel(capturedAt: capturedAt, now: now).map { "Updated \($0)" }
        case .stale(_, let needsAttention):
            needsAttention
                ? "Set up on Mac"
                : (Countdown.updatedLabel(capturedAt: capturedAt, now: now).map { "Updated \($0)" } ?? "Not updated")
        }
    }

    /// Companion rows follow the current macOS popover: the screen header owns the live
    /// freshness stamp, while only pending/stale rows carry a secondary status line.
    public static func companionStatusText(freshness: WidgetProviderFreshness) -> String? {
        switch freshness {
        case .pending:
            "Waiting for cost data"
        case .live:
            nil
        case .stale(_, let needsAttention):
            needsAttention ? "Needs setup" : "Stale"
        }
    }

    public static func amountText(_ summary: WidgetAPISpendSummary) -> String? {
        guard let amount = amountText(amount: summary.amount, currency: summary.currency) else { return nil }
        return summary.semanticKind == .balance ? "\(amount) left" : amount
    }

    public static func contextLabel(kind: APISpendKind, periodLabel: String) -> String {
        kind == .balance ? "Remaining balance" : periodLabel
    }

    public static func qualifier(kind: APISpendKind) -> String? {
        kind == .balance ? "remaining" : nil
    }

    /// The exact page where a user tops up prepaid API credits — the billing screen that
    /// hosts Anthropic's "Buy credits" / OpenAI's "Add to credit balance" control, not a
    /// docs or marketing page. Anthropic's console moved to platform.claude.com (late
    /// 2025), so we link there directly instead of riding the console.anthropic.com
    /// redirect. Kept in Core so the mapping is unit-tested.
    public static func addCreditsURL(for providerID: ProviderID) -> URL? {
        switch providerID {
        case .claude:
            URL(string: "https://platform.claude.com/settings/billing")
        case .codex:
            URL(string: "https://platform.openai.com/settings/organization/billing/overview")
        case .grok:
            URL(string: "https://console.x.ai")
        default:
            nil
        }
    }
}
