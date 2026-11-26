#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

enum LedgerMetrics {
    static let margin: CGFloat = PDS.Space.m
    static let topInset: CGFloat = 10
    static let corner: CGFloat = 16
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 38
    static let summaryHeight: CGFloat = 2 * PDS.Space.m + 13 + 21 + PDS.Space.s + 13 + 3 * PDS.Space.xs
    static let sectionHeaderHeight = PDS.Metrics.sectionHeader
    static let sectionTop: CGFloat = PDS.Space.xs
    static let sectionBottom: CGFloat = PDS.Space.xs
    static let rowHeight: CGFloat = PDS.Metrics.row
    static let accountContentHeight = rowHeight - PDS.Space.s
    static let paddedRowHeight = accountContentHeight + 2 * PDS.Space.s
    static let detailRowHeight: CGFloat = 22
    static let paceWidth: CGFloat = 70
    static let percentageWidth: CGFloat = 42
    static let resetWidth: CGFloat = 52
    static let rowGap: CGFloat = PDS.Space.s
    static let disclosureWidth = PDS.Metrics.providerMark
    static let nameGap: CGFloat = PDS.Space.xs
    static let readingWidth = paceWidth + percentageWidth + resetWidth + 2 * rowGap
    static let sectionCorner: CGFloat = PDS.Radius.card
    static let columnGap = PDS.Space.s

    static let columns = AccountColumnsMetrics(
        cardPadding: Double((sectionTop + sectionBottom) / 2), cardGap: Double(PDS.Space.s), accountGap: Double(PDS.Metrics.dividerSlot), columnWidth: 360, horizontalGap: Double(columnGap)
    )

    static func width(for columns: Int) -> CGFloat { columns == 2 ? 750 : 384 }
}

enum PopoverLedgerType {
    static let header = PDS.Typography.rowTitle
    static let hero = PDS.Typography.numberLarge
    static let caps = PDS.Typography.caps
    static let column = PDS.Typography.caps
    static let name = PDS.Typography.rowTitle
    static let sentence = PDS.Typography.secondary
    static let value = PDS.Typography.number
    static let unit = PDS.Typography.secondary
    static let countdown = PDS.Typography.numberSmall
    static let chip = PDS.Typography.caps
}

typealias LedgerChip = PDSChip
