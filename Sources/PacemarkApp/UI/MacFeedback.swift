import Foundation
import PacemarkCore

@MainActor
enum MacFeedback {
    /// Both About and setup recovery prepare the same issue for the user to review in GitHub.
    static func issueURL(
        store: UsageStore,
        isInert: Bool = AppComposition.usesInertFeedback(),
        cliVersions: () async -> [FeedbackDiagnostics.CLI] = { await CLIVersionReader.versions() }
    ) async -> URL? {
        guard !isInert else { return nil }
        let diagnostics = FeedbackDiagnosticsCollector.diagnostics(
            store: store, platform: .current(appVersion: AppVersionLabel.plain),
            cliVersions: await cliVersions()
        )
        return FeedbackIssue(diagnostics: diagnostics).url
    }
}
