import SwiftUI

struct IOSSyncStatusView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "iphone")
        } description: {
            Text(message)
        }
        .padding()
    }
}
