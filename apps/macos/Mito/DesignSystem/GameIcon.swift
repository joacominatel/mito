import MitoCore
import SwiftUI

/// A champion, item, rune or spell icon from the app's `IconSource`, with a neutral placeholder
/// while it loads or when there is none. Decorative unless it gets a `label`: most sit next to
/// their name.
struct GameIcon: View {
    let asset: GameAsset?
    let size: CGFloat
    /// The name VoiceOver reads when no name is shown next to the icon.
    var label: String?

    @Environment(\.iconSource) private var icons

    init(_ asset: GameAsset?, size: CGFloat, label: String? = nil) {
        self.asset = asset
        self.size = size
        self.label = label
    }

    var body: some View {
        let request = asset.flatMap { icons?.request(for: $0) }
        let shape = RoundedRectangle(
            cornerRadius: Self.isRound(asset) ? size / 2 : Self.squareRadius(size))
        Group {
            if let image = icons?.image(for: request) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                shape.fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .task(id: request) {
            if let request { await icons?.load(request) }
        }
        .accessibilityHidden(label == nil)
        .accessibilityLabel(Text(verbatim: label ?? ""))
        .accessibilityAddTraits(.isImage)
    }

    /// Champion, item and spell art is square; runes are round art on transparency.
    static func isRound(_ asset: GameAsset?) -> Bool {
        switch asset {
        case .perk, .perkStyle: true
        case .champion, .item, .spell, nil: false
        }
    }

    static func squareRadius(_ size: CGFloat) -> CGFloat { size * 0.18 }
}

/// `ChampionIcon(id:size:state:)` of §22.3. Each state changes the shape, not only the color: a
/// dashed outline while hovered, a solid one when locked, a slash when banned, faded when it
/// cannot be picked.
struct ChampionIcon: View {
    enum State: Hashable {
        case normal
        case hover
        case locked
        case banned
        case unavailable
    }

    enum Outline: Hashable {
        case none
        case dashed
        case solid
    }

    let id: ChampionID?
    let size: CGFloat
    var state: State = .normal
    var label: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GameIcon.squareRadius(size))
        GameIcon(id.map(GameAsset.champion), size: size)
            .saturation(Self.isMuted(state) ? 0 : 1)
            .opacity(Self.opacity(state))
            .overlay {
                switch Self.outline(state) {
                case .none: EmptyView()
                case .dashed:
                    shape.strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                case .solid: shape.strokeBorder(.tint, lineWidth: 2)
                }
            }
            .overlay {
                if state == .banned {
                    Rectangle()
                        .fill(.red)
                        .frame(width: max(2, size / 14), height: size * 1.3)
                        .rotationEffect(.degrees(45))
                }
            }
            .clipShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(label == nil)
            .accessibilityLabel(Text(verbatim: label ?? ""))
            .accessibilityValue(Self.stateText(state).map(Text.init) ?? Text(verbatim: ""))
            .accessibilityAddTraits(.isImage)
    }

    static func outline(_ state: State) -> Outline {
        switch state {
        case .hover: .dashed
        case .locked: .solid
        case .normal, .banned, .unavailable: .none
        }
    }

    static func isMuted(_ state: State) -> Bool {
        state == .banned || state == .unavailable
    }

    static func opacity(_ state: State) -> Double {
        switch state {
        case .normal, .locked: 1
        case .hover, .banned: 0.75
        case .unavailable: 0.4
        }
    }

    static func stateText(_ state: State) -> LocalizedStringResource? {
        switch state {
        case .normal: nil
        case .hover: LocalizedStringResource("en hover", table: "DesignSystem")
        case .locked: LocalizedStringResource("lockeado", table: "DesignSystem")
        case .banned: LocalizedStringResource("baneado", table: "DesignSystem")
        case .unavailable: LocalizedStringResource("no disponible", table: "DesignSystem")
        }
    }
}

#Preview("Estados") {
    HStack(spacing: 12) {
        ForEach(
            [ChampionIcon.State.normal, .hover, .locked, .banned, .unavailable], id: \.self
        ) { state in
            ChampionIcon(id: ChampionID(rawValue: 103), size: 40, state: state)
        }
        GameIcon(.item(ItemID(rawValue: 3089)), size: 28)
        GameIcon(.perk(PerkID(rawValue: 8112)), size: 28)
        GameIcon(.spell(SummonerSpellID(rawValue: 4)), size: 28)
    }
    .padding()
}
