import Foundation
import Testing
@testable import PacemarkCore

struct AboutLinksTests {
    @Test func aboutDestinations() {
        #expect(MacAboutLinks.maker.map(\.destination) == ["in/kezaer", "kezaer"])
        #expect(MacAboutLinks.license.url.absoluteString == "https://github.com/kezaer/pacemark/blob/main/LICENSE")
    }
}
