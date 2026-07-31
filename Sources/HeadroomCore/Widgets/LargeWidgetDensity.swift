import Foundation

/// Density tier for the large widget family. The tile is fixed-size but its content varies
/// per user (provider count, meters per provider, API spend on/off), so spacing floors and
/// meter prominence step down as the row count grows instead of being hand-tuned for one
/// content mix. Mirrors the popover's precedent of compact meter density at higher account
/// counts.
public enum LargeWidgetDensity: Equatable, Sendable {
    case roomy
    case regular
    case compact
    case ultraCompact

    public enum Scale: Equatable, Sendable {
        case hero
        case standard
        case dense
        case ultraDense

        public var barHeight: Double {
            switch self {
            case .hero: 8
            case .standard: 6
            case .dense: 5
            case .ultraDense: 4
            }
        }

        public var meterSpacing: Double {
            switch self {
            case .hero: 7
            case .standard: 6
            case .dense: 4
            case .ultraDense: 3
            }
        }
    }

    /// Rows = one header per provider + one row per subscription meter + one row per
    /// extra weekly sub-limit meter + one for the spend strip. Subscription meters include
    /// weekly and 5-hour windows; extra rows are model-specific weekly limits like Fable.
    public init(providerCount: Int, meterCount: Int, hasSpend: Bool) {
        self.init(providerCount: providerCount, meterCount: meterCount, spendCount: hasSpend ? 1 : 0)
    }

    public init(providerCount: Int, meterCount: Int, spendCount: Int) {
        let rows = providerCount + meterCount + max(0, spendCount)
        if rows <= 5 {
            self = .roomy
        } else if rows <= 7 {
            self = .regular
        } else if rows <= 11 {
            self = .compact
        } else {
            self = .ultraCompact
        }
    }

    public init(envelope: WidgetSnapshotEnvelope) {
        // The established 1–2 provider layout renders API entries in one horizontal
        // strip. Higher provider counts may wrap them, so account for each entry there.
        let spendRows = envelope.providers.count <= 2
            ? min(1, envelope.apiSpendProviders.count)
            : envelope.apiSpendProviders.count
        self.init(
            providerCount: envelope.providers.count,
            meterCount: envelope.providers.reduce(0) { $0 + $1.subscriptionWindows.count + $1.extraWeeklyWindows.count },
            spendCount: spendRows
        )
    }

    /// Minimum size of each flexible gap (top edge, between sections, bottom edge).
    public var gapFloor: Double {
        switch self {
        case .roomy: 14
        case .regular: 11
        case .compact: 8
        case .ultraCompact: 5
        }
    }

    /// Provider header → first meter.
    public var headerSpacing: Double {
        switch self {
        case .roomy: 9
        case .regular: 8
        case .compact: 6
        case .ultraCompact: 4
        }
    }

    /// Meter → meter within one provider.
    public var meterSpacing: Double {
        switch self {
        case .roomy: 12
        case .regular: 11
        case .compact: 8
        case .ultraCompact: 5
        }
    }

    public var scale: Scale {
        switch self {
        case .roomy: .hero
        case .regular: .standard
        case .compact: .dense
        case .ultraCompact: .ultraDense
        }
    }

    public var glancePercentFontStep: Scale {
        scale
    }

    public var windowTitleFontStep: Scale {
        scale
    }

    public var providerHeaderFontStep: Scale {
        scale
    }

    public var providerIconSize: Double {
        switch self {
        case .roomy: 24
        case .regular: 20
        case .compact: 18
        case .ultraCompact: 16
        }
    }

    public var barHeight: Double {
        scale.barHeight
    }

}
