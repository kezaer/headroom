import Foundation

/// A prefilled issue the user can review and submit in their browser.
public struct FeedbackIssue: Sendable {
    public static let newIssueURL = URL(string: "https://github.com/kezaer/pacemark/issues/new")!
    public let url: URL

    public init(diagnostics: FeedbackDiagnostics?) {
        url = FeedbackEmail.boundedURL(diagnostics: diagnostics, maximumLength: 1_799) { title, body in
            var components = URLComponents(url: Self.newIssueURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "body", value: body),
            ]
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return components.url!
        }
    }
}
