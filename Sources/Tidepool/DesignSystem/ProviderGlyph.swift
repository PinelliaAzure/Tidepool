import SwiftUI

/// 小尺寸 Provider 品牌图形（Tab、设置、引导共用）。
struct ProviderGlyph: View {
    let provider: ProviderID
    var size: CGFloat = 14
    var colorMode: Bool = true

    var body: some View {
        if let image = ProviderIconRenderer.icon(for: provider, colorMode: colorMode, size: size) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(provider.brandColor)
                .frame(width: size * 0.55, height: size * 0.55)
        }
    }
}
