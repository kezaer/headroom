import Foundation
import Testing
@testable import PacemarkCore

struct ResetDiagnosticTests {
    @Test func everyResetEvidenceStateHasAnAllowlistedCategoryAndAge() {
        let now = Date(timeIntervalSince1970: 10_000)
        let schedules: [(ResetSchedule, ResetDiagnosticCategory)] = [
            (.scheduled(now.addingTimeInterval(60)), .scheduled),
            (.unresolved(.absent), .absent),
            (.unresolved(.elapsed), .elapsed),
            (.unresolved(.unparseable), .unparseable),
            (.unresolved(.implausible), .implausible),
            (.unresolved(.invalidZone), .invalidZone),
            (.unresolved(.legacyUnknown), .legacyUnknown),
        ]

        for (schedule, category) in schedules {
            let line = ResetDiagnostic.line(
                for: schedule,
                observedAt: now.addingTimeInterval(-42),
                now: now
            )
            #expect(line == "reset-evidence=\(category.rawValue) age-seconds=42")
        }
    }

    @Test func reportCannotContainProviderTextPathsIdentityOrCredentials() {
        let output = ResetDiagnostic.line(
            for: .unresolved(.unparseable),
            observedAt: nil,
            now: Date(timeIntervalSince1970: 10_000)
        )

        for forbidden in [
            "Resets Aug 7 at 9am",
            "America/Los_Angeles",
            "/Users/example/.claude",
            "example@example.com",
            "sk-ant-secret",
            "Current session",
        ] {
            #expect(!output.contains(forbidden))
        }
        #expect(output == "reset-evidence=unparseable age-seconds=unknown")
    }
}
