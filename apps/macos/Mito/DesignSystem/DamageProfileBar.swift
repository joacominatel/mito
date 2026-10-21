import SwiftUI

/// `DamageProfileBar` of §22.3: physical and magic shares as one bar, true damage in the rest.
/// Decorative: the text next to it carries the numbers.
struct DamageProfileBar: View {
    let physical: Double
    let magic: Double

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(.orange).frame(width: proxy.size.width * physical)
                Rectangle().fill(.blue).frame(width: proxy.size.width * magic)
                Rectangle().fill(.quaternary)
            }
            .clipShape(.capsule)
        }
        .frame(minWidth: 80, idealWidth: 140, maxWidth: 180)
        .frame(height: 6)
        .draftAnimation(value: physical)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        DamageProfileBar(physical: 0.78, magic: 0.17)
        DamageProfileBar(physical: 0.41, magic: 0.52)
        DamageProfileBar(physical: 0.2, magic: 0.6)
    }
    .padding()
}
