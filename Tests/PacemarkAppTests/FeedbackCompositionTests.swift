import Foundation
import Testing
import PacemarkCore
@testable import Pacemark

/// Feedback plan R8: demos, the render and bench harnesses and this test host read no CLI
/// versions or open a browser from either feedback action.
@MainActor
@Suite(.sharedAppState)
struct FeedbackCompositionTests {
    @Test func onlyARealLaunchReadsCLIsAndOpensGitHub() {
        for arguments in [
            ["Pacemark", "--demo"],
            ["Pacemark", "--render-popover", "/tmp/out"],
            ["Pacemark", "--bench-ui", "settings"],
        ] {
            #expect(AppComposition.usesInertFeedback(arguments: arguments, environment: [:]), "\(arguments)")
        }
        #expect(AppComposition.usesInertFeedback(
            arguments: ["Pacemark"],
            environment: ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]))
        #expect(!AppComposition.usesInertFeedback(arguments: ["Pacemark"], environment: [:]))
    }

    @Test func theTestHostIsInert() {
        #expect(AppComposition.usesInertFeedback())
    }
    @Test func inertLaunchesSkipIssuePreparation() async {
        let defaults = DemoMemoryDefaults()

        let store = UsageStore(providers: [], preferences: Preferences(defaults: defaults))
        let url = await MacFeedback.issueURL(store: store) {
            Issue.record("Inert feedback read CLI versions")
            return []
        }
        #expect(url == nil)
    }
}

@Test @MainActor func importSkipsInertLaunchesAndOtherBundles() {
    for (bundle, inert) in [("com.kezaer.pacemark", AppComposition.usesIsolatedServices(arguments: ["--demo"], environment: [:])),
                            ("example.other", false)] {
        FirstLaunchImport.run(bundleID: bundle, inert: inert) {
            Issue.record("Unexpected import")
            return false
        }
    }
}
