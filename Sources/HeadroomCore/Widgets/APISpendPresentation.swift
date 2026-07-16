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
        amountText(amount: summary.amount, currency: summary.currency)
    }
}
