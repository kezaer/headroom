import AppKit
import Darwin
import Foundation
import PacemarkCore
import SwiftUI

enum DevCaptureCommand {
    static let flag = "--capture-demo"

    private static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pacemark/DevCapture", isDirectory: true)
    }

    static func load(path: String?) throws -> DemoCapture {
        let url = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? directory.appendingPathComponent("latest.json")
        let capture = try JSONDecoder().decode(DemoCapture.self, from: Data(contentsOf: url))
        guard capture.isSupportedVersion else { throw Failure.unsupportedVersion }
        return capture
    }

    @MainActor
    static func showLoadFailure(_ error: Error) {
        let reason: String
        switch error {
        case Failure.unsupportedVersion:
            reason = "This version of Pacemark cannot replay the capture’s format."
        case is DecodingError:
            reason = "The capture contains invalid or incomplete JSON."
        case let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile:
            reason = "The capture file could not be found."
        default:
            reason = "The capture file could not be read."
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let alert = NSAlert()
        alert.messageText = "Could not load the Pacemark demo capture"
        alert.informativeText = "\(reason)\n\nTo recapture while online, run:\n/Applications/Pacemark.app/Contents/MacOS/Pacemark --capture-demo"
        alert.addButton(withTitle: "Quit")
        app.activate()
        alert.runModal()
    }

    static func run() -> Never {
        // Restrict new capture and staging files to this macOS user.
        umask(0o077)
        Task { @MainActor in
            let preferences = AppComposition.launchPreferences
            let store = AppComposition.store(preferences: preferences, capturingDemo: true)
            await store.refreshAll()
            let capture = DemoCapture(
                store: store, preferences: preferences, at: Date(),
                hasT3Claude: AppComposition.isT3ClaudeAvailable(),
                hasT3Antigravity: AppComposition.isT3AntigravityAvailable()
            )
            do {
                try save(capture)
                print("Saved the Pacemark demo capture.")
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Could not save the Pacemark demo capture.\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        RunLoop.main.run()
        exit(EXIT_FAILURE)
    }

    private static func save(_ capture: DemoCapture) throws {
        let files = FileManager.default
        let directory = self.directory
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let lock = open(directory.appendingPathComponent(".lock").path, O_WRONLY | O_CREAT | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw Failure.lockUnavailable }
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw Failure.lockUnavailable }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(capture)
        let latest = directory.appendingPathComponent("latest.json")
        let previous = directory.appendingPathComponent("previous.json")
        if files.fileExists(atPath: latest.path) {
            try Data(contentsOf: latest).write(to: previous, options: .atomic)
        }
        try data.write(to: latest, options: .atomic)
    }

    private enum Failure: Error {
        case unsupportedVersion, lockUnavailable
    }
}

struct CapturedDemoLinks: ViewModifier {
    let isReplaying: Bool

    func body(content: Content) -> some View {
        if isReplaying {
            content.environment(\.openURL, OpenURLAction { _ in .discarded })
        } else {
            content
        }
    }
}
