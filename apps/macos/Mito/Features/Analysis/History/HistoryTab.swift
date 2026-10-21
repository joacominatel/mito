import SwiftUI

/// The "Mi historial" tab of the analysis panel (§20.2). A placeholder until its unit lands.
struct HistoryTab: View {
    let subject: AnalysisSubject

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Mi historial", tableName: "History")
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
        } description: {
            Text("Tu rendimiento con este campeón: muy pronto.", tableName: "History")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
