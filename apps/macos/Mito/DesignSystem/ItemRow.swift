import MitoCore
import SwiftUI

/// `ItemRow(items:)` of §22.3: the items' icons in build order. Decorative: their names sit next
/// to it.
struct ItemRow: View {
    let items: [ItemID]
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                GameIcon(.item(item), size: size)
            }
        }
    }
}

/// `RunePageView(page:)` of §22.3, compact: the keystone and the secondary tree. Decorative: the
/// page's names sit next to it.
struct RunePageView: View {
    let page: RunePage
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.assets(page).enumerated()), id: \.offset) { _, asset in
                GameIcon(asset, size: size)
            }
        }
    }

    static func assets(_ page: RunePage) -> [GameAsset] {
        (page.perks.first.map { [.perk($0)] } ?? []) + [.perkStyle(page.subStyle)]
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        RunePageView(
            page: RunePage(
                primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
                perks: [PerkID(rawValue: 8112)]))
        ItemRow(items: [ItemID(rawValue: 6655), ItemID(rawValue: 3020), ItemID(rawValue: 3089)])
    }
    .padding()
}
