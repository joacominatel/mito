import SwiftUI

/// The "Composición" tab of the analysis panel (§20.2). A placeholder until its unit lands.
struct CompositionTab: View {
    let subject: AnalysisSubject

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Composición", tableName: "Composition")
            } icon: {
                Image(systemName: "person.3")
            }
        } description: {
            Text("Los dos equipos, cara a cara: muy pronto.", tableName: "Composition")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
