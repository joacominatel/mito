import MitoCore
import SwiftUI

/// The draft summary and the top recommendation during champ select (§22.4). Empty otherwise.
struct RecommendationMenuSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        RecommendationMenuRow(model: app.champSelect)
    }
}

struct RecommendationMenuRow: View {
    let model: ChampSelectModel

    var body: some View {
        if let summary = model.menuSummary {
            Label {
                Text(summary)
            } icon: {
                Image(systemName: "person.3.fill")
                    .accessibilityHidden(true)
            }
        }
        if let recommendation = model.menuRecommendation {
            Label {
                Text(recommendation)
            } icon: {
                Image(systemName: model.isBanPhase ? "nosign" : "sparkles")
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview("Tu turno") {
    RecommendationMenuRow(
        model: PreviewDraft.model(PreviewDraft.banPick, queue: .rankedSolo)
    )
    .padding()
}

#Preview("Fuera de champ select") {
    RecommendationMenuRow(model: ChampSelectModel(connection: DisconnectedLCUConnection()))
        .padding()
}
