import SwiftUI

/// The Finder icon of the app bundle at `url`.
@MainActor
struct AppIconView: View {
    @Environment(AppCatalog.self) private var catalog

    let url: URL
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: catalog.icon(for: url))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
