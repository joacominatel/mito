import MitoCore
import SwiftUI

/// One explained fact (§22.3): a symbol in the reason's tone, the line, and the "muestra baja"
/// mark when its sample is short of reliable (§18.1).
struct ReasonRow: View {
    let reason: Reason
    var names: ReasonNames = .ids

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: ReasonText.symbol(reason.kind))
                .foregroundStyle(ReasonText.tone(reason.kind).color)
                .frame(minWidth: 16)
                .accessibilityHidden(true)
            Text(verbatim: ReasonText.text(reason, names: names))
                .fixedSize(horizontal: false, vertical: true)
            if reason.sample?.isLowSample == true {
                LowSampleMark()
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

/// Gray, with an icon and its words: never color alone (§22.1).
private struct LowSampleMark: View {
    var body: some View {
        Label {
            Text("muestra baja", tableName: "DesignSystem")
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(Text("Pocas partidas detrás de este dato", tableName: "DesignSystem"))
    }
}

#Preview("Razones") {
    VStack(alignment: .leading, spacing: 6) {
        ReasonRow(
            reason: Reason(
                kind: .matchup(opponent: ChampionID(rawValue: 238), delta: 0.021, games: 8212),
                sample: .reliable),
            names: .preview)
        ReasonRow(
            reason: Reason(
                kind: .synergy(
                    ally: ChampionID(rawValue: 64), allyRole: .jungle, delta: -0.012, games: 64),
                sample: .usable),
            names: .preview)
        ReasonRow(
            reason: Reason(kind: .fillsDamageGap(adds: .magic, alliedShare: 0.78), sample: nil))
        ReasonRow(reason: Reason(kind: .meta(tier: .s, games: 3564), sample: .reliable))
    }
    .padding()
    .frame(width: 420)
}

extension ReasonNames {
    static let preview = ReasonNames(
        champion: { id in
            [238: "Zed", 64: "Lee Sin", 103: "Ahri", 99: "Lux", 90: "Malzahar"][id.rawValue]
                ?? "Campeón \(id.rawValue)"
        },
        item: { "Ítem \($0.rawValue)" })
}
