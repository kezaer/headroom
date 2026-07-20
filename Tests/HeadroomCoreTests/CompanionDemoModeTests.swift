import Foundation
import Testing
@testable import HeadroomCore

struct CompanionDemoModeTests {
    @Test func defaultsToDisabledAndPersistsOnlyTheDemoFlag() throws {
        let suiteName = "CompanionDemoModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)
        let cache = WidgetSnapshotCache(defaults: defaults)
        let realEnvelope = WidgetSnapshotEnvelope.disabled(
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try cache.write(realEnvelope)

        #expect(!store.isEnabled)
        #expect(store.setEnabled(true) == .changed)
        #expect(store.isEnabled)
        #expect(defaults.dictionaryRepresentation().keys.contains(CompanionDemoModeStore.defaultsKey))
        #expect(store.setEnabled(true) == .unchanged)
        #expect(cache.read() == .snapshot(realEnvelope))

        #expect(store.setEnabled(false) == .changed)
        #expect(!store.isEnabled)
        #expect(defaults.object(forKey: CompanionDemoModeStore.defaultsKey) == nil)
        #expect(cache.read() == .snapshot(realEnvelope))
    }

    @Test func unavailableStoreSupportsSessionOnlyFallback() {
        let store = CompanionDemoModeStore(defaults: nil)

        #expect(!store.isEnabled)
        #expect(store.setEnabled(true) == .unavailable)
        #expect(!store.isEnabled)
    }

    @Test func variantDefaultsToFull() throws {
        let suiteName = "CompanionDemoModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)

        #expect(store.variant == "full")
    }

    @Test func variantPersistsAndRoundTrips() throws {
        let suiteName = "CompanionDemoModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CompanionDemoModeStore(defaults: defaults)

        #expect(store.setVariant("heavy") == .changed)
        #expect(store.variant == "heavy")
        #expect(store.setVariant("heavy") == .unchanged)
        #expect(store.setVariant("singleProviderFull") == .changed)
        #expect(store.variant == "singleProviderFull")
    }

    @Test func variantUnavailableWhenDefaultsNil() {
        let store = CompanionDemoModeStore(defaults: nil)

        #expect(store.setVariant("heavy") == .unavailable)
        #expect(store.variant == "full") // Still defaults to "full"
    }
}
