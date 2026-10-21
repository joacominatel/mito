import SwiftUI

/// The "Matchup" tab of the analysis panel (§20.2). A placeholder until its unit lands.
struct MatchupTab: View {
    let subject: AnalysisSubject

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Matchup", tableName: "Matchup")
            } icon: {
                Image(systemName: "arrow.left.arrow.right")
            }
        } description: {
            Text("El cruce con tu rival de línea: muy pronto.", tableName: "Matchup")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
