import Testing
@testable import Pacemark

@MainActor
@Suite(.sharedAppState)
struct WarmUpCompositionTests {
    @Test func onlyARealLaunchUsesTheWarmUpSender() {
        for arguments in [
            ["Pacemark", "--demo"],
            ["Pacemark", "--demo", "multi-20"],
            ["Pacemark", "--render-popover", "/tmp/out", "--warm-up-only"],
            ["Pacemark", "--render-loading-preview", "/tmp/out"],
            ["Pacemark", "--bench-ui", "popover"],
        ] {
            #expect(AppComposition.usesInertWarmUp(arguments: arguments, environment: [:]), "\(arguments)")
        }
        #expect(AppComposition.usesInertWarmUp(
            arguments: ["Pacemark"],
            environment: ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]
        ))
        #expect(!AppComposition.usesInertWarmUp(arguments: ["Pacemark"], environment: [:]))
    }

    @Test func testHostUsesInertWarmUp() {
        #expect(AppComposition.usesInertWarmUp())
    }
}
