import Foundation

/// One outbound link in the Settings About pane: a row title on the leading edge and the
/// destination, spelled the way people recognise it, on the trailing edge.
public struct AboutLink: Identifiable, Equatable, Sendable {
    public let title: String
    /// The trailing text. A handle or domain rather than the full URL, so the row says
    /// where it goes without printing a scheme.
    public let destination: String
    public let url: URL

    public var id: String { title }

    init(title: String, destination: String, url: String) {
        self.title = title
        self.destination = destination
        // Literals only, each pinned by `AboutLinksTests`, so a typo fails a test rather
        // than shipping a row that opens nothing.
        self.url = URL(string: url)!
    }
}

/// Every destination the About pane links out to, kept in Core so the URLs are tested
/// without a SwiftUI host.
public enum AboutLinks {
    /// The one-line description under the name in the About header.
    public static let tagline = "AI usage limits + API spend right from your menu bar."

}


public enum MacAboutLinks {
    public static let license = AboutLink(
        title: "GPL-3.0 license", destination: "GitHub", url: "https://github.com/kezaer/pacemark/blob/main/LICENSE"
    )
    public static let maker = [
        AboutLink(title: "LinkedIn", destination: "in/kezaer", url: "https://www.linkedin.com/in/kezaer"),
        AboutLink(title: "GitHub", destination: "kezaer", url: "https://github.com/kezaer"),
    ]
}
