import Foundation
import Testing
@testable import HeadroomCore

@Suite struct AccountStorageLifecycleTests {
    @Test func additionalAccountDirectoriesAreOwnerOnlyAndRemovalIsExact() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = ProviderAccount(id: AccountID("selected"), providerID: .claude, label: "Selected")
        let sibling = ProviderAccount(id: AccountID("sibling"), providerID: .claude, label: "Sibling")

        let selectedURL = try AccountStorage.ensureDirectories(for: selected, baseDirectoryURL: root)
        let siblingURL = try AccountStorage.ensureDirectories(for: sibling, baseDirectoryURL: root)
        for url in [selectedURL,
                    selectedURL.appendingPathComponent("config"),
                    selectedURL.appendingPathComponent("workspace")] {
            let mode = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            #expect(mode.intValue & 0o077 == 0)
        }

        try AccountStorage.removeDirectories(for: selected, baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: selectedURL.path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    @Test func missingDirectoryCountsAsAlreadyRemovedAndBuiltInIsNeverTouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try AccountStorage.removeDirectories(
            for: ProviderAccount(id: AccountID("missing"), providerID: .codex, label: "Missing"),
            baseDirectoryURL: root
        )
        try AccountStorage.removeDirectories(for: .builtIn(for: .codex), baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func grokRemovalDeletesOnlyTheRequestedIsolatedHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-grok-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = ProviderAccount(id: AccountID("selected"), providerID: .grok, label: "Selected")
        let sibling = ProviderAccount(id: AccountID("sibling"), providerID: .grok, label: "Sibling")
        let selectedURL = try AccountStorage.ensureDirectories(for: selected, baseDirectoryURL: root)
        let siblingURL = try AccountStorage.ensureDirectories(for: sibling, baseDirectoryURL: root)

        #expect(selectedURL.path.hasSuffix("/grok/selected"))
        #expect(siblingURL.path.hasSuffix("/grok/sibling"))
        try AccountStorage.removeDirectories(for: selected, baseDirectoryURL: root)

        #expect(!FileManager.default.fileExists(atPath: selectedURL.path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    @Test func credentialPermissionCheckRejectsGroupOrWorldReadableFiles() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("sentinel".utf8).write(to: file)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(AccountStorage.credentialFilePermissionsAreSafe(at: file))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(!AccountStorage.credentialFilePermissionsAreSafe(at: file))
    }

    @Test func activeSetupMarkerBlocksRemovalAndDeadProcessMarkerRecovers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = ProviderAccount(id: AccountID("selected"), providerID: .codex, label: "Selected")
        let accountURL = try AccountStorage.ensureDirectories(for: account, baseDirectoryURL: root)
        let marker = SetupCompletionMarker(
            pendingPath: accountURL.appendingPathComponent(".headroom-setup-pending").path,
            completedPath: accountURL.appendingPathComponent(".headroom-setup-complete").path
        )
        try AccountStorage.prepareSetupCompletionMarker(marker)
        #expect(AccountStorage.setupHandoffIsActive(marker: marker))
        #expect(throws: (any Error).self) {
            try AccountStorage.removeDirectories(for: account, baseDirectoryURL: root)
        }

        try Data("2147483647\n".utf8).write(to: URL(fileURLWithPath: marker.pendingPath))
        #expect(!AccountStorage.setupHandoffIsActive(marker: marker))
        try AccountStorage.removeDirectories(for: account, baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: accountURL.path))
    }

    @Test func abandonedOpeningMarkerExpiresWithoutWeakeningUnknownMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let startedAt = Date(timeIntervalSince1970: 1_000)
        try Data("opening:\(startedAt.timeIntervalSince1970)\n".utf8)
            .write(to: URL(fileURLWithPath: marker.pendingPath))

        #expect(AccountStorage.setupHandoffIsActive(
            marker: marker,
            now: startedAt.addingTimeInterval(AccountStorage.preparedMarkerGracePeriod - 1)
        ))
        #expect(!AccountStorage.setupHandoffIsActive(
            marker: marker,
            now: startedAt.addingTimeInterval(AccountStorage.preparedMarkerGracePeriod + 1)
        ))
        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))

        try Data("unrecognized\n".utf8).write(to: URL(fileURLWithPath: marker.pendingPath))
        #expect(AccountStorage.setupHandoffIsActive(
            marker: marker,
            now: startedAt.addingTimeInterval(86_400)
        ))
    }

    @Test func pendingMarkerRestoresExplicitDeviceCodeMode() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-mode-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let marker = SetupCompletionMarker(
            pendingPath: file.path,
            completedPath: file.path + "-complete"
        )

        try Data("deviceCode:2147483647\n".utf8).write(to: file)
        #expect(AccountStorage.setupHandoffMode(marker: marker) == .deviceCode)
        #expect(!AccountStorage.setupHandoffIsActive(marker: marker))
    }

    /// Regression (code-review finding): built-in setup markers live in the shared
    /// `Setup/` directory beside the built-in Claude workspace — not under the
    /// per-account `Accounts/<provider>/<id>/` tree. The removal gate's storage check
    /// must resolve that real location, or stop-tracking a built-in account detaches
    /// the row while its Terminal handoff is still open.
    @Test func builtInSetupMarkerAtSharedSetupDirectoryBlocksStopTracking() async throws {
        let supportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-builtin-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportRoot) }
        let workspace = supportRoot.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let account = ProviderAccount.builtIn(for: .claude)

        let marker = AccountStorage.setupCompletionMarker(
            for: account, builtInClaudeWorkspace: workspace
        )
        #expect(marker.pendingPath == supportRoot
            .appendingPathComponent("Setup", isDirectory: true)
            .appendingPathComponent(".headroom-claude-setup-pending").path)

        try AccountStorage.prepareSetupCompletionMarker(marker)
        #expect(AccountStorage.setupHandoffIsActive(
            for: account, builtInClaudeWorkspace: workspace
        ))
        let storage = DefaultAccountStorage(builtInClaudeWorkspace: workspace)
        let activeWhileMarkerPresent = await storage.setupHandoffIsActive(for: account)
        #expect(activeWhileMarkerPresent)

        AccountStorage.clearPreparedSetupCompletionMarker(marker)
        let activeAfterClear = await storage.setupHandoffIsActive(for: account)
        #expect(!activeAfterClear)
    }

    @Test func extraAccountSetupMarkerStaysInsideItsConfigHome() {
        let extra = ProviderAccount(id: AccountID("extra"), providerID: .claude, label: "Extra")
        let marker = AccountStorage.setupCompletionMarker(
            for: extra,
            builtInClaudeWorkspace: URL(fileURLWithPath: "/nonexistent/ClaudeProbe")
        )
        let home = AccountStorage.accountDirectoryURL(for: extra)
        #expect(marker.pendingPath == home.appendingPathComponent(".headroom-setup-pending").path)
        #expect(marker.completedPath == home.appendingPathComponent(".headroom-setup-complete").path)
    }

    @Test func completionMarkerClassifiesOnlyRedactionSafeExitStatus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-completion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let completedURL = URL(fileURLWithPath: marker.completedPath)

        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
        try Data("complete:0\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .succeeded)
        try Data("complete:130\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .failed)
        try Data("provider output must not be parsed\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
    }

    @Test func forceCancelMarkerCleanupRemovesPendingAndCompletedFilesAndIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-force-cancel-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        try Data("standard:2147483647\n".utf8).write(to: URL(fileURLWithPath: marker.pendingPath))
        try Data("complete:0\n".utf8).write(to: URL(fileURLWithPath: marker.completedPath))

        AccountStorage.clearSetupCompletionMarkers(marker)
        AccountStorage.clearSetupCompletionMarkers(marker)

        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))
        #expect(!FileManager.default.fileExists(atPath: marker.completedPath))
    }

    @Test func completionWrapperDoesNotOverwriteSuccessorMarkerAfterForceCancel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-force-cancel-wrapper-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("old.command")
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let script = SetupCompletionCommand.wrap(
            "sleep 0.2",
            marker: marker,
            mode: .standard
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.pendingPath) {
            Thread.sleep(forTimeInterval: 0.005)
        }
        try Data("standard:2147483647\n".utf8).write(to: URL(fileURLWithPath: marker.pendingPath))
        process.waitUntilExit()

        #expect(try String(contentsOfFile: marker.pendingPath, encoding: .utf8) == "standard:2147483647\n")
        #expect(!FileManager.default.fileExists(atPath: marker.completedPath))
        #expect(FileManager.default.fileExists(atPath: scriptURL.path))
    }
}
