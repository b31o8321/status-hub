import SwiftUI
import AppKit

struct ProviderIconView: View {
    let icon: String
    let baseDirectory: URL
    var status: HubStatus? = nil
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image = providerImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: icon)
                    .font(.system(size: size))
                    .foregroundColor(status?.color ?? .accentColor)
            }
        }
        .frame(width: size, height: size)
    }

    private var providerImage: NSImage? {
        guard looksLikeImagePath(icon) else { return nil }
        let url = expandedIconURL(icon, baseDirectory: baseDirectory)
        return NSImage(contentsOf: url)
    }

    private func looksLikeImagePath(_ value: String) -> Bool {
        value.contains("/") || value.contains(".")
    }

    private func expandedIconURL(_ value: String, baseDirectory: URL) -> URL {
        if value.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath)
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return baseDirectory.appendingPathComponent(value)
    }
}
